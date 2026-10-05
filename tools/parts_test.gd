extends SceneTree
## Checks the parts you can see and the things that turn up at home: fitted
## wheels, exhaust, roof rack and spotlights show on the car at its Mount_*
## empties; parts you can't buy are out in the city, can't be fitted until
## you find them, and are yours once you do; the classics get their own
## wheels; field gear (rod, esky, binoculars) rides in and on the car; and
## what you've earned shows around the townhouse.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/parts_test.gd -- --no-save
##
## Exits with code 1 if any check fails.

var _quitting := false
var _main: Node
var _car: Node
var _failures: Array[String] = []
var _frames := 0


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		return false
	_frames += 1
	if _frames == 60:
		_parts_on_the_car()
		_found_parts()
	elif _frames == 62:
		_classic()
	elif _frames == 63:
		_field_gear()
	elif _frames == 64:
		_decor_earned()
	elif _frames == 70:
		_decor_shows()
		return _finish()
	return false


func _parts_on_the_car() -> void:
	var catalogue: Variant = load("res://scripts/vehicle/parts_catalogue.gd")
	var body := _car.get_node("Body") as Node3D
	for slot: String in ["roof", "lights"]:
		_check(catalogue.get_part(StringName(slot + "_stock")) != null, "there's a stock %s" % slot)
	var wheel_before := _wheel_path()
	_car.install_part(catalogue.get_part(&"wheels_alloy15"))
	_check(_wheel_path() != wheel_before and _wheel_path().contains("alloy15"),
		"alloys show on the car (%s)" % _wheel_path())
	_car.remove_part(&"wheels")
	_check(_wheel_path() == wheel_before, "stock wheels come back")
	for id: String in ["exhaust_twin", "roof_surf_rack", "lights_period_spots"]:
		var part: Resource = catalogue.get_part(StringName(id))
		_check(part != null, "%s exists" % id)
		if part == null:
			continue
		_car.install_part(part)
		var model := body.get_node_or_null(NodePath("Part_" + String(part.slot))) as Node3D
		_check(model != null, "%s shows on the car" % id)
		if model:
			_check(model.position.distance_to(Vector3.ZERO) > 0.2, "%s sits at its mount (%s)" % [id, model.position])
	_check(get_nodes_in_group(&"car_spotlights").size() == 2, "the spotlights have two lamps")
	_car.remove_part(&"roof")
	_check(body.get_node_or_null(^"Part_roof") == null or body.get_node(^"Part_roof").is_queued_for_deletion(),
		"taking the rack off takes it off the car")
	_car.remove_part(&"lights")
	_car.remove_part(&"exhaust")


func _found_parts() -> void:
	var catalogue: Variant = load("res://scripts/vehicle/parts_catalogue.gd")
	var garage := root.get_node("Garage")
	var nodes := get_nodes_in_group(&"found_parts")
	var entries: Array = load("res://scripts/world/found_part.gd").entries()
	_check(entries.size() >= 4, "there are parts you can't buy (%d)" % entries.size())
	_check(nodes.size() == entries.size(), "each one is out in the city (%d of %d)" % [nodes.size(), entries.size()])
	for e: Dictionary in entries:
		var part: Resource = catalogue.get_part(StringName(e.part))
		_check(part != null and part.found_only, "%s is found, not bought" % e.part)
	_check(catalogue.fits(catalogue.get_part(&"wheels_campagnolo"), "classic_nuova"), "classic wheels fit a classic")
	_check(not catalogue.fits(catalogue.get_part(&"wheels_campagnolo"), "pop_12"), "classic wheels don't fit the Pop")
	_check(not catalogue.fits(catalogue.get_part(&"wheels_alloy15"), "classic_nuova"), "modern alloys don't fit a classic")
	var rack: Resource = catalogue.get_part(&"roof_surf_rack")
	_check(not garage.owns(rack, _car), "the surf rack isn't yours yet")
	_check(not garage.buy(rack, _car), "and it can't be bought")
	var node: Node = null
	for n in nodes:
		if n.part_id == "roof_surf_rack":
			node = n
	_check(node != null, "the surf rack is somewhere")
	if node == null:
		return
	var before: float = root.get_node("Progression").get_stat("parts_found")
	node.take()
	_check(garage.owns(rack, _car), "found it, so it's yours")
	_check(root.get_node("Progression").get_stat("parts_found") == before + 1.0, "parts found goes up")
	_check(garage.buy_and_fit(rack, _car), "it fits in the workshop")
	_check(_car.get_part_ids().has("roof_surf_rack"), "it's on the car")
	_car.remove_part(&"roof")


