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
		_world = _sandbox.world_root
		_sandbox.main.get_node("HUD").visible = false
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
	if shot.get("train", false):
		var west = null
		for e in _traffic.graph.rail_edges:
			if e.pts[0].x < -180.0:
				west = e
		# Northbound on the west track, rear 420 m south of the avenue.
		_train = _traffic.spawn_train_at(west, 1320.0, false, 3)


func _capture(shot_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := _out.path_join(shot_name + ".png")
	image.save_png(path)
	print("saved ", path, "  cars=", _traffic.vehicles.size(), " people=", _traffic.pedestrians.size(), " trains=", _traffic.trains.size())
