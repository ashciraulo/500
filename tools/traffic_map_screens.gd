extends SceneTree
## Screenshots of traffic on the Perth map, for review. Needs a display (xvfb):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1280x720 --fixed-fps 60 --script res://tools/traffic_map_screens.gd -- <out_dir> [shot name filter]
##
## The car hovers above each spot so the map and traffic stream in around
## it; a free camera takes the picture.

var _out := "user://traffic_map_screens"
var _main: Node
var _map: Node3D
var _car: RigidBody3D
var _traffic
var _cam: Camera3D
var _shots: Array = []
var _shot := -1
var _frames := 0
var _train


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	# [name, hour, weather, seconds to simulate, junction near, camera height, distance back, (day: 1 is a Monday)]
	# The camera stands back along the junction's busiest approach road,
	# where the street keeps buildings out of the way. Freeway shots (height
	# over 12 m) follow the busiest stretch of traffic near the spot instead.
	_shots = [
		["william_wellington", 8.2, 0, 24.0, Vector3(391, 25, 587), 14.0, 40.0],
		["st_georges_tce", 8.4, 0, 24.0, Vector3(550, 47, 1090), 14.0, 40.0],
		["barrack_street_level", 12.5, 0, 20.0, Vector3(553, 47, 1080), 1.7, 22.0],
		["mitchell_freeway", 17.3, 0, 24.0, Vector3(-310, 20, 30), 14.0, 70.0],
		["narrows_bridge", 17.5, 0, 22.0, Vector3(-1500, 35, 2300), 16.0, 90.0],
		["perth_station", 9.0, 0, 8.0, Vector3(390, 25, 560), 0.0, 0.0],
		["northbridge_rain", 18.4, 1, 22.0, Vector3(60, 18, 205), 9.0, 30.0],
		["william_night", 22.0, 0, 22.0, Vector3(391, 25, 587), 6.0, 30.0],
		["northbridge_tuesday_night", 23.0, 0, 30.0, Vector3(380, 20, 60), 4.0, 25.0, 2],
		["northbridge_saturday_night", 23.0, 0, 30.0, Vector3(380, 20, 60), 4.0, 25.0, 6],
		["shenton_lane_mouth", 17.6, 0, 40.0, Vector3(-57.5, 21, 38.8), 7.0, 32.0],
		["wildlife_russell_square", 9.5, 0, 16.0, Vector3(160, 20, 66), 1.2, 7.0],
		["wildlife_hyde_park", 16.5, 0, 16.0, Vector3(812, 20, -827), 1.2, 7.0],
		["wildlife_kings_park_dusk", 18.3, 0, 16.0, Vector3(-1500, 50, 1400), 1.4, 11.0],
		["river_ferry_elizabeth_quay", 10.0, 0, 14.0, Vector3(220, 0, 1350), 4.0, 38.0],
		["river_boats_saturday", 15.0, 0, 14.0, Vector3(650, 0, 1800), 3.5, 0.0, 6],
		["river_ferry_night", 19.4, 0, 14.0, Vector3(220, 0, 1350), 4.0, 38.0],
		["kerbside_courier", 10.5, 0, 16.0, Vector3(500, 30, 800), 2.2, 12.0],
		["kerbside_taxi_rank", 9.0, 0, 16.0, Vector3(390, 25, 560), 2.5, 10.0],
		["kerbside_taxi_rank_night", 22.5, 0, 16.0, Vector3(390, 25, 560), 2.5, 10.0, 6],
		["kerbside_inspector", 11.0, 0, 16.0, Vector3(400, 25, 700), 1.7, 7.0],
	]
	if args.size() > 1:
		# Optional second argument: render only the shots whose names contain it.
		_shots = _shots.filter(func(shot): return args[1] in shot[0])