func _classic() -> void:
	_check(not _car.has_folding_roof() and not _car.toggle_roof(), "the Pop's roof doesn't fold")
	var pop_size: Vector3 = _car.body_size
	_car.load_vehicle_state({"car_id": "classic_nuova"})
	_check(_car.car_id == "classic_nuova", "switched to the Nuova")
	_check(_car.body_size.y < pop_size.y, "the Nuova is lower than the Pop (%s vs %s)" % [_car.body_size, pop_size])
	_check(_wheel_path().contains("classic"), "it has its own wheels (%s)" % _wheel_path())
	var catalogue: Variant = load("res://scripts/vehicle/parts_catalogue.gd")
	_car.install_part(catalogue.get_part(&"wheels_abarth_classic"))
	_check(_wheel_path().contains("abarth_classic"), "Abarth wheels show on the Nuova (%s)" % _wheel_path())
	_car.install_part(catalogue.get_part(&"exhaust_abarth_classic"))
	_check(_car.get_node("Body").get_node_or_null(^"Part_exhaust") != null, "the Abarth tailpipe shows on the Nuova")
	if _car.has_folding_roof():  # Once the models carry Roof_Open / Roof_Closed.
		var open_roof := _car.get_node("Body").find_child("Roof_Open", true, false) as Node3D
		_check(not open_roof.visible, "the Nuova's canvas starts closed")
		_check(_car.toggle_roof() and open_roof.visible, "and rolls back")
		var state: Dictionary = _car.vehicle_state()
		_check(state.get("roof_open", false), "an open roof is saved")
		_car.toggle_roof()
		_car.load_vehicle_state(state)
		_check(_car.roof_open and open_roof.visible, "and comes back open")
	_car.load_vehicle_state({"car_id": "pop_12"})


func _field_gear() -> void:
	var body := _car.get_node("Body") as Node3D
	var all := PackedStringArray(["fishing_rod", "esky", "tackle_box", "binoculars", "camera", "kayak"])
	_car.set_field_gear(all)
	_check(not _car.has_field_gear("kayak"), "unknown gear is skipped")
	for id: String in ["esky", "tackle_box", "binoculars", "camera"]:
		var model := body.get_node_or_null(NodePath("Gear_" + id)) as Node3D
		_check(model != null, "%s in the Pop" % id.replace("_", " "))
		if model:
			_check(model.position.y > 0.2 and model.position.y < 1.0, "on a seat, not on the road or roof (%s)" % model.position)
	_check(body.get_node_or_null(^"Gear_fishing_rod") == null, "no rack, so the rod's in the boot")
	_car.install_part(load("res://scripts/vehicle/parts_catalogue.gd").get_part(&"roof_surf_rack"))
	var rod := body.get_node_or_null(^"Gear_fishing_rod") as Node3D
	_check(rod != null and rod.position.y > 1.3, "with a rack the rod rides on the roof")
	var saved: Dictionary = _car.save_state()
	_car.set_field_gear(PackedStringArray())
	_check(body.get_children().filter(func(n: Node) -> bool:
		return n.name.begins_with("Gear_") and not n.is_queued_for_deletion()).is_empty(), "gear comes out")
	_car.load_state(saved)
	_check(_car.has_field_gear("esky") and _car.get_node("Body").get_node_or_null(^"Gear_esky") != null, "gear is saved")
	_car.load_vehicle_state({"car_id": "classic_nuova"})
	_check(_car.get_node("Body").get_node_or_null(^"Gear_esky") != null, "the gear moves to the next car")
	_car.set_field_gear(PackedStringArray())
	_car.load_vehicle_state({"car_id": "pop_12"})
	_car.remove_part(&"roof")
	# Parked, from the driver's seat.
	_check(_car.is_parked_for_viewing(), "stopped in the carport counts as parked")
	var eye: Transform3D = _car.driver_eye()
	_check(eye.origin.distance_to(_car.global_position) < 1.5 and eye.origin.y > _car.global_position.y,
		"the driver's eye is in the car")
	# Dashboard needles: the Pop's own, or stand-ins on a body without them.
	var pop_body := _car.get_node("Body") as Node3D
	var added: Array[Node3D] = []
	for needle_name: String in ["Needle_Rev_7", "Needle_Speed_200"]:
		if pop_body.find_child(needle_name, true, false) == null:
			var stand_in := Node3D.new()
			stand_in.name = needle_name
			pop_body.add_child(stand_in)
			added.append(stand_in)
	var rev := pop_body.find_child("Needle_Rev_7", true, false) as Node3D
	var speedo := pop_body.find_child("Needle_Speed_200", true, false) as Node3D
	var rev_rest := rev.basis
	var speedo_rest := speedo.basis
	_car._needles_body = null  # Pick up any stand-ins.
	_car.rpm = 3500.0
	for i in 30:
		_car._update_needles(0.1)
	var rev_angle := rad_to_deg((rev_rest.inverse() * rev.basis).get_euler().y)
	_check(absf(rev_angle + 120.0) < 2.0, "the rev needle points straight up at 3,500 rpm (%.0f deg)" % rev_angle)
	_check(speedo.basis.is_equal_approx(speedo_rest), "the speedo rests on zero when parked")
	var odo_window := pop_body.find_child("Odometer_*", true, false) as Node3D
	if odo_window == null:
		odo_window = Node3D.new()
		odo_window.name = "Odometer_7"
		pop_body.add_child(odo_window)
		added.append(odo_window)
		_car._needles_body = null
	var km_before: float = _car.odometer_km
	_car.odometer_km = 1234.6
	_car._update_needles(0.1)
	var digits := odo_window.get_node_or_null(^"Digits") as Label3D
	_check(digits != null and digits.text == "001234", "the odometer shows the distance (%s)" % (digits.text if digits else "none"))
	_car.odometer_km = km_before
	for stand_in in added:
		stand_in.free()
	_car._needles_body = null
	# Wear and servicing.
	var garage := root.get_node("Garage")
	var wallet := root.get_node("Wallet")
	var due: Array[String] = []
	_car.service_due.connect(func(item: String) -> void: due.append(item))
	_car._add_wear("tyres", 400.0)
	_check(_car.wear.tyres > 0.85 and due.has("tyres"), "tyres wear with distance and say when they're due")
	_check(_car.tyre_grip_factor() < 0.9, "worn tyres grip less (%.2f)" % _car.tyre_grip_factor())
	_car._add_wear("oil", 300.0)
	_check(_car.oil_factor() < 0.95, "old oil takes the edge off (%.2f)" % _car.oil_factor())
	var wear_state: Dictionary = _car.vehicle_state()
	_car.load_vehicle_state({"car_id": _car.car_id})
	_check(_car.wear.tyres == 0.0, "a state without wear means fresh")
	_car.load_vehicle_state(wear_state)
	_check(_car.wear.tyres > 0.85, "wear is saved with the car")
	wallet.balance = maxi(wallet.balance, 1000)
	var money_before: int = wallet.balance
	var hour_before: float = root.get_node("GameClock").time_of_day
	_check(garage.service(_car, "tyres") and _car.wear.tyres == 0.0, "new tyres at the carport")
	_check(wallet.balance == money_before - garage.SERVICES.tyres[1], "and they cost money")
	_check(not is_equal_approx(root.get_node("GameClock").time_of_day, hour_before), "and take a while")
	_check(not garage.service(_car, "tyres"), "nothing to do on new tyres")
	_check(not _car.logbook.is_empty() and String(_car.logbook[-1].text).contains("tyres"), "the service book says so")
	_check(_car.vehicle_state().logbook.size() == _car.logbook.size(), "the service book is saved")
	_car._add_wear("brakes", 300.0)
	_car.load_vehicle_state({"car_id": "classic_nuova"})
	_check(_car.wear.brakes == 0.0, "another car has its own wear")
	_car.load_vehicle_state({"car_id": "pop_12"})
	root.get_node("GameClock").set_time(10.0)
	# The time of day, for birds.
	var clock := root.get_node("GameClock")
	var phases := {}
	for hour in [2.0, 5.8, 12.0, 17.8, 22.0]:
		clock.set_time(hour)
		phases[hour] = clock.sun_phase()
	_check(phases[2.0] == &"night" and phases[5.8] == &"dawn" and phases[12.0] == &"day"
		and phases[17.8] == &"dusk" and phases[22.0] == &"night", "dawn, day, dusk and night (%s)" % phases)
	clock.set_time(10.0)
	# Journal stats come from the field journal when it's there.
	var progression := root.get_node("Progression")
	if root.get_node_or_null(^"FieldJournal") == null:
		var stub := Node.new()
		var script := GDScript.new()
		script.source_code = "extends Node\nfunc stat(name: String) -> float:\n\treturn 7.0 if name == \"species_photographed\" else 0.0\n"
		script.reload()
		stub.set_script(script)
		stub.name = "FieldJournal"
		root.add_child(stub)
		_check(progression.get_stat("species_photographed") == 7.0, "career reads species photographed from the journal")
		root.remove_child(stub)
		stub.free()


