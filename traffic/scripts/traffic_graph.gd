class_name TrafficGraph
extends RefCounted
## Lane-level road network for traffic, built from the map's road data.
##
## Input is a plain Dictionary (see docs/TRAFFIC.md for the format): nodes with
## ids and positions, roads between two node ids with a centreline polyline,
## plus optional rail lines, footways, bus stops and stations. `add_data()` can
## be called again as more map tiles load; roads join on shared node ids.
##
## From that the graph builds:
## - Lanes: one per lane per direction, offset to the LEFT of the centreline
##   (Australia drives on the left), trimmed back from junctions.
## - Connectors: short curved lanes across each junction, with turn rules
##   (left turns from the kerb lane, right turns from the lane by the centre
##   line) and who gives way to whom.
## - Signal controllers for junctions tagged `signals`.
## - A pedestrian network along both footpaths of each street, with corner and
##   crossing links at junctions, plus any footways in the data.
## - A rail network for trains, stations and level crossings.
##
## World axes match the game: -Z north, +X east, +Y up. Units are metres.

const LANE_WIDTH := 3.2
## Extra tarmac outside the kerb lanes, per side.
const SHOULDER := 0.4
const FOOTPATH_GAP := 1.5
const SAMPLE_STEP := 12.0
const CELL := 64.0

enum Turn { STRAIGHT, LEFT, RIGHT, UTURN }

## rank: priority at junctions. speed: default km/h. walk: has footpaths.
const KINDS := {
	&"motorway": { "rank": 7, "speed": 100.0, "walk": false },
	&"motorway_link": { "rank": 6, "speed": 70.0, "walk": false },
	&"trunk": { "rank": 6, "speed": 80.0, "walk": false },
	&"trunk_link": { "rank": 5, "speed": 60.0, "walk": false },
	&"primary": { "rank": 5, "speed": 60.0, "walk": true },
	&"primary_link": { "rank": 4, "speed": 50.0, "walk": true },
	&"secondary": { "rank": 4, "speed": 60.0, "walk": true },
	&"secondary_link": { "rank": 3, "speed": 50.0, "walk": true },
	&"tertiary": { "rank": 3, "speed": 50.0, "walk": true },
	&"tertiary_link": { "rank": 3, "speed": 40.0, "walk": true },
	&"unclassified": { "rank": 2, "speed": 50.0, "walk": true },
	&"residential": { "rank": 2, "speed": 50.0, "walk": true },
	&"living_street": { "rank": 1, "speed": 10.0, "walk": true },
	&"service": { "rank": 1, "speed": 20.0, "walk": false },
}


class GNode:
	var id: int
	var pos: Vector3
	## &"", &"signals", &"give_way" or &"stop".
	var ctrl: StringName = &""
	var roads: Array = []
	## How far lanes stop short of the node, so connectors have room to turn.
	var radius := 0.0
	var signal_controller: SignalController
	## Roads that must give way here (explicit give_way/stop tags nearby).
	var minor_roads := {}
	var stop_roads := {}
	var connectors: Array = []

	func degree() -> int:
		return roads.size()


class Road:
	var index: int
	var key: String
	var a: GNode
	var b: GNode
	var pts: PackedVector3Array
	var cum: PackedFloat32Array
	var length := 0.0
	var kind: StringName
	var rank := 2
	var lanes_fwd := 1
	var lanes_back := 1
	var speed := 13.9
	var roundabout := false
	## A painted bike lane (OSM cycleway=lane/track): cyclists favour it.
	var bike_lane := false
	var walk := true
	var half_width := 3.6
	var footpath_offset := 5.0
	var lanes: Array = []
	var footpaths: Array = []
	var name := ""

	func other(n: GNode) -> GNode:
		return b if n == a else a

	## Unit horizontal vector pointing away from `n` along the road.
	func direction_from(n: GNode) -> Vector3:
		var d: Vector3
		if n == a:
			d = TrafficGraph.point_at(pts, cum, minf(8.0, length * 0.5)) - pts[0]
		else:
			d = TrafficGraph.point_at(pts, cum, maxf(length - 8.0, length * 0.5)) - pts[pts.size() - 1]
		d.y = 0.0
		return d.normalized()

	func lanes_into(n: GNode) -> Array:
		return lanes.filter(func(l): return l.to_node == n)

	func lanes_from(n: GNode) -> Array:
		return lanes.filter(func(l): return l.from_node == n)


class Lane:
	var id: int
	## The road this lane belongs to; null for junction connectors.
	var road: Road
	var from_node: GNode
	var to_node: GNode
	## Lane index counted from the right (0 = next to the centre line or the
	## right-hand edge of a one-way road); count - 1 is the kerb lane.
	var k := 0
	var count := 1
	var pts: PackedVector3Array
	var cum: PackedFloat32Array
	var length := 0.0
	## m/s
	var speed := 13.9
	## For road lanes: connectors leaving the end. For connectors: [out lane].
	var next: Array = []
	var connector := false
	var turn := Turn.STRAIGHT
	## Connectors only: the lane we came from and the junction node.
	var in_lane: Lane
	var node: GNode
	## Connectors only: lanes whose traffic has right of way over this move.
	var yield_to: Array = []
	## Connectors only: come to a full stop before entering (stop sign).
	var full_stop := false
	## Connectors only: other connectors at the same junction whose paths
	## cross or merge with this one. Don't enter while one is occupied.
	var conflicts: Array = []
	## Things that can halt traffic along this lane: [{s, gate}], sorted by s.
	var stops: Array = []
	## Cached TrafficGraph.reach() and the graph version it was worked out for.
	var reach := 0.0
	var reach_version := -1
	## [s0, s1] coned off for roadworks (empty when open; see TrafficRoadworks).
	var closed: Array = []
	## [s0, s1] stretches of this lane inside keep-clear boxes (see keep_clear_on).
	var keep_clear: Array = []
	var keep_clear_version := -1
	## Vehicles currently registered on this lane (managed by the traffic sim).
	var vehicles: Array = []
	## Parallel lanes in the same direction (for lane changes).
	var left_lane: Lane
	var right_lane: Lane
	## Signal approach at the end of the lane, if any.
	var signal_gate: SignalGate

	func point(s: float) -> Vector3:
		return TrafficGraph.point_at(pts, cum, s)

	func tangent(s: float) -> Vector3:
		return TrafficGraph.tangent_at(pts, cum, s)

	func set_points(p: PackedVector3Array) -> void:
		pts = p
		cum = TrafficGraph.cumulative(p)
		length = cum[cum.size() - 1] if cum.size() > 0 else 0.0

	func add_stop(s: float, gate: RefCounted) -> void:
		stops.append({ "s": s, "gate": gate })
		stops.sort_custom(func(x, y): return x.s < y.s)


