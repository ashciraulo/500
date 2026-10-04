extends SceneTree
## Checks the parts you can see and the things that turn up at home: fitted
## wheels, exhaust, roof rack and spotlights show on the car at its Mount_*
## empties; parts you can't buy are out in the city, can't be fitted until
## you find them, and are yours once you do; the classics get their own
## wheels; and what you've earned shows around the townhouse.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/parts_test.gd -- --no-save
##
## Exits with code 1 if any check fails.

var _main: Node
var _car: Node
var _failures: Array[String] = []
var _frames := 0


func _process(_delta: float) -> bool:
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
	_car.load_vehicle_state({"car_id": "pop_12"})


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
	quit(1 if _failures.size() else 0)
	return true