func _process(_delta: float) -> bool:
	if _main == null:
		# Never write a save file, which would move the next run's start.
		root.get_node("SaveGame").enabled = false
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		var world: Node3D = _main.get_node("LoFi/SubViewport/World")
		_map = world.get_node("PerthMap")
		_car = world.get_node("Car")
		_traffic = world.get_node("Traffic")
		_traffic.random_seed = 500
		_cam = Camera3D.new()
		_cam.far = 2500.0
		world.add_child(_cam)
		_main.get_node("HUD").visible = false
		_car.visible = false
		# The on-foot player's "Get out" prompt isn't part of the picture.
		for child in world.get_children():
			if child is CharacterBody3D and "in_car" in child:
				for layer in child.get_children():
					if layer is CanvasLayer:
						layer.visible = false
		return false
	if _shot < 0:
		_next_shot()
		return false
	_frames += 1
	var shot: Array = _shots[_shot]
	if _frames == 300 and shot[0] == "perth_station":
		# The tiles around the station have streamed in by now.
		var pick := _station_view()
		if pick.is_empty():
			print("no station found (%d rail edges, %d stations); skipping" % [_traffic.graph.rail_edges.size(), _traffic.graph.stations.size()])
		else:
			_cam.look_at_from_position(pick[0], pick[1])
	if _frames == int(shot[3] * 60.0) - 20 and shot[0] != "perth_station":
		var view: Array
		if shot[0] == "shenton_lane_mouth":
			view = _across_view(shot[4], shot[5], shot[6])
		elif shot[0].begins_with("wildlife"):
			view = _wildlife_view(shot[0], shot[4], shot[5], shot[6])
		elif shot[0].begins_with("river"):
			view = _river_view(shot[0], shot[5], shot[6])
		elif shot[0].begins_with("kerbside"):
			view = _kerbside_view(shot[0], shot[4], shot[5], shot[6])
		elif shot[5] <= 12.0:
			view = _junction_view(shot[4], shot[5], shot[6])
		else:
			view = _traffic_view(shot[4], shot[5], shot[6])
		_cam.look_at_from_position(view[0], view[1])
	var ready := _frames >= int(shot[3] * 60.0)
	if ready and shot[0] == "perth_station" and _train != null:
		ready = _train.dwell > 0.5 or _frames > 60 * 90
	if ready:
		_capture(shot[0])
		if _shot + 1 >= _shots.size():
			print("done: ", _out)
			quit(0)
			return true
		_next_shot()
	return false


func _next_shot() -> void:
	_shot += 1
	_frames = 0
	_train = null
	var shot: Array = _shots[_shot]
	var clock := root.get_node("GameClock")
	clock.day = shot[7] if shot.size() > 7 else 2
	var hour: float = shot[1]
	if shot[0].begins_with("river_ferry"):
		# Wind on to when the ferry has just left Elizabeth Quay.
		for k in 2000:
			var st: Array = TrafficBoats.ferry_state(hour, clock.seconds_per_day)
			var out: float = st[0].distance_to(TrafficBoats.FERRY_ROUTE[0])
			if not st[2] and out > 120.0 and out < 260.0:
				break
			hour += 0.002
	clock.set_time(hour)
	clock.set_locked(true)
	var weather := root.get_node("Weather")
	weather.set_state(shot[2], true)
	weather.set_locked(true)
	var target: Vector3 = shot[4]
	var cam_pos := target + Vector3(30, 30, 30)
	_car.freeze = true
	_car.global_position = target + Vector3(0, 30, 0)
	_traffic.clear_all()
	_cam.look_at_from_position(cam_pos, target)
	_cam.current = true


