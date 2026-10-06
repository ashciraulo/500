extends SceneTree
## Screenshots of the minimap and the full map, for reviewing them.
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/map_screens.gd -- --no-save shots=/tmp/map
##
## only=<name,name> shoots just those (names are the steps below).

var _shots := "/tmp/map"
var _only := PackedStringArray()
var _main: Node
var _car: RigidBody3D
var _step := -1
var _frames := 0
var _steps: Array = []
## Loaded when used: it reads autoloads, which a --script tool can't name.
var _pins: GDScript


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=").split(",")
	DirAccess.make_dir_recursive_absolute(_shots)
	_pins = load("res://scripts/ui/map_pins.gd")
	# [name, setup, frames to wait, teardown]
	_steps = [
		["mini_home", func() -> void: _set_time(10.0), 60, Callable()],
		["mini_cbd", func() -> void: _teleport(Vector3(563.66, 11.91, 1317.86), 2.2), 200, Callable()],
		["mini_freo", func() -> void: _teleport(Vector3(-9920.86, 7.95, 12307.88), -2.44), 200, Callable()],
		["mini_marker", func() -> void:
			_pins.markers.clear()
			_pins.add_marker(Vector2(-9300.0, 11500.0), "Sunset spot")
			_set_time(19.4), 90, Callable()],
		["full_home", func() -> void:
			_teleport(Vector3(-1.37, 22.09, -0.73), 1.08)
			_set_time(10.0), 200, Callable()],
		["full_open", func() -> void:
			_pins.markers.clear()
			_pins.add_marker(Vector2(-935.0, 1455.0), "Kings Park lookout")
			_pins.add_marker(Vector2(560.0, 1500.0), "Coffee by the quay")
			_screen().open(), 20, Callable()],
		["full_street", func() -> void:
			_zoom(1.4, Vector2(60.0, 120.0))
			_screen().call("_select", 1), 20, Callable()],
		["full_city", func() -> void: _zoom(22.0, Vector2(-3500.0, 3000.0)), 20, Callable()],
		["full_pad", func() -> void:
			UiStyle.using_pad = true
			_zoom(3.0, Vector2(560.0, 1450.0)), 20, func() -> void:
			UiStyle.using_pad = false
			_screen().toggle()],
	]


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_frames = -240  # settle: streaming, the map data
		return false
	_frames += 1
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			_next()
		return false
	if _step >= _steps.size():
		return true
	if _frames >= int(_steps[_step][2]):
		var name: String = _steps[_step][0]
		root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
		print("shot ", name, " car ", _car.global_position, " where ", _main.find_child("Minimap", true, false).get("_street").text, "|", _main.find_child("Minimap", true, false).get("_suburb").text)
		var teardown: Callable = _steps[_step][3]
		if teardown.is_valid():
			teardown.call()
		_next()
	return false


func _next() -> void:
	_step += 1
	while _step < _steps.size() and not _only.is_empty() and not _only.has(_steps[_step][0]):
		_step += 1
	_frames = 0
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()


func _screen() -> Node:
	return _main.get_node("MapScreen")


func _zoom(mpp: float, at: Vector2) -> void:
	var view: Variant = _screen().get("_view")
	_screen().set("_zoom", mpp)
	view.metres_per_px = mpp
	view.centre = at


func _set_time(hours: float) -> void:
	root.get_node("GameClock").set_time(hours)


func _teleport(at: Vector3, yaw: float) -> void:
	_car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 6.0)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
