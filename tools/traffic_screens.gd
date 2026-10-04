extends SceneTree
## Screenshots of the traffic sandbox for review. Needs a display (xvfb):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1280x720 --fixed-fps 60 --script res://tools/traffic_screens.gd -- <out_dir> [shot name filter]
##
## Writes PNGs to <out_dir> (default user://traffic_screens).

var _out := "user://traffic_screens"
var _sandbox: Node
var _traffic
var _world: Node3D
var _cam: Camera3D
var _shots: Array = []
var _shot := -1
var _frames := 0
var _waiting_for: Callable
var _train


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_shots = [
		{ "name": "day_chase", "time": 8.3, "weather": 0, "sim": 25.0 },
		{ "name": "day_junction", "time": 8.4, "weather": 0, "sim": 4.0, "cam": [Vector3(-62, 26, 42), Vector3(-104, 0, -2)] },
		{ "name": "roundabout", "time": 9.0, "weather": 0, "sim": 12.0, "cam": [Vector3(252, 24, -168), Vector3(220, 0, -200)] },
		{ "name": "footpath", "time": 12.5, "weather": 0, "sim": 8.0, "cam": [Vector3(-113, 1.6, 9.0), Vector3(-98, 1.0, 10.5)] },
		{ "name": "level_crossing", "time": 16.8, "weather": 0, "sim": 2.0, "train": true, "until_front_z": 75.0, "cam": [Vector3(-163, 4.0, -16), Vector3(-181, 1.5, 22)] },
		{ "name": "station", "time": 16.9, "weather": 0, "sim": 1.0, "until_dwell": true, "cam": [Vector3(-158, 7.0, -58), Vector3(-182, 2.0, -112)] },
		{ "name": "dusk_rain", "time": 18.6, "weather": 1, "sim": 14.0, "cam": [Vector3(-60, 18, 36), Vector3(-104, 0, -2)] },
		{ "name": "rain_umbrellas", "time": 18.7, "weather": 1, "sim": 6.0, "cam": [Vector3(-120, 1.8, 14), Vector3(-96, 1.0, 8)] },
		{ "name": "night_avenue", "time": 22.0, "weather": 0, "sim": 12.0, "cam": [Vector3(-84, 3.2, 9.5), Vector3(-200, 1.0, -2)] },
		{ "name": "night_chase", "time": 22.1, "weather": 0, "sim": 6.0 },
		{ "name": "car_park_day", "time": 11.0, "weather": 0, "sim": 3.0, "cam": [Vector3(-24, 9, -22), Vector3(-56, 0, -44)] },
		{ "name": "car_park_night", "time": 2.0, "weather": 0, "sim": 3.0, "cam": [Vector3(-24, 9, -22), Vector3(-56, 0, -44)] },
		{ "name": "street_parking", "time": 21.0, "weather": 0, "sim": 3.0, "cam": [Vector3(-93, 2.0, -160), Vector3(-90, 0.8, -110)] },
		{ "name": "ambulance", "time": 10.5, "weather": 0, "sim": 6.5, "setup": "_setup_ambulance", "cam": [Vector3(52, 4.0, 13), Vector3(130, 1.0, 3)] },
		{ "name": "cyclist", "time": 9.5, "weather": 0, "sim": 2.5, "setup": "_setup_cyclist", "cam": [Vector3(122, 2.2, 10.5), Vector3(170, 0.8, 4)] },
		{ "name": "roadworks", "time": 10.0, "weather": 0, "sim": 25.0, "setup": "_setup_roadworks", "cam": [Vector3(70, 7.0, 16), Vector3(150, 0.5, 3)] },
		{ "name": "roadworks_night", "time": 21.5, "weather": 0, "sim": 25.0, "setup": "_setup_roadworks", "cam": [Vector3(70, 7.0, 16), Vector3(150, 0.5, 3)] },
	]
	if args.size() > 1:
		# Optional second argument: render only the shots whose names contain it.
		_shots = _shots.filter(func(shot): return args[1] in shot.name)