## Stand back along the busiest road into the junction nearest `near`.
func _junction_view(near: Vector3, height: float, back: float) -> Array:
	var best = null
	var best_d := INF
	for id in _traffic.graph.nodes:
		var n = _traffic.graph.nodes[id]
		if n.degree() >= 3 and n.pos.distance_to(near) < best_d:
			best_d = n.pos.distance_to(near)
			best = n
	if best == null:
		return [near + Vector3(30, 30, 30), near]
	# The approach with the most cars queued on it, then the widest.
	var road = null
	var road_score := -1.0
	for r in best.roads:
		var score: float = r.lanes_fwd + r.lanes_back + minf(r.length, back) * 0.01
		for lane in r.lanes:
			score += lane.vehicles.size() * 4.0
		if score > road_score:
			road_score = score
			road = r
	var from_end: bool = road.b == best
	var s: float = clampf(back, 0.0, road.length) if not from_end else road.length - clampf(back, 0.0, road.length)
	var p: Vector3 = TrafficGraph.point_at(road.pts, road.cum, s)
	var out: Vector3 = (p - best.pos)
	out.y = 0.0
	var side: Vector3 = Vector3(out.z, 0, -out.x).normalized() * road.half_width * 0.3
	return [p + side + Vector3(0, height, 0), best.pos + Vector3(0, 1.0, 0)]


## Along the road past `near`, looking back at it (for the keep-clear box
## at the end of Little Shenton Lane).
func _across_view(near: Vector3, height: float, back: float) -> Array:
	var best = null
	var best_d := INF
	for entry in _traffic.graph.samples_near(near, 20.0):
		var lane = entry[0]
		if lane.connector:
			continue
		var s := TrafficGraph.closest_s(lane.pts, lane.cum, near)
		var d: float = lane.point(s).distance_to(near)
		if d < best_d:
			best_d = d
			best = [lane, s]
	if best == null:
		return [near + Vector3(30, 30, 30), near]
	# Up the road from the lane mouth, a little off to its side, so the
	# queue and the gap left for the lane are both in view.
	var lane = best[0]
	var p: Vector3 = lane.point(best[1])
	var dir: Vector3 = (lane.point(minf(best[1] + 5.0, lane.length)) - lane.point(maxf(best[1] - 5.0, 0.0))).normalized()
	var side: Vector3 = (near - p)
	side.y = 0.0
	side = side.normalized() if side.length() > 0.3 else Vector3(dir.z, 0, -dir.x)
	print("across view on ", lane.road.name, " (", lane.vehicles.size(), " cars on the lane)")
	return [p + dir * back - side * 6.0 + Vector3(0, height, 0), p + side * 2.0]


## Find grass near `near` (clear of the car hovering above it, which would
## scare them off), put some animals on it, and look at them from `back`.
func _wildlife_view(shot_name: String, near: Vector3, height: float, back: float) -> Array:
	var wild: TrafficWildlife = _traffic.wildlife
	var roo := "kings_park" in shot_name
	var want: Array = [&"grass", &"dirt"] if roo else [&"grass"]
	for r in range(25, 200, 10):
		for i in 24:
			var ang := TAU * i / 24.0
			var g: Dictionary = wild._ground(near + Vector3(cos(ang), 0, sin(ang)) * r)
			if g.is_empty() or not want.has(g.surface):
				continue
			# A proper patch of it, with room for the camera on it too.
			var open := true
			for k in 6:
				var q: Dictionary = wild._ground(g.pos + Vector3(cos(TAU * k / 6.0), 0, sin(TAU * k / 6.0)) * back)
				open = open and not q.is_empty() and want.has(q.surface) and absf(q.pos.y - g.pos.y) < 2.5
			if not open:
				continue
			var p: Vector3 = g.pos
			if roo:
				wild.spawn_group(TrafficWildlife.Kind.ROO, p, 2)
				wild.spawn_group(TrafficWildlife.Kind.MAGPIE, p + Vector3(4, 0, -2), 1)
			else:
				wild.spawn_group(TrafficWildlife.Kind.IBIS, p, 4, false)
				wild.spawn_group(TrafficWildlife.Kind.MAGPIE, p + Vector3(3, 0, 2), 2, false)
			var out := Vector3(cos(ang), 0, sin(ang))
			var cam_g: Dictionary = wild._ground(p + out * back)
			var cam_y: float = cam_g.pos.y if not cam_g.is_empty() else p.y
			print("wildlife on ", g.surface, " at ", p, " (", wild.animals.size(), " animals)")
			return [Vector3(p.x, cam_y, p.z) + out * back + Vector3(0, height, 0), p + Vector3(0, 0.5, 0)]
	print("no grass found near ", near)
	return [near + Vector3(30, 30, 30), near]


