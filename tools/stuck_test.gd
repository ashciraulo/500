extends SceneTree
## Checks the player can't get stuck on foot, headless:
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/stuck_test.gd -- --no-save
##
## - Next door's front yard (out the front door, turn left): walk in, and
##   walk back out to the garden without hopping.
## - A hop (Space) gets you up a ledge too high to step, and Shift hurries.
## - Falling out of the world puts you back where you last walked.
##
## With a display and shots=<dir> it saves a screenshot at each stage.
## Exits with code 1 if any check fails.

const LEDGE := 0.55
## The test ledge: on the lane in front of the house (house coordinates).
const LEDGE_AT := Vector3(2.7, -7.0, 0.0)

var _quitting := false
var _main: Node
# Untyped: naming the game's classes here would compile them before the autoloads exist.
var _car: RigidBody3D
var _player: CharacterBody3D
var _home: Node3D
var _failures: Array[String] = []
var _stage := 0
var _t := 0.0
var _shots := ""
var _block: StaticBody3D
var _mark := Vector3.ZERO


func _process(delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("shots="):
				_shots = arg.trim_prefix("shots=")
				DirAccess.make_dir_recursive_absolute(_shots)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(16.5)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_player = _main.get_node("LoFi/SubViewport/World/Player")
		return false
	_t += delta
	match _stage:
		0:
			if _t > 3.0:
				_home = _main.get_node("LoFi/SubViewport/World/PerthMap").get_home()
				_check(_home != null, "the townhouse is loaded")
				if _home == null:
					return _finish()
				_player.get_out()
				_next()
		1:
			if _t > 2.0:
				_check(not _player.in_car, "got out of the car")
				# By the front door, turned left toward next door's front yard.
				_put(Vector3(4.6, -1.2, 0.1), Vector3(9.0, -1.2, 1.0))
				_next()
		2:  # into next door's yard, then back to the garden
			if _t > 0.5 and _t - delta <= 0.5:
				Input.action_press("accelerate")
			if _t > 3.0 and _t - delta <= 3.0:
				Input.action_release("accelerate")
				_mark = _local(_player.global_position)
				_shot("01_next_doors_yard")
				Input.action_press("brake")
			if _t > 6.5:
				Input.action_release("brake")
				var p := _local(_player.global_position)
				_check(_mark.x > 6.0, "walked into next door's front yard (%s)" % _mark)
				_check(p.x < 5.0 and p.z > 0.0, "and back out to the front garden without a hop (%s)" % p)
				_shot("02_back_in_the_garden")
				_make_ledge()
				_put(LEDGE_AT + Vector3(0, 3.0, 0), LEDGE_AT + Vector3(0, 0, 1.0))
				_next()
		3:  # walk at a ledge too high to step: it stops you
			if _t > 0.5 and _t - delta <= 0.5:
				Input.action_press("accelerate")
			if _t > 2.5 and _t - delta <= 2.5:
				var h := _local(_player.global_position).z
				_check(h < LEDGE - 0.3, "a %.2f m ledge is too high to step up (%.2f)" % [LEDGE, h])
				Input.action_press("jump")
			if _t > 2.6 and _t - delta <= 2.6:
				Input.action_release("jump")
			if _t > 4.0:
				Input.action_release("accelerate")
				var h := _local(_player.global_position).z
				_check(absf(h - LEDGE) < 0.1, "Space hops up onto it (%.2f)" % h)
				_shot("03_hopped_up")
				_block.queue_free()
				_put(Vector3(-6.0, -6.0, 0.0), Vector3(6.0, -6.0, 1.0))  # on the lane, looking along it
				_next()
		4:  # hurry
			if _t > 0.5 and _t - delta <= 0.5:
				_mark = _player.global_position
				Input.action_press("accelerate")
				Input.action_press("hurry")
			if _t > 1.5:
				Input.action_release("accelerate")
				Input.action_release("hurry")
				var d := _player.global_position.distance_to(_mark)
				_check(d > 2.6, "Shift hurries (%.1f m in a second)" % d)
				# Walk a few metres to leave a trail, then drop out of the world.
				Input.action_press("accelerate")
				_next()
		5:
			if _t > 3.0 and _t - delta <= 3.0:
				Input.action_release("accelerate")
				_mark = _player.global_position
				_player.global_position += Vector3.DOWN * 40.0  # under the ground, as if through a gap
			if _t > 3.5 and _t - delta <= 3.5:
				_check(not _player.is_on_floor(), "falling under the map")
			if _t > 8.5:
				var d := _player.global_position.distance_to(_mark)
				_check(d < 3.0 and _player.is_on_floor(), "falling out of the world puts you back where you walked (%.1f m)" % d)
				return _finish()
	return false


## A block LEDGE high, 4 m square, on the lane.
func _make_ledge() -> void:
	_block = StaticBody3D.new()
	_block.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, LEDGE, 4.0)
	shape.shape = box
	_block.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	_block.add_child(mesh)
	_home.add_child(_block)
	_block.global_position = _world(LEDGE_AT + Vector3(0, 0, LEDGE * 0.5))


func _put(feet: Vector3, look: Vector3) -> void:
	_player.teleport(_world(feet) + Vector3.UP * 0.05, _world(look))


## House coordinates (Blender: x across, y back from the street, z up).
func _world(b: Vector3) -> Vector3:
	return _home.to_global(Vector3(b.x, b.z, -b.y))


func _local(w: Vector3) -> Vector3:
	var p: Vector3 = _home.to_local(w)
	return Vector3(p.x, -p.z, p.y)


func _shot(name: String) -> void:
	if _shots == "":
		return
	var hud := _main.get_node_or_null("HUD")
	if hud and hud.get("_help"):
		hud._help.visible = false
	var img := root.get_texture().get_image()
	img.save_png(_shots.path_join(name + ".png"))
	print("saved ", name)


func _next() -> void:
	_stage += 1
	_t = 0.0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
	print(("ok   " if ok else "FAIL ") + what)


func _finish() -> bool:
	Input.action_release("accelerate")
	Input.action_release("brake")
	for f in _failures:
		printerr("FAIL: ", f)
	print("STUCK TEST ", "PASSED" if _failures.is_empty() else "FAILED")
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
	return false
