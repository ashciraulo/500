extends SceneTree
## Captures frame sequences of the map while the camera glides along a street,
## to check that textures stay put on the ground, roads and walls. Needs a
## display (or xvfb), not --headless:
##
##   godot --path . --script res://tools/surface_swim_capture.gd -- out_dir=/tmp/swim
##
## Options: route=<name> (see ROUTES), frames=<n>, step=<metres per frame>,
## affine=<0..1> and snap=<0|1> override the Soft preset, preset=<index>.
## Writes <route>_<nnn>.png per frame and prints, per frame, how many low-res
## pixels changed from the frame before (a crude flicker measure).

const ROUTES := {
	# James St, Northbridge, at chase-camera height.
	"james_st": [Vector3(-125, 0, 2), Vector3(60, 0, 100), 2.2],
	# William St heading into the CBD.
	"street_level": [Vector3(596, 0, 973), Vector3(512, 0, 1178), 2.2],
	# A long straight run of Albany Hwy, Victoria Park.
	"albany_hwy": [Vector3(4104, 0, 3151), Vector3(4012, 0, 2962), 2.2],
	# Beaufort St, Mount Lawley, from a little higher up to see far down it.
	"beaufort_st": [Vector3(1473, 0, -1827), Vector3(1663, 0, -2159), 6.0],
}

var _main: Node
var _frame := 0
var _shot := 0
var _out := "user://swim"
var _from := Vector3.ZERO
var _dir := Vector3.FORWARD
var _above := 2.2
var _ground_y := 0.0
var _frames := 48
var _step := 0.35
var _prev: Image
var _changed: Array[int] = []


func _process(_delta: float) -> bool:
	if _main == null:
		_out = _arg("out_dir", _out)
		DirAccess.make_dir_recursive_absolute(_out)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(float(_arg("hour", "16.5")))
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		var settings := root.get_node("Settings")
		var render := root.get_node("RenderSettings")
		settings.use_lofi_preset(int(_arg("preset", str(render.DEFAULT_PRESET))))
		settings.apply()
		if _arg("affine", "") != "":
			render.affine_strength = float(_arg("affine", "0"))
			render.apply()
		var route: Array = ROUTES[_arg("route", "james_st")]
		_from = route[0]
		_dir = (route[1] - route[0]).normalized()
		_above = float(_arg("above", str(route[2])))
		_frames = int(_arg("frames", str(_frames)))
		_step = float(_arg("step", str(_step)))
		_place_camera()
		return false
	_frame += 1
	var cam := _camera()
	if _arg("snap", "") == "0":
		RenderingServer.global_shader_parameter_set("ps1_snap_resolution", Vector2(8192, 8192))
	if _frame < 300:
		if _frame % 40 == 0:
			_ground_y = _ground_at(_from)
		cam.global_position = Vector3(_from.x, _ground_y + _above, _from.z)
		cam.look_at(cam.global_position + _dir * 30.0 + Vector3.DOWN * _above * 0.6)
		return false
	# Glide forward and save each frame.
	var t := _frame - 300
	if t > 0:
		var img := root.get_texture().get_image()
		var name := "%s_%03d.png" % [_arg("route", "james_st"), t - 1]
		img.save_png(_out.path_join(name))
		var low := _low_res()
		if _prev:
			_changed.append(_diff(_prev, low))
		_prev = low
	if t > _frames:
		var total := 0
		for c in _changed:
			total += c
		print("SWIM changed-pixels per frame: ", _changed)
		print("SWIM mean: %.0f" % (float(total) / maxf(1.0, _changed.size())))
		quit(0)
		return true
	var p := _from + _dir * _step * t
	cam.global_position = Vector3(p.x, _ground_y + _above, p.z)
	cam.look_at(cam.global_position + _dir * 30.0 + Vector3.DOWN * _above * 0.6)
	return false


func _camera() -> Camera3D:
	return _main.get_node("LoFi/SubViewport/World/CameraRig/Camera3D") as Camera3D


func _low_res() -> Image:
	var vp := _main.get_node("LoFi/SubViewport") as SubViewport
	return vp.get_texture().get_image()


func _diff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var n := 0
	var da := a.get_data()
	var db := b.get_data()
	var bpp := da.size() / (a.get_width() * a.get_height())
	for i in range(0, da.size(), bpp):
		if absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2]) > 24:
			n += 1
	return n


func _arg(key: String, default: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return arg.trim_prefix(key + "=")
	return default


func _ground_at(p: Vector3) -> float:
	var world := _main.get_node("LoFi/SubViewport/World") as Node3D
	var space := world.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 120, p.z), Vector3(p.x, -50, p.z)))
	return 0.0 if hit.is_empty() else hit.position.y


func _place_camera() -> void:
	var world := _main.get_node("LoFi/SubViewport/World")
	(world.get_node("Car") as RigidBody3D).freeze = true
	(world.get_node("Car") as Node3D).global_position = Vector3(0, -200, 0)
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var rig := world.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var cam := _camera()
	cam.fov = 70
	cam.global_position = _from + Vector3.UP * 30.0
	cam.look_at(_from + _dir * 30.0)
	var map := world.get_node("PerthMap")
	map.set("_target", cam)