## Anything that stops traffic at a point on a lane.
class Gate:
	extends RefCounted
	const GO := 0
	const AMBER := 1
	const STOP := 2

	func state() -> int:
		return GO

	## Buses only, for bus stops.
	func buses_only() -> bool:
		return false


class SignalGate:
	extends Gate
	var controller: SignalController
	var group := 0

	func _init(c: SignalController, g: int) -> void:
		controller = c
		group = g

	func state() -> int:
		return controller.state_for(group)


## Fixed-time traffic lights for one junction (or a cluster of nodes that make
## up one junction, e.g. where two dual carriageways cross). Approaches are
## split into two groups by axis; each group gets green, amber, then all-red.
class SignalController:
	var nodes: Array = []
	var center := Vector3.ZERO
	var axis := Vector3.RIGHT
	var green := PackedFloat32Array([22.0, 16.0])
	const AMBER_TIME := 3.5
	const ALL_RED := 2.0
	var phase := 0
	var timer := 0.0
	var changed_this_frame := false
	## Set once the lights first run. A map tile adding a road to the set
	## later must not restart the cycle or swap which way is green: cars
	## already committed on green would suddenly face a red.
	var running := false
	## Rank of the biggest road through the lights so far.
	var axis_rank := -1
	## Gates and lanes per group, for pedestrians and visuals.
	var approaches: Array = []

	func phase_length(p: int) -> float:
		match p % 3:
			0: return green[p / 3]
			1: return AMBER_TIME
			_: return ALL_RED

	func update(dt: float) -> void:
		changed_this_frame = false
		timer += dt
		while timer >= phase_length(phase):
			timer -= phase_length(phase)
			phase = (phase + 1) % 6
			changed_this_frame = true

	func state_for(group: int) -> int:
		var active := phase / 3
		if active != group:
			return Gate.STOP
		match phase % 3:
			0: return Gate.GO
			1: return Gate.AMBER
			_: return Gate.STOP

	func group_for(direction: Vector3) -> int:
		return 0 if absf(direction.dot(axis)) >= 0.7071 else 1


class BusStopGate:
	extends Gate
	var pos: Vector3

	func state() -> int:
		return STOP

	func buses_only() -> bool:
		return true


class LevelCrossing:
	extends Gate
	var pos: Vector3
	## Direction of the rail line through the crossing.
	var rail_dir := Vector3.FORWARD
	var rail_edge: RailEdge
	var rail_s := 0.0
	var roads: Array = []
	var closed := false
	## 0 open .. 1 down, animated by the manager.
	var boom := 0.0

	func state() -> int:
		return STOP if closed else GO


class PedNode:
	var pos: Vector3
	var edges: Array = []


class PedEdge:
	var a: PedNode
	var b: PedNode
	var pts: PackedVector3Array
	var cum: PackedFloat32Array
	var length := 0.0
	## Crossing a road at a junction: pedestrians check for traffic first.
	var crossing := false
	var road: Road
	var node: GNode
	## Footpaths: which PedNode sits at each end of the road (GNode -> PedNode).
	var ends := {}

	func other(n: PedNode) -> PedNode:
		return b if n == a else a


class RailNode:
	var pos: Vector3
	var edges: Array = []


class RailEdge:
	var a: RailNode
	var b: RailNode
	var pts: PackedVector3Array
	var cum: PackedFloat32Array
	var length := 0.0
	## [{s, name}] along the edge.
	var stations: Array = []
	var crossings: Array = []

	func other(n: RailNode) -> RailNode:
		return b if n == a else a


var nodes := {}
var roads: Array = []
var lanes: Array = []
## Every junction connector (gathered from the nodes when asked; tests and
## debugging only, so adding a map tile doesn't walk the whole list).
var connectors: Array:
	get:
		if _connectors_dirty:
			_connectors_dirty = false
			_connectors = []
			for id in nodes:
				_connectors.append_array(nodes[id].connectors)
		return _connectors
var _connectors: Array = []
var _connectors_dirty := false
var signal_controllers: Array = []
var ped_nodes: Array = []
var ped_edges: Array = []
var rail_nodes: Array = []
var rail_edges: Array = []
var crossings: Array = []
var bus_stops: Array = []
var stations: Array = []
## Parking spots from the map: { pos, yaw, kind, seed }. See TrafficParking.
var parking: Array = []
## Boxes traffic mustn't stop in, like a driveway it would block: { pos, radius }.
var keep_clear: Array = []
## Bus routes from the map: ref -> { ref, name, colour, roads: { road id: true } }.
var bus_routes := {}

## Bumped whenever roads are added, so cached route facts get refreshed.
var version := 0
var _road_keys := {}
var _pending_bus_stops: Array = []
var _parking_keys := {}
var _parking_cells := {}
var _lane_cells := {}
var _ped_cells := {}
var _rail_cells := {}
var _ped_node_cells := {}
var _rail_node_cells := {}
var _next_lane_id := 1
## Connectors and gates replaced by a rebuild (see dispose).
var _dropped: Array = []
var _next_synthetic_id := -1


# --- Teardown -----------------------------------------------------------------

## Break every reference cycle among the graph's objects (lanes and their
## roads, nodes and connectors, gates and controllers, and whatever in
## `extra` points into them, such as vehicles), so they're all freed when
## the graph goes. RefCounted cycles otherwise outlive the game and trip
## Godot up at exit. The graph is empty and unusable afterwards.
func dispose(extra: Array = []) -> void:
	var seen := {}
	var queue: Array = []
	var roots: Array = [nodes, roads, lanes, connectors, signal_controllers, ped_nodes, ped_edges, rail_nodes,
		rail_edges, crossings, bus_stops, stations, parking, keep_clear, bus_routes, _dropped, extra]
	for r in roots:
		_collect(r, seen, queue)
	while not queue.is_empty():
		var obj: Object = queue.pop_back()
		for prop in obj.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			_collect(obj.get(prop.name), seen, queue)
	for obj in seen:
		for prop in obj.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var value = obj.get(prop.name)
			if value is Array or value is Dictionary:
				value.clear()
			elif value is RefCounted and not value is Resource:
				obj.set(prop.name, null)
	for r in roots:
		r.clear()
	for d in [_road_keys, _parking_keys, _parking_cells, _lane_cells, _ped_cells, _rail_cells, _ped_node_cells, _rail_node_cells]:
		d.clear()
	_connectors.clear()
	_pending_bus_stops.clear()


