extends SceneTree
## Renders screenshots of the Perth map through the game's own camera and
## lo-fi filter. Needs a display (or xvfb), not --headless:
##
##   godot --path . --script res://tools/map_screenshot.gd -- out_dir=/tmp/shots
##
## Shots: the car in the carport at home, the townhouse block from above, an
## aerial view over Northbridge towards the CBD, Kings Park, a street and the
## Narrows.

var _main: Node
var _frame := 0
var _shot := 0
var _out := "user://screenshots"
var _shots := []


func _process(_delta: float) -> bool:
	if _main == null:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("out_dir="):
				_out = arg.trim_prefix("out_dir=")
		DirAccess.make_dir_recursive_absolute(_out)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(float(_arg("hour", "16.5")))
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_shots = [
			{name = "home_chase", wait = 240},
			{name = "traffic_james_st", wait = 900, cam = [Vector3(-125, 0, 2), Vector3(60, 0, 100)], fog = 0.003, above = 5.0},
			{name = "home_block", wait = 240, cam = [Vector3(2, 70, 30), Vector3(-6, 22, -4)], fog = 0.002},
			{name = "aerial_cbd", wait = 240, cam = [Vector3(-100, 260, -450), Vector3(350, 20, 900)], fog = 0.0008},
			{name = "kings_park", wait = 240, cam = [Vector3(-700, 170, 1100), Vector3(-1600, 10, 2300)], fog = 0.0010},
			{name = "street_level", wait = 240, cam = [Vector3(596, 0, 973), Vector3(512, 0, 1178)], fog = 0.0030, above = 2.5},
			{name = "narrows", wait = 240, cam = [Vector3(-1250, 0, 2050), Vector3(-1650, 0, 2500)], fog = 0.0025, above = 9.0},
			{name = "oxford_st", wait = 300, cam = [Vector3(-1136, 0, -1055), Vector3(-1346, 0, -1056)], fog = 0.003, above = 3.0},
			{name = "albany_hwy", wait = 300, cam = [Vector3(4104, 0, 3151), Vector3(4012, 0, 2962)], fog = 0.003, above = 3.0},
			{name = "subiaco_aerial", wait = 300, cam = [Vector3(-2500, 200, 600), Vector3(-3000, 20, 150)], fog = 0.0010},
			{name = "optus_stadium", wait = 300, cam = [Vector3(2800, 180, 1100), Vector3(3317, 20, 580)], fog = 0.0010},
			{name = "fremantle_markets", wait = 300, cam = [Vector3(-9927, 0, 12300), Vector3(-9792, 0, 12461)], fog = 0.003, above = 3.0},
			{name = "cottesloe_aerial", wait = 300, cam = [Vector3(-9288, 157, 5385), Vector3(-9688, 7, 5385)], fog = 0.0012},
			{name = "scarborough_beach", wait = 300, cam = [Vector3(-9213, 0, -5773), Vector3(-9273, 0, -5975)], fog = 0.003, above = 3.0},
			{name = "elizabeth_quay", wait = 300, cam = [Vector3(420, 0, 1560), Vector3(340, 25, 1360)], fog = 0.002, above = 18.0},
			{name = "matagarup_bridge", wait = 300, cam = [Vector3(2380, 0, 960), Vector3(2580, 20, 760)], fog = 0.002, above = 8.0},
			{name = "skyline_south_perth", wait = 300, cam = [Vector3(197, 0, 2442), Vector3(420, 70, 1250)], fog = 0.0012, above = 3.0},
			{name = "skyline_kings_park", wait = 300, cam = [Vector3(-1500, 0, 1250), Vector3(600, 80, 1250)], fog = 0.0006, above = 30.0},
			{name = "night_skyline_kings_park", wait = 300, hour = 21.5, cam = [Vector3(-1500, 0, 1250), Vector3(600, 80, 1250)], fog = 0.0006, above = 30.0},
			{name = "night_skyline", wait = 300, hour = 21.5, cam = [Vector3(197, 0, 2442), Vector3(420, 70, 1250)], fog = 0.0012, above = 3.0},
			{name = "beaufort_st_mt_lawley", wait = 300, cam = [Vector3(1473, 0, -1827), Vector3(1663, 0, -2159)], fog = 0.003, above = 3.0},
			{name = "osborne_park", wait = 300, cam = [Vector3(-3251, 0, -5100), Vector3(-3451, 20, -5400)], fog = 0.0015, above = 60.0},
			{name = "guildford_james_st", wait = 300, cam = [Vector3(10950, 0, -5320), Vector3(11142, 0, -5136)], fog = 0.003, above = 3.0},
			{name = "night_james_st", wait = 300, hour = 22.0, cam = [Vector3(-125, 0, 2), Vector3(60, 0, 100)], fog = 0.003, above = 5.0},
			{name = "night_aerial", wait = 240, hour = 22.0, cam = [Vector3(-100, 260, -450), Vector3(350, 20, 900)], fog = 0.0008},
		]
		var only := _arg("only", "")
		if only != "":
			var names := only.split(",")
			_shots = _shots.filter(func(s): return s.name in names)
		return false
	_frame += 1
	if _shot >= _shots.size():
		quit(0)
		return true
	var shot: Dictionary = _shots[_shot]
	if _frame == 1:
		root.get_node("GameClock").set_time(float(shot.get("hour", float(_arg("hour", "16.5")))))
	if _frame == 1 and shot.has("cam"):
		_place_camera(shot.cam[0], shot.cam[1], shot.get("fog", 0.003))
	if shot.has("above") and _frame % 40 == 0:
		_drop_camera_to_ground(shot.cam[0], shot.cam[1], shot.above)
	if _frame >= shot.wait:
		var img := root.get_texture().get_image()
		var path: String = _out.path_join(shot.name + ".png")
		img.save_png(path)
		print("saved ", path, " tiles loaded: ", _main.get_node("LoFi/SubViewport/World/PerthMap").loaded_tile_count())
		_shot += 1
		_frame = 0
	return false


func _arg(key: String, default: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return arg.trim_prefix(key + "=")
	return default


func _drop_camera_to_ground(from: Vector3, to: Vector3, above: float) -> void:
	var world := _main.get_node("LoFi/SubViewport/World") as Node3D
	var space := world.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(from.x, 120, from.z), Vector3(from.x, -50, from.z)))
	if hit.is_empty():
		return
	var cam := world.get_node("CameraRig/Camera3D") as Camera3D
	cam.global_position = Vector3(from.x, hit.position.y + above, from.z)
	cam.look_at(Vector3(to.x, hit.position.y + above * 0.6, to.z))


func _place_camera(from: Vector3, to: Vector3, fog: float) -> void:
	var world := _main.get_node("LoFi/SubViewport/World")
	(world.get_node("Car") as RigidBody3D).freeze = true
	_main.get_node("HUD").visible = false
	var rig := world.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.global_position = from
	cam.look_at(to)
	cam.fov = 60
	cam.far = 6000.0
	var env_ctl := world.get_node("EnvironmentController")
	env_ctl.fog_density_clear = fog
	# Stream around the camera instead of the car.
	var map := world.get_node("PerthMap")
	map.set("_target", cam)
