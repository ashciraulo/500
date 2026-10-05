class_name TrafficSchools
extends Node3D
## School zones: on school days, 7:30 to 9 and 2:30 to 4, the streets round
## each school drop to 40 km/h (Lane.zone_speed) behind flashing signs; a
## crossing guard in a hi-vis vest walks out with the STOP lollipop and sees
## the kids across, and parents double-park outside with their hazards on
## while a kid hops out.
##
## Schools come from the map's road data (`schools`, OSM amenity=school).
## Signs, guards and parents are only built near the player, and parents only
## turn up or go away out of the player's view.

## School zone times have started or finished (for the HUD and audio).
signal zone_changed(active: bool)
## A crossing guard has stepped out and stopped the traffic.
signal guard_out(position: Vector3)

const ZONE_SPEED := 40.0 / 3.6
## How far round a school its streets are a school zone.
const ZONE_RADIUS := 110.0
## How near the player a school has its signs, guard and parents.
const NEAR := 450.0
const GUARD_RANGE := 140.0
const KIDS_PER_CROSSING := 3
const WEEKDAY := 0
const FRIDAY := 1
const PARENT_TYPES := [[&"suv", 0.5], [&"hatch", 0.25], [&"sedan", 0.2], [&"ute", 0.05]]
const UNIFORMS := [Color(0.45, 0.62, 0.85), Color(0.12, 0.3, 0.2), Color(0.45, 0.1, 0.15), Color(0.85, 0.75, 0.25)]


## A gate the crossing guard closes: traffic stops at the line while the
## guard's out with the sign.
class GuardGate:
	extends TrafficGraph.Gate
	var closed := false

	func state() -> int:
		return STOP if closed else GO


## Someone standing in the road, for the traffic's obstacle scan.
class Obstacle:
	extends RefCounted
	var position := Vector3.ZERO
	var forward := Vector3.FORWARD
	var velocity := Vector3.ZERO
	var speed := 0.0
	var length := 0.9
	var width := 0.9


@export var enabled := true
@export var max_parents := 3
## Tests switch the school hours off (always a school zone).
@export var always_on := false

## { name, pos, lanes, edge, near, signs: [Node3D], guard: {} }
var schools: Array = []
## { school, lane, road_key, fwd, k, s, pos, dir, kerb, node, type, paint, kid, kid_t, time_left }
var parents: Array = []
var active := false
var stats := { "parents": 0, "crossings": 0, "kids": 0 }

var graph: TrafficGraph
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _version := -1
var _count := -1
var _blink := 0.0
var _hazard_on: Material
var _hazard_off: Material
var _lamp_on: Material
var _lamp_off: Material
var _body_pool: Array = []


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph
	_rng.randomize()
	_hazard_on = TrafficModels.material(Color(1.0, 0.6, 0.1), 3.0)
	_hazard_off = TrafficModels.material(Color(0.5, 0.3, 0.05))
	_lamp_on = TrafficModels.material(Color(1.0, 0.7, 0.15), 4.0)
	_lamp_off = TrafficModels.material(Color(0.35, 0.25, 0.08))


func _clock() -> Node:
	return get_node("/root/GameClock")


## Whether it's school zone time: school days (Monday to Friday) 7:30 to 9
## and 2:30 to 4.
func zone_hours() -> bool:
	if always_on:
		return true
	var clock := _clock()
	var kind: int = _manager.day_kind(clock.day)
	if kind != WEEKDAY and kind != FRIDAY:
		return false
	var h: float = clock.time_of_day
	return (h >= 7.5 and h < 9.0) or (h >= 14.5 and h < 16.0)


## The school zone limit at p in m/s right now, or 0 when p isn't in one
## (for the HUD, and for anything that books the player for speeding).
func zone_limit_at(p: Vector3) -> float:
	if not active:
		return 0.0
	for entry in graph.samples_near(p, 8.0):
		var lane: TrafficGraph.Lane = entry[0]
		if lane.zone_speed > 0.0 and lane.point(entry[1]).distance_to(p) < 6.0:
			return lane.zone_speed
	return 0.0