static func _collect(value, seen: Dictionary, queue: Array) -> void:
	if value is Array:
		for v in value:
			_collect(v, seen, queue)
	elif value is Dictionary:
		for k in value:
			_collect(k, seen, queue)
			_collect(value[k], seen, queue)
	elif value is RefCounted and not value is Resource and not seen.has(value):
		seen[value] = true
		queue.append(value)


# --- Building -----------------------------------------------------------------

## Merge map data into the graph. Returns the number of roads added.


func add_data(data: Dictionary) -> int:
	for n in data.get("nodes", []):
		var id := int(n.id)
		var gnode: GNode = nodes.get(id)
		if gnode == null:
			gnode = GNode.new()
			gnode.id = id
			nodes[id] = gnode
		gnode.pos = _vec(n.p)
		gnode.ctrl = StringName(n.get("ctrl", ""))

	var dirty := {}
	var added: Array = []
	for r in data.get("roads", []):
		var road := _make_road(r)
		if road == null:
			continue
		added.append(road)
		dirty[road.a] = true
		dirty[road.b] = true

	for p in data.get("parking", []):
		_add_parking(p)
	for r in data.get("bus_routes", []):
		_add_bus_route(r)
	for k in data.get("keep_clear", []):
		add_keep_clear(_vec(k.p), float(k.get("radius", 6.0)))
	if not added.is_empty():
		version += 1
		_mark_minor_approaches(dirty.keys())
		for node in dirty.keys():
			_compute_radius(node)
		# Roads touching a dirty node get their lanes (re)built.
		var rebuild := {}
		for node in dirty.keys():
			for road in node.roads:
				rebuild[road] = true
		for road in rebuild.keys():
			_build_lanes(road)
		# Lanes were rebuilt at both ends of those roads, so the junctions at
		# both ends need their connectors redone too.
		var junctions := dirty.duplicate()
		for road in rebuild.keys():
			junctions[road.a] = true
			junctions[road.b] = true
		_connectors_dirty = true
		for node in junctions.keys():
			_build_connectors(node)
		for node in junctions.keys():
			_find_conflicts(node)
		_build_signals(junctions.keys())
		for road in added:
			_index_road(road)
			_build_footpaths(road)
		for node in dirty.keys():
			_link_footpaths(node)

	for f in data.get("footways", []):
		_add_footway(_points(f.pts))
	var rail_before := rail_edges.size()
	for r in data.get("rail", []):
		_add_rail(_points(r.pts))
	for st in data.get("stations", []):
		_add_station(_vec(st.p), str(st.get("name", "")))
	if not added.is_empty() and not _pending_bus_stops.is_empty():
		var waiting := _pending_bus_stops
		_pending_bus_stops = []
		for p in waiting:
			_add_bus_stop(p)
	for bs in data.get("bus_stops", []):
		_add_bus_stop(_vec(bs.p))
	# Only new track, and track near new roads, can have new crossings.
	if not rail_edges.is_empty() and (rail_edges.size() > rail_before or not added.is_empty()):
		var check := {}
		for i in range(rail_before, rail_edges.size()):
			check[rail_edges[i]] = true
		for road in added:
			for p in road.pts:
				for entry in _cells_near(_rail_cells, p, CELL * 0.5):
					check[entry[0]] = true
		_find_level_crossings(check.keys())
	return added.size()


func _make_road(r: Dictionary) -> Road:
	var a: GNode = nodes.get(int(r.a))
	var b: GNode = nodes.get(int(r.b))
	if a == null or b == null:
		push_warning("traffic: road references a missing node (%s -> %s)" % [r.a, r.b])
		return null
	var pts := _points(r.get("pts", []))
	if pts.size() < 2:
		pts = PackedVector3Array([a.pos, b.pos])
	var key := str(r.get("id", "%d-%d-%s" % [int(r.a), int(r.b), pts[pts.size() / 2].snapped(Vector3.ONE * 0.5)]))
	if _road_keys.has(key):
		return null
	_road_keys[key] = true
	if a == b:
		# A closed loop (e.g. an unsplit roundabout): split it in two.
		var mid := GNode.new()
		mid.id = _next_synthetic_id
		_next_synthetic_id -= 1
		var half := pts.size() / 2
		mid.pos = pts[half]
		nodes[mid.id] = mid
		var first := r.duplicate()
		first.b = mid.id
		first.pts = _to_array(pts.slice(0, half + 1))
		first.id = key + "/1"
		var second := r.duplicate()
		second.a = mid.id
		second.pts = _to_array(pts.slice(half))
		second.id = key + "/2"
		var r1 := _make_road(first)
		_make_road(second)
		return r1

	var road := Road.new()
	road.index = roads.size()
	road.key = key
	road.a = a
	road.b = b
	road.pts = pts
	road.cum = cumulative(pts)
	road.length = road.cum[road.cum.size() - 1]
	road.kind = StringName(r.get("kind", "residential"))
	var info: Dictionary = KINDS.get(road.kind, KINDS[&"residential"])
	road.rank = info.rank
	road.roundabout = bool(r.get("roundabout", false))
	road.bike_lane = bool(r.get("bike_lane", false))
	var oneway := bool(r.get("oneway", false)) or road.roundabout
	road.lanes_fwd = maxi(1, int(r.get("lanes_fwd", 1)))
	road.lanes_back = 0 if oneway else maxi(1, int(r.get("lanes_back", 1)))
	road.speed = float(r.get("speed_kmh", info.speed)) / 3.6
	road.walk = bool(r.get("sidewalks", info.walk)) and not road.roundabout
	road.half_width = float(r.get("width", (road.lanes_fwd + road.lanes_back) * LANE_WIDTH + SHOULDER * 2.0)) * 0.5
	road.footpath_offset = float(r.get("footpath_offset", road.half_width + FOOTPATH_GAP))
	road.name = str(r.get("name", ""))
	roads.append(road)
	a.roads.append(road)
	b.roads.append(road)
	return road