## The ferry pulling out of Elizabeth Quay, from off its beam; or, for the
## boats shot, the South Perth side looking across Perth Water at the city
## with boats put out on it.
func _river_view(shot_name: String, height: float, back: float) -> Array:
	var boats: TrafficBoats = _traffic.boats
	if shot_name.begins_with("river_ferry"):
		var f: Node3D = boats.ferry
		if f == null:
			print("no ferry")
			return [Vector3(260, 20, 1450), TrafficBoats.FERRY_ROUTE[0]]
		var fwd := -f.global_basis.z
		var side := Vector3(-fwd.z, 0, fwd.x)
		print("ferry at ", f.global_position)
		return [f.global_position + side * back - fwd * 30.0 + Vector3(0, height, 0), f.global_position + Vector3(0, 2, 0)]
	var cam := Vector3(700, height, 2125)
	var spots := [Vector3(690, 0, 2085), Vector3(735, 0, 2065), Vector3(650, 0, 2050), Vector3(770, 0, 2020), Vector3(610, 0, 2000), Vector3(705, 0, 1985)]
	var kinds := [TrafficBoats.Kind.RUNABOUT, TrafficBoats.Kind.YACHT, TrafficBoats.Kind.YACHT, TrafficBoats.Kind.RUNABOUT, TrafficBoats.Kind.YACHT, TrafficBoats.Kind.YACHT]
	var put := 0
	for i in spots.size():
		if not boats.spawn_boat(kinds[i], spots[i]).is_empty():
			put += 1
	print("boats out: ", put, " of ", spots.size(), " (", boats.boats.size(), " on the river)")
	return [cam, Vector3(680, 4, 1700)]


## A courier double-parked, the taxi rank at the nearest station, or a
## parking inspector on their rounds, near `near`.
func _kerbside_view(shot_name: String, near: Vector3, height: float, back: float) -> Array:
	var kb: TrafficKerbside = _traffic.kerbside
	kb.clear()
	if "courier" in shot_name:
		var best = null
		for entry in _traffic.graph.samples_near(near, 300.0):
			var lane: TrafficGraph.Lane = entry[0]
			if lane.connector or lane.length < 90.0:
				continue
			var s := lane.length * 0.5
			if kb.van_fits(lane, s) and (best == null or lane.point(s).distance_to(near) < best[0].point(best[1]).distance_to(near)):
				best = [lane, s]
		if best == null:
			print("no lane for a van near ", near)
			return [near + Vector3(30, 30, 30), near]
		var van := kb.add_van(best[0], best[1], 10.0)
		van.courier_t = 0.55
		van.courier_wait = 0.0
		var dir: Vector3 = van.dir
		var side := TrafficGraph.left_of(dir)
		print("courier at ", van.pos)
		return [van.pos - dir * back - side * 3.5 + Vector3(0, height, 0), van.pos + dir * 2.0 + Vector3(0, 1.0, 0)]
	if "taxi" in shot_name:
		var st_best = null
		for st in _traffic.graph.stations:
			if st_best == null or st.pos.distance_to(near) < st_best.pos.distance_to(near):
				st_best = st
		var spot: Array = kb._rank_spot(st_best.pos) if st_best != null else []
		if spot.is_empty():
			print("no rank spot")
			return [near + Vector3(30, 30, 30), near]
		var rank := kb.add_rank(st_best.name, spot[0], spot[1])
		var front := kb.rank_slot_transform(rank, 0)
		var rear := kb.rank_slot_transform(rank, TrafficKerbside.RANK_SLOTS - 1).origin
		var fwd := -front.basis.z
		var side := TrafficGraph.left_of(fwd)
		print("taxi rank at ", st_best.name, " ", front.origin)
		# From the road behind the queue, looking up it.
		return [rear - fwd * back - side * 3.8 + Vector3(0, height, 0), front.origin + Vector3(0, 0.8, 0)]
	# An inspector at a parked car.
	var spots: Array = _traffic.graph.parking_near(near, 300.0)
	spots.sort_custom(func(a, b): return a.pos.distance_to(near) < b.pos.distance_to(near))
	for spot in spots:
		if spot.kind != &"street" or not _traffic.parking.shown.has(spot):
			continue
		# Properly at a kerb, beside a lane at the same height.
		var by_lane := false
		for entry in _traffic.graph.samples_near(spot.pos, 8.0):
			var q: Vector3 = entry[0].point(TrafficGraph.closest_s(entry[0].pts, entry[0].cum, spot.pos))
			if absf(q.y - spot.pos.y) < 0.8 and Vector2(q.x - spot.pos.x, q.z - spot.pos.z).length() < 6.0:
				by_lane = true
		if not by_lane:
			continue
		var path := kb._kerb_walk(spot)
		if path.size() < 3:
			continue
		var ins := kb.add_inspector(path)
		ins.wait = 30.0
		var car: Node3D = _traffic.parking.shown[spot]
		var look: Vector3 = car.global_position - ins.node.position
		look.y = 0.0
		ins.node.basis = Basis.looking_at(look.normalized(), Vector3.UP)
		ins.node.get_node("Body/Device").visible = true
		var out: Vector3 = (ins.node.position - car.global_position)
		out.y = 0.0
		out = out.normalized()
		var along := out.cross(Vector3.UP)
		print("inspector at ", ins.node.position)
		return [ins.node.position + out * 2.0 + along * back + Vector3(0, height, 0), ins.node.position + Vector3(0, 1.0, 0) - along * 1.5]
	print("no parked street car near ", near)
	return [near + Vector3(30, 30, 30), near]