func update(delta: float, focus: Vector3) -> void:
	if graph == null:
		return
	_blink += delta
	var flash := fmod(_blink, 1.0) < 0.5
	var hazard := fmod(_blink, 0.8) < 0.4
	for school in schools:
		for sign in school.signs:
			var a: MeshInstance3D = sign.get_node("LampA")
			var b: MeshInstance3D = sign.get_node("LampB")
			a.material_override = _lamp_on if active and flash else _lamp_off
			b.material_override = _lamp_on if active and not flash else _lamp_off
		if not school.guard.is_empty():
			_update_guard(school, delta)
	for p in parents:
		var mesh: MeshInstance3D = p.node.get_node("Mesh")
		mesh.set_surface_override_material(TrafficModels.Surf.IND_L, _hazard_on if hazard else _hazard_off)
		mesh.set_surface_override_material(TrafficModels.Surf.IND_R, _hazard_on if hazard else _hazard_off)
		_update_kid(p, delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	if graph.version != _version or graph.schools.size() != _count:
		_version = graph.version
		_count = graph.schools.size()
		_relink()
	var now := enabled and zone_hours()
	if now != active:
		active = now
		zone_changed.emit(active)
	for school in schools:
		for lane in school.lanes:
			lane.zone_speed = ZONE_SPEED if active else 0.0
		_manage_school(school, focus)
	_manage_parents(focus)


func clear() -> void:
	for p in parents.duplicate():
		remove_parent(p)
	for school in schools:
		_tear_down(school)
		for lane in school.lanes:
			lane.zone_speed = 0.0


# --- Zones ----------------------------------------------------------------------

func _sources() -> Array:
	return graph.schools


## Lanes are rebuilt when map tiles arrive: work the zones out again.
func _relink() -> void:
	var old := {}
	for school in schools:
		old[school.name + str(school.pos)] = school
	var fresh: Array = []
	for src in _sources():
		var school: Dictionary = old.get(src.name + str(src.pos), {})
		old.erase(src.name + str(src.pos))
		if school.is_empty():
			school = { "name": src.name, "pos": src.pos, "lanes": [], "edge": null, "near": false, "signs": [], "guard": {} }
		for lane in school.lanes:
			lane.zone_speed = 0.0
		school.lanes = _zone_lanes(school.pos)
		if not school.lanes.is_empty():
			# Snap to the ground the streets are on.
			school.pos.y = school.lanes[0].pts[0].y
		var edge = _guard_crossing(school)
		if edge != school.edge:
			_remove_guard(school)
			school.edge = edge
		elif not school.guard.is_empty():
			_gate_crossing(school)
		if school.near:
			_remove_signs(school)
			_build_signs(school)
		fresh.append(school)
	for school in old.values():
		_tear_down(school)
		for lane in school.lanes:
			lane.zone_speed = 0.0
	schools = fresh
	for p in parents.duplicate():
		var lane := _find_lane(p.road_key, p.fwd, p.k)
		if lane == null:
			remove_parent(p)
			continue
		p.lane = lane
		p.s = TrafficGraph.closest_s(lane.pts, lane.cum, p.pos)
		_close_for(p)


func _zone_lanes(p: Vector3) -> Array:
	var roads := {}
	for entry in graph.samples_near(p, ZONE_RADIUS):
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null or lane.road.rank <= 0:
			continue
		var q := lane.point(entry[1])
		if Vector2(q.x - p.x, q.z - p.z).length() < ZONE_RADIUS:
			roads[lane.road] = true
	var lanes: Array = []
	for road in roads:
		# Freeways and highways keep their limit.
		if road.kind in [&"motorway", &"trunk", &"motorway_link", &"trunk_link"]:
			continue
		lanes.append_array(road.lanes)
	return lanes


## Whether a road is part of this school's zone.
static func _in_zone(school: Dictionary, road) -> bool:
	for lane in school.lanes:
		if lane.road == road:
			return true
	return false


func _manage_school(school: Dictionary, focus: Vector3) -> void:
	var d := Vector2(school.pos.x - focus.x, school.pos.z - focus.z).length()
	var near: bool = d < NEAR and not school.lanes.is_empty()
	if near and not school.near:
		school.near = true
		_build_signs(school)
	elif not near and school.near and d > NEAR + 100.0 and not _manager._visible(school.pos, 60.0):
		_tear_down(school)
	if school.near and active and school.edge != null and school.guard.is_empty():
		_add_guard(school)
	elif school.guard.size() > 0 and not active and school.guard.phase == &"wait" and not _manager._visible(school.guard.node.global_position, 20.0):
		_remove_guard(school)


func _tear_down(school: Dictionary) -> void:
	school.near = false
	_remove_signs(school)
	_remove_guard(school)


# --- Signs ----------------------------------------------------------------------

## A 40 sign facing the traffic on each street into the zone.
func _build_signs(school: Dictionary) -> void:
	var seen := {}
	for lane in school.lanes:
		var road = lane.road
		if lane.k != lane.count - 1 or lane.length < 20.0:
			continue
		var node = lane.from_node
		if node.degree() < 2:
			continue
		var into := false
		for r in node.roads:
			if r != road and not _in_zone(school, r):
				into = true
		if not into or seen.has([road, node]):
			continue
		seen[[road, node]] = true
		var s := minf(10.0, lane.length * 0.3)
		var dir: Vector3 = lane.tangent(s)
		var on_road := TrafficGraph.point_at(road.pts, road.cum, TrafficGraph.closest_s(road.pts, road.cum, lane.point(s)))
		var left := TrafficGraph.left_of(dir)
		var sign := school_sign()
		add_child(sign)
		sign.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), on_road + left * (road.half_width + 0.7))
		school.signs.append(sign)
		if school.signs.size() >= 10:
			return


