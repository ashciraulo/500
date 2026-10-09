class_name RepeatStreet
extends LateDrive
## Repeat Street (STORY.md, event 8). A quiet street after midnight, from
## act 3: the deck clicks on, and up ahead a streetlamp flickers on over a
## mustard sedan parked on the verge, with a man in a long coat standing
## under it. You pass them. A little further on, the same lamp flickers on
## over the same car and the same man. And again.
##
## Stop the car, or flash the headlights, and you're through: they blink out
## and the deck clunks off. It also lets you go if you turn off the street,
## turn round or reach its end. On Gentle there's no man, just the car and
## the lamp.
##
## The three are built here: a traffic sedan in a seventies colour, a person
## from the traffic's own builder, and a lamp post with a sodium light.

## Streets it happens on.
const KINDS := ["residential", "unclassified", "tertiary", "living_street", "road"]
const MIN_KMH := 20.0
const MAX_KMH := 75.0
## How far ahead (m) the three wait, and how near they flicker on.
const AHEAD := 115.0
const REVEAL := 85.0
## Passed: this far (m) behind the car.
const PASSED := 12.0
## The street ahead must carry on this far (m) for it to start.
const MIN_PATH := 380.0
const MAX_PATH := 900.0
## However many times you let it, it lets you go after this many.
const MAX_PASSES := 6
## Off the street: this far (m) from its line.
const OFF_STREET := 14.0
const STOPPED_KMH := 3.0
const STOPPED_FOR := 1.5
const TURN_ROUND := 2.0
## Where the three stand (m left of the street's line): the car at the kerb,
## the lamp post and the man on the footpath, on a street whose kerb is KERB
## out; on others they move in or out with it.
const KERB := 5.3
const CAR_SIDE := 4.3
const LAMP_SIDE := 6.0
const MAN_SIDE := 6.8
const CAR_PAINT := Color(0.66, 0.5, 0.16)
const LAMP_LIGHT := Color(1.0, 0.62, 0.28)

var passes := 0
var street := ""

var _path := PackedVector3Array()
var _cum := PackedFloat32Array()
var _at := 0          # index of the path segment the car is on
var _s := 0.0         # how far along the path the car is
var _three: Node3D
var _lamp: OmniLight3D
var _lamp_glow: MeshInstance3D
var _three_s := 0.0
var _shown := false
var _stopped := 0.0
var _against := 0.0
var _flicker_t := 0.0
var _how := ""
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	event = &"repeat_street"
	from_act = 3
	every_days = 3
	chance = 0.5


func _ready_to_start() -> bool:
	var v := speed_kmh()
	if not force and (v < MIN_KMH or v > MAX_KMH):
		return false
	var found := street_ahead(_car.global_position, _heading())
	if found.is_empty():
		return false
	_path = found.points
	street = found.name
	_cum = TrafficGraph.cumulative(_path)
	return _cum[_cum.size() - 1] >= MIN_PATH


## The named street the car is on, from where it is onwards, joined up past
## its junctions as far as it goes straight on: {name, points}, or {}.
static func street_ahead(from: Vector3, heading: Vector2) -> Dictionary:
	var data := MapData.shared()
	if not data.is_loaded:
		return {}
	var g := data.routes
	var road := -1
	var s := 0.0
	for hit: Array in g.nearest(Vector2(from.x, from.z)):
		var r: int = hit[0]
		if float(hit[2]) < 8.0 and g.road_names[r] != "" and g.road_kinds[r] in KINDS:
			road = r
			s = hit[1]
			break
	if road < 0:
		return {}
	var street_name := g.road_names[road]
	var t := TrafficGraph.tangent_at(g.road_pts[road], g.road_cum[road], s)
	var way := 0 if Vector2(t.x, t.z).dot(heading) >= 0.0 else 1
	if way == 1 and g.road_oneway[road] == 1:
		return {}
	var points := PackedVector3Array()
	_add(points, _piece(g, road, s, g.road_len[road] if way == 0 else 0.0))
	var node := g.road_b[road] if way == 0 else g.road_a[road]
	var length := 0.0
	var seen := {road: true}
	while length < MAX_PATH and points.size() >= 2:
		var n := points.size()
		var arrive := Vector2(points[n - 1].x - points[n - 2].x, points[n - 1].z - points[n - 2].z).normalized()
		var best := -1
		var best_way := 0
		var best_dot := 0.8
		for r2: int in g.node_roads[node]:
			if seen.has(r2) or g.road_names[r2] != street_name:
				continue
			for w in 2:
				var end := g.road_a[r2] if w == 0 else g.road_b[r2]
				if end != node or (w == 1 and g.road_oneway[r2] == 1):
					continue
				var leave := g.road_dir_a[r2] if w == 0 else g.road_dir_b[r2]
				var d := arrive.dot(leave)
				if d > best_dot:
					best_dot = d
					best = r2
					best_way = w
		if best < 0:
			break
		seen[best] = true
		_add(points, _piece(g, best, 0.0 if best_way == 0 else g.road_len[best], g.road_len[best] if best_way == 0 else 0.0))
		node = g.road_b[best] if best_way == 0 else g.road_a[best]
		var cum := TrafficGraph.cumulative(points)
		length = cum[cum.size() - 1]
	if points.size() < 2:
		return {}
	return {"name": street_name, "points": points}


