extends SceneTree
## Walks the player around the townhouse on foot: out of the car in the
## carport, the courtyard, the lounge, up the stairs, through a door, to bed,
## the locked shed, and back into the car.
##
##   godot --headless --path . --fixed-fps 120 --script res://tools/on_foot_test.gd -- --no-save
##
## With a display (or xvfb) and shots=<dir>, it also saves a screenshot at
## each stage:
##
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/on_foot_test.gd -- --no-save shots=/tmp/shots
##
## Exits with code 1 if any check fails.

const FZ0 := 0.15
const FZ1 := 3.16

var _main: Node
var _car: RigidBody3D
var _player: Node
var _home: Node3D
var _failures: Array[String] = []
var _stage := 0
var _t := 0.0
var _shots := ""
var _day := 0
var _rig_cam: Camera3D


func _process(delta: float) -> bool:
	if _main == null:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("shots="):
				_shots = arg.trim_prefix("shots=")
				DirAccess.make_dir_recursive_absolute(_shots)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(17.5)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_player = _main.get_node("LoFi/SubViewport/World/Player")
		_rig_cam = _main.get_node("LoFi/SubViewport/World/CameraRig/Camera3D")
		return false
	_t += delta
	match _stage:
		0:  # settle in the carport
			if _t > 3.0:
				_home = _main.get_node("LoFi/SubViewport/World/PerthMap").get_home()
				_check(_home != null, "the townhouse is loaded")
				if _home == null:
					return _finish()
				_check(_player.in_car, "starts in the car")
				_shot("01_in_car")
				_action("interact", true)  # hold F to get out
				_next()
		1:
			if _t > 0.25 and _t - delta <= 0.25:
				_check(_player.in_car, "a tap of F doesn't get out")
			if _t > 0.8 and _t - delta <= 0.8:
				_action("interact", false)
			if _t > 1.4:
				var workshop := _main.find_child("Workshop", true, false)
				_check(workshop == null or not workshop.is_open(), "holding F doesn't open the workshop")
				_check(not _player.in_car, "got out of the car")
				_check(_player.is_on_floor(), "standing on the ground after getting out")
				_check(_player.get_node("Eyes").current, "first-person camera is live")
				_check(_player.global_position.distance_to(_car.global_position) < 3.0, "got out beside the car")
				_check(not _car.player_controlled, "the car ignores input while you're out")
				_shot("02_out_of_car")
				_put(Vector3(3.2, 14.2, 0.0), Vector3(3.0, 11.5, 1.3))
				_next()
		2:
			if _t > 0.6:
				_check(_player.surface() == "brick", "courtyard footsteps are brick (%s)" % _player.surface())
				var fs = _player.get_node_or_null("FootstepAudio")
				_check(fs != null and fs.surface_under() == "brick", "FootstepAudio hears brick in the courtyard")
				_shot("03_courtyard")
				_put(Vector3(2.6, 3.6, FZ0), Vector3(0.2, 3.2, FZ0 + 1.0))
				_next()
		3:
			if _t > 0.6:
				_check(_player.is_on_floor(), "standing in the lounge")
				_check(_player.surface() == "timber", "lounge footsteps are timber (%s)" % _player.surface())
				_shot("04_lounge")
				_put(Vector3(0.5, 9.3, FZ0), Vector3(0.5, 5.0, FZ1 + 0.9))
				_next()
		4:  # walk up the stairs
			if _t > 0.4 and _t < 0.5:
				Input.action_press("accelerate")
			if _t > 0.42 and _t - delta <= 0.42:
				_shot("05_stairs")
			if OS.get_environment("ONFOOT_DEBUG") != "" and fmod(_t, 0.5) < delta:
				print("stairs t=%.1f local=%s vel=%s floor=%s" % [_t, _local(_player.global_position), _player.velocity, _player.is_on_floor()])
			if _t > 5.0:
				Input.action_release("accelerate")
				var h := _local(_player.global_position).z
				_check(h > FZ1 - 0.1, "climbed the stairs (floor height %.2f)" % h)
				_check(_player._footsteps.steps >= 4, "footsteps played on the way up (%d)" % _player._footsteps.steps)
				_put(Vector3(1.55, 7.3, FZ1), Vector3(1.55, 8.4, FZ1 + 1.1))
				_next()
		5:  # open the studio door and walk in
			if _t > 0.6 and _t - delta <= 0.6:
				_check(_player._target() == ["door", &"Door_Bed2"], "looking at the studio door (%s)" % [_player._target()])
				_player.interact()
			if _t > 1.6 and _t - delta <= 1.6:
				_check(_home.is_door_open(&"Door_Bed2"), "the studio door opens")
				Input.action_press("accelerate")
			if _t > 3.6:
				Input.action_release("accelerate")
				_check(_local(_player.global_position).y > 8.3, "walked through into the studio")
				_shot("06_studio")
				_put(Vector3(2.4, 2.05, FZ1), Vector3(4.4, 2.05, FZ1 + 0.4))
				_next()
		6:  # go to bed
			if _t > 0.6 and _t - delta <= 0.6:
				_check(_player._target() == ["bed", null], "the bed is in reach")
				_shot("07_bedroom")
				_day = root.get_node("GameClock").day
				root.get_node("GameClock").set_locked(false)
				_player.interact()
			if _t > 6.0:
				var clock := root.get_node("GameClock")
				_check(clock.day == _day + 1 and absf(clock.time_of_day - 7.0) < 0.5,
					"sleeping ends the day (day %d, %.1f h)" % [clock.day, clock.time_of_day])
				clock.set_time(17.5)
				clock.set_locked(true)
				_put_at_shed()
				_next()
		7:  # the shed is locked
			if _t > 0.6 and _t - delta <= 0.6:
				_check(_player._target() == ["door", &"Shed_Door"], "looking at the shed door (%s)" % [_player._target()])
				_player.interact()
				_check(not _home.is_door_open(&"Shed_Door"), "the shed stays locked")
				_check(_player._prompt.text.begins_with("Locked"), "says the shed is locked")
				_shot("08_shed")
			if _t > 1.2:
				var side := _car.global_basis * Vector3(1.4, 0, 0.1)
				_player.teleport(_ground(_car.global_position + side), _car.global_position + Vector3.UP * 0.8)
				_next()
		8:  # back in the car
			if _t > 0.6 and _t - delta <= 0.6:
				_check(_player._target() == ["car", null], "the car is in reach")
				_shot("09_back_to_car")
				_player.interact()
			if _t > 1.2:
				_check(_player.in_car, "got back in")
				_check(_car.player_controlled, "the car drives again")
				_check(_rig_cam.current, "the driving camera is back")
				return _finish()
	return false