func _remove_signs(school: Dictionary) -> void:
	for sign in school.signs:
		sign.queue_free()
	school.signs = []


## The flashing school zone sign: white with a red-ringed 40, the times
## underneath and two amber lamps on top (LampA, LampB). It faces +Z.
static func school_sign() -> Node3D:
	var root := Node3D.new()
	var grey := TrafficModels.material(Color(0.6, 0.6, 0.62))
	var white := TrafficModels.material(Color(0.92, 0.92, 0.9))
	var black := TrafficModels.material(Color(0.06, 0.06, 0.06))
	TrafficModels._add_part(root, "sz_pole", Vector3(0.08, 3.1, 0.08), Vector3(0, 1.55, 0), Vector3.ZERO, grey)
	TrafficModels._add_part(root, "sz_panel", Vector3(0.72, 1.12, 0.04), Vector3(0, 2.32, 0.05), Vector3.ZERO, white)
	TrafficModels._add_part(root, "sz_bar", Vector3(0.72, 0.16, 0.05), Vector3(0, 2.96, 0.05), Vector3.ZERO, black)
	for side in [-1.0, 1.0]:
		var lamp := TrafficModels._add_part(root, "sz_lamp", Vector3(0.16, 0.16, 0.06), Vector3(side * 0.22, 2.96, 0.08), Vector3.ZERO, TrafficModels.material(Color(0.35, 0.25, 0.08)))
		lamp.name = "LampA" if side < 0.0 else "LampB"
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.26
	torus.rings = 16
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = TrafficModels.material(Color(0.8, 0.08, 0.06))
	ring.rotation = Vector3(PI * 0.5, 0, 0)
	ring.position = Vector3(0, 2.36, 0.08)
	root.add_child(ring)
	_text(root, "SCHOOL ZONE", Vector3(0, 2.76, 0.075), 0.002)
	_text(root, "40", Vector3(0, 2.36, 0.075), 0.0068)
	_text(root, "7.30-9.00 AM\n2.30-4.00 PM\nSCHOOL DAYS", Vector3(0, 1.94, 0.075), 0.0021)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 260.0
	for child in root.find_children("*", "Label3D", true, false):
		child.visibility_range_end = 120.0
	return root


