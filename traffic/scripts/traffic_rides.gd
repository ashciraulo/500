class_name TrafficRides
extends Node3D
## Weekend bunch rides, run by TrafficManager: on Saturday and Sunday
## mornings (6 till 10) clubs of road cyclists in matching kit roll round
## the river loop (Mounts Bay Road, Riverside Drive, Mill Point Road, the
## South Perth Esplanade, Kings Park, Lake Monger), a dozen or so riders
## sitting on each other's wheels, staggered two abreast by the kerb. A few
## early bunches go out on weekdays before work (5:30 till 7).

signal bunch_started(position: Vector3, club: String, riders: int)

## Roads the bunches ride (OSM names).
const RIDE_ROADS := ["Mounts Bay Road", "Riverside Drive", "Riverside Road", "Mill Point Road",
	"South Perth Esplanade", "Kings Park Road", "Fraser Avenue", "Lake Monger Drive",
	"Canning Beach Road", "The Esplanade", "Burswood Road"]
## [club, jersey, helmet and frame]
const CLUBS := [
	["Swan River Wheelers", Color(0.1, 0.25, 0.65), Color(0.95, 0.95, 0.93)],
	["Kings Park Velo", Color(0.15, 0.5, 0.3), Color(0.12, 0.12, 0.14)],
	["Black Swan CC", Color(0.12, 0.12, 0.14), Color(0.95, 0.8, 0.1)],
	["Narrows Racing", Color(0.85, 0.15, 0.2), Color(0.95, 0.95, 0.93)],
	["Mends St Coffee Club", Color(0.95, 0.55, 0.15), Color(0.35, 0.22, 0.15)],
]
## Bunch pace, m/s (about 31 to 35 km/h).
const PACE := Vector2(8.6, 9.8)
## Wheel to wheel, front of one to front of the next, at the start.
const SPACING := 3.3

@export var enabled := true
## Tests: ignore the clock and the calendar.
@export var always_on := false
@export var max_bunches := 2
@export var riders := Vector2i(8, 14)

## { riders: [TrafficVehicle], club, sound (AudioStreamPlayer3D or null) }
var bunches: Array = []
var stats := { "bunches": 0, "riders": 0 }

var graph: TrafficGraph
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _roads := {}


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph
	if manager.get("random_seed"):
		_rng.seed = hash([manager.random_seed, "rides"])
	else:
		_rng.randomize()
	for r in RIDE_ROADS:
		_roads[r] = true


func _clock() -> Node:
	return get_node("/root/GameClock")


## How many bunches may be out now (0 outside riding hours).
func bunches_wanted() -> int:
	if always_on:
		return max_bunches
	var weather := get_node_or_null("/root/Weather")
	if weather and weather.rain > 0.3:
		return 0
	var c := _clock()
	var h: float = c.time_of_day
	if _manager.is_weekend(c.day):
		return max_bunches if h >= 6.0 and h < 10.0 else 0
	return 1 if h >= 5.5 and h < 7.0 else 0


func update(delta: float, focus: Vector3) -> void:
	if graph == null:
		return
	for b in bunches:
		# The whirr of the bunch goes along with its middle.
		var mid: TrafficVehicle = b.riders[b.riders.size() / 2]
		if b.sound and mid.active:
			b.sound.global_position = mid.position + Vector3(0, 1.0, 0)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.0
	for b in bunches.duplicate():
		b.riders = b.riders.filter(func(v): return v.active and v.type == &"bike" and v.bunch == b.id)
		if b.riders.is_empty():
			_end(b)
	if not enabled or bunches.size() >= bunches_wanted():
		return
	var spot := _ride_spot(focus)
	if not spot.is_empty():
		add_bunch(spot[0], spot[1], _rng.randi_range(riders.x, riders.y))


func clear() -> void:
	for b in bunches.duplicate():
		_end(b)


func _end(b: Dictionary) -> void:
	bunches.erase(b)
	if b.sound:
		b.sound.queue_free()


## A kerb lane on one of the ride roads, out of sight and with room behind
## for the whole bunch: [lane, s], or [] if there's none about.
func _ride_spot(focus: Vector3) -> Array:
	var radius: float = _manager.spawn_radius
	var samples: Array = graph.samples_near(focus, radius)
	var lanes := {}
	for entry in samples:
		var lane: TrafficGraph.Lane = entry[0]
		if not lane.connector and lane.road and _roads.has(lane.road.name) and lane.k == lane.count - 1 and lane.length > 70.0:
			lanes[lane] = true
	var list: Array = lanes.keys()
	for attempt in 8:
		if list.is_empty():
			return []
		var lane: TrafficGraph.Lane = list[_rng.randi() % list.size()]
		var s := lane.length - 12.0
		var p := lane.point(s)
		var d := p.distance_to(focus)
		if d < _manager.min_spawn_radius * 0.7 or d > radius or _manager._visible(p, 25.0) or _manager._visible(lane.point(20.0), 25.0):
			continue
		if graph.reach(lane) < TrafficGraph.REACH:
			continue
		var clear := true
		for o in lane.vehicles:
			if o.s > 0.0 and o.s < lane.length:
				clear = false
		if clear:
			return [lane, s]
	return []


## Start a bunch of `count` riders on `lane`, the front rider at `s` and the
## rest strung out behind. Returns the riders, front first.
func add_bunch(lane: TrafficGraph.Lane, s: float, count: int) -> Array:
	var club: Array = CLUBS[_rng.randi() % CLUBS.size()]
	var pace := _rng.randf_range(PACE.x, PACE.y)
	count = mini(count, int((s - 2.0) / SPACING) + 1)
	var out: Array = []
	var ahead: TrafficVehicle = null
	for i in count:
		var v: TrafficVehicle = _manager.spawn_vehicle_at(&"bike", lane, s - i * SPACING, pace * 0.8)
		if v == null:
			break
		# The front rider sets the pace; the rest can close a gap.
		v.max_speed = pace if ahead == null else pace * 1.08
		v.keep_lane = true
		v.ride_roads = _roads
		v.bunch = stats.bunches + 1
		v.bunch_side = 0.0 if i % 2 == 0 else 0.6
		v.eagerness = 1.0
		if ahead:
			v.follow = ahead
			v.follow_serial = ahead.serial
			# It planned its own way on spawning: take the leader's instead.
			v.route.resize(1)
			v.commits.clear()
			_manager._extend_route(v)
		# Club kit, mostly; the odd rider in something else.
		var jersey: Color = club[1] if _rng.randf() < 0.85 else TrafficModels.JERSEYS[_rng.randi() % TrafficModels.JERSEYS.size()]
		v.paint = club[2]
		v.mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(club[2]))
		v.mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(jersey))
		out.append(v)
		ahead = v
	if out.is_empty():
		return out
	var sound := TrafficNight.loop_player(self, "traffic/traffic_bunch_loop", &"Vehicles", 6.0, 70.0)
	if sound:
		add_child(sound)
		sound.global_position = out[0].position
	bunches.append({ "id": stats.bunches + 1, "riders": out, "club": club[0], "sound": sound })
	stats.bunches += 1
	stats.riders += out.size()
	bunch_started.emit(out[0].position, club[0], out.size())
	return out
