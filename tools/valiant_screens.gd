extends SceneTree
## The Valiant, from the story to the driveway: not on the car yard's lot
## before the 1979 lane, on it after, Gaz's call the next morning, "Just in"
## at the car yard, buying it, and then driving it (outside, in the seat,
## pulling away, at night). Photographed; fails (exit 1) if a step doesn't
## tick off.
##
##   godot --path . --resolution 1280x720 --script res://tools/valiant_screens.gd \
##       -- --no-save shots=/tmp/valiant

const ID := "valiant_vc"

var _shots := "user://valiant"
var _main: Node
var _world: Node
var _car  # CarController
var _player  # OnFoot
var _home  # HomeBase
var _shop  # Workshop
var _cam: Camera3D
var _H79: GDScript
var _steps: Array = []
var _step := -1
var _frames := 0
var _failed := 0
var _driving := false
var _top_kmh := 0.0
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


func _look(from: Vector3, to: Vector3) -> void:
	_cam.current = true
	_cam.global_position = from
	_cam.look_at(to)


func _rig() -> Node:
	return _world.get_node("CameraRig")


func _drive_view() -> void:
	(_world.get_node("CameraRig/Camera3D") as Camera3D).current = true


func _hold(action: StringName, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func _dealer() -> Node:
	for spot in get_nodes_in_group(&"workshop_spots"):
		if spot.offers("dealer"):
			return spot
	return null


## The car yard's screen, on its cars tab.
func _open_yard() -> void:
	_shop.open(_dealer())
	var tabs: TabContainer = _shop.get("_tabs")
	tabs.current_tab = _shop.TAB_KINDS.find("cars")


## The text of every label on the cars tab.
func _yard_text() -> String:
	var out := ""
	for l in (_shop.get("_cars_list") as Node).find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out


func _engine_set() -> String:
	for n in _car.find_children("*", "", true, false):
		if "engine_set" in n:
			return String(n.get("engine_set"))
	return ""


func _build_steps() -> void:
	# [name, call at the start, frames to wait, shoot]
	_steps.append(["vd_00_start", func() -> void:
		# Long after the first day (the opening keeps the machine's cards quiet).
		var first: Node = _main.find_child("FirstDay", true, false)
		if first:
			first.load_state({"step": 4})
		_check(CarCatalogue.rare().size() == 1, "one rare car in the list")
		_check(not CarCatalogue.on_the_lot(CarCatalogue.get_car(ID)), "not on the lot before the story shows it")
		_check(root.get_node("Garage").car_blocker(ID) == "not on the lot", "can't be bought yet (%s)" % root.get_node("Garage").car_blocker(ID)), 60, false])
	_steps.append(["vd_01_yard_before", func() -> void:
		_open_yard(), 20, true])
	_steps.append(["vd_01b_yard_before_end", func() -> void:
		var scroll := (_shop.get("_cars_list") as Node).get_parent() as ScrollContainer
		if scroll:
			scroll.scroll_vertical = 100000
		_check(not _yard_text().contains("Valiant"), "the car yard doesn't list it"), 20, true])
	_steps.append(["vd_02_night", func() -> void:
		_shop.close()
		_drive_view()
		root.get_node("GameClock").set_time(1.0)
		_main.find_child("StoryPeople", true, false).card_act = 5
		_player.call("get_out"), 200, false])
	_steps.append(["vd_03_lane_1979", func() -> void:
		var looking: Node = _main.find_child("LookingOut", true, false)
		looking.force = true
		_check(looking.begin(&"1979"), "the 1979 lane starts")
		_look(_h(3.5, 2.4, 1.65), _h(3.3, -9.0, 1.0)), 90, true])
	_steps.append(["vd_03b_lane_1979_valiant", func() -> void:
		_look(_h(5.0, -2.2, 2.2), _h(9.4, -5.6, 0.6))
		_check(root.get_node("Discoveries").has("oddity/looking_out_1979"), "the lane's been seen")
		_check(CarCatalogue.on_the_lot(CarCatalogue.get_car(ID)), "and now it's on the lot")
		_check(not root.get_node("Story").has_message(&"yard_valiant"), "no call in the middle of the night"), 30, true])
	_steps.append(["vd_04_morning", func() -> void:
		var looking: Node = _main.find_child("LookingOut", true, false)
		looking.force = false
		looking.let_go()
		_drive_view()
		root.get_node("Notices").clear()
		root.get_node("GameClock").set_time(9.5), 60, true])
	_steps.append(["vd_04b_call", func() -> void:
		_check(root.get_node("Story").has_message(&"yard_valiant"), "Gaz rang in the morning")
		_check(_seen.has("info: A new message on the answering machine at home."), "and a card says so %s" % [_seen])
		var left: Variant = root.get_node("Story").message(&"yard_valiant")
		print("message: ", left)
		var machine: Node3D = _home.find_child("AnsweringMachine", false, false)
		(_player.get("_camera") as Camera3D).current = true
		if machine:
			_player.call("teleport", _h(3.4, 8.0, 0.15), machine.global_position), 60, false])
	_steps.append(["vd_04c_play_it", func() -> void:
		var machine: Node = _home.find_child("AnsweringMachine", false, false)
		_check(_player.call("_nearest_thing") == machine, "the machine is what you'd use")
		_hold(&"interact", true)
		_hold(&"interact", false), 240, true])
	_steps.append(["vd_04d_heard", func() -> void:
		_check(root.get_node("Story").heard(&"yard_valiant"), "the call's heard"), 10, false])
	_steps.append(["vd_05_just_in", func() -> void:
		_check(root.get_node("Garage").car_blocker(ID) == "can't afford it yet", "on the lot, needs the money (%s)" % root.get_node("Garage").car_blocker(ID))
		_open_yard(), 20, false])
	_steps.append(["vd_05b_just_in", func() -> void:
		var scroll := (_shop.get("_cars_list") as Node).get_parent() as ScrollContainer
		if scroll:
			scroll.scroll_vertical = 100000
		_check(_yard_text().contains("Just in"), "the car yard has a Just in list")
		_check(_yard_text().contains("Valiant VC (1966-1967)"), "with the Valiant on it"), 20, true])
	_steps.append(["vd_06_can_buy", func() -> void:
		_shop.close()
		root.get_node("Wallet").earn(12000, "test")
		_check(root.get_node("Garage").car_blocker(ID) == "", "with the money it's for sale, whatever the tier")
		_open_yard(), 20, false])
	_steps.append(["vd_06b_can_buy", func() -> void:
		var scroll := (_shop.get("_cars_list") as Node).get_parent() as ScrollContainer
		if scroll:
			scroll.scroll_vertical = 100000, 20, true])
	_steps.append(["vd_07_bought", func() -> void:
		var bought := false
		for b in (_shop.get("_cars_list") as Node).find_children("*", "Button", true, false):
			var row := (b as Node).get_parent()
			var words := ""
			for l in row.find_children("*", "Label", true, false):
				words += (l as Label).text
			if words.contains("Valiant") and (b as Button).text == "Buy it":
				(b as Button).pressed.emit()
				bought = true
		_check(bought, "pressed Buy it"), 30, true])
	_steps.append(["vd_08_home_day", func() -> void:
		_shop.close()
		_check(_car.car_id == ID, "driving the Valiant (%s)" % _car.car_id)
		_check(root.get_node("Garage").owns_car(ID), "and it's yours")
		_check(root.get_node("Story").has_message(&"yard_valiant"), "Gaz's call stays left once")
		_check(String(_car.get("wheel_style")) == "vc" if "wheel_style" in _car else true, "its own wheels")
		_check(absf(float(_car.wheel_radius) - 0.305) < 0.03, "wheel radius %.3f" % _car.wheel_radius)
		_check(_engine_set() == "slant6", "the slant six (%s)" % _engine_set())
		var seat := _car.get_node_or_null("DriverSeat") as Node3D
		_check(seat != null and _car.has_meta(&"seat_rest") and seat.position != _car.get_meta(&"seat_rest"), "the seat's under the model's eye (%s)" % [seat.position if seat else null])
		root.get_node("GameClock").set_time(13.0)
		_player.call("get_in"), 240, false])
	_steps.append(["vd_08b_chase", func() -> void:
		_check(bool(_player.get("in_car")), "back in the car")
		_drive_view(), 60, true])
	_steps.append(["vd_09_side", func() -> void:
		var b: Basis = _car.global_basis
		_look(_car.global_position + b.x * 5.5 - b.z * 1.0 + Vector3.UP * 0.9, _car.global_position + Vector3.UP * 0.4), 20, true])
	_steps.append(["vd_09b_front", func() -> void:
		var b: Basis = _car.global_basis
		_look(_car.global_position - b.z * 6.0 + b.x * 2.5 + Vector3.UP * 1.2, _car.global_position + Vector3.UP * 0.4), 20, true])
	_steps.append(["vd_09c_back", func() -> void:
		var b: Basis = _car.global_basis
		_look(_car.global_position + b.z * 6.0 - b.x * 2.5 + Vector3.UP * 1.2, _car.global_position + Vector3.UP * 0.4), 20, true])
	_steps.append(["vd_10_cockpit", func() -> void:
		_drive_view()
		_rig().toggle_mode(), 60, true])
	_steps.append(["vd_10b_in_the_lane", func() -> void:
		# Out of the carport and along the lane, where the 1979 one parks.
		var at := _h(15.0, -6.6, 0.0) + Vector3.UP * 0.8
		_car.teleport(Transform3D(_home.global_basis * Basis(Vector3.UP, PI * 0.5), at)), 90, true])
	_steps.append(["vd_11_pulling_away", func() -> void:
		_driving = true
		_hold(&"accelerate", true), 100, true])
	_steps.append(["vd_11b_chase_moving", func() -> void:
		print("top speed %.1f km/h" % _top_kmh)
		_check(_top_kmh > 15.0, "it pulls away (%.0f km/h)" % _top_kmh)
		_rig().toggle_mode(), 20, true])
	_steps.append(["vd_12_night", func() -> void:
		_hold(&"accelerate", false)
		_driving = false
		_hold(&"brake", true)
		root.get_node("GameClock").set_time(21.5), 150, false])
	_steps.append(["vd_12b_night", func() -> void:
		_hold(&"brake", false)
		_check(_car.headlights_on, "headlights on at night"), 60, true])
	_steps.append(["vd_12c_night_front", func() -> void:
		var b: Basis = _car.global_basis
		_look(_car.global_position - b.z * 7.0 + b.x * 2.0 + Vector3.UP * 1.3, _car.global_position + Vector3.UP * 0.5), 20, true])
	_steps.append(["vd_13_saved", func() -> void:
		var saved: Dictionary = _car.vehicle_state()
		_check(String(saved.get("car_id", "")) == ID, "the car saves as the Valiant")
		var garage: Dictionary = root.get_node("Garage").save_state()
		_check(Array(garage.get("owned_cars", [])).has(ID), "and as owned"), 5, false])


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		_H79 = load("res://scripts/world/late_city/house_1979.gd")
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		_player = _world.get_node_or_null("Player")
		_shop = _main.get_node("Workshop")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_frames = -240
		return false
	_frames += 1
	if _driving:
		_top_kmh = maxf(_top_kmh, _car.speed_kmh())
	var shown: Dictionary = root.get_node("Notices").showing()
	if not shown.is_empty():
		var line := "%s: %s" % [shown.kind, shown.text]
		if not _seen.has(line):
			_seen.append(line)
			print("card ", line)
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			_home = get_first_node_in_group(&"home_base")
			if _home == null or _dealer() == null:
				_check(false, "the home and the car yard are in the world")
				quit(1)
				return true
			_cam = Camera3D.new()
			_cam.fov = 60.0
			_world.add_child(_cam)
			_build_steps()
			_next()
		return false
	if _step >= _steps.size():
		print("valiant: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
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
