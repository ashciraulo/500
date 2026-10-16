extends SceneTree
## The Alfa 75 out in the lane in the sun at 11:00: both sides (sun and
## shade), both rear and front three-quarters and the rear arch close up, to
## judge its paint and its arches as the game draws them.
##
##   xvfb-run godot --path . --resolution 1280x720 --fixed-fps 60 \
##       --script res://tools/alfa_screens.gd -- --no-save shots=/tmp/alfa

var _shots := "user://alfa"
var _main: Node
var _world: Node
var _car  # CarController
var _steps: Array = []
var _step := -1
var _frames := 0
var _failed := 0
var _cam: Camera3D
var _trials: Array = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("trial="):
			var t := arg.trim_prefix("trial=").split(",")
			_trials.append([t[0], float(t[1]), float(t[2])])
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
	DirAccess.make_dir_recursive_absolute(_shots)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed += 1


## A camera `back` m behind (or ahead, negative) the car, `side` m to its
## left (negative: right), `up` m up, looking at `at` in the car's space.
func _look(back: float, side: float, up: float, at := Vector3(0, 0.5, 0)) -> void:
	var b: Basis = _car.global_basis
	_cam.global_position = _car.global_position + b.z * back + b.x * side + Vector3.UP * up
	_cam.look_at(_car.global_position + b * at)


func _build_steps() -> void:
	_steps.append(["alfa_switch", func() -> void:
		root.get_node("Garage").add_car("alfa_75_v6")
		_check(root.get_node("Garage").switch_car("alfa_75_v6", _car), "switched to the Alfa"), 90, false])
	_steps.append(["alfa_carport", func() -> void:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_world.add_child(_cam)
		_cam.current = true
		_look(-4.5, 2.2, 1.0), 20, true])
	_steps.append(["alfa_lane", func() -> void:
		var home: Node3D = get_first_node_in_group(&"home_base")
		var h79: GDScript = load("res://scripts/world/late_city/house_1979.gd")
		var at: Vector3 = home.to_global(h79.at(Vector3(15.0, -6.6, 0.0))) + Vector3.UP * 0.8
		_car.teleport(Transform3D(home.global_basis * Basis(Vector3.UP, PI * 0.5), at))
		root.get_node("GameClock").set_time(11.0), 150, false])
	_steps.append(["alfa_side_l", func() -> void:
		_cam.fov = 40.0
		_look(0.0, -7.5, 0.8), 20, true])
	_steps.append(["alfa_side_r", func() -> void: _look(0.0, 7.5, 0.8), 20, true])
	for i in _trials.size():
		var t: Array = _trials[i]
		_steps.append(["trial%d_side_l" % i, func() -> void:
			var mat: ShaderMaterial = _car.get_node("Body").get("_materials").get("Paint")
			mat.set_shader_parameter("albedo_color", Color(t[0]))
			mat.set_shader_parameter("roughness", t[1])
			mat.set_shader_parameter("metallic", t[2])
			_look(0.0, -7.5, 0.8), 10, true])
		_steps.append(["trial%d_side_r" % i, func() -> void: _look(0.0, 7.5, 0.8), 10, true])
	_steps.append(["alfa_front34", func() -> void: _look(-5.5, 2.6, 1.0), 20, true])
	_steps.append(["alfa_rear34", func() -> void: _look(5.5, -2.6, 1.0), 20, true])
	_steps.append(["alfa_rear_arch", func() -> void: _look(2.6, -2.4, 0.6, Vector3(0.7, 0.4, 1.3)), 20, true])
	_steps.append(["alfa_shade_rear34", func() -> void: _look(5.5, 2.6, 1.0), 20, true])


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		root.get_node("GameClock").set_locked(true)
		root.get_node("GameClock").set_time(10.5)
		root.get_node("Weather").set_locked(true)
		root.get_node("Wallet").earn(50000, "test")
		_frames = -300
		return false
	_frames += 1
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			var first: Node = _main.find_child("FirstDay", true, false)
			if first:
				first.load_state({"step": 4})
			root.get_node("Notices").clear()
			_build_steps()
			_next()
		return false
	if _step >= _steps.size():
		print("alfa: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
		quit(1 if _failed else 0)
		return true
	if _frames >= int(_steps[_step][2]):
		var name: String = _steps[_step][0]
		if _steps[_step][3]:
			root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
			print("shot ", name)
		_next()
	return false


func _next() -> void:
	_step += 1
	_frames = 0
	# The story's act card would sit over the car in the close-ups.
	for card in _main.find_children("*", "CanvasLayer", true, false):
		if card.has_method("show_act"):
			card.clear()
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()