func _finish() -> bool:
	for f in _failures:
		printerr("FAIL: ", f)
	print("ON FOOT TEST ", "PASSED" if _failures.is_empty() else "FAILED")
	quit(1 if _failures.size() else 0)
	return true


func _next() -> void:
	if OS.get_environment("ONFOOT_DEBUG") != "" and _home:
		print("stage %d ends at %s floor=%s target=%s" % [_stage, _local(_player.global_position), _player.is_on_floor(), _player._target()])
	_stage += 1
	_t = 0.0


## House coordinates (Blender: x across, y back from the street, z up).
func _world(b: Vector3) -> Vector3:
	return _home.to_global(Vector3(b.x, b.z, -b.y))


func _local(w: Vector3) -> Vector3:
	var p: Vector3 = _home.to_local(w)
	return Vector3(p.x, -p.z, p.y)


func _put(feet: Vector3, look: Vector3) -> void:
	_player.teleport(_world(feet) + Vector3.UP * 0.05, _world(look))


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0, 3)
	q.exclude = [_car.get_rid()]
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


## Stand in the carport between the shed door and the parked car, facing
## the door.
func _put_at_shed() -> void:
	var door: Node3D = _home.find_child("Shed_Door", true, false)
	var mesh: MeshInstance3D = door if door is MeshInstance3D else door.find_children("*", "MeshInstance3D")[0]
	var centre := _local(mesh.global_transform * mesh.get_aabb().get_center())
	_put(Vector3(centre.x, centre.y + 0.4, 0.0), Vector3(centre.x, centre.y, 1.4))


func _shot(name: String) -> void:
	if _shots == "":
		return
	var hud := _main.get_node_or_null("HUD")
	if hud and hud.get("_help"):
		hud._help.visible = false
	var img := root.get_texture().get_image()
	img.save_png(_shots.path_join(name + ".png"))
	print("saved ", name)


func _action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
	print(("ok   " if ok else "FAIL ") + what)
