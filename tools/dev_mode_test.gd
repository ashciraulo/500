extends SceneTree
## Checks dev mode (scripts/dev/dev_mode.gd), headless:
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/dev_mode_test.gd -- --no-save
##
## Out of the car, it walks off a platform too high to step back onto and
## checks unstuck puts you back on top; flies through the house; jumps home,
## to the car and brings the car over; drives, then unstucks the car back
## along the road and sends it home; and marks a spot. It also walks from
## Little Shenton Lane into the neighbour's front yard and back, and says
## whether that got stuck (a report, not a check: the map tiles decide it).
##
## With a display and shots=<dir> it saves a screenshot at each stage:
##
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/dev_mode_test.gd -- --no-save shots=/tmp/dev
##
## Exits with code 1 if any check fails.

const PLATFORM_TOP := 0.6
## Where the test platform stands: on the lane in front of the house (house coordinates).
const PLATFORM := Vector3(2.7, -7.0, 0.0)

var _quitting := false
var _main: Node
# Untyped: naming the game's classes here would compile them before the autoloads exist.
var _car: RigidBody3D
var _player: CharacterBody3D
var _dev: CanvasLayer
var _home: Node3D
var _failures: Array[String] = []
var _stage := 0
var _t := 0.0
var _shots := ""
var _platform: StaticBody3D
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
				_dev = _main.get_node_or_null("DevMode")
				_check(_dev != null, "debug builds get dev mode")
				_home = _main.get_node("LoFi/SubViewport/World/PerthMap").get_home()
				_check(_home != null, "the townhouse is loaded")
				if _dev == null or _home == null:
					return _finish()
				# Scratch files, not the player's own setting and marked spots.
				_dev.settings_path = "user://dev_mode_test.cfg"
				_dev.marks_path = "user://dev_marks_test.txt"
				_dev.set_enabled(false)
				_key(KEY_V)
				_check(not _player.noclip, "dev keys do nothing while dev mode is off")
				_key(KEY_F3)
				_player.get_out()
				_next()
		1:
			if _t > 2.0:
				_check(_dev.enabled and _dev.get_node("DevPanel").visible, "F3 turns dev mode on and shows its panel")
				_check(not _player.in_car, "got out of the car")
				# In the front garden by the front door, turned left toward next door's front yard.
				_put(Vector3(4.6, -1.2, 0.1), Vector3(9.0, -1.2, 1.0))
				_next()
		2:  # into the neighbour's yard, then back out the way you came
			if _t > 0.5 and _t - delta <= 0.5:
				Input.action_press("accelerate")
			if _t > 3.0 and _t - delta <= 3.0:
				Input.action_release("accelerate")
				_shot("01_neighbours_yard")
				print("     in the neighbour's yard at %s" % _local(_player.global_position))
				Input.action_press("brake")
			if _t > 6.5:
				Input.action_release("brake")
				var p := _local(_player.global_position)
				print("     report: walking back out of the neighbour's yard %s (ended at %s)"
					% ["got stuck" if p.x > 5.4 else "worked", p])
				_make_platform()
				_put(PLATFORM + Vector3(0, 0, PLATFORM_TOP + 0.05), PLATFORM + Vector3(0, -4.0, 1.5))
				_next()
		3:  # walk off a platform too high to step back onto
			if _t > 0.5 and _t - delta <= 0.5:
				_check(absf(_local(_player.global_position).z - PLATFORM_TOP) < 0.1, "standing on the test platform")
				Input.action_press("accelerate")
			if _t > 2.5 and _t - delta <= 2.5:
				Input.action_release("accelerate")
				Input.action_press("brake")  # and try to back up onto it
			if _t > 4.5:
				Input.action_release("brake")
				var h := _local(_player.global_position).z
				_check(h < PLATFORM_TOP - 0.3, "dropped off the platform and can't step back up (%.2f)" % h)
				_shot("02_stuck_below_ledge")
				_key(KEY_U)
				_next()
		4:
			if _t > 0.6:
				var h := _local(_player.global_position).z
				_check(absf(h - PLATFORM_TOP) < 0.1 and _player.is_on_floor(), "unstuck puts you back on top of the drop (%.2f)" % h)
				_shot("03_unstuck_on_top")
				_platform.queue_free()
				# Front garden, looking at the house, and fly through it.
				_put(Vector3(2.7, -1.0, 0.1), Vector3(2.7, 4.0, 1.5))
				_key(KEY_V)
				_check(_player.noclip, "V: flying")
				_mark = _player.global_position
				Input.action_press("accelerate")
				_next()
		5:
			if _t > 1.5 and _t - delta <= 1.5:
				Input.action_release("accelerate")
				var through := _local(_player.global_position).y
				_check(through > 8.0, "flying goes through the house walls (y %.1f)" % through)
				Input.action_press("shift_up")
			if _t > 3.0 and _t - delta <= 3.0:
				Input.action_release("shift_up")
				_check(_player.global_position.y > _mark.y + 8.0, "E flies up")
				_player._pitch = -0.9
				_player._yaw += PI
			if _t > 3.3:
				_shot("04_flying_over_home")
				_key(KEY_V)
				_check(not _player.noclip, "V again: back on your feet")
				_key(KEY_1)
				_next()
		6:
			if _t > 1.0:
				var front: Vector3 = _home.spawn_transform(&"Spawn_Front").origin
				_check(_player.global_position.distance_to(front) < 0.6 and _player.is_on_floor(), "1: home, at the front gate")
				_shot("05_home")
				_mark = _car.global_position
				_key(KEY_3)  # facing the front door, the car parked out the back
				_next()
		7:
			if _t > 2.0:
				var d := _car.global_position.distance_to(_player.global_position)
				_check(d < 8.0 and _car.global_position.distance_to(_mark) > 5.0 and _car.global_basis.y.dot(Vector3.UP) > 0.95,
					"3 at the front gate: the car comes round to you (%.1f m, at %s)" % [d, _local(_car.global_position)])
				var to := (_car.global_position - _player.global_position) * Vector3(1, 0, 1)
				var look := -_player.global_basis.z * Vector3(1, 0, 1)
				_check(look.normalized().dot(to.normalized()) > 0.8, "and you're turned to face it")
				_shot("05b_car_at_the_front")
				_key(KEY_2)
				_next()
		8:
			if _t > 1.0:
				_check(_player.global_position.distance_to(_car.global_position) < 3.0 and _player.is_on_floor(), "2: beside the car")
				_shot("06_at_the_car")
				_put(Vector3(-6.0, -6.0, 0.0), Vector3(6.0, -6.0, 1.0))  # on the lane, looking along it
				_next()
		9:
			if _t > 0.5 and _t - delta <= 0.5:
				_key(KEY_3)
			if _t > 3.0:
				var d := _car.global_position.distance_to(_player.global_position)
				_check(d < 7.0 and _car.global_basis.y.dot(Vector3.UP) > 0.95, "3: the car comes to you, on its wheels (%.1f m)" % d)
				_shot("07_car_brought_over")
				_player.get_in()
				_next()
		10:  # drive along the lane, then unstuck the car back along it
			if _t > 2.5 and _t - delta <= 2.5:
				_check(_player.in_car and _car.player_controlled, "back in the car")
				Input.action_press("accelerate")
			if _t > 6.0 and _t - delta <= 6.0:
				Input.action_release("accelerate")
				Input.action_press("brake")
			if _t > 7.5:
				Input.action_release("brake")
				_mark = _car.global_position
				_key(KEY_U)
				_next()
		11:
			if _t > 1.5:
				var back := _car.global_position.distance_to(_mark)
				_check(back > 6.0 and _car.global_basis.y.dot(Vector3.UP) > 0.95, "U in the car: back along the road, upright (%.1f m)" % back)
				_shot("08_car_unstuck")
				_key(KEY_1)
				_next()
		12:
			if _t > 1.5:
				var spawn: Vector3 = _home.spawn_transform(&"Spawn_Car").origin
				_check(_car.global_position.distance_to(spawn) < 1.5, "1 in the car: back in the carport")
				var line: String = _dev.mark_spot()
				_check(line.contains("tile 0_") or line.contains("tile -1_"), "X: marks the spot (%s)" % line)
				_check(FileAccess.file_exists(_dev.marks_path), "marked spots go in a file")
				_shot("09_panel_in_car")
				return _finish()
	return false


## A 4 m square block PLATFORM_TOP high on the lane in front of the house.
func _make_platform() -> void:
	_platform = StaticBody3D.new()
	_platform.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, PLATFORM_TOP, 4.0)
	shape.shape = box
	_platform.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	_platform.add_child(mesh)
	_home.add_child(_platform)
	_platform.global_position = _world(PLATFORM + Vector3(0, 0, PLATFORM_TOP * 0.5))


func _put(feet: Vector3, look: Vector3) -> void:
	_player.teleport(_world(feet) + Vector3.UP * 0.05, _world(look))


## House coordinates (Blender: x across, y back from the street, z up).
func _world(b: Vector3) -> Vector3:
	return _home.to_global(Vector3(b.x, b.z, -b.y))


func _local(w: Vector3) -> Vector3:
	var p: Vector3 = _home.to_local(w)
	return Vector3(p.x, -p.z, p.y)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


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
	DirAccess.remove_absolute("user://dev_mode_test.cfg")
	DirAccess.remove_absolute("user://dev_marks_test.txt")
	for f in _failures:
		printerr("FAIL: ", f)
	print("DEV MODE TEST ", "PASSED" if _failures.is_empty() else "FAILED")
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
	return false