static func _text(parent: Node3D, text: String, pos: Vector3, pixel: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.pixel_size = pixel
	label.font_size = 48
	label.outline_size = 0
	label.modulate = Color(0.05, 0.05, 0.05)
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.line_spacing = -6.0
	parent.add_child(label)


# --- Crossing guards --------------------------------------------------------------

## The crossing the school's guard looks after: the nearest one without
## traffic lights (the lights do the job there).
func _guard_crossing(school: Dictionary) -> TrafficGraph.PedEdge:
	var best: TrafficGraph.PedEdge = null
	var best_d := GUARD_RANGE
	# Crossings link the footpaths' corners at the zone streets' junctions.
	var found := {}
	for lane in school.lanes:
		for fp in lane.road.footpaths:
			for pn in fp.ends.values():
				for e in pn.edges:
					if e.crossing:
						found[e] = true
	for edge in found:
		if not edge.crossing or edge.node == null or edge.road == null or edge.node.signal_controller:
			continue
		if not _in_zone(school, edge.road) or edge.length < 4.0:
			continue
		var mid := TrafficGraph.point_at(edge.pts, edge.cum, edge.length * 0.5)
		var d := Vector2(mid.x - school.pos.x, mid.z - school.pos.z).length()
		if d < best_d:
			best_d = d
			best = edge
	return best


func _add_guard(school: Dictionary) -> void:
	var edge: TrafficGraph.PedEdge = school.edge
	var near_a: bool = edge.pts[0].distance_to(school.pos) <= edge.pts[edge.pts.size() - 1].distance_to(school.pos)
	var node := _make_guard()
	add_child(node)
	var guard := { "node": node, "phase": &"wait", "t": 0.0, "wait": _rng.randf_range(6.0, 14.0),
		"from_a": near_a, "proxy": Obstacle.new(), "gates": [], "kids": [], "step": 0.0 }
	school.guard = guard
	_gate_crossing(school)
	_place_guard(school, 0.0)


func _remove_guard(school: Dictionary) -> void:
	var guard: Dictionary = school.guard
	if guard.is_empty():
		return
	_open_gates(guard)
	_manager.obstacles.erase(guard.proxy)
	for kid in guard.kids:
		_manager.obstacles.erase(kid.proxy)
		kid.node.queue_free()
	guard.node.queue_free()
	school.guard = {}


## Gates on the street the crossing goes over: at the line on the way into
## the junction, and on the moves out of it across the crossing.
func _gate_crossing(school: Dictionary) -> void:
	var guard: Dictionary = school.guard
	var was_closed := false
	for pair in guard.gates:
		was_closed = was_closed or pair[1].closed
	_open_gates(guard)
	var edge: TrafficGraph.PedEdge = school.edge
	var mid := TrafficGraph.point_at(edge.pts, edge.cum, edge.length * 0.5)
	for lane in edge.road.lanes_into(edge.node):
		var s := TrafficGraph.closest_s(lane.pts, lane.cum, mid)
		_add_gate(guard, lane, maxf(s - 3.5, 0.0), was_closed)
	for out in edge.road.lanes_from(edge.node):
		for c in edge.node.connectors:
			if not c.next.is_empty() and c.next[0] == out and c.in_lane and c.in_lane.road != edge.road:
				_add_gate(guard, c, 0.0, was_closed)


func _add_gate(guard: Dictionary, lane: TrafficGraph.Lane, s: float, closed: bool) -> void:
	var gate := GuardGate.new()
	gate.closed = closed
	lane.add_stop(s, gate)
	guard.gates.append([lane, gate])


func _open_gates(guard: Dictionary) -> void:
	for pair in guard.gates:
		var lane: TrafficGraph.Lane = pair[0]
		var gate: GuardGate = pair[1]
		lane.stops = lane.stops.filter(func(st): return st.gate != gate)
	guard.gates = []


func _set_gates(guard: Dictionary, closed: bool) -> void:
	for pair in guard.gates:
		pair[1].closed = closed


## Whether the guard has traffic stopped right now (tests).
func guard_stopping(school: Dictionary) -> bool:
	var guard: Dictionary = school.guard
	return not guard.is_empty() and guard.gates.size() > 0 and guard.gates[0][1].closed


## The guard waits at the kerb with the sign down while the kids gather; when
## the road's clear they step out to the middle, hold the sign up while the
## kids cross, then walk back and let the traffic go.
func _update_guard(school: Dictionary, delta: float) -> void:
	var guard: Dictionary = school.guard
	var edge: TrafficGraph.PedEdge = school.edge
	guard.t += delta
	match guard.phase:
		&"wait":
			if guard.kids.size() < KIDS_PER_CROSSING and active and fmod(guard.t, 2.5) < delta:
				_add_kid(school)
			if active and guard.t >= guard.wait and guard.kids.size() > 0 and _manager._crossing_safe(edge):
				guard.phase = &"out"
				guard.t = 0.0
				_set_gates(guard, true)
				_manager.obstacles.append(guard.proxy)
				stats.crossings += 1
				guard_out.emit(guard.node.global_position)
				_sound("traffic/traffic_guard_whistle", guard.node.global_position, -2.0)
		&"out":
			if guard.t >= 2.6:
				guard.phase = &"hold"
				guard.t = 0.0
				for kid in guard.kids:
					kid.walking = true
					_manager.obstacles.append(kid.proxy)
		&"hold":
			var across := true
			for kid in guard.kids:
				across = across and kid.t >= 1.0
			if across and guard.t > 2.0:
				for kid in guard.kids:
					_manager.obstacles.erase(kid.proxy)
					kid.node.queue_free()
					stats.kids += 1
				guard.kids = []
				guard.phase = &"back"
				guard.t = 0.0
		&"back":
			if guard.t >= 2.6:
				guard.phase = &"wait"
				guard.t = 0.0
				guard.wait = _rng.randf_range(10.0, 25.0)
				_set_gates(guard, false)
				_manager.obstacles.erase(guard.proxy)
	for kid in guard.kids:
		_update_crossing_kid(school, kid, delta)
	_place_guard(school, delta)


## Where along the crossing the guard is: 0 at the kerb, 0.5 the middle.
func _guard_u(guard: Dictionary) -> float:
	match guard.phase:
		&"out":
			return 0.5 * smoothstep(0.0, 2.6, guard.t)
		&"hold":
			return 0.5
		&"back":
			return 0.5 * (1.0 - smoothstep(0.0, 2.6, guard.t))
	return 0.0


func _crossing_point(edge: TrafficGraph.PedEdge, from_a: bool, u: float) -> Vector3:
	var s := edge.length * (u if from_a else 1.0 - u)
	return TrafficGraph.point_at(edge.pts, edge.cum, s)


func _place_guard(school: Dictionary, delta: float) -> void:
	var guard: Dictionary = school.guard
	var edge: TrafficGraph.PedEdge = school.edge
	var node: Node3D = guard.node
	var u := _guard_u(guard)
	var p := _crossing_point(edge, guard.from_a, u)
	var across := (_crossing_point(edge, guard.from_a, 1.0) - _crossing_point(edge, guard.from_a, 0.0))
	across.y = 0.0
	across = across.normalized()
	var walking: bool = guard.phase == &"out" or guard.phase == &"back"
	# Out in the road: face the traffic coming up the street to the junction.
	var look := across if guard.phase == &"out" else (-across if guard.phase == &"back" else (edge.road.direction_from(edge.node) if guard.phase == &"hold" else -across))
	node.global_position = p
	if look.length() > 0.1:
		node.basis = Basis.looking_at(look, Vector3.UP)
	guard.step += delta * (7.0 if walking else 0.0)
	_swing(node.get_node("Body"), sin(guard.step) * 0.5 if walking else 0.0)
	var raised: bool = guard.phase != &"wait"
	var sign: Node3D = node.get_node("Lollipop")
	sign.position.y = lerpf(sign.position.y, 0.35 if raised else 0.0, minf(delta * 4.0, 1.0))
	var proxy: Obstacle = guard.proxy
	proxy.position = p
	proxy.forward = look if look.length() > 0.1 else Vector3.FORWARD
	proxy.length = 1.4
	proxy.width = 1.4


func _make_guard() -> Node3D:
	var person := TrafficModels.person(_rng)
	var body: Node3D = person.get_node("Body")
	var vis := TrafficModels.material(Color(1.0, 0.5, 0.08), 0.3)
	TrafficModels._add_part(body, "vest", Vector3(0.45, 0.42, 0.27), Vector3(0, 1.24, 0), Vector3.ZERO, vis)
	TrafficModels._add_part(body, "vest_band", Vector3(0.46, 0.05, 0.28), Vector3(0, 1.14, 0), Vector3.ZERO, TrafficModels.material(Color(0.85, 0.85, 0.8), 0.6))
	var white := TrafficModels.material(Color(0.92, 0.92, 0.9))
	TrafficModels._add_part(body, "hat", Vector3(0.3, 0.1, 0.3), Vector3(0, 1.8, 0.0), Vector3.ZERO, white)
	TrafficModels._add_part(body, "hat_brim", Vector3(0.42, 0.02, 0.42), Vector3(0, 1.76, 0.0), Vector3.ZERO, white)
	# The STOP lollipop, held upright in the right hand (+Z faces where
	# they're looking, so the sign reads to the traffic they face).
	var pop := Node3D.new()
	pop.name = "Lollipop"
	person.add_child(pop)
	TrafficModels._add_part(pop, "pop_pole", Vector3(0.04, 1.6, 0.04), Vector3(0.36, 0.95, -0.12), Vector3.ZERO, TrafficModels.material(Color(0.75, 0.75, 0.75)))
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.03
	cyl.radial_segments = 12
	cyl.rings = 1
	disc.mesh = cyl
	disc.material_override = TrafficModels.material(Color(0.82, 0.08, 0.06))
	disc.rotation = Vector3(PI * 0.5, 0, 0)
	disc.position = Vector3(0.36, 1.98, -0.12)
	pop.add_child(disc)
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "STOP"
		label.font_size = 48
		label.pixel_size = 0.0042
		label.outline_size = 0
		label.modulate = Color(0.95, 0.95, 0.95)
		label.double_sided = false
		label.position = Vector3(0.36, 1.98, -0.12 + side * 0.02)
		label.rotation = Vector3(0, 0 if side < 0.0 else PI, 0)
		label.visibility_range_end = 80.0
		pop.add_child(label)
	for child in person.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 220.0
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return person


func _make_kid() -> Node3D:
	var kid := TrafficModels.person(_rng)
	kid.scale = Vector3.ONE * _rng.randf_range(0.6, 0.72)
	var body: Node3D = kid.get_node("Body")
	var uniform := TrafficModels.material(UNIFORMS[_rng.randi() % UNIFORMS.size()])
	(body.get_child(0) as MeshInstance3D).material_override = uniform
	for arm in ["ArmL", "ArmR"]:
		(body.get_node(arm).get_child(0) as MeshInstance3D).material_override = uniform
	var bag := TrafficModels.material([Color(0.15, 0.3, 0.7), Color(0.8, 0.2, 0.4), Color(0.2, 0.2, 0.22), Color(0.95, 0.6, 0.1)][_rng.randi() % 4])
	TrafficModels._add_part(body, "schoolbag", Vector3(0.36, 0.42, 0.18), Vector3(0, 1.2, 0.22), Vector3.ZERO, bag)
	TrafficModels._add_part(body, "kid_hat", Vector3(0.3, 0.1, 0.3), Vector3(0, 1.8, 0), Vector3.ZERO, uniform)
	return kid


## A kid turns up at the kerb by the guard to wait for the crossing.
func _add_kid(school: Dictionary) -> void:
	var guard: Dictionary = school.guard
	var node := _make_kid()
	add_child(node)
	var proxy := Obstacle.new()
	proxy.length = 0.7
	proxy.width = 0.7
	var kid := { "node": node, "t": 0.0, "walking": false, "phase": _rng.randf() * TAU,
		"offset": (guard.kids.size() - 1) * 0.8, "speed": _rng.randf_range(0.9, 1.25), "proxy": proxy }
	guard.kids.append(kid)
	_update_crossing_kid(school, kid, 0.0)


func _update_crossing_kid(school: Dictionary, kid: Dictionary, delta: float) -> void:
	var guard: Dictionary = school.guard
	var edge: TrafficGraph.PedEdge = school.edge
	if kid.walking:
		kid.t = minf(kid.t + delta * kid.speed / maxf(edge.length + 1.5, 1.0), 1.0)
	var a := _crossing_point(edge, guard.from_a, 0.0)
	var b := _crossing_point(edge, guard.from_a, 1.0)
	var across := b - a
	across.y = 0.0
	across = across.normalized()
	var side := TrafficGraph.left_of(across)
	# Waiting just behind the kerb, then across, a little apart.
	var p: Vector3 = a.lerp(b, kid.t) + side * kid.offset - (across * 0.8 if kid.t <= 0.0 else Vector3.ZERO)
	var node: Node3D = kid.node
	node.global_position = p
	var walking: bool = kid.walking and kid.t < 1.0
	node.basis = Basis.looking_at(across, Vector3.UP)
	kid.phase += delta * (8.0 if walking else 0.0)
	_swing(node.get_node("Body"), sin(kid.phase) * 0.5 if walking else 0.0)
	kid.proxy.position = p
	kid.proxy.forward = across


static func _swing(body: Node3D, swing: float) -> void:
	body.get_node("LegL").rotation.x = swing
	body.get_node("LegR").rotation.x = -swing
	body.get_node("ArmL").rotation.x = -swing * 0.7
	body.get_node("ArmR").rotation.x = swing * 0.7


# --- The school run ---------------------------------------------------------------

## Whether a parent could stop on `lane` at `s` with the hazards on: the kerb
## lane of a zone street, clear of junctions, stops and anyone close behind.
func parent_fits(lane: TrafficGraph.Lane, s: float) -> bool:
	if lane.connector or lane.road == null or lane.road.roundabout or not lane.closed.is_empty():
		return false
	if lane.k != lane.count - 1 or s < 25.0 or s > lane.length - 25.0:
		return false
	for stop in lane.stops:
		if absf(stop.s - s) < 22.0:
			return false
	for kc in graph.keep_clear_on(lane):
		if s > kc[0] - 15.0 and s < kc[1] + 15.0:
			return false
	for v in lane.vehicles:
		if v.s > s - 35.0 and v.s < s + 12.0:
			return false
	for p in parents:
		if p.lane == lane and absf(p.s - s) < 30.0:
			return false
	return true


## Stop a parent's car on `lane` at `s` (its middle). Returns it, or {}.
func add_parent(lane: TrafficGraph.Lane, s: float, seconds := -1.0) -> Dictionary:
	if not parent_fits(lane, s):
		return {}
	var type := _pick_type()
	var node: StaticBody3D = _body_pool.pop_back() if not _body_pool.is_empty() and _body_pool[-1].get_meta("traffic") == type else null
	if node == null:
		node = _manager.kerbside._make_body(type)
		add_child(node)
	var paint := TrafficModels.pick_paint(_rng)
	var mesh: MeshInstance3D = node.get_node("Mesh")
	mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(paint))
	# Nobody can get past on a one-lane street: those stops are quick.
	var one_lane := lane.left_lane == null and lane.right_lane == null
	var p := { "lane": lane, "road_key": lane.road.key, "fwd": lane.from_node == lane.road.a, "k": lane.k,
		"s": s, "node": node, "type": type, "paint": paint, "kid": _make_kid(), "kid_t": 0.0, "kid_phase": 0.0,
		"time_left": seconds if seconds > 0.0 else (_rng.randf_range(12.0, 22.0) if one_lane else _rng.randf_range(25.0, 50.0)),
		"stuck": 0.0 }
	add_child(p.kid)
	_close_for(p)
	node.visible = true
	node.collision_layer = _manager.TRAFFIC_LAYER
	_manager.kerbside._hazard_ticks(node)
	_sound("traffic/traffic_taxi_door_close", p.pos, -8.0)
	parents.append(p)
	stats.parents += 1
	return p


