class_name RouteGraph
extends RefCounted
## The roads as a sat-nav sees them: every drivable road in the map's traffic
## data, joined at its junctions, with one-ways one way only. `find` works out
## the quickest way from where the car is (and the way it faces) to a spot,
## with no U-turns except at dead ends, like the traffic.
##
## MapData builds one on its worker thread (MapData.routes) from the tiles it
## already reads; RouteGuide asks it for routes on a worker thread too, so a
## long search never holds up a frame.

## Grid cell (m) for finding the road nearest a point.
const CELL := 64.0
const LANE_WIDTH := 3.2
## How far (m) the start or the end may be from a road and still use it, and
## how far it may be when nothing is closer (a car park, a lane off the map).
const SNAP := 30.0
const SNAP_FAR := 160.0
## Fastest anything goes (m/s), for the search's guess at what's left.
const TOP_SPEED := 100.0 / 3.6
## Seconds added for turning at a junction (right turns cross the traffic),
## so routes keep to fewer turns, and for turning round to start off.
const TURN_LEFT := 3.0
const TURN_RIGHT := 6.0
const TURN_ROUND := 25.0
## Back streets cost a bit more than their limit says, so routes keep to the
## main roads the way people drive.
const KIND_FACTOR := {"residential": 1.25, "living_street": 1.8, "unclassified": 1.15}
## Gives up past this many roads looked at (the far side of the map is ~60k).
const MAX_STEPS := 150000

var node_pos := PackedVector2Array()
var node_roads: Array[PackedInt32Array] = []
var road_a := PackedInt32Array()
var road_b := PackedInt32Array()
var road_pts: Array[PackedVector3Array] = []
var road_cum: Array[PackedFloat32Array] = []
var road_len := PackedFloat32Array()
## m/s, with KIND_FACTOR taken off.
var road_speed := PackedFloat32Array()
var road_oneway := PackedByteArray()
var road_lanes_fwd := PackedByteArray()
var road_lanes_back := PackedByteArray()
## Which way the road leaves each end (x/z, unit).
var road_dir_a := PackedVector2Array()
var road_dir_b := PackedVector2Array()

var _node_ids := {}  # map node id -> index
var _keys := {}  # road ids already added (roads on two tiles come twice)
var _grid := {}  # Vector2i -> PackedInt32Array of roads
var _next_synthetic := -1


func road_count() -> int:
	return road_a.size()


## Adds one road from a tile's traffic data ({a, b, pts, oneway, roundabout,
## lanes_fwd, lanes_back, speed_kmh, kind, id}).
func add_road(r: Dictionary) -> void:
	var key := String(r.get("id", ""))
	if key != "":
		if _keys.has(key):
			return
		_keys[key] = true
	var pts := _points(r.get("pts", []))
	if pts.size() < 2:
		return
	var a := _node(int(r.get("a", 0)), pts[0])
	var b := _node(int(r.get("b", 0)), pts[pts.size() - 1])
	if a == b:
		# A closed loop (an unsplit roundabout): two halves, joined halfway.
		var half := pts.size() / 2
		if half < 1:
			return
		var mid := _node(_next_synthetic, pts[half])
		_next_synthetic -= 1
		_add(a, mid, pts.slice(0, half + 1), r)
		_add(mid, b, pts.slice(half), r)
		return
	_add(a, b, pts, r)


