class_name TrafficParking
extends Node3D
## Parked cars on the parking spots the map hands over (`parking` in each
## tile's traffic data; see docs/TRAFFIC.md). Spots near the player are filled
## by time of day: car parks fill up in working hours, streets overnight.
## Which spots are taken changes every couple of hours, and a spot only
## changes while the camera isn't looking at it.
##
## Parked cars are static bodies on the traffic collision layer, so the
## player can bump into them; AI traffic never drives over a spot because
## spots near a lane are ignored.

## How full car parks are by hour, 0..1 (busy from 8 to 5).
const LOT_CURVE := [0.1, 0.08, 0.08, 0.08, 0.08, 0.12, 0.3, 0.6, 0.85, 0.9, 0.9, 0.9,
	0.9, 0.9, 0.9, 0.85, 0.75, 0.55, 0.4, 0.35, 0.3, 0.25, 0.18, 0.12]
## How full street parking is by hour (everyone's home overnight).
const STREET_CURVE := [0.75, 0.75, 0.75, 0.75, 0.75, 0.72, 0.65, 0.55, 0.5, 0.55, 0.6, 0.6,
	0.62, 0.6, 0.58, 0.58, 0.6, 0.65, 0.7, 0.72, 0.74, 0.75, 0.75, 0.75]
## Spots this close to a lane's centreline would stick into traffic.
const LANE_CLEARANCE := 3.0
const TYPES := [&"hatch", &"hatch", &"sedan", &"sedan", &"suv", &"ute", &"van"]

@export var radius := 170.0
@export var fill_scale := 1.0

var graph: TrafficGraph
## Spot -> its body, for spots currently showing a car.
var shown := {}
var _manager: Node
var _pool := {}
var _timer := 0.0
var _clear_version := {}
## Spots inside the radius at the last update.
var _in_range := {}


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph


func occupancy(kind: StringName, hour: float, day := 1) -> float:
	var curve := LOT_CURVE if kind == &"lot" else STREET_CURVE
	var h := fposmod(hour, 24.0)
	var i := int(h)
	var f := lerpf(curve[i], curve[(i + 1) % 24], h - i)
	if kind == &"lot":
		# The office car parks are half empty at the weekend; on a Friday or
		# Saturday night they fill up with people out on the town.
		var kind_of_day := TrafficManager.day_kind(day)
		if TrafficManager.is_weekend(day) and h >= 6.0 and h < 18.0:
			f *= 0.6 if kind_of_day == TrafficManager.Day.SATURDAY else 0.45
		if TrafficManager.is_night_out(day, hour):
			f = maxf(f, 0.6)
	return f * fill_scale


## Whether `spot` has a car in it now, and which: [taken, type, paint seed].
func wanted(spot: Dictionary) -> Array:
	# A new draw every two hours; the hour curve sets how many draws come up taken.
	var epoch: int = GameClock.day * 12 + int(GameClock.time_of_day / 2.0)
	var roll := float(hash([spot.seed, epoch]) & 0xffff) / 65536.0
	var pick: int = hash([spot.seed, epoch, 7])
	return [roll < occupancy(spot.kind, GameClock.time_of_day, GameClock.day), TYPES[pick % TYPES.size()], pick]


func update(delta: float, focus: Vector3) -> void:
	_timer -= delta
	if _timer > 0.0 or graph == null:
		return
	_timer = 0.5
	for spot in _in_range.keys():
		if spot.pos.distance_to(focus) > radius + 30.0:
			_in_range.erase(spot)
			if shown.has(spot):
				_hide(spot)
	if graph.parking.is_empty():
		return
	for spot in graph.parking_near(focus, radius):
		if spot.pos.distance_to(focus) > radius:
			continue
		var want := wanted(spot)
		var body: StaticBody3D = shown.get(spot)
		var right: bool = body != null and want[0] and body.get_meta("pick") == want[2]
		if right or (body == null and not want[0]):
			_in_range[spot] = true
			continue
		# Leave what the camera can see alone, unless it's just come into range.
		if _in_range.has(spot) and _manager._visible(spot.pos, 40.0):
			continue
		_in_range[spot] = true
		if body != null:
			_hide(spot)
		if want[0] and _clear_of_lanes(spot) and not spot.get("reserved", false):
			_show(spot, want[1], want[2])


