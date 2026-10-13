extends SceneTree
## A new game's first few minutes (scripts/world/story/first_day.gd), played
## through and photographed: the card after Side A, the plate on the step,
## the answering machine, the phone, the first job, the last card. Fails
## (exit 1) if a step doesn't tick off.
##
##   godot --path . --resolution 1280x720 --script res://tools/first_day_screens.gd \
##       -- --no-save shots=/tmp/first_day

var _shots := "user://first_day"
var _main: Node
var _world: Node
var _car  # CarController
var _player  # OnFoot
var _home  # HomeBase
var _first  # FirstDay
var _cam: Camera3D
var _H79: GDScript
var _door_x := 1.0
var _steps: Array = []
var _step := -1
var _frames := 0
var _failed := 0
## Every card Notices put on screen, as "kind: text".
var _seen: Array[String] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
	DirAccess.make_dir_recursive_absolute(_shots)


func _h(x: float, y: float, z: float) -> Vector3:
	return _home.to_global(_H79.at(Vector3(x, y, z)))


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed += 1


func _title() -> String:
	return String(_first.challenge_card().get("title", ""))


func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)


func _build_steps() -> void:
	# [name, call at the start, frames to wait, shoot]
	_steps.append(["fd_00_start", func() -> void: pass, 120, true])
	_steps.append(["fd_01_side_a", func() -> void: pass, 5 * 60, true])
	_steps.append(["fd_02_first_card", func() -> void:
		_check(_title() == "", "nothing until Side A's card has gone"), 9 * 60, true])
	_steps.append(["fd_03_get_out", func() -> void:
		_check(_title() == "Something on the step", "first card: the step (%s)" % _title())
		# The opening's steps say these already; the home street's cards wait.
		var crowd := _seen.filter(func(t: String) -> bool:
			return t.begins_with("jobs:") or t.contains("answering machine") \
				or t.begins_with("place:") or t.begins_with("progress:"))
		_check(crowd.is_empty(), "no phone, machine, street or Wandering cards ahead of it %s" % [crowd])
		_check(String(_first.challenge_card().line).begins_with("Get out"), "in the car it says get out")
		_player.call("get_out"), 150, false])
	_steps.append(["fd_04_at_the_step", func() -> void:
		_check(String(_first.challenge_card().line).begins_with("Go and see"), "on foot it says go and see")
		var plate: Vector3 = _first.interact_point()
		var stand: Vector3 = _h(_door_x + 0.2, -1.5, 0.0)
		stand.y = plate.y
		_player.call("teleport", stand, plate), 60, true])
	_steps.append(["fd_05_plate_close", func() -> void:
		_check(_player.call("_nearest_thing") == _first, "the plate is what you'd use")
		_check(_first.interact_hint() == "Take the plate", "hint: take the plate")
		var plate: Vector3 = _first.interact_point()
		_cam.current = true
		_cam.global_position = plate + _home.global_basis.z * 0.7 + Vector3.UP * 0.45
		_cam.look_at(plate), 20, true])
	_steps.append(["fd_05b_doorstep", func() -> void:
		var plate: Vector3 = _first.interact_point()
		_cam.global_position = _h(_door_x - 0.6, -3.2, 1.6)
		_cam.look_at(plate + Vector3.UP * 0.6), 20, true])
	_steps.append(["fd_06_taken", func() -> void:
		(_player.get("_camera") as Camera3D).current = true
		_press(&"interact"), 40, true])
	_steps.append(["fd_07_machine_card", func() -> void:
		_check(_first.plate_taken, "the plate's taken")
		_check(_title() == "The answering machine", "second card: the machine (%s)" % _title())
		var machine: Node3D = _home.find_child("AnsweringMachine", false, false)
		var at: Vector3 = machine.global_position
		_player.call("teleport", _h(3.4, 8.0, 0.15), at), 60, true])
	_steps.append(["fd_08_message", func() -> void:
		var machine: Node = _home.find_child("AnsweringMachine", false, false)
		_check(_player.call("_nearest_thing") == machine, "the machine is what you'd use")
		_press(&"interact"), 150, true])
	_steps.append(["fd_08b_machine_close", func() -> void:
		var machine: Node3D = _home.find_child("AnsweringMachine", false, false)
		_cam.current = true
		_cam.global_position = machine.global_position - _home.global_basis.z * 0.9 + _home.global_basis.x * -0.4 + Vector3.UP * 0.5
		_cam.look_at(machine.global_position), 20, true])
	_steps.append(["fd_09_plate_on_bar", func() -> void:
		_check(root.get_node("Story").heard(&"kostas_welcome"), "Thea's welcome heard")
		_check(_title() == "Rent's coming", "third card: take a job (%s)" % _title())
		var plate: Node3D = _first.get("_plate")
		_check(plate.visible, "the plate's on the breakfast bar")
		_cam.current = true
		_cam.global_position = plate.global_position + _home.global_basis.z * 0.8 + _home.global_basis.x * 0.3 + Vector3.UP * 0.55
		_cam.look_at(plate.global_position), 20, true])
	_steps.append(["fd_09b_plate_on_bar_side", func() -> void:
		var plate: Node3D = _first.get("_plate")
		_cam.global_position = plate.global_position - _home.global_basis.x * 0.9 + Vector3.UP * 0.6
		_cam.look_at(plate.global_position), 20, true])
	_steps.append(["fd_09c_story_moment", func() -> void:
		(_player.get("_camera") as Camera3D).current = true
		_check(root.get_node("LateCity").begin(&"first_day_test"), "a story moment starts")
		_check(_title() == "", "the card steps aside for it"), 30, true])
	_steps.append(["fd_09d_after_it", func() -> void:
		root.get_node("LateCity").end(&"first_day_test")
		_check(_title() == "Rent's coming", "and comes back after (%s)" % _title()), 30, false])
	_steps.append(["fd_10_phone", func() -> void:
		(_player.get("_camera") as Camera3D).current = true
		root.get_node("Notices").clear()
		_press(&"phone"), 60, true])
	_steps.append(["fd_11_job", func() -> void:
		_press(&"phone")
		var jobs := root.get_node("Jobs")
		jobs.accept(jobs.offers[0]), 60, true])
	_steps.append(["fd_12_paid", func() -> void:
		_check(_title() == "", "the job's own card while it's on")
		var jobs := root.get_node("Jobs")
		var job: Dictionary = jobs.active.duplicate()
		jobs.abandon()
		jobs.job_completed.emit(job, 40, "Dropped off. They hand you $40.")
		root.get_node("Notices").clear(), 60, true])
	_steps.append(["fd_13_done", func() -> void:
		_check(_title() == "Paid", "last card: paid (%s)" % _title()), 17 * 60, false])
	_steps.append(["fd_14_saved", func() -> void:
		_check(_title() == "", "and then it's done")
		var saved: Dictionary = _first.save_state()
		_check(int(saved.step) == 4, "saved as done")
		# A game saved before this existed starts with it done.
		var old: Node = load("res://scripts/world/story/first_day.gd").new()
		_main.get_node("LoFi/SubViewport/World").add_child(old)
		old.set_meta(&"probe", true), 30, false])
	_steps.append(["fd_15_old_save", func() -> void:
		var old: Node = null
		for n in _world.get_children():
			if n.has_meta(&"probe"):
				old = n
		_check(old != null and int(old.get("step")) == 4, "an older game skips it")
		if old:
			old.queue_free(), 10, false])


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		_H79 = load("res://scripts/world/late_city/house_1979.gd")
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		_player = _world.get_node_or_null("Player")
		root.get_node("Weather").set_locked(true)
		_frames = -1
		return false
	_frames += 1
	var shown: Dictionary = root.get_node("Notices").showing()
	if not shown.is_empty():
		var line := "%s: %s" % [shown.kind, shown.text]
		if not _seen.has(line):
			_seen.append(line)
			print("card ", line)
	if _step == -1:
		_home = get_first_node_in_group(&"home_base")
		_first = _main.find_child("FirstDay", true, false)
		if _home == null or _first == null:
			_check(false, "FirstDay and the home are in the world")
			quit(1)
			return true
		_door_x = _home.to_local(_home.spawn_transform(&"Spawn_Front").origin).x
		_cam = Camera3D.new()
		_cam.fov = 60.0
		_world.add_child(_cam)
		_build_steps()
		_next()
		return false
	if _step >= _steps.size():
		print("first day: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
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
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()
