extends SceneTree
## Runs the main mystery from start to finish, quickly: the midnight station
## sends you to each clue, you pick it up, it turns up in the cupboard under
## the stairs the next morning, the tier gates and the days between clues
## hold, the shed knocks back, the key opens the shed, and what's under the
## sheet ends it.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/mystery_test.gd -- --no-save
##
## With a display and shots=<dir> it saves a picture of each find, the
## cupboard and the shed. Exits with code 1 if any check fails.

var _quitting := false
var _main: Node
var _car: RigidBody3D
var _player: Node
var _home: Node3D
var _m: Node
var _failures: Array[String] = []
var _stage := 0
var _frames := 0
var _clue := 0
var _shots := ""


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("shots="):
				_shots = arg.trim_prefix("shots=")
				DirAccess.make_dir_recursive_absolute(_shots)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_player = _main.get_node_or_null("LoFi/SubViewport/World/Player")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		return false
	_frames += 1
	var clock := root.get_node("GameClock")
	var discoveries := root.get_node("Discoveries")
	match _stage:
		0:  # Settle, then the first night.
			if _frames == 60:
				_m = _main.find_child("Mystery", true, false)
				_home = get_first_node_in_group(&"home_base") as Node3D
				_check(_m != null, "the mystery is set up")
				_check(_home != null, "the townhouse is there")
				if _m == null or _home == null:
					return _finish()
				_check(_m.clues.size() == 7, "seven clues, the last one the shed key (%d)" % _m.clues.size())
				_check(_m.clues[-1].id == "shed_key", "the key is last")
				for c: Dictionary in _m.clues:
					_check(_m.spot_position(c.id) != Vector3.INF, "%s has somewhere to wait" % c.id)
				clock.set_time(14.0)
				_m._on_station_changed("midnight", "")
			elif _frames == 62:
				_check(_m.heard == "", "the station doesn't exist by day, so nothing's heard at 2 pm")
				_check(_m.notes().size() > 0, "the phone has a note")
				# Knock on the locked shed at night.
				clock.set_time(0.5)
				_check(not _home.toggle_door(&"Shed_Door"), "the shed is locked")
				_check(discoveries.has("oddity/shed_knock"), "something inside knocks back")
				_next()
		1:  # The voice sends you somewhere; go and get it.
			if _frames == 1:
				clock.set_time(0.5)
				_m._on_station_changed("midnight", "")
			elif _frames == 3:
				var expect: String = _m.clues[_clue].id
				_check(_m.heard == expect, "the voice sends you to %s (heard '%s')" % [expect, _m.heard])
				if _m.heard != expect:
					return _finish()
				_car.freeze = true
				_car.global_position = _m.spot_position(expect) + Vector3(0, 1.0, 0)
				_car.linear_velocity = Vector3.ZERO
			elif _frames > 3:
				var id: String = _m.clues[_clue].id
				if _m.found.has(id):
					_check(discoveries.has("mystery/" + id), "found %s" % id)
					_shot("find_" + id)
					_next()
				elif _frames > 900:
					_check(false, "found %s (still waiting %s, waiting object: %s)" % [id, _m._waiting_id, _m._waiting])
					return _finish()
		2:  # Home to bed; it's in the cupboard in the morning.
			if _frames == 1:
				_car.global_transform = _main.get_node("LoFi/SubViewport/World/PerthMap").get_spawn_transform().translated(Vector3.UP * 0.4)
				_home.sleep()
			elif _frames == 30:
				var id: String = _m.clues[_clue].id
				if id != "shed_key":
					_check(_m.in_cupboard.has(id), "%s turned up in the cupboard under the stairs" % id)
					_check(_home.is_door_open(&"Door_Storage"), "the cupboard is open in the morning")
					_check(_m._shelf.get_child_count() == _m.in_cupboard.size(), "%d things on the boxes" % _m.in_cupboard.size())
					_home.toggle_door(&"Door_Storage")
				# The next one waits for the career and a couple of days.
				clock.set_time(0.5)
				_m._on_station_changed("midnight", "")
				_check(_m.heard == "", "nothing new the very next night")
				_clue += 1
				if _clue >= _m.clues.size():
					_stage = 3
					_frames = 0
					return false
				var need := int(_m.clues[_clue].tier)
				if need > 0:
					root.get_node("Progression").tier_index = need - 1
					clock.advance(48.0)
					clock.set_time(0.5)
					_m._on_station_changed("midnight", "")
					_check(_m.heard == "", "%s waits for tier %d" % [_m.clues[_clue].id, need + 1])
				root.get_node("Progression").tier_index = need
				clock.advance(48.0)
				_stage = 1
				_frames = 0
		3:  # The key opens the shed; what's under the sheet ends it.
			if _frames == 1:
				_check(_m.has_key, "you have the shed key")
				_check(_home.toggle_door(&"Shed_Door"), "the key opens the shed")
				_check(_home.shed_is_unlocked, "the shed stays unlocked")
				_car.freeze = false
				if _player:
					_player.get_out()
			elif _frames == 120 and _player:
				var centre: Vector3 = _m._shed_centre()
				var door := _home.find_child("Shed_Door", true, false) as Node3D
				var feet := centre + (door.global_position - centre).normalized() * 1.2
				feet.y = _home.global_position.y + 0.05
				_player.teleport(feet, centre + Vector3.UP * 0.8)
			elif _frames == 240:
				_check(_m.is_solved, "the mystery is solved in the shed")
				_check(_m._shed_props != null, "the table and transmitter are under the sheet")
				_check(not (_home.find_child("Shed_Sheeted", true, false) as Node3D).visible, "the sheet's off")
				_check(root.get_node("Progression").rewards.has("trinket_night_drive_tape"), "the tape is yours")
				_check(discoveries.has("mystery/solved"), "it counts as a discovery")
				_shot("shed")
				var state: Dictionary = _m.save_state()
				_m.load_state(JSON.parse_string(JSON.stringify(state)))
				_check(_m.save_state() == state, "it saves and loads")
				return _finish()
			elif _player == null and _frames > 2:
				return _finish()
	return false


func _next() -> void:
	_stage += 1
	_frames = 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))


func _finish() -> bool:
	print("MYSTERY ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Takes the game down before quitting (a plain quit() crashed on exit on Windows).
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
	return false