## Behind and above the car near `near` with the most company, looking
## down the road ahead of it.
func _traffic_view(near: Vector3, height: float, back: float) -> Array:
	var best = null
	var best_score := -INF
	for v in _traffic.vehicles:
		var company := 0
		for o in _traffic.vehicles:
			if o != v and o.position.distance_to(v.position + v.forward * 25.0) < 30.0:
				company += 1
		var score: float = company * 50.0 - v.position.distance_to(near)
		if score > best_score:
			best_score = score
			best = v
	if best == null:
		return [near + Vector3(30, 30, 30), near]
	return [best.position - best.forward * back + Vector3(0, height, 0), best.position + best.forward * 30.0]


## A camera on Perth station's platform end (or another city station), with
## a train on its way in.
func _station_view() -> Array:
	var pick = null
	for edge in _traffic.graph.rail_edges:
		for st in edge.stations:
			if st.s > edge.length - 5.0:
				continue
			if pick == null or (st.name == "Perth" and pick[1].name != "Perth"):
				pick = [edge, st]
	if pick == null:
		return []
	var edge = pick[0]
	var st = pick[1]
	var p: Vector3 = TrafficGraph.point_at(edge.pts, edge.cum, st.s)
	var ahead: Vector3 = TrafficGraph.point_at(edge.pts, edge.cum, st.s + 30.0)
	var dir := (ahead - p).normalized()
	_train = _traffic.spawn_train_at(edge, maxf(st.s - 250.0, 0.0), true, 4)
	print("station: ", st.name, " at ", p)
	var side := Vector3(dir.z, 0, -dir.x)
	return [p + dir * 75.0 + side * 9.0 + Vector3(0, 5.0, 0), p - dir * 20.0 + Vector3(0, 1.5, 0)]


func _capture(shot_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := _out.path_join(shot_name + ".png")
	image.save_png(path)
	print("saved ", path, "  cars=", _traffic.vehicles.size(), " people=", _traffic.pedestrians.size(), " trains=", _traffic.trains.size())
