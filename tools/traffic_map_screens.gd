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
	# [name, hour, weather, seconds to simulate, junction near, camera height, distance back]
	# The camera stands back along the junction's busiest approach road,
	# where the street keeps buildings out of the way.
	_shots = [
		["william_wellington", 8.2, 0, 24.0, Vector3(391, 25, 587), 14.0, 40.0],
		["st_georges_tce", 8.4, 0, 24.0, Vector3(550, 47, 1090), 14.0, 40.0],
		["barrack_street_level", 12.5, 0, 20.0, Vector3(553, 47, 1080), 1.7, 22.0],
		["mitchell_freeway", 17.3, 0, 24.0, Vector3(-310, 20, 30), 14.0, 70.0],
		["narrows_bridge", 17.5, 0, 22.0, Vector3(-1500, 35, 2300), 16.0, 90.0],
		["perth_station", 9.0, 0, 4.0, Vector3.ZERO, 0.0, 0.0],
		["northbridge_rain", 18.4, 1, 22.0, Vector3(60, 18, 205), 9.0, 30.0],
		["william_night", 22.0, 0, 22.0, Vector3(391, 25, 587), 6.0, 30.0],
	]
	if args.size() > 1:
		# Optional second argument: render only the shots whose names contain it.
		_shots = _shots.filter(func(shot): return args[1] in shot[0])


func _process(_delta: float) -> bool:
	if _main == null:
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
		return false
	if _shot < 0:
		_next_shot()
		return false
	_frames += 1
	var shot: Array = _shots[_shot]
	if _frames == int(shot[3] * 60.0) - 20 and shot[0] != "perth_station":
		var view := _junction_view(shot[4], shot[5], shot[6])
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
	clock.set_time(shot[1])
	clock.set_locked(true)
	var weather := root.get_node("Weather")
	weather.set_state(shot[2], true)
	weather.set_locked(true)
	var target: Vector3 = shot[4]
	var cam_pos := target + Vector3(30, 30, 30)
	if shot[0] == "perth_station":
		var pick := _station_view()
		if pick.is_empty():
			print("no station found; skipping")
			_frames = 1 << 30
			return
		cam_pos = pick[0]
		target = pick[1]
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


## A camera on a city station's platform end, with a train on its way in.
func _station_view() -> Array:
	for edge in _traffic.graph.rail_edges:
		for st in edge.stations:
			if st.s < 260.0 or st.s > edge.length - 40.0:
				continue
			var p: Vector3 = TrafficGraph.point_at(edge.pts, edge.cum, st.s)
			var ahead: Vector3 = TrafficGraph.point_at(edge.pts, edge.cum, st.s + 30.0)
			var dir := (ahead - p).normalized()
			_train = _traffic.spawn_train_at(edge, st.s - 250.0, true, 4)
			print("station: ", st.name, " at ", p)
			var side := Vector3(dir.z, 0, -dir.x)
			return [p + dir * 75.0 + side * 9.0 + Vector3(0, 5.0, 0), p - dir * 20.0 + Vector3(0, 1.5, 0)]
	return []


func _capture(shot_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := _out.path_join(shot_name + ".png")
	image.save_png(path)
	print("saved ", path, "  cars=", _traffic.vehicles.size(), " people=", _traffic.pedestrians.size(), " trains=", _traffic.trains.size())
