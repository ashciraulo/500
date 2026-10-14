extends SceneTree
## Checks the dev menu (scripts/dev/dev_menu.gd, F4 in dev mode), headless:
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/dev_menu_test.gd -- --no-save
##
## F4 opens it only while dev mode is on, and F4 and Esc close it. Then what
## it does: drive any car (from the car and on foot, a classic restored, one
## as a wreck), fit parts (bought and found ones), every part, stock again,
## the best field gear and every bird, money, time, weather, game speed,
## traffic, the career tier (and the act with it), finishing a tier, story
## choices and endings, readying the late city's events, going somewhere far
## in the car and on foot, T on the map, and a snapshot saved and loaded.
##
## With a display and shots=<dir> it saves each tab and each stage:
##
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/dev_menu_test.gd -- --no-save shots=/tmp/devmenu
##
## Exits with code 1 if any check fails.

var _quitting := false
var _main: Node
# Untyped: naming the game's classes here would compile them before the autoloads exist.
var _car: RigidBody3D
var _player: CharacterBody3D
var _dev: CanvasLayer
var _menu: CanvasLayer
var _failures: Array[String] = []
var _steps: Array = []  # [Callable, seconds to wait after it]
var _step := -1
var _wait := 3.0
var _shots := ""
var _mark := {}


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
		_auto("GameClock").set_time(15.0)
		_auto("GameClock").set_locked(true)
		_auto("Weather").set_locked(true)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_player = _main.get_node("LoFi/SubViewport/World/Player")
		if _shots != "":
			_main.get_node("HUD").hide_help()
		_steps = _plan()
		return false
	_wait -= delta
	if _wait > 0.0:
		return false
	_step += 1
	if _step >= _steps.size():
		_finish()
		return false
	var s: Array = _steps[_step]
	(s[0] as Callable).call()
	_wait = float(s[1])
	return false


