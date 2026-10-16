extends SceneTree
## The workshop at home with the car in view: the Parts, Tuning and Paint tabs
## for the Pop and the Valiant, the Alfa with its Simmons wheels, sport
## exhaust and bead covers on, and out in the lane in the sun, a set of wheels going on, a respray and a
## night shot under the carport. Fails (exit 1) if the car view doesn't take
## over on those tabs or doesn't hand the camera back.
##
##   xvfb-run godot --path . --resolution 1280x720 --fixed-fps 60 \
##       --script res://tools/workshop_screens.gd -- --no-save shots=/tmp/workshop

var _shots := "user://workshop"
var _main: Node
var _world: Node
var _car  # CarController
var _shop  # Workshop
var _spot  # WorkshopSpot
var _steps: Array = []
var _step := -1
var _frames := 0
var _failed := 0
var _cam: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
	DirAccess.make_dir_recursive_absolute(_shots)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed += 1


func _tab(kind: String) -> void:
	(_shop.get("_tabs") as TabContainer).current_tab = _shop.TAB_KINDS.find(kind)


func _view() -> Node:
	return _shop.get("_car_view")


func _viewing() -> bool:
	var view := _view()
	return view != null and view.is_active()


## Hover the parts row for `slot`'s first button (what a player does to browse it).
func _browse(slot: String) -> void:
	var list: Node = _shop.get("_parts_list")
	for b in list.find_children("*", "Button", true, false):
		if b.get_meta(&"slot", &"") == StringName(slot):
			(b as Button).grab_focus()
			return


