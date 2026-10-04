class_name TrafficTestNetworks
extends RefCounted
## Road networks in the same format the map produces (docs/TRAFFIC.md), for
## testing traffic before (and alongside) the real Perth data.
##
## - `test_grid()` matches the streets of scenes/world/test_grid.tscn, so the
##   current prototype has traffic: the town block, the oval and its link road.
## - `sandbox()` is a small suburb with everything traffic handles: a
##   four-lane avenue with traffic lights, give-ways, a roundabout, a railway
##   with level crossings and a station, and bus stops.

const Y := 0.02


class Net:
	var nodes: Array = []
	var roads: Array = []
	var rail: Array = []
	var stations: Array = []
	var bus_stops: Array = []
	var _ids := {}
	var _next := 1

	## Node at a position (reused if one already exists there).
	func node(x: float, z: float, ctrl := "") -> int:
		var key := Vector2i(roundi(x * 10.0), roundi(z * 10.0))
		if _ids.has(key):
			var id: int = _ids[key]
			if ctrl != "":
				for n in nodes:
					if n.id == id:
						n.ctrl = ctrl
			return id
		var id := _next
		_next += 1
		_ids[key] = id
		nodes.append({ "id": id, "p": [x, Y, z], "ctrl": ctrl })
		return id

	func pos(id: int) -> Vector3:
		for n in nodes:
			if n.id == id:
				return Vector3(n.p[0], n.p[1], n.p[2])
		return Vector3.ZERO

	func road(a: int, b: int, extra := {}, pts: Array = []) -> void:
		var r := { "a": a, "b": b, "kind": "residential" }
		r.merge(extra, true)
		r.pts = pts if not pts.is_empty() else [pos(a), pos(b)]
		roads.append(r)

	## A straight street through a list of x (or z) stops, split at each one.
	func street(points: Array, extra := {}) -> void:
		for i in points.size() - 1:
			road(points[i], points[i + 1], extra)

	func data() -> Dictionary:
		return { "nodes": nodes, "roads": roads, "rail": rail, "stations": stations, "bus_stops": bus_stops }


static func test_grid() -> Dictionary:
	var net := Net.new()
	var grid := { "width": 8.0, "footpath_offset": 4.6 }
	var ids := {}
	for i in 7:
		for j in 7:
			var ctrl := "signals" if i == 3 and j == 3 else ""
			ids[Vector2i(i, j)] = net.node(-315.0 + i * 30.0, -315.0 + j * 30.0, ctrl)
	for i in 7:
		for j in 7:
			var through := grid.duplicate()
			if i < 6:
				through.kind = "tertiary" if j == 3 else "residential"
				net.road(ids[Vector2i(i, j)], ids[Vector2i(i + 1, j)], through)
			if j < 6:
				var col := grid.duplicate()
				col.kind = "tertiary" if i == 3 else "residential"
				net.road(ids[Vector2i(i, j)], ids[Vector2i(i, j + 1)], col)

	# The oval and the road out to it from the car park.
	var oval := { "kind": "tertiary", "width": 8.0, "sidewalks": false, "speed_kmh": 60 }
	var a := net.node(30, -40)
	var b := net.node(100, -40)
	var c := net.node(100, -160)
	var d := net.node(220, -160)
	var e := net.node(220, -40)
	net.road(a, b, { "kind": "residential", "width": 8.0, "sidewalks": false })
	net.road(b, c, oval)
	net.road(d, e, oval)
	var north: Array = []
	var south: Array = []
	for k in 17:
		var t := PI * k / 16.0
		north.append(Vector3(160.0 - cos(t) * 60.0, Y, -160.0 - sin(t) * 60.0))
		south.append(Vector3(160.0 + cos(t) * 60.0, Y, -40.0 + sin(t) * 60.0))
	net.road(c, d, oval, north)
	net.road(e, b, oval, south)
	return net.data()


## Sandbox suburb, about 840 m square, centred on the origin.
static func sandbox() -> Dictionary:
	var net := Net.new()
	var avenue := { "kind": "primary", "lanes_fwd": 2, "lanes_back": 2, "speed_kmh": 60, "name": "Sandbox Avenue" }
	var secondary := { "kind": "secondary", "speed_kmh": 60, "name": "Station Street" }
	var tertiary := { "kind": "tertiary", "name": "Roundabout Road" }
	var residential := { "kind": "residential" }

	# The avenue, west to east, with signals at Station Street and Roundabout Road.
	var av: Array = [net.node(-420, 0), net.node(-260, 0), net.node(-100, 0, "signals"),
		net.node(60, 0), net.node(220, 0, "signals"), net.node(420, 0)]
	net.street(av, avenue)
	# Station Street runs the full height.
	net.street([net.node(-100, -420), net.node(-100, -200), av[2], net.node(-100, 200), net.node(-100, 420)], secondary)
	# Residential cross streets.
	net.street([net.node(-260, -200), av[1], net.node(-260, 200)], residential)
	net.street([net.node(60, -200), av[3], net.node(60, 200)], residential)
	# A stop sign where the west street meets the avenue's south side.
	var stop_node := net.node(-260, 14, "stop")
	net.roads = net.roads.filter(func(r): return not (r.a == av[1] and r.b == net.node(-260, 200)))
	net.road(av[1], stop_node, residential)
	net.road(stop_node, net.node(-260, 200), residential)

	# Back streets.
	net.street([net.node(-260, -200), net.node(-100, -200), net.node(60, -200)], residential)
	net.street([net.node(-260, 200), net.node(-100, 200), net.node(60, 200), net.node(220, 200)], residential)

	# A single-lane roundabout at (220, -200). Traffic goes clockwise (seen
	# from above) because Australia drives on the left.
	var c := Vector3(220, Y, -200)
	var r := 14.0
	var ring_ids: Array = []
	for k in 4:
		var a := k * PI * 0.5
		ring_ids.append(net.node(c.x + sin(a) * r, c.z - cos(a) * r))
	for k in 4:
		var pts: Array = []
		for step in 7:
			var a := (k + step / 6.0) * PI * 0.5
			pts.append(Vector3(c.x + sin(a) * r, Y, c.z - cos(a) * r))
		net.road(ring_ids[k], ring_ids[(k + 1) % 4], { "kind": "tertiary", "roundabout": true, "speed_kmh": 30 }, pts)
	net.road(net.node(60, -200), ring_ids[3], residential)              # West arm
	net.road(ring_ids[0], net.node(220, -420), tertiary)                # North arm
	net.road(ring_ids[1], net.node(420, -200), tertiary)                # East arm
	net.road(ring_ids[2], av[4], tertiary)                              # South arm to the avenue
	net.road(av[4], net.node(220, 200), tertiary)

	# Two-track railway with level crossings, and a station north of the avenue.
	for x in [-182.0, -178.0]:
		net.rail.append({ "pts": [Vector3(x, Y, -900), Vector3(x, Y, 900)], "kind": "rail" })
	net.stations.append({ "p": Vector3(-180, Y, -110), "name": "Sandbox" })

	# Bus stops on the avenue, one each way.
	net.bus_stops.append({ "p": Vector3(-30, Y, -6.6) })
	net.bus_stops.append({ "p": Vector3(150, Y, 6.6) })
	return net.data()