## OSM puts give_way/stop tags on the minor road a few metres before the
## junction. Pass them on to the junction they belong to.
func _mark_minor_approaches(touched: Array) -> void:
	# A junction can gain roads after its give-way node was added (map tiles
	# arrive one at a time), so look at the neighbours of touched nodes too.
	var candidates := {}
	for node in touched:
		candidates[node] = true
		for road in node.roads:
			candidates[road.other(node)] = true
	for node in candidates.keys():
		if node.ctrl != &"give_way" and node.ctrl != &"stop":
			continue
		if node.degree() >= 3:
			continue
		for road in node.roads:
			var other: GNode = road.other(node)
			if other.degree() >= 3 and road.length < 35.0:
				other.minor_roads[road] = true
				if node.ctrl == &"stop":
					other.stop_roads[road] = true


func _compute_radius(node: GNode) -> void:
	var deg := node.degree()
	if deg <= 1:
		node.radius = 0.0
		return
	if deg == 2:
		var d0: Vector3 = node.roads[0].direction_from(node)
		var d1: Vector3 = node.roads[1].direction_from(node)
		# Sharp bends need room to round the corner.
		node.radius = lerpf(1.0, 6.0, clampf((d0.dot(d1) + 0.7) / 1.4, 0.0, 1.0))
		return
	var widest := 0.0
	for road in node.roads:
		widest = maxf(widest, road.half_width)
	node.radius = widest + 2.0


func _build_lanes(road: Road) -> void:
	var trim_a := road.a.radius
	var trim_b := road.b.radius
	var limit := road.length * 0.8
	if trim_a + trim_b > limit:
		var f := limit / (trim_a + trim_b)
		trim_a *= f
		trim_b *= f
	var reversed := road.pts.duplicate()
	reversed.reverse()
	var specs: Array = []
	var two_way := road.lanes_back > 0
	for k in road.lanes_fwd:
		var off := (k + 0.5) * LANE_WIDTH if two_way else (k - (road.lanes_fwd - 1) * 0.5) * LANE_WIDTH
		specs.append([true, k, road.lanes_fwd, off])
	for k in road.lanes_back:
		specs.append([false, k, road.lanes_back, (k + 0.5) * LANE_WIDTH])

	var reuse := road.lanes.duplicate()
	road.lanes.clear()
	for spec in specs:
		var fwd: bool = spec[0]
		var lane: Lane = reuse.pop_front() if not reuse.is_empty() else null
		if lane == null:
			lane = Lane.new()
			lane.id = _next_lane_id
			_next_lane_id += 1
			lanes.append(lane)
		lane.road = road
		lane.from_node = road.a if fwd else road.b
		lane.to_node = road.b if fwd else road.a
		lane.k = spec[1]
		lane.count = spec[2]
		lane.speed = road.speed
		var base: PackedVector3Array = road.pts if fwd else reversed
		var full := offset_polyline(base, spec[3])
		var cut := cut_polyline(full, trim_a if fwd else trim_b, trim_b if fwd else trim_a)
		lane.set_points(cut)
		lane.next.clear()
		for st in lane.stops:
			if st.gate is SignalGate:
				_dropped.append(st.gate)
		lane.stops = lane.stops.filter(func(st): return not (st.gate is SignalGate))
		lane.signal_gate = null
		road.lanes.append(lane)
	for lane in road.lanes:
		lane.left_lane = null
		lane.right_lane = null
		for other in road.lanes:
			if other.from_node == lane.from_node and other != lane:
				if other.k == lane.k + 1:
					lane.left_lane = other
				elif other.k == lane.k - 1:
					lane.right_lane = other


func _build_connectors(node: GNode) -> void:
	# Keep the same connector objects where the same move still exists, so
	# cars already on them (or planning through them) stay consistent when a
	# new map tile rebuilds the junction.
	var old := {}
	for c in node.connectors:
		old[[c.in_lane, c.next[0]]] = c
	node.connectors.clear()
	var majors := _major_roads(node)
	var deg := node.degree()
	for rin in node.roads:
		for lin in rin.lanes_into(node):
			lin.next.clear()
			for rout in node.roads:
				if rout == rin and deg > 1:
					continue
				var outs: Array = rout.lanes_from(node)
				if outs.is_empty():
					continue
				var d_in: Vector3 = lin.tangent(lin.length)
				var d_out: Vector3 = outs[0].tangent(0.0)
				var turn := Turn.STRAIGHT
				if rout == rin:
					turn = Turn.UTURN
				elif deg >= 3:
					var ang := atan2(d_out.dot(left_of(d_in)), d_out.dot(d_in))
					if ang > 0.6:
						turn = Turn.LEFT
					elif ang < -0.6:
						turn = Turn.RIGHT
				for lout in _target_lanes(lin, outs, turn, deg):
					var c := _make_connector(lin, lout, node, turn, old.get([lin, lout]))
					old.erase([lin, lout])
					_assign_priority(c, node, rin, rout, majors)
					lin.next.append(c)
	# Moves that no longer exist: kept aside (a car may still be on one) and
	# untangled with the rest in dispose().
	_dropped.append_array(old.values())


func _target_lanes(lin: Lane, outs: Array, turn: int, deg: int) -> Array:
	var n_in := lin.count
	var n_out := outs.size()
	var by_k := {}
	for o in outs:
		by_k[o.k] = o
	var result: Array = []
	match turn:
		Turn.LEFT:
			if lin.k == n_in - 1:
				result.append(by_k[n_out - 1])
		Turn.RIGHT, Turn.UTURN:
			if lin.k == 0 or (turn == Turn.UTURN and deg <= 1):
				result.append(by_k[0])
		_:
			# Line up from the kerb; lanes that end merge into their neighbour.
			var from_kerb := n_in - 1 - lin.k
			var target := clampi(n_out - 1 - from_kerb, 0, n_out - 1)
			result.append(by_k[target])
			if deg <= 2 and lin.k == 0:
				for kk in range(0, target):
					result.append(by_k[kk])
	return result


