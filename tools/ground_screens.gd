extends SceneTree
## Low street-level and oblique screenshots for checking how smooth the roads
## and the ground beside them are. Needs a display (or xvfb):
##
##   godot --path . --script res://tools/ground_screens.gd -- out_dir=/tmp/shots [only=a,b]
##
## Each street shot stands the camera 1.4 m above the road and looks 120 m
## along it, so lumps show as a wavy skyline of kerbs and lane lines.

const SHOTS := [
	{name = "hay_st", from = Vector3(4, 0, 731), to = Vector3(-97, 0, 692)},
	{name = "aberdeen_st", from = Vector3(437, 0, 40), to = Vector3(584, 0, 118)},
	{name = "beaufort_st", from = Vector3(782, 0, 478), to = Vector3(832, 0, 383)},
	{name = "william_st", from = Vector3(242, 0, 972), to = Vector3(209, 0, 1057)},
	{name = "lake_st", from = Vector3(216, 0, 320), to = Vector3(269, 0, 220)},
	{name = "newcastle_st", from = Vector3(1050, 0, 236), to = Vector3(943, 0, 178)},
	{name = "wellington_st", from = Vector3(-422, 0, 258), to = Vector3(-325, 0, 296)},
	{name = "northbridge_oblique", from = Vector3(-60, 45, 180), to = Vector3(260, 10, 520), air = true},
	{name = "herdsman_west_bank", from = Vector3(-5620, 30, -2900), to = Vector3(-5470, 4, -2960), air = true},
	{name = "herdsman_east_bank", from = Vector3(-3720, 35, -2900), to = Vector3(-3900, 4, -2960), air = true},
]

var _main: Node
var _frame := 0
var _shot := 0
var _out := "user://screenshots"
var _shots := []


func _process(_delta: float) -> bool:
	if _main == null:
		_out = _arg("out_dir", _out)
		DirAccess.make_dir_recursive_absolute(_out)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(float(_arg("hour", "16.0")))
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_shots = SHOTS.duplicate()
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
		_place_camera(shot.from, shot.to)
	if not shot.get("air", false) and _frame % 40 == 0:
		_drop_camera(shot.from, shot.to)
	if _frame >= 300:
		var img := root.get_texture().get_image()
		var path: String = _out.path_join(shot.name + ".png")
		img.save_png(path)
		print("saved ", path)
		_shot += 1
		_frame = 0
	return false


func _arg(key: String, default: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return arg.trim_prefix(key + "=")
	return default


func _ground(world: Node3D, p: Vector3) -> float:
	var space := world.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 150, p.z), Vector3(p.x, -50, p.z)))
	return p.y if hit.is_empty() else hit.position.y


func _drop_camera(from: Vector3, to: Vector3) -> void:
	var world := _main.get_node("LoFi/SubViewport/World") as Node3D
	var cam := world.get_node("CameraRig/Camera3D") as Camera3D
	var dir := (Vector3(to.x, 0, to.z) - Vector3(from.x, 0, from.z)).normalized()
	var far := from + dir * 120.0
	cam.global_position = Vector3(from.x, _ground(world, from) + 1.4, from.z)
	cam.look_at(Vector3(far.x, _ground(world, far) + 1.4, far.z))


func _place_camera(from: Vector3, to: Vector3) -> void:
	var world := _main.get_node("LoFi/SubViewport/World")
	(world.get_node("Car") as RigidBody3D).freeze = true
	_main.get_node("HUD").visible = false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var rig := world.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.global_position = from
	cam.look_at(to)
	cam.fov = 55
	cam.far = 3000.0
	world.get_node("EnvironmentController").fog_density_clear = 0.002
	var traffic := world.get_node_or_null("Traffic")
	if traffic:
		traffic.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("PerthMap").set("_target", cam)