func _add(a: int, b: int, pts: PackedVector3Array, r: Dictionary) -> void:
	if pts.size() < 2:
		return
	var index := road_a.size()
	road_a.append(a)
	road_b.append(b)
	road_pts.append(pts)
	var cum := TrafficGraph.cumulative(pts)
	road_cum.append(cum)
	road_len.append(maxf(cum[cum.size() - 1], 0.1))
	var kind := String(r.get("kind", "residential"))
	var kmh := float(r.get("speed_kmh", 50.0))
	road_speed.append(maxf(kmh, 10.0) / 3.6 / float(KIND_FACTOR.get(kind, 1.0)))
	road_oneway.append(1 if bool(r.get("oneway", false)) or bool(r.get("roundabout", false)) else 0)
	road_lanes_fwd.append(clampi(int(r.get("lanes_fwd", 1)), 1, 8))
	road_lanes_back.append(clampi(int(r.get("lanes_back", 1)), 1, 8))
	road_dir_a.append(_dir(pts, false))
	road_dir_b.append(_dir(pts, true))
	node_roads[a].append(index)
	node_roads[b].append(index)
	var cells := {}
	for i in pts.size() - 1:
		var lo := Vector2i(floori(minf(pts[i].x, pts[i + 1].x) / CELL), floori(minf(pts[i].z, pts[i + 1].z) / CELL))
		var hi := Vector2i(floori(maxf(pts[i].x, pts[i + 1].x) / CELL), floori(maxf(pts[i].z, pts[i + 1].z) / CELL))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				cells[Vector2i(cx, cy)] = true
	for c: Vector2i in cells:
		var list: PackedInt32Array = _grid.get(c, PackedInt32Array())
		list.append(index)
		_grid[c] = list


func _node(id: int, p: Vector3) -> int:
	if _node_ids.has(id):
		return _node_ids[id]
	var i := node_pos.size()
	_node_ids[id] = i
	node_pos.append(Vector2(p.x, p.z))
	node_roads.append(PackedInt32Array())
	return i