func clear() -> void:
	for spot in shown.keys():
		_hide(spot)
	_in_range.clear()


func _clear_of_lanes(spot: Dictionary) -> bool:
	if _clear_version.get(spot.seed, -1) == graph.version:
		return spot.get("clear", true)
	_clear_version[spot.seed] = graph.version
	spot.clear = true
	for box in graph.keep_clear:
		if box.pos.distance_to(spot.pos) < box.radius + 5.0:
			spot.clear = false
			return false
	for entry in graph.samples_near(spot.pos, 20.0):
		var lane: TrafficGraph.Lane = entry[0]
		var s := TrafficGraph.closest_s(lane.pts, lane.cum, spot.pos)
		var p := lane.point(s)
		if absf(p.y - spot.pos.y) < 3.0 and Vector2(p.x - spot.pos.x, p.z - spot.pos.z).length() < LANE_CLEARANCE:
			spot.clear = false
			break
	return spot.clear


func _show(spot: Dictionary, type: StringName, pick: int) -> void:
	var pool: Array = _pool.get(type, [])
	var body: StaticBody3D = pool.pop_back() if not pool.is_empty() else _create(type)
	var rng := RandomNumberGenerator.new()
	rng.seed = pick
	var mesh: MeshInstance3D = body.get_node("Mesh")
	mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(TrafficModels.pick_paint(rng)))
	body.set_meta("pick", pick)
	# A little untidy, like real parking.
	var yaw: float = spot.yaw + rng.randf_range(-0.04, 0.04)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), spot.pos)
	body.visible = true
	body.collision_layer = _manager.TRAFFIC_LAYER
	shown[spot] = body


func _hide(spot: Dictionary) -> void:
	var body: StaticBody3D = shown[spot]
	shown.erase(spot)
	body.visible = false
	body.collision_layer = 0
	body.position = Vector3(0, -500, 0)
	var type: StringName = body.get_meta("type")
	if not _pool.has(type):
		_pool[type] = []
	_pool[type].append(body)


func _create(type: StringName) -> StaticBody3D:
	var info: Dictionary = TrafficModels.TYPES[type]
	var body := StaticBody3D.new()
	body.name = "parked_%s_%d" % [type, get_child_count()]
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_meta("type", type)
	body.set_meta("surface", &"concrete")
	body.set_meta("traffic", type)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(info.width, info.height * 0.85, info.length)
	shape.shape = box
	shape.position = Vector3(0, info.height * 0.5 + 0.1, 0)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = TrafficModels.vehicle_mesh(type)
	mesh.visibility_range_end = radius + 40.0
	mesh.set_surface_override_material(TrafficModels.Surf.GLASS, TrafficModels.material(Color(0.07, 0.08, 0.1)))
	mesh.set_surface_override_material(TrafficModels.Surf.TYRES, TrafficModels.material(Color(0.05, 0.05, 0.05)))
	mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(Color(0.2, 0.2, 0.2)))
	mesh.set_surface_override_material(TrafficModels.Surf.HEAD, TrafficModels.material(Color(0.8, 0.8, 0.75)))
	mesh.set_surface_override_material(TrafficModels.Surf.TAIL, TrafficModels.material(Color(0.45, 0.05, 0.04)))
	var amber := TrafficModels.material(Color(0.5, 0.3, 0.05))
	mesh.set_surface_override_material(TrafficModels.Surf.IND_L, amber)
	mesh.set_surface_override_material(TrafficModels.Surf.IND_R, amber)
	body.add_child(mesh)
	add_child(body)
	return body