func _make_connector(lin: Lane, lout: Lane, node: GNode, turn: int, reuse: Lane = null) -> Lane:
	var c := reuse
	if c == null:
		c = Lane.new()
		c.id = _next_lane_id
		_next_lane_id += 1
	c.yield_to.clear()
	c.conflicts.clear()
	c.full_stop = false
	c.stops.clear()
	c.connector = true
	c.node = node
	c.in_lane = lin
	c.from_node = node
	c.to_node = node
	c.turn = turn
	c.next = [lout]
	var p0: Vector3 = lin.pts[lin.pts.size() - 1]
	var p3: Vector3 = lout.pts[0]
	var d1 := lin.tangent(lin.length)
	var d2 := lout.tangent(0.0)
	var dist := p0.distance_to(p3)
	var handle := dist * 0.45
	if turn == Turn.UTURN:
		handle = maxf(dist, 4.0) * 1.3
	var p1 := p0 + d1 * handle
	var p2 := p3 - d2 * handle
	var steps := clampi(int(dist / 2.0), 3, 12)
	var pts := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3)
	c.set_points(pts)
	var theta := acos(clampf(d1.dot(d2), -1.0, 1.0))
	var limit := minf(lin.speed, lout.speed)
	if theta > 0.15:
		var radius := maxf(c.length / theta, 2.0)
		limit = minf(limit, sqrt(2.8 * radius))
	c.speed = maxf(limit, 3.0)
	node.connectors.append(c)
	return c


func _find_conflicts(node: GNode) -> void:
	var list: Array = node.connectors
	for c in list:
		c.conflicts.clear()
	# Where the road just bends, the only conflict is a lane ending and
	# merging into its neighbour.
	var bend := node.degree() == 2
	for i in list.size():
		for j in range(i + 1, list.size()):
			var c1: Lane = list[i]
			var c2: Lane = list[j]
			if c1.in_lane == c2.in_lane:
				continue  # Same queue: the car in front is enough.
			if c1.next[0] == c2.next[0] or (not bend and _paths_touch(c1.pts, c2.pts, 2.6)):
				c1.conflicts.append(c2)
				c2.conflicts.append(c1)


static func _paths_touch(a: PackedVector3Array, b: PackedVector3Array, dist: float) -> bool:
	for i in a.size() - 1:
		for j in b.size() - 1:
			var p := Geometry3D.get_closest_points_between_segments(a[i], a[i + 1], b[j], b[j + 1])
			if p[0].distance_to(p[1]) < dist:
				return true
	return false


## The through route at a junction: roundabout roads, or the two highest
## ranked roads that line up best. Everyone else gives way to them.
func _major_roads(node: GNode) -> Dictionary:
	var result := {}
	if node.degree() < 3:
		return result
	var round_roads := node.roads.filter(func(r): return r.roundabout)
	if not round_roads.is_empty():
		for r in round_roads:
			result[r] = true
		return result
	var candidates := node.roads.filter(func(r): return not node.minor_roads.has(r))
	if candidates.is_empty():
		candidates = node.roads.duplicate()
	var top := 0
	for r in candidates:
		top = maxi(top, r.rank)
	var best := candidates.filter(func(r): return r.rank == top)
	var pool: Array = best if best.size() >= 2 else candidates
	var anchor: Road = best[0]
	var pair: Road
	var pair_dot := 2.0
	for i in pool.size():
		for j in range(i + 1, pool.size()):
			if best.size() < 2 and pool[i] != anchor and pool[j] != anchor:
				continue
			var dot: float = pool[i].direction_from(node).dot(pool[j].direction_from(node))
			if dot < pair_dot:
				pair_dot = dot
				anchor = pool[i]
				pair = pool[j]
	result[anchor] = true
	if pair != null and pair_dot < -0.5:
		result[pair] = true
	return result


func _assign_priority(c: Lane, node: GNode, rin: Road, rout: Road, majors: Dictionary) -> void:
	c.yield_to.clear()
	c.full_stop = node.ctrl == &"stop" or node.stop_roads.has(rin)
	if node.degree() < 3 or node.ctrl == &"signals":
		return
	if majors.has(rin):
		if c.turn == Turn.RIGHT or c.turn == Turn.UTURN:
			# Right turns cross the oncoming half of the major road.
			for r in majors.keys():
				if r != rin:
					c.yield_to.append_array(r.lanes_into(node))
		return
	for r in majors.keys():
		if r != rin:
			c.yield_to.append_array(r.lanes_into(node))


## Signal junctions: cluster nearby signal nodes, give each approach a gate,
## and make right turns give way to oncoming traffic on the same green.
func _build_signals(touched: Array) -> void:
	for node in touched:
		if node.ctrl != &"signals" or node.signal_controller != null:
			continue
		# Signal nodes joined by short roads are one set of lights. Part of the
		# set may already exist (it arrived with an earlier map tile).
		var cluster: Array = []
		var stack: Array = [node]
		while not stack.is_empty():
			var n: GNode = stack.pop_back()
			if cluster.has(n):
				continue
			cluster.append(n)
			for road in n.roads:
				# Follow short links, through plain bends, to the next set of
				# signals: a dual carriageway crossing is one intersection.
				var path: Array = []
				var o: GNode = road.other(n)
				var link: Road = road
				var total: float = road.length
				while o.ctrl != &"signals" and o.degree() == 2 and total < 30.0:
					path.append(o)
					link = o.roads[0] if o.roads[1] == link else o.roads[1]
					o = link.other(o)
					total += link.length
				if o.ctrl == &"signals" and total < 30.0 and not cluster.has(o):
					stack.append(o)
					for m in path:
						if not cluster.has(m):
							cluster.append(m)
		var controller: SignalController = null
		for n in cluster:
			if n.signal_controller != null:
				controller = n.signal_controller
				break
		if controller == null:
			controller = SignalController.new()
			signal_controllers.append(controller)
		for n in cluster:
			if n.signal_controller == null:
				n.signal_controller = controller
				controller.nodes.append(n)
		var center := Vector3.ZERO
		for n in controller.nodes:
			center += n.pos
		controller.center = center / controller.nodes.size()

	for controller in signal_controllers:
		if not controller.nodes.any(func(n): return touched.has(n)):
			continue
		# Main axis follows the highest ranked road, and gets the longer
		# green. Once running, a bigger road arriving with a later tile
		# moves the longer green to its group without swapping which way is
		# green now.
		for n in controller.nodes:
			for road in n.roads:
				if road.rank <= controller.axis_rank or road.lanes_into(n).is_empty():
					continue
				controller.axis_rank = road.rank
				if not controller.running:
					controller.axis = road.direction_from(n)
				var main: int = controller.group_for(road.direction_from(n))
				controller.green = PackedFloat32Array([22.0, 16.0] if main == 0 else [16.0, 22.0])
		for ap in controller.approaches:
			var lane: Lane = ap.lane
			lane.stops = lane.stops.filter(func(st): return not (st.gate is SignalGate and st.gate.controller == controller))
			if lane.signal_gate != null and lane.signal_gate.controller == controller:
				lane.signal_gate = null
		controller.approaches.clear()
		# Offset each set of lights by where it is, so runs are repeatable.
		if not controller.running:
			controller.timer = fposmod(controller.center.x * 0.37 + controller.center.z * 0.61, 20.0)
			controller.running = true
		for n in controller.nodes:
			for road in n.roads:
				var o: GNode = road.other(n)
				if controller.nodes.has(o) and road.length < 30.0:
					continue  # Internal link of a split junction.
				for lane in road.lanes_into(n):
					var dir: Vector3 = -road.direction_from(n)
					var group: int = controller.group_for(dir)
					var gate := SignalGate.new(controller, group)
					lane.signal_gate = gate
					lane.add_stop(lane.length, gate)
					controller.approaches.append({ "lane": lane, "group": group, "dir": dir, "road": road, "node": n })
		for n in controller.nodes:
			for c in n.connectors:
				if c.turn != Turn.RIGHT and c.turn != Turn.UTURN:
					continue
				var my_dir: Vector3 = c.in_lane.tangent(c.in_lane.length)
				for ap in controller.approaches:
					if ap.dir.dot(my_dir) < -0.7 and controller.group_for(ap.dir) == controller.group_for(my_dir):
						c.yield_to.append(ap.lane)


