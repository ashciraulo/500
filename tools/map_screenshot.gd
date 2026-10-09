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
			{name = "lm_bell_tower", wait = 300, cam = [Vector3(520, 70, 1560), Vector3(408, 40, 1439)], fog = 0.002},
			{name = "lm_eq_bridge", wait = 300, cam = [Vector3(110, 0, 1560), Vector3(177, 8, 1472)], fog = 0.002, above = 6.0},
			{name = "lm_matagarup", wait = 300, cam = [Vector3(2700, 12, 760), Vector3(2884, 38, 991)], fog = 0.0015},
			{name = "lm_optus", wait = 300, cam = [Vector3(3020, 110, 860), Vector3(3346, 10, 567)], fog = 0.0012},
			{name = "night_lm_optus", wait = 300, hour = 21.5, cam = [Vector3(3020, 110, 860), Vector3(3346, 10, 567)], fog = 0.0012},
			{name = "lm_memorial", wait = 300, cam = [Vector3(-850, 66, 1676), Vector3(-877, 72, 1647)], fog = 0.002},
			{name = "lm_round_house", wait = 300, cam = [Vector3(-10610, 24, 12245), Vector3(-10637, 17, 12218)], fog = 0.003},
			{name = "lm_indiana", wait = 300, cam = [Vector3(-9735, 14, 5455), Vector3(-9678, 13, 5494)], fog = 0.003},
			{name = "herdsman_lake", wait = 400, cam = [Vector3(-3950, 90, -2350), Vector3(-4500, 5, -2850)], fog = 0.0012},
			{name = "bold_park", wait = 300, cam = [Vector3(-6700, 180, -100), Vector3(-7273, 30, -715)], fog = 0.0010},
			{name = "point_walter", wait = 300, cam = [Vector3(-6000, 120, 6900), Vector3(-6370, 2, 7224)], fog = 0.0012},
			{name = "alfred_cove", wait = 300, cam = [Vector3(-3300, 140, 8700), Vector3(-3752, 2, 9052)], fog = 0.0012},
			{name = "trigg", wait = 300, cam = [Vector3(-9300, 120, -7300), Vector3(-9672, 5, -7633)], fog = 0.0012},
			{name = "north_mole", wait = 300, cam = [Vector3(-11600, 120, 11450), Vector3(-11929, 2, 11786)], fog = 0.0012},
			{name = "cottesloe_groyne", wait = 300, cam = [Vector3(-9640, 70, 5420), Vector3(-9790, 0, 5500)], fog = 0.002},
			{name = "fishing_boat_harbour", wait = 300, cam = [Vector3(-10050, 80, 12560), Vector3(-10204, 0, 12676)], fog = 0.0015},
			{name = "claisebrook_cove", wait = 300, cam = [Vector3(2420, 30, 560), Vector3(2360, 1, 670)], fog = 0.002},
			{name = "lm_council_house", wait = 300, cam = [Vector3(700, 0, 1225), Vector3(645, 26, 1185)], fog = 0.002, above = 4.0},
			{name = "night_lm_council_house", wait = 300, hour = 21.5, cam = [Vector3(700, 0, 1225), Vector3(645, 26, 1185)], fog = 0.002, above = 4.0},
			{name = "lm_dna_tower", wait = 300, cam = [Vector3(-1705, 0, 2048), Vector3(-1673, 68, 2028)], fog = 0.002, above = 4.0},
			{name = "lm_rac_arena", wait = 300, cam = [Vector3(-40, 0, 420), Vector3(-191, 30, 269)], fog = 0.0015, above = 25.0},
			{name = "night_lm_rac_arena", wait = 300, hour = 21.5, cam = [Vector3(-40, 0, 420), Vector3(-191, 30, 269)], fog = 0.0015, above = 25.0},
			{name = "lm_fremantle_markets", wait = 300, cam = [Vector3(-9800, 0, 12260), Vector3(-9863, 8, 12201)], fog = 0.003, above = 12.0},
			{name = "lm_rendezvous", wait = 300, cam = [Vector3(-9420, 0, -5650), Vector3(-9188, 35, -5803)], fog = 0.0015, above = 20.0},
			{name = "pelican_point", wait = 300, cam = [Vector3(-2300, 90, 4400), Vector3(-2525, 0, 4616)], fog = 0.0015},
			{name = "garratt_rd_bridge", wait = 300, cam = [Vector3(5900, 60, -1800), Vector3(6041, 0, -1614)], fog = 0.0015},
			{name = "baigup_wetlands", wait = 300, cam = [Vector3(5200, 70, -1600), Vector3(5361, 0, -1398)], fog = 0.0015},
			{name = "ashfield_flats", wait = 300, cam = [Vector3(8500, 70, -3300), Vector3(8671, 0, -3098)], fog = 0.0015},
			{name = "bull_creek_mouth", wait = 300, cam = [Vector3(300, 70, 9650), Vector3(480, 0, 9827)], fog = 0.0015},
			{name = "kent_st_weir", wait = 300, cam = [Vector3(6150, 50, 8200), Vector3(6318, 0, 8355)], fog = 0.0015},
			{name = "prop_kent_st_weir", wait = 300, cam = [Vector3(6270, 10, 8385), Vector3(6316, 1, 8354)], fog = 0.002},
			{name = "prop_garratt_jetty", wait = 300, cam = [Vector3(6022, 12, -1598), Vector3(6045, 5, -1622)], fog = 0.002},
			{name = "prop_pelican_club", wait = 300, cam = [Vector3(-2650, 14, 4368), Vector3(-2671, 3, 4413)], fog = 0.002},
			{name = "prop_pelican_tip", wait = 300, cam = [Vector3(-2530, 35, 4565), Vector3(-2510, 1, 4615)], fog = 0.002},
			{name = "prop_pelican_top", wait = 300, cam = [Vector3(-2560, 220, 4600), Vector3(-2560, 0, 4601)], fog = 0.001},
			{name = "lm_state_war_memorial", wait = 300, cam = [Vector3(-1000, 75, 1700), Vector3(-876, 40, 1649)], fog = 0.002},
			{name = "bibra_lake", wait = 600, cam = [Vector3(-3600, 160, 17400), Vector3(-2700, 5, 16200)], fog = 0.0010},
			{name = "bibra_lookout", wait = 300, cam = [Vector3(-3125, 16, 16025), Vector3(-2447, 8, 16304)], fog = 0.002},
			{name = "bibra_reeds", wait = 300, cam = [Vector3(-2540, 15, 15626), Vector3(-2470, 10, 15560)], fog = 0.002},
			{name = "bibra_boardwalk", wait = 300, cam = [Vector3(-2560, 22, 15660), Vector3(-2600, 12, 15760)], fog = 0.002},
			{name = "bibra_seam", wait = 300, cam = [Vector3(-3700, 60, 10300), Vector3(-3700, 15, 10800)], fog = 0.002},
			{name = "bibra_barrier", wait = 300, cam = [Vector3(-3612, 15, 10440), Vector3(-3606, 11, 10530)], fog = 0.002},
			{name = "bibra_boardwalk_close", wait = 300, cam = [Vector3(-2480, 14.5, 15610), Vector3(-2522, 12, 15630)], fog = 0.002},
			{name = "north_lake_rd", wait = 300, cam = [Vector3(-3760, 30, 13300), Vector3(-3700, 12, 14200)], fog = 0.002},
			{name = "north_mole_rocks", wait = 300, cam = [Vector3(-11700, 30, 11700), Vector3(-11860, 2, 11760)], fog = 0.002},
			{name = "trigg_point", wait = 300, cam = [Vector3(-9690, 8, -7760), Vector3(-9760, 0, -7760)], fog = 0.002},
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
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false  # prompts and labels too
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