func _plan() -> Array:
	return [
		[func() -> void:
			_dev = _main.get_node_or_null("DevMode")
			_check(_dev != null, "debug builds get dev mode")
			if _dev == null:
				_finish()
				return
			_menu = _dev.menu
			_dev.settings_path = "user://dev_menu_test.cfg"
			_menu.snapshot_path = "user://dev_menu_test_snapshot_%d.json"
			_dev.set_enabled(false)
			_key(KEY_F4), 0.5],
		[func() -> void:
			_check(not _menu.is_open(), "F4 does nothing while dev mode is off")
			_dev.set_enabled(true)
			_key(KEY_F4), 0.5],
		[func() -> void:
			_check(_menu.is_open(), "F4 opens the dev menu")
			_check(paused, "the game pauses while it's open")
			_key(KEY_F4), 0.5],
		[func() -> void:
			_check(not _menu.is_open() and not paused, "F4 closes it and the game runs again")
			_key(KEY_F4), 0.5],
		[func() -> void:
			_key(KEY_ESCAPE), 0.5],
		[func() -> void:
			_check(not _menu.is_open() and not paused, "Esc closes it too")
			_menu.open(), 0.4],
	] + _tab_shots() + [
		# Cars, from the driver's seat.
		[func() -> void:
			_menu.close()
			_chase_camera()
			_check(_dev.tools.give_car("abarth_500") != "", "give a car")
			_check(_car.car_id == "abarth_500" and _auto("Garage").owns_car("abarth_500"), "you're in the Abarth and it's yours"), 1.0],
		[func() -> void:
			_dev.tools.give_car("valiant_vc")
			_check(_car.car_id == "valiant_vc", "the Valiant without the 1979 lane"), 2.0],
		[func() -> void:
			_shot("07_valiant")
			_dev.tools.give_car("classic_500l")
			_check(_car.car_id == "classic_500l" and _auto("Classics").can_drive("classic_500l"), "a classic comes restored and drives"), 2.0],
		[func() -> void:
			_shot("08_classic_500l")
			_dev.tools.give_wreck("classic_nuova")
			_check(_auto("Garage").owns_car("classic_nuova") and not _auto("Classics").can_drive("classic_nuova"),
				"a classic as a wreck is on the bench, not driveable")
			_dev.tools.give_car("pop_12")
			_check(_car.car_id == "pop_12", "back in the Pop"), 1.0],
		# Parts.
		[func() -> void:
			var parts: Array = _parts_for("exhaust")
			_check(not parts.is_empty(), "there are exhausts for the Pop")
			if not parts.is_empty():
				_dev.tools.fit_part(parts[0])
				_check(_car.get_part_ids().has(String(parts[0].id)), "fit an exhaust")
			var rack = _found_part()
			if rack:
				_dev.tools.fit_part(rack)
				_check(_car.get_part_ids().has(String(rack.id)) and _auto("Discoveries").has("part/" + String(rack.id)),
					"fit a found part (counts as found)")
			var money: int = _auto("Wallet").balance
			_dev.tools.own_all_parts()
			_check(_auto("Wallet").balance == money and not _auto("Garage").spare_parts(_car).is_empty(),
				"every part on the shelf, for nothing")
			_menu.open()
			_menu._tabs.current_tab = 1, 0.6],
		[func() -> void:
			_shot("09_parts_after")
			_menu.close(), 1.0],
		[func() -> void:
			_shot("10_pop_with_parts")
			_dev.tools.all_stock()
			_check(_car.get_part_ids().is_empty(), "all stock again")
			var journal := _auto("FieldJournal")
			_dev.tools.best_field_gear()
			_check(journal.binoculars == 2 and journal.rod == 2 and journal.has_crab_net
				and _auto("Discoveries").has("field/binoculars"), "the best field gear")
			_dev.tools.see_all_birds()
			_check(journal.seen_count() > 20, "every bird in the journal (%d)" % journal.seen_count()), 0.5],
		# Money, time, weather, speed, traffic.
		[func() -> void:
			var wallet := _auto("Wallet")
			var was: int = wallet.balance
			var earned: int = wallet.total_earned
			_dev.tools.add_money(10000)
			_check(wallet.balance == was + 10000 and wallet.total_earned == earned, "+$10,000, not counted as earnings")
			_dev.tools.add_money(-wallet.balance)
			_check(wallet.balance == 0, "money back to none")
			_dev.tools.add_money(5000)
			_menu.open()
			_menu._tabs.current_tab = 2, 0.5],
		[func() -> void:
			_press(_menu, "Night")
			_press(_menu, "Storm")
			_press(_menu, "2x"), 0.5],
		[func() -> void:
			_check(absf(_auto("GameClock").time_of_day - 21.5) < 0.1, "Night sets the clock")
			_check(_auto("Weather").state == 2, "Storm sets the weather")
			_check(is_equal_approx(Engine.time_scale, 2.0), "2x speeds the game up")
			_shot("11_world_after")
			_press(_menu, "1x")
			_press(_menu, "Clear")
			_press(_menu, "Noon")
			var traffic := get_first_node_in_group(&"traffic")
			if traffic:
				_press_in_row(_menu, "Cars", "Busy")
				_check(traffic.density_scale > 2.0, "busy traffic")
				_press_in_row(_menu, "Cars", "Normal")
			_check(is_equal_approx(Engine.time_scale, 1.0), "back to 1x"), 0.5],
		# Career tier, the act, choices and endings, events.
		[func() -> void:
			var story := _auto("Story")
			_dev.tools.set_tier(3)
			_check(story.act() == 4, "tier 4 makes it act 4")
			_dev.tools.finish_tier()
			_check(_auto("Progression").tier_index == 4 and story.act() == 5, "finishing tier 4 moves up to tier 5, act 5")
			_dev.tools.set_choice(&"robyn", &"found")
			_check(story.choice(&"robyn") == &"found", "make a choice")
			_dev.tools.set_choice(&"robyn", &"")
			_check(story.choice(&"robyn") == &"", "unmake it")
			_dev.tools.set_ending(&"half_light")
			_check(story.ending() == &"half_light", "set an ending")
			_dev.tools.set_ending(&"")
			_check(story.ending() == &"", "and none again")
			_dev.tools.set_tier(0)
			_check(story.act() == 1, "back to tier 1, act 1")
			_menu.open()
			_menu._tabs.current_tab = 4, 0.5],
		[func() -> void:
			_check(_menu._events.size() == _menu.EVENTS.size(), "every late-city event found (%d of %d)" % [_menu._events.size(), _menu.EVENTS.size()])
			_press(_menu, "Ready")
			var first: Node = _menu._events.get(_menu.EVENTS[0][0])
			_check(first != null and first.get("force") == true, "Ready readies an event")
			if first:
				first.set("force", false)
			_menu._tabs.current_tab = 3, 0.5],
		[func() -> void:
			# Places: somewhere far, in the car.
			var target := _far_place(600.0)
			_check(target.size() == 2, "a place far off to go to")
			_mark = {"at": target[1] if target.size() == 2 else Vector3.ZERO}
			if target.size() == 2:
				_menu._go(target[1], target[0])
				print("going to ", target[0], " ", target[1]), 3.0],
		[func() -> void:
			var at: Vector3 = _mark.at
			var d := Vector2(_car.global_position.x - at.x, _car.global_position.z - at.z).length()
			_check(d < 60.0, "the car got there (%.0f m off)" % d)
			_check(_car.global_basis.y.dot(Vector3.UP) > 0.9 and _player.get("in_car"), "on its wheels, you in it")
			_shot("12_went_in_car")
			# On foot, to a fishing jetty.
			_player.get_out(), 2.5],
		[func() -> void:
			var spot: Dictionary = _auto("FieldJournal").spots[0]
			var stand: Array = spot.stand
			_mark = {"at": Vector3(stand[0], stand[1], stand[2])}
			_dev.go_to(_mark.at, String(spot.name)), 2.0],
		[func() -> void:
			var at: Vector3 = _mark.at
			var d: float = _player.global_position.distance_to(at)
			_check(d < 8.0 and _player.is_on_floor(), "on foot, standing at the jetty (%.1f m off)" % d)
			_shot("13_went_on_foot")
			# Drive a car while on foot: it turns up beside you.
			_menu.open()
			_menu._drive("e_500e_2013"), 0.5],
		[func() -> void:
			_menu.close(), 1.0],
		[func() -> void:
			_check(_car.car_id == "e_500e_2013" and _car.global_position.distance_to(_player.global_position) < 9.0,
				"a car given on foot is beside you")
			_shot("14_car_beside_you")
			# T on the map.
			_key(KEY_M), 0.6],
		[func() -> void:
			var map := _main.get_node("MapScreen")
			_check(map.is_open(), "the map opens")
			# Put Little Shenton Lane under the pointer, wherever it is.
			var view: Control = map._view
			view.centre += Vector2(-57.5, 38.8) - view.to_world(view.get_local_mouse_position())
			_key(KEY_T), 2.5],
		[func() -> void:
			var d := Vector2(_player.global_position.x + 57.5, _player.global_position.z - 38.8).length()
			_check(not _main.get_node("MapScreen").is_open() and d < 12.0, "T on the map goes there (%.1f m off)" % d)
			_shot("15_map_t")
			# Snapshots.
			_menu.open()
			_menu._tabs.current_tab = 5, 0.5],
		[func() -> void:
			_press(_menu, "Save")
			_check(FileAccess.file_exists(_menu.snapshot_path % 1), "a snapshot saved")
			_dev.tools.add_money(777)
			_menu._refresh(), 0.3],
		[func() -> void:
			_shot("16_saves")
			var money: int = _auto("Wallet").balance
			_press(_menu, "Load")
			_check(_auto("Wallet").balance == money - 777, "loading it puts the money back")
			_check(not _menu.is_open(), "and closes the menu"), 1.0],
		[func() -> void:
			_check(_auto("SaveGame").enabled == false, "this run (--no-save) stays out of the save"), 0.1],
	]


