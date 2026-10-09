class_name TrafficTrain
extends RefCounted
## A Transperth electric train running along the rail network: a few
## carriages following one path, stopping at stations. Distances are measured
## along `segs`, a chain of rail edges each walked forwards or backwards.

const GAP := 0.6
const MAX_SPEED := 22.0
const ACCEL := 0.8
const BRAKE := 1.0
const DWELL := 14.0
## Stops of one station closer than this along the path are one stop.
const SAME_STATION := 150.0

var root: Node3D
var cars: Array = []
var front := 0.0
var speed := 0.0
var top_speed := MAX_SPEED
var dwell := 0.0
var served := {}
var dead_end := false
## [{edge, fwd, start}] with `start` = path distance where the edge begins.
var segs: Array = []
var length := 0.0


func rear() -> float:
	return front - length


func add_seg(edge: TrafficGraph.RailEdge, fwd: bool, start: float) -> void:
	segs.append({ "edge": edge, "fwd": fwd, "start": start })


func seg_end(seg: Dictionary) -> float:
	return seg.start + seg.edge.length


func path_end() -> float:
	return seg_end(segs[segs.size() - 1])


func point(d: float) -> Vector3:
	var seg: Dictionary = segs[0]
	for sg in segs:
		if d >= sg.start:
			seg = sg
		else:
			break
	var local := clampf(d - seg.start, 0.0, seg.edge.length)
	var s: float = local if seg.fwd else seg.edge.length - local
	return TrafficGraph.point_at(seg.edge.pts, seg.edge.cum, s)


## Path distance of a point given as (edge, s along edge), or NAN if the edge
## isn't on our path.
func distance_of(edge: TrafficGraph.RailEdge, s: float) -> float:
	for seg in segs:
		if seg.edge == edge:
			return seg.start + (s if seg.fwd else edge.length - s)
	return NAN


## Grow the path ahead, picking the straightest way at each junction.
func extend(ahead: float) -> void:
	while not dead_end and path_end() < front + ahead:
		var last: Dictionary = segs[segs.size() - 1]
		var edge: TrafficGraph.RailEdge = last.edge
		var end_node: TrafficGraph.RailNode = edge.b if last.fwd else edge.a
		var end_dir := _dir_at_end(edge, last.fwd)
		var best: TrafficGraph.RailEdge
		var best_fwd := true
		var best_dot := 0.3
		for e in end_node.edges:
			if e == edge:
				continue
			var fwd: bool = e.a == end_node
			var d := _dir_at_start(e, fwd)
			var dot := d.dot(end_dir)
			if dot > best_dot:
				best_dot = dot
				best = e
				best_fwd = fwd
		if best == null:
			dead_end = true
			return
		add_seg(best, best_fwd, path_end())


func trim() -> void:
	while segs.size() > 1 and seg_end(segs[0]) < rear() - 40.0:
		segs.pop_front()


## Upcoming station stop: path distance where the train's front should halt.
func next_station_stop() -> float:
	for seg in segs:
		for st in seg.edge.stations:
			var key := "%d/%d" % [seg.edge.get_instance_id(), int(st.s)]
			if served.has(key):
				continue
			var d: float = seg.start + (st.s if seg.fwd else seg.edge.length - st.s)
			var stop_front := d + length * 0.5
			if stop_front > front - 1.0:
				return stop_front
	return INF


## Mark the stop the train just dwelled at as served, with any other stop of
## the same station along the next platform's length: a station can attach to
## two edges that meet near it, and the train would stop twice.
func mark_served_near(d: float) -> void:
	var names := {}
	for seg in segs:
		for st in seg.edge.stations:
			var sd: float = seg.start + (st.s if seg.fwd else seg.edge.length - st.s)
			if absf(sd + length * 0.5 - d) < 2.0:
				served["%d/%d" % [seg.edge.get_instance_id(), int(st.s)]] = true
				names[st.name] = true
	for seg in segs:
		for st in seg.edge.stations:
			var sd: float = seg.start + (st.s if seg.fwd else seg.edge.length - st.s)
			if names.has(st.name) and absf(sd + length * 0.5 - d) < SAME_STATION:
				served["%d/%d" % [seg.edge.get_instance_id(), int(st.s)]] = true


static func _dir_at_end(e: TrafficGraph.RailEdge, fwd: bool) -> Vector3:
	var n := e.pts.size()
	var d: Vector3 = (e.pts[n - 1] - e.pts[n - 2]) if fwd else (e.pts[0] - e.pts[1])
	d.y = 0.0
	return d.normalized()


static func _dir_at_start(e: TrafficGraph.RailEdge, fwd: bool) -> Vector3:
	var n := e.pts.size()
	var d: Vector3 = (e.pts[1] - e.pts[0]) if fwd else (e.pts[n - 2] - e.pts[n - 1])
	d.y = 0.0
	return d.normalized()