func _process(_delta: float) -> bool:
	if _sandbox == null:
		_sandbox = load("res://traffic/sandbox/traffic_sandbox.tscn").instantiate()
		root.add_child(_sandbox)
		return false
	if _traffic == null:
		_traffic = _sandbox.traffic
		# Roadworks only where a shot puts them.
		_traffic.roadworks.site_chance = 0.0
		_world = _sandbox.world_root
		_sandbox.main.get_node("HUD").visible = false
		# The on-foot player's "Get out" prompt isn't part of the picture.
		for layer in _sandbox.main.find_children("*", "CanvasLayer", true, false):
			if layer.get_parent() is CharacterBody3D:
				layer.visible = false
		_cam = Camera3D.new()
		_cam.far = 1500.0
		_world.add_child(_cam)
		_next_shot()
		return false
	_frames += 1
	var shot: Dictionary = _shots[_shot]
	var ready := _frames >= int(shot.sim * 60.0)
	if ready and shot.has("until_front_z"):
		ready = _train != null and _train.cars[0].global_position.z < shot.until_front_z
	if ready and shot.has("until_dwell"):
		ready = _train != null and _train.dwell > 0.0 and _train.dwell < 11.0
	if _frames > 60 * 120:
		ready = true
	if ready:
		_capture(shot.name)
		if _shot + 1 >= _shots.size():
			print("done: ", _out)
			quit(0)
			return true
		_next_shot()
	return false


func _next_shot() -> void:
	_shot += 1
	_frames = 0
	var shot: Dictionary = _shots[_shot]
	var clock := root.get_node("GameClock")
	clock.set_time(shot.time)
	clock.set_locked(true)
	var weather := root.get_node("Weather")
	weather.set_state(shot.weather, true)
	weather.set_locked(true)
	# Parked cars only change out of sight; start each shot from a fresh draw.
	_traffic.parking.clear()
	if shot.has("cam"):
		_cam.look_at_from_position(shot.cam[0], shot.cam[1])
		_cam.current = true
	else:
		_cam.current = false
		_world.get_node("CameraRig/Camera3D").current = true
	_traffic.roadworks.clear()
	if shot.has("setup"):
		call(shot.setup)
	if shot.get("train", false):
		var west = null
		for e in _traffic.graph.rail_edges:
			if e.pts[0].x < -180.0:
				west = e
		# Northbound on the west track, rear 420 m south of the avenue.
		_train = _traffic.spawn_train_at(west, 1320.0, false, 3)


## The avenue's westbound kerb lane between the Roundabout Road lights and the
## next corner (x 60 to 220).
func _avenue_lane() -> TrafficGraph.Lane:
	for lane in _traffic.graph.lanes:
		if lane.connector or lane.road == null or lane.road.name != "Sandbox Avenue":
			continue
		var a: Vector3 = lane.point(0.0)
		var b: Vector3 = lane.point(lane.length)
		if a.x > b.x and a.x > 150.0 and b.x < 90.0 and lane.k == lane.count - 1:
			return lane
	return null


func _clear_lane(lane: TrafficGraph.Lane) -> void:
	for v in lane.vehicles.duplicate():
		_traffic._despawn_vehicle(v)


func _setup_ambulance() -> void:
	var lane := _avenue_lane()
	if lane == null:
		return
	_clear_lane(lane)
	_traffic.spawn_vehicle_at(&"sedan", lane, 70.0, 7.0)
	_traffic.spawn_vehicle_at(&"hatch", lane, 85.0, 7.0)
	_traffic.spawn_vehicle_at(&"ambulance", lane, 2.0, 13.0)
	_aim(lane, 100.0, -4.6, 2.3, 72.0)


func _setup_cyclist() -> void:
	var lane := _avenue_lane()
	if lane == null:
		return
	_clear_lane(lane)
	_traffic.spawn_vehicle_at(&"bike", lane, 30.0, 5.5)
	_traffic.spawn_vehicle_at(&"suv", lane, 4.0, 12.0)
	_aim(lane, 8.0, -1.8, 2.6, 50.0)


func _setup_roadworks() -> void:
	var lane := _avenue_lane()
	if lane == null:
		return
	var road: TrafficGraph.Road = lane.road
	var site: Dictionary = _traffic.roadworks.add_site(road, lane.from_node == road.a, lane.k, road.length * 0.42, road.length * 0.42 + 50.0)
	_aim(lane, lane.closed[0] - 30.0, 7.0, 5.0, lane.closed[0] + 15.0)


## Camera beside `lane` at `s` (`side` metres to its left, `height` up),
## looking at the lane at `look_s`.
func _aim(lane: TrafficGraph.Lane, s: float, side: float, height: float, look_s: float) -> void:
	var p := lane.point(s) + TrafficGraph.left_of(lane.tangent(s)) * side + Vector3(0, height, 0)
	_cam.look_at_from_position(p, lane.point(look_s) + Vector3(0, 0.8, 0))
	_cam.current = true
	# Keep traffic alive around the camera rather than the parked player.
	_traffic.focus_path = _traffic.get_path_to(_cam)


func _capture(shot_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := _out.path_join(shot_name + ".png")
	image.save_png(path)
	print("saved ", path, "  cars=", _traffic.vehicles.size(), " people=", _traffic.pedestrians.size(), " trains=", _traffic.trains.size())