func remove_parent(p: Dictionary) -> void:
	parents.erase(p)
	var lane: TrafficGraph.Lane = p.lane
	if lane and not lane.closed.is_empty() and lane.closed[0] <= p.s and lane.closed[1] >= p.s:
		lane.closed = []
	_manager.kerbside._release_body(p.node, _body_pool)
	if p.kid:
		p.kid.queue_free()


## Kid's out: hazards off and away. Returns the moving car, or null when
## there's no room to pull out yet.
func parent_drive_off(p: Dictionary) -> TrafficVehicle:
	var lane: TrafficGraph.Lane = p.lane
	for v in lane.vehicles:
		if v.s > p.s - 16.0 and v.s < p.s + 8.0:
			return null
	var paint: Color = p.paint
	var s: float = p.s
	var type: StringName = p.type
	remove_parent(p)
	var moving: TrafficVehicle = _manager.spawn_vehicle_at(type, lane, s, 0.0)
	if moving:
		moving.paint = paint
		moving.mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(paint))
		moving.indicator = 1
	return moving


func _close_for(p: Dictionary) -> void:
	var lane: TrafficGraph.Lane = p.lane
	var s: float = p.s
	var length: float = TrafficModels.TYPES[p.type].length
	var dir := lane.tangent(s)
	var kerb := TrafficGraph.left_of(dir)
	p.pos = lane.point(s) + kerb * 0.5
	p.dir = dir
	p.kerb = kerb
	p.node.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p.pos)
	lane.closed = [maxf(s - length * 0.5 - 12.0, 0.0), s + length * 0.5 + 1.0]