## A mouse drag across the car (press, move, let go).
func _drag(from: Vector2, by: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	Input.parse_input_event(press)
	for i in 10:
		var move := InputEventMouseMotion.new()
		move.position = from + by * (i + 1) / 10.0
		move.relative = by / 10.0
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(move)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = from + by
	Input.parse_input_event(release)


func _fit(id: String) -> void:
	var list: Node = _shop.get("_parts_list")
	var part = PartsCatalogue.get_part(StringName(id))
	_check(part != null, "%s is a part" % id)
	_shop.call("_fit", part)


func _build_steps() -> void:
	var rig_camera := _world.get_node("CameraRig/Camera3D") as Camera3D
	# [name, call at the start, frames to wait, shoot]
	_steps.append(["ws_00_carport", func() -> void: pass, 30, true])
	_steps.append(["ws_01_pop_parts", func() -> void:
		_shop.open(_spot)
		_tab("parts"), 90, true])
	_steps.append(["ws_02_pop_parts_wheels", func() -> void:
		_check(_viewing(), "the car view is up on Parts")
		_browse("wheels"), 90, true])
	_steps.append(["ws_03_pop_wheels_fitted", func() -> void:
		_fit("wheels_alloy15")
		_browse("wheels"), 60, true])
	_steps.append(["ws_04_pop_parts_exhaust", func() -> void:
		_browse("exhaust"), 90, true])
	_steps.append(["ws_05_pop_tuning", func() -> void:
		_tab("tuning"), 90, true])
	_steps.append(["ws_06_pop_service", func() -> void:
		_tab("service"), 30, true])
	_steps.append(["ws_06b_service_check", func() -> void:
		_check(not _viewing(), "no car view on Service")
		_check(rig_camera.current, "the driving camera is back on Service"), 1, false])
	_steps.append(["ws_07_pop_closed", func() -> void:
		_tab("parts")
		_shop.close(), 30, true])
	_steps.append(["ws_07b_closed_check", func() -> void:
		_check(not _viewing(), "the car view goes when the workshop closes")
		_check(rig_camera.current, "and the driving camera has the view again"), 1, false])
	_steps.append(["ws_08_pop_night", func() -> void:
		root.get_node("GameClock").set_time(22.0)
		_shop.open(_spot)
		_tab("parts"), 120, true])
	_steps.append(["ws_09_valiant_parts", func() -> void:
		_shop.close()
		root.get_node("GameClock").set_time(10.5)
		root.get_node("Garage").add_car("valiant_vc")
		_check(root.get_node("Garage").switch_car("valiant_vc", _car), "switched to the Valiant"), 60, true])
	_steps.append(["ws_10_valiant_parts", func() -> void:
		_shop.open(_spot)
		_tab("parts"), 120, true])
	_steps.append(["ws_11_valiant_tyres", func() -> void:
		_browse("tyres"), 90, true])
	_steps.append(["ws_11b_valiant_dragged", func() -> void:
		_browse("engine")
		_drag(Vector2(300, 360), Vector2(-260, 30)), 90, true])
	_steps.append(["ws_12_valiant_tuning", func() -> void:
		_tab("tuning"), 90, true])
	_steps.append(["ws_13_valiant_paint", func() -> void:
		_shop.call("_respray", 2)
		_tab("parts"), 90, true])
	_steps.append(["ws_14_alfa_carport", func() -> void:
		_shop.close()
		root.get_node("Garage").add_car("alfa_75_v6")
		_check(root.get_node("Garage").switch_car("alfa_75_v6", _car), "switched to the Alfa"), 90, true])
	_steps.append(["ws_15_alfa_parts", func() -> void:
		_shop.open(_spot)
		_tab("parts"), 120, true])
	_steps.append(["ws_16_alfa_wheels", func() -> void:
		_check(_viewing(), "the car view is up for the Alfa")
		_browse("wheels"), 90, true])
	_steps.append(["ws_17_alfa_simmons", func() -> void:
		_fit("wheels_a75_simmons")
		_browse("wheels"), 60, true])
	_steps.append(["ws_18_alfa_exhaust", func() -> void:
		_fit("exhaust_a75_sport")
		_browse("exhaust"), 90, true])
	_steps.append(["ws_19_alfa_seats", func() -> void:
		_fit("seat_covers_a75_beads")
		_browse("seat_covers"), 90, true])
	_steps.append(["ws_20_alfa_cockpit", func() -> void:
		_shop.close()
		_world.get_node("CameraRig").toggle_mode(), 60, true])
	_steps.append(["ws_21_alfa_lane_front", func() -> void:
		# Out in the lane in the sun, where its paint can be judged.
		_world.get_node("CameraRig").toggle_mode()
		var home: Node3D = get_first_node_in_group(&"home_base")
		var h79: GDScript = load("res://scripts/world/late_city/house_1979.gd")
		var at: Vector3 = home.to_global(h79.at(Vector3(15.0, -6.6, 0.0))) + Vector3.UP * 0.8
		_car.teleport(Transform3D(home.global_basis * Basis(Vector3.UP, PI * 0.5), at))
		root.get_node("GameClock").set_time(11.0), 90, false])
	_steps.append(["ws_22_alfa_sun_front", func() -> void:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_world.add_child(_cam)
		var b: Basis = _car.global_basis
		_cam.current = true
		_cam.global_position = _car.global_position - b.z * 5.5 + b.x * 2.6 + Vector3.UP * 1.0
		_cam.look_at(_car.global_position + Vector3.UP * 0.5), 20, true])
	_steps.append(["ws_23_alfa_sun_back", func() -> void:
		var b: Basis = _car.global_basis
		_cam.global_position = _car.global_position + b.z * 5.5 - b.x * 2.6 + Vector3.UP * 1.0
		_cam.look_at(_car.global_position + Vector3.UP * 0.5), 20, true])


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		_shop = _main.get_node("Workshop")
		root.get_node("GameClock").set_locked(true)
		root.get_node("GameClock").set_time(10.5)
		root.get_node("Weather").set_locked(true)
		root.get_node("Wallet").earn(50000, "test")
		_frames = -300
		return false
	_frames += 1
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			var first: Node = _main.find_child("FirstDay", true, false)
			if first:
				first.load_state({"step": 4})
			root.get_node("Notices").clear()
			for spot in get_nodes_in_group(&"workshop_spots"):
				if spot.offers("parts") and (_spot == null
						or spot.global_position.distance_to(_car.global_position)
						< _spot.global_position.distance_to(_car.global_position)):
					_spot = spot
			if _spot == null:
				_check(false, "there's a workshop")
				quit(1)
				return true
			print("workshop: %s, %.1f m from the car" % [_spot.display_name, _spot.global_position.distance_to(_car.global_position)])
			_build_steps()
			_next()
		return false
	if _step >= _steps.size():
		print("workshop: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
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
	# The story's act card would sit over the car in the close-ups.
	for card in _main.find_children("*", "CanvasLayer", true, false):
		if card.has_method("show_act"):
			card.clear()
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()