func _tab_shots() -> Array:
	var steps: Array = []
	for i in 6:
		steps.append([func() -> void: _menu._tabs.current_tab = i, 0.5])
		steps.append([func() -> void: _shot("%02d_tab_%s" % [i + 1, String(_menu._tabs.get_tab_title(i)).to_lower()]), 0.1])
	return steps


## Presses the first button (or check button) in the menu's open tab whose text is `text`.
func _press(menu: Node, text: String) -> void:
	var list: Node = menu._lists[String(menu._tabs.get_current_tab_control().name)]
	for b in list.find_children("*", "BaseButton", true, false):
		if (b as BaseButton).visible and (b as Button).text == text and not (b as BaseButton).disabled:
			if b is CheckButton:
				(b as CheckButton).button_pressed = not (b as CheckButton).button_pressed
			else:
				(b as BaseButton).pressed.emit()
			return
	_check(false, "a '%s' button on the %s tab" % [text, menu._tabs.get_current_tab_control().name])


## Presses `text` in the row labelled `row`.
func _press_in_row(menu: Node, row: String, text: String) -> void:
	var list: Node = menu._lists[String(menu._tabs.get_current_tab_control().name)]
	for label in list.find_children("*", "Label", true, false):
		if (label as Label).text == row:
			var r: Node = label.get_parent().get_parent()
			for b in r.find_children("*", "Button", true, false):
				if (b as Button).text == text:
					(b as Button).pressed.emit()
					return
	_check(false, "a '%s' button in the %s row" % [text, row])


## The chase camera and no act card, so shots show the car.
func _chase_camera() -> void:
	var rig := _main.get_node("LoFi/SubViewport/World/CameraRig")
	if rig.get("mode") != 0:
		rig.toggle_mode()
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.has_method("show_act"):
			layer.clear()


func _parts_for(slot: String) -> Array:
	var out: Array = []
	var catalogue := load("res://scripts/vehicle/parts_catalogue.gd")
	for part in catalogue.for_car(StringName(slot), _car.car_id):
		if not part.is_stock() and not part.found_only:
			out.append(part)
	return out


func _found_part() -> Resource:
	var catalogue := load("res://scripts/vehicle/parts_catalogue.gd")
	for part in catalogue.all():
		if part.found_only and part.slot == &"roof" and catalogue.fits(part, _car.car_id):
			return part
	return null


## The first workshop at least `far` metres away: [name, position].
func _far_place(far: float) -> Array:
	for node in get_nodes_in_group(&"workshop_spots"):
		if node.global_position.distance_to(_car.global_position) > far:
			return [String(node.get("display_name")), node.global_position]
	return []


func _auto(name: String) -> Node:
	return root.get_node(name)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _shot(name: String) -> void:
	if _shots == "":
		return
	root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
	print("saved ", name)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
	print(("ok   " if ok else "FAIL ") + what + "   (%.1f s)" % (Time.get_ticks_msec() / 1000.0))


func _finish() -> void:
	if _quitting:
		return
	Engine.time_scale = 1.0
	DirAccess.remove_absolute("user://dev_menu_test.cfg")
	for i in range(1, 4):
		DirAccess.remove_absolute("user://dev_menu_test_snapshot_%d.json" % i)
	for f in _failures:
		printerr("FAIL: ", f)
	print("DEV MENU TEST ", "PASSED" if _failures.is_empty() else "FAILED")
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