func _index_road(road: Road) -> void:
	for lane in road.lanes:
		var s := 6.0
		while s < lane.length - 6.0:
			var cell := cell_of(lane.point(s))
			if not _lane_cells.has(cell):
				_lane_cells[cell] = []
			_lane_cells[cell].append([lane, s])
			s += SAMPLE_STEP


# --- Footpaths ----------------------------------------------------------------

func _build_footpaths(road: Road) -> void:
	if not road.walk:
		return
	var trim_a := maxf(road.a.radius - 0.5, 0.0) if road.a.degree() >= 3 else 0.0
	var trim_b := maxf(road.b.radius - 0.5, 0.0) if road.b.degree() >= 3 else 0.0
	if trim_a + trim_b > road.length * 0.8:
		return
	for side in [1.0, -1.0]:
		var pts := cut_polyline(offset_polyline(road.pts, road.footpath_offset * side), trim_a, trim_b)
		if pts.size() < 2:
			continue
		var edge := _add_ped_edge(pts)
		edge.road = road
		# Remember which end belongs to which junction, for corner links.
		edge.ends = { road.a: edge.a, road.b: edge.b }
		road.footpaths.append(edge)


func _link_footpaths(node: GNode) -> void:
	var ends: Array = []
	for road in node.roads:
		for e in road.footpaths:
			var pn: PedNode = e.ends.get(node)
			if pn != null:
				var rel := pn.pos - node.pos
				ends.append({ "pn": pn, "road": road, "angle": atan2(rel.x, rel.z) })
	if ends.size() < 2:
		return
	ends.sort_custom(func(x, y): return x.angle < y.angle)
	var linked := {}
	for i in ends.size():
		var e0: Dictionary = ends[i]
		var e1: Dictionary = ends[(i + 1) % ends.size()]
		if e0.pn == e1.pn:
			continue
		if e0.road == e1.road and node.degree() == 2:
			continue  # No crossings at mere bends.
		var key := [e0.pn.get_instance_id(), e1.pn.get_instance_id()]
		key.sort()
		if linked.has(key):
			continue
		linked[key] = true
		if e0.pn.pos.distance_to(e1.pn.pos) < 0.5:
			continue
		var edge := _add_ped_edge(PackedVector3Array([e0.pn.pos, e1.pn.pos]), e0.pn, e1.pn)
		if e0.road == e1.road:
			edge.crossing = true
			edge.road = e0.road
			edge.node = node


func _add_footway(pts: PackedVector3Array) -> void:
	if pts.size() >= 2:
		_add_ped_edge(pts)


func _add_ped_edge(pts: PackedVector3Array, a: PedNode = null, b: PedNode = null) -> PedEdge:
	var edge := PedEdge.new()
	edge.pts = pts
	edge.cum = cumulative(pts)
	edge.length = edge.cum[edge.cum.size() - 1]
	edge.a = a if a != null else _ped_node_at(pts[0])
	edge.b = b if b != null else _ped_node_at(pts[pts.size() - 1])
	edge.a.edges.append(edge)
	edge.b.edges.append(edge)
	ped_edges.append(edge)
	if not edge.crossing:
		var s := 2.0
		while s < edge.length - 2.0:
			var cell := cell_of(edge.pts[0] if edge.length < 4.0 else point_at(edge.pts, edge.cum, s))
			if not _ped_cells.has(cell):
				_ped_cells[cell] = []
			_ped_cells[cell].append([edge, s])
			s += 8.0
	return edge