func _decor_earned() -> void:
	var progression := root.get_node("Progression")
	if not progression.rewards.has("garage_road_map"):
		progression.rewards.append("garage_road_map")
	if not progression.rewards.has("garage_neon_sign"):
		progression.rewards.append("garage_neon_sign")
	root.get_node("Classics").find_wreck("classic_500l")
	var decor := _main.find_child("HomeDecor", true, false)
	_check(decor != null, "the townhouse decorates itself")
	if decor:
		decor.refresh()


func _decor_shows() -> void:
	var home := get_first_node_in_group(&"home_base") as Node3D
	_check(home != null, "the townhouse is there")
	if home == null:
		return
	for empty_name: String in ["Deco_RoadMap", "Deco_NeonSign", "Corkboard_Pin_1"]:
		var empty := home.find_child(empty_name, true, false)
		_check(empty != null, "the home has %s" % empty_name)
		if empty:
			_check(empty.get_node_or_null(^"Decor") != null, "something's at %s" % empty_name)
	var pin_2 := home.find_child("Corkboard_Pin_2", true, false)
	_check(pin_2 == null or pin_2.get_node_or_null(^"Decor") == null, "one classic found, one card")


func _wheel_path() -> String:
	var wheel := _car.find_child("Wheel", true, false)
	return wheel.scene_file_path if wheel else ""


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	print("PARTS ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Takes the game down before quitting (a plain quit() crashed on exit on Windows).
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
	return false
