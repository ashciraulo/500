extends SceneTree
## Screenshots of the servos (data/world/servos.json) for reviewing them:
## driving up to each, from above, at night, parked in the bay, and on the
## full map. Needs a display (or xvfb):
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/servo_screens.gd -- --no-save shots=/tmp/servos [ids=servo_1,servo_2] [only=approach,night]
##
## Without ids= it shoots every servo. The shots per servo are approach,
## above, night, bay and map; only= picks some.

var _shots := "/tmp/servos"
var _ids := PackedStringArray()
var _only := PackedStringArray()
var _main: Node
var _car: RigidBody3D
var _step := -1
var _frames := 0
var _steps: Array = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
		elif arg.begins_with("ids="):
			_ids = arg.trim_prefix("ids=").split(",")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=").split(",")
	DirAccess.make_dir_recursive_absolute(_shots)


func _want(shot: String) -> bool:
	return _only.is_empty() or _only.has(shot)


func _build_steps() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/servos.json"))
	var n := 0
	for entry: Dictionary in data.servos:
		if not _ids.is_empty() and not _ids.has(String(entry.id)):
			continue
		n += 1
		var at := Vector3(entry.position[0], entry.position[1], entry.position[2])
		var basis := Basis(Vector3.UP, float(entry.yaw))
		var end := float(entry.get("open_end", 1))
		var tag := "%02d_%s" % [n, String(entry.name).to_snake_case().replace(" ", "_")]
		# The car faces its -z: drive in from the open end.
		var car_yaw := float(entry.yaw) + (0.0 if end > 0.0 else PI)
		var out := at + basis * Vector3(0, 0, end * 16.0)
		if _want("approach"):
			_steps.append([tag + "_1_approach", func() -> void:
				_hour(11.0)
				_free_camera(false)
				_teleport(out, car_yaw), 200])
		if _want("above"):
			_steps.append([tag + "_2_above", func() -> void:
				_free_camera(true, at + basis * Vector3(-14, 16, end * 18), at + Vector3.UP * 2.0), 60])
		if _want("side"):
			_steps.append([tag + "_3_side", func() -> void:
				_free_camera(true, at + basis * Vector3(-12, 2.0, end * 4), at + basis * Vector3(3, 2.0, 0)), 30])
		if _want("night"):
			_steps.append([tag + "_4_night", func() -> void:
				_hour(21.5)
				_free_camera(false)
				_teleport(out, car_yaw), 240])
		if _want("bay"):
			_steps.append([tag + "_5_in_the_bay", func() -> void:
				_hour(11.0)
				_free_camera(false)
				_teleport(at, car_yaw), 240])
		if _want("map"):
			_steps.append([tag + "_6_map", func() -> void:
				_free_camera(false)
				_teleport(out, car_yaw)
				_screen().open()
				_zoom(1.0, Vector2(at.x, at.z)), 60, func() -> void: _screen().toggle()])
		print("servo ", tag, " ", entry.id, " at ", at)


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_frames = -240
		return false
	_frames += 1
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			_build_steps()
			_next()
		return false
	if _step >= _steps.size():
		quit(0)
		return true
	if _frames >= int(_steps[_step][2]):
		var name: String = _steps[_step][0]
		root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
		print("shot ", name, " car ", _car.global_position)
		if _steps[_step].size() > 3:
			(_steps[_step][3] as Callable).call()
		_next()
	return false


func _next() -> void:
	_step += 1
	_frames = 0
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()


func _hour(h: float) -> void:
	root.get_node("GameClock").set_time(h)


func _screen() -> Node:
	return _main.get_node("MapScreen")


func _zoom(mpp: float, at: Vector2) -> void:
	var view: Variant = _screen().get("_view")
	_screen().set("_zoom", mpp)
	view.metres_per_px = mpp
	view.centre = at


func _teleport(at: Vector3, yaw: float) -> void:
	_car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 1.0)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO


## Hold the camera at `from` looking at `to`, or (on = false) give it back to the car.
func _free_camera(on: bool, from := Vector3.ZERO, to := Vector3.ZERO) -> void:
	var world := _main.get_node("LoFi/SubViewport/World")
	var rig := world.get_node("CameraRig")
	rig.set_process(not on)
	rig.set_physics_process(not on)
	_car.freeze = on
	if on:
		var cam := rig.get_node("Camera3D") as Camera3D
		cam.global_position = from
		cam.look_at(to)