func _ped_node_at(p: Vector3) -> PedNode:
	var key := Vector2i(roundi(p.x / 2.0), roundi(p.z / 2.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for pn in _ped_node_cells.get(key + Vector2i(dx, dz), []):
				if pn.pos.distance_to(p) < 1.5:
					return pn
	var pn := PedNode.new()
	pn.pos = p
	ped_nodes.append(pn)
	if not _ped_node_cells.has(key):
		_ped_node_cells[key] = []
	_ped_node_cells[key].append(pn)
	return pn


# --- Rail ---------------------------------------------------------------------

func _add_rail(pts: PackedVector3Array) -> void:
	if pts.size() < 2:
		return
	var edge := RailEdge.new()
	edge.pts = pts
	edge.cum = cumulative(pts)
	edge.length = edge.cum[edge.cum.size() - 1]
	edge.a = _rail_node_at(pts[0])
	edge.b = _rail_node_at(pts[pts.size() - 1])
	edge.a.edges.append(edge)
	edge.b.edges.append(edge)
	rail_edges.append(edge)
	for st in stations:
		_attach_station(edge, st)
	var s := 0.0
	while s < edge.length:
		var cell := cell_of(point_at(edge.pts, edge.cum, s))
		if not _rail_cells.has(cell):
			_rail_cells[cell] = []
		_rail_cells[cell].append([edge, s])
		s += 25.0


func _rail_node_at(p: Vector3) -> RailNode:
	var key := Vector2i(roundi(p.x / 4.0), roundi(p.z / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for rn in _rail_node_cells.get(key + Vector2i(dx, dz), []):
				if rn.pos.distance_to(p) < 2.0:
					return rn
	var rn := RailNode.new()
	rn.pos = p
	rail_nodes.append(rn)
	if not _rail_node_cells.has(key):
		_rail_node_cells[key] = []
	_rail_node_cells[key].append(rn)
	return rn


func _add_station(p: Vector3, station_name: String) -> void:
	stations.append({ "pos": p, "name": station_name })
	for edge in rail_edges:
		_attach_station(edge, stations[stations.size() - 1])


## Rail and stations can arrive in different map tiles, so whichever comes
## second does the attaching.
func _attach_station(edge: RailEdge, st: Dictionary) -> void:
	var s := closest_s(edge.pts, edge.cum, st.pos)
	if point_at(edge.pts, edge.cum, s).distance_to(st.pos) < 40.0:
		if not edge.stations.any(func(e): return absf(e.s - s) < 1.0):
			edge.stations.append({ "s": s, "name": st.name })


func _add_bus_stop(p: Vector3) -> void:
	var best: Lane
	var best_s := 0.0
	var best_d := 15.0
	for entry in samples_near(p, 30.0):
		var lane: Lane = entry[0]
		if lane.k != lane.count - 1:
			continue  # Buses pull in at the kerb.
		var s := closest_s(lane.pts, lane.cum, p)
		var d := lane.point(s).distance_to(p)
		if d < best_d:
			best_d = d
			best = lane
			best_s = s
	if best == null:
		_pending_bus_stops.append(p)
		return
	var gate := BusStopGate.new()
	gate.pos = p
	best.add_stop(best_s, gate)
	bus_stops.append({ "pos": p, "lane": best, "s": best_s })


func _add_parking(p: Dictionary) -> void:
	var pos := _vec(p.pos)
	var key := pos.snapped(Vector3.ONE * 0.5)
	if _parking_keys.has(key):
		return  # Tiles overlap a little at their edges.
	_parking_keys[key] = true
	var spot := { "pos": pos, "yaw": float(p.get("yaw", 0.0)), "kind": StringName(p.get("kind", "street")),
		"seed": hash(key) }
	parking.append(spot)
	var cell := cell_of(pos)
	if not _parking_cells.has(cell):
		_parking_cells[cell] = []
	_parking_cells[cell].append(spot)


## A route can come in pieces, one per tile: pieces with the same ref join up.
func _add_bus_route(r: Dictionary) -> void:
	var ref := str(r.get("ref", r.get("name", "")))
	if ref == "":
		return
	if not bus_routes.has(ref):
		bus_routes[ref] = { "ref": ref, "name": str(r.get("name", ref)), "colour": r.get("colour", ""), "roads": {} }
	for id in r.get("roads", []):
		bus_routes[ref].roads[str(id)] = true


## Don't let traffic stop across `pos` (a lane mouth or driveway).
func add_keep_clear(pos: Vector3, radius := 6.0) -> void:
	keep_clear.append({ "pos": pos, "radius": radius })
	version += 1


## The [s0, s1] stretches of `lane` that run through a keep-clear box.
func keep_clear_on(lane: Lane) -> Array:
	if lane.keep_clear_version == version:
		return lane.keep_clear
	lane.keep_clear_version = version
	lane.keep_clear = []
	for box in keep_clear:
		var s := closest_s(lane.pts, lane.cum, box.pos)
		var p := lane.point(s)
		if p.distance_to(box.pos) > box.radius or absf(p.y - box.pos.y) > 3.0:
			continue
		lane.keep_clear.append([maxf(s - box.radius, 0.0), minf(s + box.radius, lane.length)])
	return lane.keep_clear


## Refs of the bus routes that run along `road`.
func routes_on(road: Road) -> Array:
	var refs: Array = []
	for ref in bus_routes:
		if bus_routes[ref].roads.has(road.key):
			refs.append(ref)
	return refs


## Parking spots within `radius` of `p` (roughly: whole cells).
func parking_near(p: Vector3, radius: float) -> Array:
	return _cells_near(_parking_cells, p, radius)


func _find_level_crossings(edges: Array) -> void:
	for edge in edges:
		for i in edge.pts.size() - 1:
			var r0: Vector3 = edge.pts[i]
			var r1: Vector3 = edge.pts[i + 1]
			var nearby := {}
			var seg_len := r0.distance_to(r1)
			var steps := maxi(1, ceili(seg_len / CELL))
			for st in steps + 1:
				for entry in samples_near(r0.lerp(r1, float(st) / steps), CELL * 0.5):
					nearby[entry[0].road] = true
			for road in nearby.keys():
				for j in road.pts.size() - 1:
					var hit = _segment_intersection(r0, r1, road.pts[j], road.pts[j + 1])
					if hit == null:
						continue
					# Roads and rail at different heights (bridges, tunnels) don't cross.
					var rail_y: float = lerpf(r0.y, r1.y, hit.x)
					var road_y: float = lerpf(road.pts[j].y, road.pts[j + 1].y, hit.y)
					if absf(rail_y - road_y) > 2.5:
						continue
					var pos := r0.lerp(r1, hit.x)
					if edge.crossings.any(func(c): return c.pos.distance_to(pos) < 5.0):
						continue
					var xing := LevelCrossing.new()
					xing.pos = pos
					xing.rail_dir = (r1 - r0).normalized()
					xing.rail_edge = edge
					xing.rail_s = edge.cum[i] + r0.distance_to(pos)
					xing.roads.append(road)
					edge.crossings.append(xing)
					crossings.append(xing)
					for lane in road.lanes:
						var s := closest_s(lane.pts, lane.cum, pos)
						lane.add_stop(maxf(s - 6.0, 0.0), xing)


# --- Queries ------------------------------------------------------------------

const REACH := 250.0

## How far you can drive on from the start of `lane`, capped at REACH metres.
## Short answers mean a dead end ahead: a one-way street into a laneway
## traffic doesn't use, or the edge of the loaded map.
func reach(lane: Lane, depth := 0) -> float:
	if lane.reach_version == version:
		return lane.reach
	if depth > 40:
		return REACH
	lane.reach_version = version
	lane.reach = REACH  # A loop back to here counts as open road.
	var best := 0.0
	for n in lane.next:
		best = maxf(best, reach(n, depth + 1))
		if lane.length + best >= REACH:
			break
	lane.reach = minf(lane.length + best, REACH)
	return lane.reach


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## Lane sample points [lane, s] within `radius` of `p`.
func samples_near(p: Vector3, radius: float) -> Array:
	return _cells_near(_lane_cells, p, radius)


func ped_samples_near(p: Vector3, radius: float) -> Array:
	return _cells_near(_ped_cells, p, radius)


func rail_samples_near(p: Vector3, radius: float) -> Array:
	return _cells_near(_rail_cells, p, radius)


## Lane samples in the ring between `inner` and `outer` around `p`.
func samples_in_ring(cells: Dictionary, p: Vector3, inner: float, outer: float) -> Array:
	var result: Array = []
	var c0 := cell_of(p - Vector3(outer, 0, outer))
	var c1 := cell_of(p + Vector3(outer, 0, outer))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			var center := Vector3((x + 0.5) * CELL, p.y, (z + 0.5) * CELL)
			var d := Vector2(center.x - p.x, center.z - p.z).length()
			if d + CELL * 0.71 < inner or d - CELL * 0.71 > outer:
				continue
			var list: Array = cells.get(Vector2i(x, z), [])
			if not list.is_empty():
				result.append(list)
	return result


func lane_cells() -> Dictionary:
	return _lane_cells


func ped_cells() -> Dictionary:
	return _ped_cells


func rail_cells() -> Dictionary:
	return _rail_cells


func _cells_near(cells: Dictionary, p: Vector3, radius: float) -> Array:
	var result: Array = []
	var c0 := cell_of(p - Vector3(radius, 0, radius))
	var c1 := cell_of(p + Vector3(radius, 0, radius))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			result.append_array(cells.get(Vector2i(x, z), []))
	return result


# --- Geometry helpers ---------------------------------------------------------

## Vehicles drive on the left: this is the "left" of travel direction `d`.
static func left_of(d: Vector3) -> Vector3:
	return Vector3(d.z, 0.0, -d.x).normalized()


static func cumulative(pts: PackedVector3Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var total := 0.0
	for i in pts.size():
		if i > 0:
			total += pts[i - 1].distance_to(pts[i])
		cum[i] = total
	return cum


static func _index_at(cum: PackedFloat32Array, s: float) -> int:
	var i := cum.bsearch(s, true) - 1
	return clampi(i, 0, cum.size() - 2)


static func point_at(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	if pts.size() == 1:
		return pts[0]
	var i := _index_at(cum, s)
	var seg := cum[i + 1] - cum[i]
	var t := 0.0 if seg <= 0.0001 else clampf((s - cum[i]) / seg, 0.0, 1.0)
	return pts[i].lerp(pts[i + 1], t)


static func tangent_at(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	if pts.size() < 2:
		return Vector3.FORWARD
	var i := _index_at(cum, s)
	var d := pts[i + 1] - pts[i]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD


static func closest_s(pts: PackedVector3Array, cum: PackedFloat32Array, p: Vector3) -> float:
	var best := 0.0
	var best_d := INF
	for i in pts.size() - 1:
		var q := Geometry3D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = cum[i] + pts[i].distance_to(q)
	return best


## Offset a polyline sideways: positive = to the left of travel.
static func offset_polyline(pts: PackedVector3Array, offset: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	var n := pts.size()
	for i in n:
		var d_prev := Vector3.ZERO
		var d_next := Vector3.ZERO
		if i > 0:
			d_prev = pts[i] - pts[i - 1]
			d_prev.y = 0.0
			d_prev = d_prev.normalized()
		if i < n - 1:
			d_next = pts[i + 1] - pts[i]
			d_next.y = 0.0
			d_next = d_next.normalized()
		var d := (d_prev + d_next)
		if d.length_squared() < 0.0001:
			d = d_next if d_next != Vector3.ZERO else d_prev
		d = d.normalized()
		var normal := left_of(d)
		# Keep the offset distance true on bends (with a miter limit).
		var scale := 1.0
		if d_prev != Vector3.ZERO and d_next != Vector3.ZERO:
			scale = 1.0 / maxf(left_of(d_prev).dot(normal), 0.5)
		out[i] = pts[i] + normal * offset * scale
	return out


## Cut `from_start` metres off the start and `from_end` off the end.
static func cut_polyline(pts: PackedVector3Array, from_start: float, from_end: float) -> PackedVector3Array:
	var cum := cumulative(pts)
	var total := cum[cum.size() - 1]
	var s0 := clampf(from_start, 0.0, total)
	var s1 := clampf(total - from_end, s0, total)
	var out := PackedVector3Array([point_at(pts, cum, s0)])
	for i in pts.size():
		if cum[i] > s0 + 0.01 and cum[i] < s1 - 0.01:
			out.append(pts[i])
	out.append(point_at(pts, cum, s1))
	return out


## Intersection of two segments in the XZ plane: Vector2(t on first, t on second) or null.
static func _segment_intersection(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> Variant:
	var p := Vector2(a0.x, a0.z)
	var r := Vector2(a1.x - a0.x, a1.z - a0.z)
	var q := Vector2(b0.x, b0.z)
	var s := Vector2(b1.x - b0.x, b1.z - b0.z)
	var denom := r.cross(s)
	if absf(denom) < 0.000001:
		return null
	var t := (q - p).cross(s) / denom
	var u := (q - p).cross(r) / denom
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return null
	return Vector2(t, u)


static func _vec(v) -> Vector3:
	if v is Vector3:
		return v
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _points(list) -> PackedVector3Array:
	if list is PackedVector3Array:
		return list
	var out := PackedVector3Array()
	for v in list:
		out.append(_vec(v))
	return out


static func _to_array(pts: PackedVector3Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append(p)
	return out
