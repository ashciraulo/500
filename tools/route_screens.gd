extends SceneTree
## Screenshots of suggested routes: the minimap and the full map with a job's
## route on them, the arrows on the road ahead, a new route after leaving
## the old one, and the mouse on the full map (wheel, drag, right-click).
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/route_screens.gd -- --no-save shots=/tmp/routes
##
## only=<name,name> shoots just those (names are the steps below).

var _shots := "/tmp/routes"
var _only := PackedStringArray()
var _main: Node
var _car: RigidBody3D
var _step := -1
var _frames := 0
var _steps: Array = []
## Loaded when used: these read autoloads, which a --script tool can't name.
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
		["01_job_minimap_home", func() -> void:
			_set_time(10.0)
			_take_job("subiaco_markets"), 120, Callable()],
		["02_job_full_map", func() -> void:
			_screen().open()
			_zoom(4.5, Vector2(-700.0, -500.0)), 20, func() -> void: _screen().toggle()],
		["03_road_arrows_james_st", func() -> void: _onto_route(60.0), 220, Callable()],
		["04_road_arrows_turn", func() -> void: _onto_route(420.0), 220, Callable()],
		["05_road_arrows_further", func() -> void: _onto_route(1100.0), 220, Callable()],
		["06_off_route_before", func() -> void: _onto_route(1500.0), 220, Callable()],
		["07_off_route_new_way", func() -> void:
			# Off down a side street, the wrong way: a new route comes in.
			var g := _guide()
			var p: Vector3 = g.points[g.points.size() / 2]
			_teleport(p + Vector3(180.0, 0.0, 120.0), 0.0), 260, Callable()],
		["08_night_arrows", func() -> void:
			_set_time(21.5)
			_onto_route(300.0), 220, Callable()],
		["09_map_only_setting", func() -> void:
			root.get_node("Settings").set("route_guide", 1)
			_set_time(10.0)
			_onto_route(300.0), 200, Callable()],
		["10_marker_go_here", func() -> void:
			root.get_node("Settings").set("route_guide", 2)
			root.get_node("Jobs").call("abandon")
			_teleport(Vector3(-1.37, 22.09, -0.73), 1.08)
			_pins.markers.clear()
			_pins.add_marker(Vector2(-935.0, 1455.0), "Kings Park lookout")
			_screen().open()
			_screen().call("_select", 0)
			_screen().call("_toggle_route")
			_zoom(5.0, Vector2(-450.0, 700.0)), 90, func() -> void: _screen().toggle()],
		["11_pause_menu_setting", func() -> void: _main.get_node("PauseMenu").call("open"), 30,
			func() -> void: _main.get_node("PauseMenu").call("close")],
		# The mouse on the full map, sent through the window like a real one.
		["12_mouse_map_open", func() -> void:
			root.get_node("Jobs").call("abandon")
			_pins.markers.clear()
			_teleport(Vector3(-1.37, 22.09, -0.73), 1.08)
			_screen().open()
			_zoom(5.0, Vector2(-1.37, -0.73)), 30, Callable()],
		["13_mouse_wheel_zoom", func() -> void:
			for i in 3:
				_click(MOUSE_BUTTON_WHEEL_UP, _view_mid() + Vector2(120.0, -60.0)), 20, Callable()],
		["14_mouse_drag_pan", func() -> void: _drag(_view_mid(), Vector2(-260.0, 140.0)), 20, Callable()],
		["15_mouse_right_click_marker", func() -> void:
			_click(MOUSE_BUTTON_RIGHT, _view_mid() + Vector2(-90.0, 50.0)), 20,
			func() -> void: _screen().toggle()],
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
		var g := _guide()
		print("shot ", name, " car ", _car.global_position, " route ", g.length if g else -1.0, " m, along ", g.progress if g else -1.0)
		if _screen().call("is_open"):
			var view: Variant = _screen().get("_view")
			print("  map at ", view.centre, ", %.2f m/px, %d markers" % [view.metres_per_px, _pins.markers.size()])
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


func _guide() -> Node:
	return get_first_node_in_group(&"route_guide")


func _screen() -> Node:
	return _main.get_node("MapScreen")


## Takes a delivery whose pickup is `site` (made up if the board has none).
func _take_job(site: String) -> void:
	var jobs := root.get_node("Jobs")
	jobs.call("refresh_offers")
	var job: Dictionary = {}
	for o: Dictionary in jobs.get("offers"):
		if o.get("type", "") == "delivery":
			job = o
			break
	job.pickup = site
	jobs.call("accept", job)


## Puts the car on the route `s` metres along, facing along it.
func _onto_route(s: float) -> void:
	var g := _guide()
	if g == null or g.lane.size() < 2:
		return
	var cum := TrafficGraph.cumulative(g.lane)
	var at := TrafficGraph.point_at(g.lane, cum, s)
	var t := TrafficGraph.tangent_at(g.lane, cum, s)
	_teleport(at, atan2(-t.x, -t.z))


func _zoom(mpp: float, at: Vector2) -> void:
	var view: Variant = _screen().get("_view")
	_screen().set("_zoom", mpp)
	view.metres_per_px = mpp
	view.centre = at


## The middle of the full map, in window pixels.
func _view_mid() -> Vector2:
	var view: Control = _screen().get("_view")
	return view.get_global_transform_with_canvas() * (view.size * 0.5)


func _click(button: MouseButton, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.position = at
		ev.pressed = pressed
		root.push_input(ev, true)


func _drag(from: Vector2, by: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = from
	down.pressed = true
	root.push_input(down, true)
	for i in 10:
		var move := InputEventMouseMotion.new()
		move.position = from + by * (i + 1) / 10.0
		move.relative = by / 10.0
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(move, true)
	var up := down.duplicate() as InputEventMouseButton
	up.position = from + by
	up.pressed = false
	root.push_input(up, true)


func _set_time(hours: float) -> void:
	root.get_node("GameClock").set_time(hours)


func _teleport(at: Vector3, yaw: float) -> void:
	_car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 1.0)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