static func _piece(g: RouteGraph, r: int, s0: float, s1: float) -> PackedVector3Array:
	var pts := g.road_pts[r]
	var cum := g.road_cum[r]
	var lo := minf(s0, s1)
	var hi := maxf(s0, s1)
	var out := PackedVector3Array([TrafficGraph.point_at(pts, cum, lo)])
	for i in pts.size():
		if cum[i] > lo + 0.05 and cum[i] < hi - 0.05:
			out.append(pts[i])
	out.append(TrafficGraph.point_at(pts, cum, hi))
	if s1 < s0:
		out.reverse()
	return out


static func _add(into: PackedVector3Array, part: PackedVector3Array) -> void:
	for i in part.size():
		if not into.is_empty() and into[into.size() - 1].distance_squared_to(part[i]) < 0.25:
			continue
		into.append(part[i])


func _heading() -> Vector2:
	var f := -_car.global_basis.z
	return Vector2(f.x, f.z).normalized()


func _start() -> void:
	passes = 0
	_at = 0
	_s = 0.0
	_stopped = 0.0
	_against = 0.0
	_how = ""
	_rng.seed = hash(street)
	LateCity.fade_look(0.6, 2.5)
	LateCity.set_hiss(true)
	_three = _build_three()
	add_child(_three)
	_place(_s + AHEAD)


func _run(delta: float) -> void:
	if not driving():
		_let_go("")
		return
	_follow()
	var total := _cum[_cum.size() - 1]
	var p := _car.global_position
	var on := TrafficGraph.point_at(_path, _cum, _s)
	if Vector2(p.x - on.x, p.z - on.z).length() > OFF_STREET or _s > total - 5.0:
		_let_go("")
		return
	var t := TrafficGraph.tangent_at(_path, _cum, _s)
	_against = _against + delta if Vector2(t.x, t.z).dot(_heading()) < -0.3 else 0.0
	if _against > TURN_ROUND:
		_let_go("turned")
		return
	_stopped = _stopped + delta if speed_kmh() < STOPPED_KMH else 0.0
	if _stopped > STOPPED_FOR:
		_let_go("stopped")
		return
	if not _shown and _three_s - _s < REVEAL:
		_show(true)
	if _shown and _s - _three_s > PASSED:
		passes += 1
		if passes >= MAX_PASSES or _three_s + AHEAD > total - 10.0:
			_let_go("")
			return
		_show(false)
		_place(_s + AHEAD)
	_flicker(delta)


func _on_flash() -> void:
	_let_go("flashed")


## Where the car is along the path (it only goes forwards, a little at a time).
func _follow() -> void:
	var p := Vector2(_car.global_position.x, _car.global_position.z)
	var best := INF
	var best_i := _at
	var best_s := _s
	for i in range(maxi(_at - 2, 0), mini(_at + 30, _path.size() - 1)):
		var a := Vector2(_path[i].x, _path[i].z)
		var b := Vector2(_path[i + 1].x, _path[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			best_i = i
			best_s = _cum[i] + a.distance_to(q)
	_at = best_i
	_s = best_s


func _let_go(how: String) -> void:
	_how = how
	finish()
	if passes < 1:
		return
	Discoveries.discover("oddity/repeat_street")
	var times: String = ["once", "twice", "three times", "four times", "five times", "six times"][clampi(passes, 1, 6) - 1]
	var who := "the same parked car under the same flickering lamp" if Story.gentle() \
		else "the same parked car, the same man under the same flickering lamp"
	var out: String = {"stopped": " I stopped and I was through.", "flashed": " I flashed my lights and I was through.",
		"turned": " I turned round and it was an ordinary street."}.get(how, "")
	Story.log_night(StringName("repeat_street_%d" % GameClock.day),
		"On %s after midnight I passed %s, %s.%s" % [street, who, times, out])


func _stop() -> void:
	if _three:
		if _shown:
			LateCity.play_flicker(_three.global_position + Vector3.UP * 2.0)
		_three.queue_free()
		_three = null
	_shown = false


## Put the three at `s` along the street, hidden until the car's near.
func _place(s: float) -> void:
	_three_s = s
	var p := TrafficGraph.point_at(_path, _cum, s)
	var t := TrafficGraph.tangent_at(_path, _cum, s)
	var forward := Vector3(t.x, 0.0, t.z).normalized()
	var left := Vector3(forward.z, 0.0, -forward.x)
	_three.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), p)
	# Each on the ground where it stands: the car at the kerb, the lamp and
	# the man on the footpath behind it (streets aren't all one width).
	var kerb := _kerb(p, left)
	for child: Node3D in [_three.get_node(^"Car"), _three.get_node(^"Lamp"), _three.get_node_or_null(^"Man")]:
		if child == null:
			continue
		var side: float = child.get_meta(&"side")
		var at := p + left * (side + kerb - KERB)
		child.global_position = _ground(at)
	_show(false)