func _pick_type() -> StringName:
	var r := _rng.randf()
	for entry in PARENT_TYPES:
		r -= entry[1]
		if r <= 0.0:
			return entry[0]
	return &"suv"


## The kid gets out of the back seat on the kerb side, walks onto the
## footpath and off towards the school gate.
func _update_kid(p: Dictionary, delta: float) -> void:
	var kid: Node3D = p.kid
	if kid == null:
		return
	p.kid_t += delta
	var door: Vector3 = p.pos - p.dir * 0.6 + p.kerb * 1.1
	var path: Vector3 = p.pos - p.dir * 0.6 + p.kerb * 4.2
	var pos: Vector3
	var look: Vector3
	var walking := true
	if p.kid_t < 1.2:
		pos = door
		look = p.kerb
		walking = false
	elif p.kid_t < 4.2:
		pos = door.lerp(path, (p.kid_t - 1.2) / 3.0)
		look = p.kerb
	else:
		var school_dir: Vector3 = p.dir
		var to_school: Vector3 = p.get("school_pos", p.pos) - path
		if to_school.dot(p.dir) < 0.0:
			school_dir = -p.dir
		pos = path + school_dir * (p.kid_t - 4.2) * 1.1
		look = school_dir
		if p.kid_t > 14.0:
			kid.visible = false
	kid.global_position = pos
	kid.basis = Basis.looking_at(look, Vector3.UP)
	p.kid_phase += delta * (8.0 if walking else 0.0)
	_swing(kid.get_node("Body"), sin(p.kid_phase) * 0.5 if walking else 0.0)