## The way a road leaves its start (or, with `from_end`, its end), over ~8 m.
static func _dir(pts: PackedVector3Array, from_end: bool) -> Vector2:
	var base := pts[pts.size() - 1] if from_end else pts[0]
	var run := 0.0
	var i := pts.size() - 2 if from_end else 1
	var step := -1 if from_end else 1
	var p := base
	while i >= 0 and i < pts.size():
		p = pts[i]
		run = Vector2(p.x - base.x, p.z - base.z).length()
		if run >= 8.0:
			break
		i += step
	var d := Vector2(p.x - base.x, p.z - base.z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.UP


# --- finding the way -----------------------------------------------------------

## The quickest way by road from `from` to `to` (world positions). `heading`
## is which way the car faces (x/z; zero when it doesn't matter). Returns {}
## when either end is nowhere near a road or there's no way through, else:
## {points: PackedVector3Array (down the middle of each road), lane:
## PackedVector3Array (down the middle of your side of it), length (m),
## seconds (a rough driving time)}.
func find(from: Vector3, heading: Vector2, to: Vector3) -> Dictionary:
	var starts := nearest(Vector2(from.x, from.z))
	var goals := nearest(Vector2(to.x, to.z))
	if starts.is_empty() or goals.is_empty():
		return {}
	var target := Vector2(to.x, to.z)
	var n2 := road_a.size() * 2
	# States: road * 2 + way (0 = a to b, 1 = b to a), meaning "driven that
	# road that way, now at its end". Past n2: one per way into the end.
	var goal_list: Array = []  # [state, s, seconds from the way in]
	var goal_of := {}  # state -> [goal indices]
	for gl: Array in goals:
		var r: int = gl[0]
		var s: float = gl[1]
		for d in 2:
			if d == 1 and road_oneway[r] == 1:
				continue
			var st := r * 2 + d
			var along := s if d == 0 else road_len[r] - s
			var k := goal_list.size()
			goal_list.append([st, s, along / road_speed[r] + float(gl[2]) / 5.0])
			var list: Array = goal_of.get(st, [])
			list.append(k)
			goal_of[st] = list
	var total := n2 + goal_list.size()
	var g := PackedFloat64Array()
	g.resize(total)
	g.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(total)
	parent.fill(-1)
	var start_s := {}  # state -> where on its road the car starts
	var heap: Array = []
	for st_info: Array in starts:
		var r: int = st_info[0]
		var s: float = st_info[1]
		var extra := float(st_info[2]) / 5.0
		for d in 2:
			if d == 1 and road_oneway[r] == 1:
				continue
			var st := r * 2 + d
			var cost := extra
			if heading != Vector2.ZERO:
				var t := _tangent(r, s)
				if (t if d == 0 else -t).dot(heading) < -0.3:
					cost += TURN_ROUND
			# The end may be along this very road, ahead.
			for k: int in goal_of.get(st, []):
				var sg: float = goal_list[k][1]
				if (d == 0 and sg >= s) or (d == 1 and sg <= s):
					var c := cost + absf(sg - s) / road_speed[r]
					if c < g[n2 + k]:
						g[n2 + k] = c
						parent[n2 + k] = -2
						start_s[n2 + k] = s
						TrafficGraph._heap_push(heap, [c, n2 + k, c])
			cost += ((road_len[r] - s) if d == 0 else s) / road_speed[r]
			if cost < g[st]:
				g[st] = cost
				parent[st] = -2
				start_s[st] = s
				TrafficGraph._heap_push(heap, [cost + _guess(r, d, target), st, cost])
	var steps := 0
	var found := -1
	while not heap.is_empty() and steps < MAX_STEPS:
		var item: Array = TrafficGraph._heap_pop(heap)
		var st: int = item[1]
		if float(item[2]) > g[st]:
			continue  # a better way here was already found
		if st >= n2:
			found = st
			break
		steps += 1
		var r := st >> 1
		var d := st & 1
		var n := road_b[r] if d == 0 else road_a[r]
		var dir_in := -(road_dir_b[r] if d == 0 else road_dir_a[r])
		var roads: PackedInt32Array = node_roads[n]
		var deg := roads.size()
		for r2: int in roads:
			if r2 == r and deg > 1:
				continue  # no U-turns, but at a dead end
			var d2 := 0 if road_a[r2] == n else 1
			if r2 == r:
				d2 = 1 - d
			if d2 == 1 and road_oneway[r2] == 1:
				continue
			var turn := 0.0
			if r2 == r:
				turn = TURN_ROUND * 0.5
			elif deg >= 3:
				var dir_out := road_dir_a[r2] if d2 == 0 else road_dir_b[r2]
				var ang := atan2(dir_out.dot(Vector2(dir_in.y, -dir_in.x)), dir_out.dot(dir_in))
				if ang > 0.6:
					turn = TURN_LEFT
				elif ang < -0.6:
					turn = TURN_RIGHT
			var base := g[st] + turn
			var st2 := r2 * 2 + d2
			for k: int in goal_of.get(st2, []):
				var c: float = base + float(goal_list[k][2])
				if c < g[n2 + k]:
					g[n2 + k] = c
					parent[n2 + k] = st
					TrafficGraph._heap_push(heap, [c, n2 + k, c])
			var c2 := base + road_len[r2] / road_speed[r2]
			if c2 < g[st2]:
				g[st2] = c2
				parent[st2] = st
				TrafficGraph._heap_push(heap, [c2 + _guess(r2, d2, target), st2, c2])
	if found < 0:
		return {}
	return _trace(found, n2, goal_list, parent, start_s, g[found])


## Seconds at top speed from the end of a road (driven way `d`) to the target.
func _guess(r: int, d: int, target: Vector2) -> float:
	return node_pos[road_b[r] if d == 0 else road_a[r]].distance_to(target) / TOP_SPEED


func _trace(found: int, n2: int, goal_list: Array, parent: PackedInt32Array, start_s: Dictionary, seconds: float) -> Dictionary:
	var goal: Array = goal_list[found - n2]
	var gr: int = int(goal[0]) >> 1
	var gd: int = int(goal[0]) & 1
	var sg: float = goal[1]
	# [road, way, from s, to s] in road terms, end first.
	var pieces: Array = []
	if parent[found] == -2:
		pieces.append([gr, gd, float(start_s[found]), sg])
	else:
		pieces.append([gr, gd, 0.0 if gd == 0 else road_len[gr], sg])
		var st := parent[found]
		while st >= 0:
			var r := st >> 1
			var d := st & 1
			var from_s := (0.0 if d == 0 else road_len[r])
			if parent[st] == -2:
				from_s = float(start_s[st])
			pieces.append([r, d, from_s, road_len[r] if d == 0 else 0.0])
			st = parent[st]
	pieces.reverse()
	var points := PackedVector3Array()
	var lane := PackedVector3Array()
	for p: Array in pieces:
		var r: int = p[0]
		var part := _cut(r, float(p[2]), float(p[3]))
		if part.size() < 2:
			continue
		var offset := 0.0
		if road_oneway[r] == 0:
			offset = float(road_lanes_fwd[r] if int(p[1]) == 0 else road_lanes_back[r]) * LANE_WIDTH * 0.5
		var side := TrafficGraph.offset_polyline(part, offset) if offset > 0.0 else part
		_join(points, part)
		_join(lane, side)
	if points.size() < 2:
		return {}
	var cum := TrafficGraph.cumulative(points)
	return {points = points, lane = lane, length = cum[cum.size() - 1], seconds = seconds}


static func _join(into: PackedVector3Array, part: PackedVector3Array) -> void:
	var from := 0
	if not into.is_empty() and into[into.size() - 1].distance_squared_to(part[0]) < 4.0:
		from = 1
	for i in range(from, part.size()):
		into.append(part[i])


## A road's points from s0 to s1 (s1 < s0 runs it backwards).
func _cut(r: int, s0: float, s1: float) -> PackedVector3Array:
	var pts := road_pts[r]
	var cum := road_cum[r]
	var lo := minf(s0, s1)
	var hi := maxf(s0, s1)
	var out := PackedVector3Array([TrafficGraph.point_at(pts, cum, lo)])
	for i in pts.size():
		if cum[i] > lo + 0.05 and cum[i] < hi - 0.05:
			out.append(pts[i])
	out.append(TrafficGraph.point_at(pts, cum, hi))
	if s1 < s0:
		out.reverse()
	if out.size() == 2 and out[0].distance_squared_to(out[1]) < 0.01:
		return PackedVector3Array()
	return out


func _tangent(r: int, s: float) -> Vector2:
	var t := TrafficGraph.tangent_at(road_pts[r], road_cum[r], s)
	return Vector2(t.x, t.z)


## The roads near a point (x/z): up to three within SNAP, nearest first, or
## the nearest within SNAP_FAR. Each: [road, s along it, distance].
func nearest(at: Vector2) -> Array:
	var found := _near(at, SNAP)
	if found.is_empty():
		found = _near(at, SNAP_FAR)
		return found.slice(0, 1)
	return found.slice(0, 3)


func _near(at: Vector2, reach: float) -> Array:
	var c := Vector2i(floori(at.x / CELL), floori(at.y / CELL))
	var span := ceili(reach / CELL)
	var seen := {}
	var out: Array = []
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			var list: Variant = _grid.get(c + Vector2i(dx, dy))
			if list == null:
				continue
			for r: int in list:
				if seen.has(r):
					continue
				seen[r] = true
				var hit := closest(r, at)
				if hit.y <= reach:
					out.append([r, hit.x, hit.y])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[2] < y[2])
	return out


## Where on road r is closest to `at`: Vector2(s along it, distance).
func closest(r: int, at: Vector2) -> Vector2:
	var pts := road_pts[r]
	var cum := road_cum[r]
	var best_s := 0.0
	var best_d := INF
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(at, a, b)
		var dd := q.distance_squared_to(at)
		if dd < best_d:
			best_d = dd
			best_s = cum[i] + a.distance_to(q)
	return Vector2(best_s, sqrt(best_d))


static func _points(pts: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts is PackedVector3Array:
		out = pts
	elif pts is Array:
		for p: Variant in pts:
			if p is Vector3:
				out.append(p)
			elif (p is Array or p is PackedFloat32Array) and p.size() >= 3:
				out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var clean := PackedVector3Array()
	for p in out:
		if clean.is_empty() or clean[clean.size() - 1].distance_squared_to(p) > 0.01:
			clean.append(p)
	return clean