func _show(on: bool) -> void:
	_shown = on
	_three.visible = on
	if on:
		LateCity.play_flicker(_lamp.global_position)
		_flicker_t = 0.0


## The lamp coming on: a few stutters, then a slow uneven buzz.
func _flicker(delta: float) -> void:
	if not _shown:
		return
	_flicker_t += delta
	var on := true
	if _flicker_t < 0.9:
		on = fmod(_flicker_t, 0.22) < 0.11
	elif _rng.randf() < delta * 0.8:
		on = false
	_lamp.light_energy = 2.4 if on else 0.15
	_lamp_glow.visible = on


## How far out (m) the kerb on the left is: the first little step up from
## the road. KERB if it can't be found.
func _kerb(p: Vector3, left: Vector3) -> float:
	var road := _ground(p + left * 1.0).y
	var d := 2.0
	while d < 9.0:
		var step := _ground(p + left * d).y - road
		if step > 0.06 and step < 0.45:
			return d
		d += 0.25
	return KERB


func _ground(at: Vector3) -> Vector3:
	var space := _car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0)
	q.exclude = [_car.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else at


## The parked car, the lamp and the man, facing along the street.
func _build_three() -> Node3D:
	var root := Node3D.new()
	root.name = "RepeatStreet"
	var car := TrafficModels.model("sedan", TrafficModels.VEHICLE_DIR)
	if car == null:
		car = Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = TrafficModels.vehicle_mesh(&"sedan")
		car.add_child(mi)
	else:
		TrafficModels.recolour(car, {"Paint": CAR_PAINT})
	car.name = "Car"
	car.set_meta(&"side", CAR_SIDE)
	root.add_child(car)
	var lamp := Node3D.new()
	lamp.name = "Lamp"
	lamp.set_meta(&"side", LAMP_SIDE)
	root.add_child(lamp)
	var pole := TrafficModels.material(Color(0.32, 0.32, 0.3))
	_part(lamp, Vector3(0.14, 6.2, 0.14), Vector3(0, 3.1, 0), pole)
	# The arm reaches out over the road (+x: the street is to the lamp's right).
	_part(lamp, Vector3(1.8, 0.1, 0.12), Vector3(0.9, 6.15, 0), pole)
	_lamp_glow = _part(lamp, Vector3(0.5, 0.12, 0.26), Vector3(1.7, 6.05, 0), PS1Material.glowing(LAMP_LIGHT, 2.2))
	_lamp = OmniLight3D.new()
	_lamp.light_color = LAMP_LIGHT
	_lamp.light_energy = 2.4
	_lamp.omni_range = 14.0
	_lamp.omni_attenuation = 1.2
	_lamp.position = Vector3(1.7, 5.6, 0)
	lamp.add_child(_lamp)
	if not Story.gentle():
		var man := TrafficModels.person(_rng)
		man.name = "Man"
		man.set_meta(&"side", MAN_SIDE)
		# Facing the road, hands by his sides, a long dark coat.
		man.rotation.y = -PI * 0.5
		TrafficModels._add_part(man.get_node(^"Body"), "coat", Vector3(0.48, 0.95, 0.3), Vector3(0, 1.0, 0), Vector3.ZERO,
			TrafficModels.material(Color(0.14, 0.12, 0.1)))
		root.add_child(man)
	LateCity.add_shimmer(root, 0.6)
	return root


static func _part(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
