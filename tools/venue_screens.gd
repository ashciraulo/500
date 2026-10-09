extends SceneTree
## Screenshots of Northbridge's cafes, bars, pubs and restaurants
## (data/world/venues.json) for reviewing them: each from across the street
## by day and at night, from the car going past, and the full map over
## Northbridge. Needs a display (or xvfb):
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/venue_screens.gd -- --no-save shots=/tmp/venues [ids=no_capo,saffra] [only=day,night]
##
## Without ids= it shoots every venue. The shots per venue are day, night,
## drive and side (at night from along the footpath, as someone walking up
## sees the blade signs and the tables); only= picks some (map is one shot
## at the end).

var _shots := "/tmp/venues"
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
	var n := 0
	for entry: Dictionary in Venue.entries():
		if not _ids.is_empty() and not _ids.has(String(entry.id)):
			continue
		n += 1
		var at := Vector3(entry.position[0], entry.position[1], entry.position[2])
		var basis := Basis(Vector3.UP, float(entry.yaw))
		var w := float(entry.width)
		var depth := float(entry.get("depth", 3.0))
		var tag := "%02d_%s" % [n, String(entry.id)]
		# Park up the street (it streams the tiles in, out of the shot) and
		# look back at the shopfront from the far footpath.
		var road := at + basis * Vector3(25, 0, depth + 3.5)
		var car_yaw := float(entry.yaw) + PI / 2
		var eye := at + basis * Vector3(-w * 0.35, 1.7, maxf(depth + 9.0, 12.0))
		var look := at + basis * Vector3(0, 2.3, 0)
		var hours: Array = entry.get("hours", [])
		var open_day := 13.0 if hours.is_empty() else clampf(float(hours[0][0]) + 1.0, 8.0, 18.0)
		if _want("day"):
			_steps.append([tag + "_1_day", func() -> void:
				_hour(open_day)
				_free_camera(false)
				_teleport(road, car_yaw)
				_free_camera(true, eye, look), 150])
		if _want("night"):
			_steps.append([tag + "_2_night", func() -> void:
				_hour(21.0)
				_free_camera(false)
				_teleport(road, car_yaw)
				_free_camera(true, eye, look), 60])
		if _want("side"):
			var from := at + basis * Vector3(-w * 0.5 - 7.0, 1.7, minf(depth - 0.8, 4.0))
			_steps.append([tag + "_4_side", func() -> void:
				_hour(21.0)
				_free_camera(false)
				_teleport(road, car_yaw)
				_free_camera(true, from, at + basis * Vector3(w * 0.25, 2.2, 1.0)), 60])
		if _want("drive"):
			_steps.append([tag + "_3_drive", func() -> void:
				_hour(open_day)
				_free_camera(false)
				_teleport(at + basis * Vector3(-14, 0, depth + 3.0), car_yaw + PI), 150])
		print("venue ", tag, " ", entry.name, " at ", at)
	if _want("map"):
		_steps.append(["99_map", func() -> void:
			_free_camera(false)
			_screen().open()
			_zoom(0.9, Vector2(250, 120)), 60, func() -> void: _screen().toggle()])


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