func _manage_parents(focus: Vector3) -> void:
	for p in parents.duplicate():
		p.time_left -= 1.0
		var far: bool = p.pos.distance_to(focus) > NEAR + 150.0
		if far and not _manager._visible(p.pos, 10.0):
			remove_parent(p)
		elif p.time_left <= 0.0 and p.kid_t > 4.5:
			if not _manager._visible(p.pos, 10.0) and p.pos.distance_to(focus) > 150.0:
				remove_parent(p)
			elif parent_drive_off(p) == null:
				p.stuck += 1.0
				if p.stuck > 20.0 and not _manager._visible(p.pos, 10.0):
					remove_parent(p)
	if not active or not enabled or parents.size() >= max_parents:
		return
	for school in schools:
		if not school.near or school.lanes.is_empty():
			continue
		for attempt in 4:
			var lane: TrafficGraph.Lane = school.lanes[_rng.randi() % school.lanes.size()]
			if lane.length < 60.0:
				continue
			var s := _rng.randf_range(25.0, lane.length - 25.0)
			var pos := lane.point(s)
			if pos.distance_to(focus) < 40.0 or _manager._visible(pos, 10.0):
				continue
			var p := add_parent(lane, s)
			if not p.is_empty():
				p.school_pos = school.pos
				return


func _find_lane(road_key: String, fwd: bool, k: int) -> TrafficGraph.Lane:
	for road in graph.roads:
		if road.key == road_key:
			for lane in road.lanes:
				if (lane.from_node == road.a) == fwd and lane.k == k:
					return lane
	return null


## The audio thread's sounds, once they're in.
func _sound(sound_name: String, p: Vector3, db: float) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has(sound_name):
		audio.play_at(sound_name, p, db, "SFX")
