extends SceneTree
## Checks that every menu's key closes it as well as opening it, and that Esc
## closes it too, with real key presses (so a focused button can't swallow them):
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/menu_keys_test.gd -- --no-save
##
## Menus you open with F at a spot in the world are closed with F too. The
## record crate and decorate are walked up to on foot and opened with F
## where the player can pick them out; the lab and tackle counters and the
## workshop are opened directly. The dev menu opens with F4 once dev mode
## is on (F3), with the setting kept in a scratch file. Exits with code 1 if
## any check fails.
##
## With a display and shots=<dir> it saves each menu open and just after its
## key shut it:
##
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/menu_keys_test.gd -- --no-save shots=/tmp/keys

const WAIT := 0.25
const DEV_SETTINGS := "user://menu_keys_dev_mode.cfg"

var _quitting := false
var _main: Node
var _failures: Array[String] = []
var _cases: Array = []
var _case := -1
var _phase := 0
var _t := 0.0
var _player: Node3D
var _shots := ""


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
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		return false
	_t += delta
	if _case < 0:
		if _player == null:
			_player = _main.get_node("LoFi/SubViewport/World/Player")
		if _t < 3.0:
			if _t > 1.0 and _player.get("in_car"):
				_player.call("get_out")
			return false
		root.get_node("Discoveries").discover("field/binoculars")
		_cases = _build_cases()
		_start(0)
		return false
	if _t < WAIT:
		return false
	_t = 0.0
	var c: Array = _cases[_case]
	var is_open: Callable = c[2]
	match _phase:
		0:  # open it
			_check(is_open.call(), "%s opens with %s" % [c[0], _what(c[1])])
			if not is_open.call():
				return _skip()
			_shot("%02d_open" % _case)
			_press(c[3])
			_phase = 1
		1:  # its own key shuts it
			_check(not is_open.call(), "%s closes with %s" % [c[0], _what(c[3])])
			_shot("%02d_closed" % _case)
			if is_open.call():
				_press(KEY_ESCAPE)  # tidy up for the next one
				_phase = 2
				return false
			_open(c[1])
			_phase = 3
		2:
			_skip()
		3:  # and Esc shuts it too
			if not is_open.call():
				return _skip()
			_press(KEY_ESCAPE)
			_phase = 4
		4:
			_check(not is_open.call(), "%s closes with Esc" % c[0])
			_check(not paused, "the game runs again after %s closes" % c[0])
			_skip()
	return false


func _build_cases() -> Array:
	var places := "LoFi/SubViewport/World/GameplayPlaces/"
	var records: Node = _main.get_node(places + "Records")
	var furniture: Node = _main.get_node(places + "HomeFurniture")
	var workshop: Node = _main.get_node("Workshop")
	var spot: Node = get_first_node_in_group(&"workshop_spots")
	# [name, how it opens (a key or a Callable), is it open?, the key that should close it]
	return [
		["The phone", KEY_TAB, _node("Phone").is_open, KEY_TAB],
		["The map", KEY_M, _node("MapScreen").is_open, KEY_M],
		["The journal", KEY_J, _field("FieldJournalScreen").is_open, KEY_J],
		["Photo mode", KEY_P, _node("PhotoMode").is_open, KEY_P],
		["The binoculars", KEY_B, _field("Binoculars").is_open, KEY_B],
		["The record crate", _walk_up.bind(&"Use_crate"), records.is_picking, KEY_F],
		["Decorate", _walk_up.bind(&"Use_catalogue"), func() -> bool: return furniture.get("_panel") != null, KEY_F],
		["The photo lab counter", _field("LabScreen").open, _field("LabScreen").is_open, KEY_F],
		["The tackle shop counter", _field("TackleScreen").open, _field("TackleScreen").is_open, KEY_F],
		["The workshop", workshop.open.bind(spot), workshop.is_open, KEY_F],
		["The dev menu", _dev_menu, _node("DevMode").menu.is_open, KEY_F4],
		["The pause menu", KEY_ESCAPE, _node("PauseMenu").is_open, KEY_ESCAPE],
	]


func _start(i: int) -> void:
	_case = i
	_phase = 0
	_t = 0.0
	if _case >= _cases.size():
		_finish()
		return
	_open(_cases[_case][1])


func _skip() -> bool:
	_start(_case + 1)
	return false


func _open(how: Variant) -> void:
	if how is Callable:
		(how as Callable).call()
	else:
		_press(how)


## Stand next to the spot named `spot_name` on the floor, look at it and press F.
func _walk_up(spot_name: StringName) -> void:
	var spot: Node3D
	for n in get_nodes_in_group(&"interactables"):
		if n.name == spot_name:
			spot = n
	_check(spot != null and not _player.get("in_car"), "out of the car to walk up to " + spot_name)
	if spot == null:
		return
	var space := _player.get_world_3d().direct_space_state
	var at := spot.global_position
	# Try each side until the player is looking at it, not at a wall.
	for dir: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
		var from := at + dir * 0.9 + Vector3.UP * 0.6
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
		q.exclude = [(_player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.position.y < at.y:
			_player.call("teleport", hit.position, at)
			if _player.call("_target") == ["thing", spot]:
				_press(KEY_F)
				return
	# Nowhere to stand that picks it out from what's beside it (the record
	# player crowds the crate): use it the way OnFoot does on F.
	spot.call("interact")


## Dev mode on (with its setting kept in a scratch file), then F4.
func _dev_menu() -> void:
	var dev := _node("DevMode")
	dev.settings_path = DEV_SETTINGS
	dev.set_enabled(true)
	_press(KEY_F4)


func _press(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _what(how: Variant) -> String:
	return OS.get_keycode_string(how) if how is int else "F"


func _node(path: String) -> Node:
	return _main.get_node(path)


## The field screens sit on the current scene (the root, under this script).
func _field(name: String) -> Node:
	var n := root.get_node_or_null(name)
	return n if n else _main.find_child(name, true, false)


func _shot(name: String) -> void:
	if _shots != "":
		root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	DirAccess.remove_absolute(DEV_SETTINGS)
	print("menu keys: %d failure(s)" % _failures.size())
	_quitting = true
	quit(1 if not _failures.is_empty() else 0)
