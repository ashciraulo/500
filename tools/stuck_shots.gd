extends SceneTree
## Screenshots of the traps tools/stuck_sweep.gd found, from just above where
## you walk in, with a red post on the trap and a yellow one where you get in:
##
##   xvfb-run godot --path . --script res://tools/stuck_shots.gd -- in=/tmp/stuck.json shots=/tmp/stuck [count=12] [min_area=2] [inside]
##
## With inside, the camera stands in the trap looking back at where you got
## in (for tunnels and cuttings, which you can't see into from above).
## Takes the traps in the order the sweep listed them (nearest home first).

var _main: Node
var _player: CharacterBody3D
var _traps: Array = []
var _shots := "user://stuck_shots"
var _count := 12
var _min_area := 2.0
var _inside := false
var _at := 0
var _t := 0.0
var _started := false
var _markers: Array[Node3D] = []
var _quitting := false


func _process(delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		var path := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("in="):
				path = arg.trim_prefix("in=")
			elif arg.begins_with("shots="):
				_shots = arg.trim_prefix("shots=")
			elif arg.begins_with("count="):
				_count = int(arg.trim_prefix("count="))
			elif arg.begins_with("min_area="):
				_min_area = float(arg.trim_prefix("min_area="))
			elif arg == "inside":
				_inside = true
		DirAccess.make_dir_recursive_absolute(_shots)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for trap: Dictionary in data.traps:
			if float(trap.area) >= _min_area and _traps.size() < _count:
				_traps.append(trap)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(11.0)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_player = _main.get_node("LoFi/SubViewport/World/Player")
		print("STUCK SHOTS %d traps" % _traps.size())
		return false
	_t += delta
	if not _started:
		if _t > 3.0:
			_player.get_out()
			_started = true
			_t = -2.0
		return false
	if _at >= _traps.size():
		print("STUCK SHOTS done")
		_quitting = true
		root.get_node("SaveGame").quit_cleanly(0)
		return false
	if _t < 0.0:
		return false
	var trap: Dictionary = _traps[_at]
	var at := _vec(trap.at)
	if _t - delta <= 0.0:
		_player.noclip = true
		var hud := _main.get_node_or_null("HUD")
		if hud and hud.get("_help"):
			hud._help.visible = false
		var dev := _main.get_node_or_null("DevMode")
		if dev:
			dev.visible = false
		var entry := _vec(trap.entry) if not (trap.entry as Array).is_empty() else at + Vector3(4, 0, 0)
		var away := Vector3(entry.x - at.x, 0.0, entry.z - at.z)
		away = away.normalized() if away.length() > 0.1 else Vector3.BACK
		# From where you'd walk in (open ground, by definition), a little up.
		var eye := entry + away * 3.0 + Vector3.UP * 4.0
		if _inside:
			eye = at + Vector3.UP * 1.62
		_player.teleport(eye - Vector3.UP * 1.62, entry if _inside else at)
		_mark(at, Color(0.9, 0.15, 0.1))
		_mark(entry, Color(1.0, 0.8, 0.1))
	if _t > 4.0:  # tiles stream in around the camera
		var name := "%02d_%s_%dm2" % [_at + 1, trap.tile, roundi(float(trap.area))]
		root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
		print("saved %s  at %s  climb %.2f m" % [name, trap.at, float(trap.climb)])
		for m in _markers:
			m.queue_free()
		_markers.clear()
		_at += 1
		_t = -0.01
	return false


func _mark(p: Vector3, colour: Color) -> void:
	var post := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = 2.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	post.mesh = mesh
	_main.get_node("LoFi/SubViewport/World").add_child(post)
	post.global_position = p + Vector3.UP * 1.25
	_markers.append(post)


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
