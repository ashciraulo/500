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
var _pad: Node
var _pad_from := Vector3.ZERO
var _laps := 0
var _pad_done := false


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
		_drivetrain()
		_looks()
		_setups()
		_shelf()
	elif _frames == 70:
		_decor_shows()
		_records()
		_furniture()
		_pad = _main.find_child("Skidpad", true, false)
		_check(_pad != null, "there's a skidpad")
		if _pad == null:
			return _finish()
		_pad_from = _car.global_position
		_pad.lap_done.connect(func(_s: float, _g: float) -> void: _laps += 1)
		_pad.start(_car)
		_check(_car.global_position.distance_to(_pad.global_position) < 25.0, "the car is out on the skidpad")
		_check(root.get_node("SaveGame").hold, "and isn't saved out there")
		_car.player_controlled = false
	elif _frames > 70 and _laps == 0 and _frames < 70 + 60 * 45:
		_circle()
	elif _frames > 70 and not _pad_done:
		_pad_done = true
		_car.throttle_input = 0.0
		_check(_laps > 0, "a lap of the ring counts (%d)" % _laps)
		_check(_pad.last_g > 0.2 and _pad.last_g < 1.3, "with a believable sideways g (%.2f in %.1f s)" % [_pad.last_g, _pad.last_lap])
		_check(not _pad.best_for(String(_car.car_id)).is_empty(), "and it's the car's best")
		_pad.finish()
		_check(_car.global_position.distance_to(_pad_from) < 1.0, "finishing puts the car back at the carport")
		_check(not root.get_node("SaveGame").hold, "and saving carries on")
		_car.player_controlled = true
		return _finish()
	return false


## Drive round the skidpad ring at about 30 km/h.
func _circle() -> void:
	var flat: Vector3 = _car.global_position - _pad.global_position
	flat.y = 0.0
	var out := flat.normalized()
	var tangent := out.cross(Vector3.UP)
	var want := (tangent - out * (flat.length() - 17.0) * 0.25).normalized()
	var forward: Vector3 = -_car.global_basis.z
	forward.y = 0.0
	var turn := forward.normalized().signed_angle_to(want, Vector3.UP)
	_car.steer_input = clampf(turn * 2.5, -1.0, 1.0)
	if _frames % 30 == 0 and OS.get_environment("PAD_DEBUG") != "":
		print("pad r=%.1f y=%.1f v=%.1f turn=%.2f active=%s" % [flat.length(), _car.global_position.y - _pad.global_position.y, _car.linear_velocity.length(), turn, _pad.active])
	_car.throttle_input = clampf((8.5 - _car.linear_velocity.length()) * 0.4 + 0.2, 0.0, 1.0)


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


## The diff, flywheel and anti-roll bars change how the car drives.
func _drivetrain() -> void:
	var catalogue: Variant = load("res://scripts/vehicle/parts_catalogue.gd")
	for slot: String in ["diff", "flywheel", "anti_roll"]:
		_check(catalogue.get_part(StringName(slot + "_stock")) != null, "there's a stock %s" % slot)
	var lock: float = _car.diff_lock
	var revs: float = _car.free_rev_up
	var roll: float = _car.anti_roll_strength
	var shift: float = _car.shift_time
	# The inside wheel can only take 500 N; the outside one has 3000 N of grip.
	var inside := {"cap": 500.0, "driven": true}
	var outside := {"cap": 3000.0, "driven": true}
	var open_drive: float = _car._drive_share(2000.0, outside, inside)
	_check(_car._drive_share(2000.0, inside, outside) == 2000.0, "the inside wheel gets its half (and spins)")
	_car.install_part(catalogue.get_part(&"diff_lsd"))
	_check(_car.diff_lock > lock + 0.3, "the LSD locks the diff up (%.2f to %.2f)" % [lock, _car.diff_lock])
	var lsd_drive: float = _car._drive_share(2000.0, outside, inside)
	_check(lsd_drive > open_drive * 1.5, "out of a corner the LSD puts more down (%d N vs %d N open)" % [lsd_drive, open_drive])
	_car.install_part(catalogue.get_part(&"flywheel_light"))
	_check(_car.free_rev_up > revs * 1.5 and _car.shift_time < shift, "a light flywheel revs quicker and shifts sooner")
	_car.install_part(catalogue.get_part(&"anti_roll_sport"))
	_check(_car.anti_roll_strength > roll * 1.3, "sport anti-roll bars stiffen it up")
	var tuning: Variant = load("res://scripts/vehicle/car_tuning.gd")
	_check(tuning.is_available(tuning.option("diff_lock_add"), _car.get_part_ids()), "the LSD can be tuned")
	_check(not tuning.is_available(tuning.option("anti_roll_mult"), _car.get_part_ids()), "fixed bars can't be")
	_car.install_part(catalogue.get_part(&"anti_roll_adjustable"))
	_check(tuning.is_available(tuning.option("anti_roll_mult"), _car.get_part_ids()), "adjustable bars can")
	for slot: String in ["diff", "flywheel", "anti_roll"]:
		_car.remove_part(StringName(slot))
	_check(is_equal_approx(_car.diff_lock, lock) and is_equal_approx(_car.free_rev_up, revs)
		and is_equal_approx(_car.anti_roll_strength, roll), "stock comes back")


## Fog lamps light up yellow with the headlights, a custom plate goes on the
## Plate material, and the carb and big-bore kits show a finned sump.
func _looks() -> void:
	var catalogue: Variant = load("res://scripts/vehicle/parts_catalogue.gd")
	var body := _car.get_node("Body")
	var plate_mat: ShaderMaterial = body._materials.get("Plate")
	_check(plate_mat != null, "the car has a number plate")
	var stock_tex: Variant = plate_mat.get_shader_parameter("albedo_texture") if plate_mat else null
	_car.install_part(catalogue.get_part(&"plate_bream"))
	var tex: Texture2D = plate_mat.get_shader_parameter("albedo_texture") if plate_mat else null
	_check(tex != null and tex.resource_path.ends_with("plate_bream.png"), "a custom plate goes on")
	_car.remove_part(&"plate")
	_check(plate_mat != null and plate_mat.get_shader_parameter("albedo_texture") == stock_tex, "and comes off again")
	_car.install_part(catalogue.get_part(&"lights_fog"))
	var lamps := _car.find_child("Part_lights", true, false)
	_check(lamps != null and lamps.has_meta("fog_lens"), "fog lamps sit on the bumper")
	if lamps and lamps.has_meta("fog_lens"):
		var lens: ShaderMaterial = lamps.get_meta("fog_lens")
		var was: bool = _car.headlights_on
		_car.headlights_on = true
		_car._update_lights()
		_check(float(lens.get_shader_parameter("emission_energy")) > 0.5, "their lenses light with the headlights")
		_car.headlights_on = false
		_car._update_lights()
		_check(float(lens.get_shader_parameter("emission_energy")) == 0.0, "and go out with them")
		_car.headlights_on = was
		_car._update_lights()
	_car.remove_part(&"lights")
	for id: String in ["engine_carb_kit", "engine_big_bore"]:
		var kit: Resource = catalogue.get_part(StringName(id))
		_check(kit != null and kit.visual == "sump_finned" and catalogue.fits(kit, "classic_500f")
			and not catalogue.fits(kit, "pop_12"), "%s is a classic kit with a finned sump" % id)
	_check(ResourceLoader.exists("res://art/models/cars/parts/sump_finned.glb"), "the finned sump model is in")


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
	# Roof racks: none on open-topped cars; the rod lies where the rack says.
	var rack: CarPart = PartsCatalogue.get_part(&"roof_plain_rack")
	_check(rack != null and PartsCatalogue.fits(rack, "pop_12"), "a plain roof rack fits the Pop")
	_check(rack != null and not PartsCatalogue.fits(rack, "lounge_c_14") and not PartsCatalogue.fits(rack, "classic_jolly"),
		"but not the 500C or the Jolly")
	if rack and ResourceLoader.exists("res://art/models/cars/parts/roofrack_plain_modern.glb"):
		_car.install_part(rack)
		var fitted := _car.get_node("Body").get_node_or_null(^"Part_roof") as Node3D
		_check(fitted != null and fitted.scene_file_path.ends_with("roofrack_plain_modern.glb"), "the Pop gets the modern rack")
		_car.set_field_gear(PackedStringArray(["fishing_rod"]))
		var rack_rod := _car.get_node("Body").get_node_or_null(^"Gear_fishing_rod") as Node3D
		var rod_spot := fitted.find_child("Mount_Rod", true, false) as Node3D if fitted else null
		_check(rack_rod != null and rod_spot != null and rack_rod.global_position.distance_to(rod_spot.global_position) < 0.01,
			"the rod lies at the rack's Mount_Rod")
		_car.set_field_gear(PackedStringArray())
		_car.remove_part(&"roof")
	# Body and interior parts.
	for slot: StringName in PartsCatalogue.SLOTS:
		_check(PartsCatalogue.get_part(StringName(String(slot) + "_stock")) != null, "%s has a stock part" % slot)
	var lid_rack: CarPart = PartsCatalogue.get_part(&"rear_rack_classic")
	_check(PartsCatalogue.fits(lid_rack, "classic_500f") and not PartsCatalogue.fits(lid_rack, "pop_12")
		and not PartsCatalogue.fits(lid_rack, "classic_giardiniera"), "lid racks only on classics with an engine lid")
	_check(PartsCatalogue.fits(PartsCatalogue.get_part(&"bumpers_overriders"), "classic_nuova")
		and not PartsCatalogue.fits(PartsCatalogue.get_part(&"bumpers_overriders"), "pop_12")
		and PartsCatalogue.fits(PartsCatalogue.get_part(&"bumpers_nudge"), "pop_12"), "overriders for classics, nudge bars for moderns")
	_car.install_part(PartsCatalogue.get_part(&"mudflaps_rubber"))
	_check(is_equal_approx(_car.dirt_multiplier, 0.85), "mud flaps keep some dirt off")
	pop_body = _car.get_node("Body") as Node3D
	if ResourceLoader.exists("res://art/models/cars/parts/mudflap.glb"):
		_check(pop_body.get_node_or_null(^"Part_mudflaps") != null and pop_body.get_node_or_null(^"Part_mudflaps_2") != null, "a flap behind each rear wheel")
	_car.remove_part(&"mudflaps")
	_check(_car.dirt_multiplier == 1.0 and pop_body.get_node_or_null(^"Part_mudflaps") == null, "and off again")
	if ResourceLoader.exists("res://art/models/cars/parts/wheel_wood.glb"):
		_car.install_part(PartsCatalogue.get_part(&"steering_wheel_wood"))
		var stock_wheel := pop_body.find_child("SteeringWheel", true, false) as Node3D
		var wood := pop_body.get_node_or_null(^"Part_steering_wheel") as Node3D
		_check(wood != null and stock_wheel != null and not stock_wheel.visible, "the wooden wheel replaces the stock one")
		if wood:
			var rest := wood.basis
			_car.steer_angle = 0.3
			pop_body._process(0.016)
			_check(not wood.basis.is_equal_approx(rest), "and turns with the steering")
			_car.steer_angle = 0.0
		_car.remove_part(&"steering_wheel")
		_check(stock_wheel == null or stock_wheel.visible, "the stock wheel comes back")
	if ResourceLoader.exists("res://art/models/cars/parts/seatcover_sheepskin_modern.glb"):
		_car.install_part(PartsCatalogue.get_part(&"seat_covers_sheepskin"))
		var cover_r := pop_body.get_node_or_null(^"Part_seat_covers_2") as Node3D
		_check(pop_body.get_node_or_null(^"Part_seat_covers") != null and cover_r != null and cover_r.basis.determinant() < 0.0,
			"sheepskin on both seats, mirrored for the driver's")
		_car.remove_part(&"seat_covers")
	if ResourceLoader.exists("res://art/models/cars/parts/bumper_nudge.glb"):
		_car.install_part(PartsCatalogue.get_part(&"bumpers_nudge"))
		_check(pop_body.get_node_or_null(^"Part_bumpers") != null and pop_body.get_node_or_null(^"Part_bumpers_2") == null, "a nudge bar only goes on the front")
		_car.remove_part(&"bumpers")
	# Field journal rewards on the dash and the glovebox.
	var wagtail := Trinkets.build({"id": "trinket_dash_wagtail"})
	_check(wagtail.find_child("Bob", true, false) != null, "the dash wagtail nods")
	wagtail.free()
	var sticker := Trinkets.build({"id": "trinket_naturalist_sticker", "color": "#3d6b3a"})
	_check(sticker.find_children("*", "MeshInstance3D", true, false).size() == 1, "the club sticker is a sticker")
	sticker.free()
	_check(int(root.get_node("Progression").cosmetics.get("trinket_dash_wagtail", {}).get("species", 0)) == 10, "the wagtail comes at 10 species")
	# Spray shop: clear coats and liveries.
	var paint_mat: ShaderMaterial = _car.get_node("Body")._materials.get("Paint")
	var stock_rough: float = paint_mat.get_shader_parameter("roughness") if paint_mat else 0.0
	wallet.balance = maxi(wallet.balance, 5000)
	_check(garage.apply_finish(_car, "metallic") and _car.finish == "metallic", "a metallic coat at the spray shop")
	if paint_mat:
		_check(is_equal_approx(paint_mat.get_shader_parameter("metallic"), garage.FINISHES.metallic[4]), "and the paint shines like metal")
	_check(garage.paint_livery(_car, "rally_numbers", 2, 27) and _car.cosmetics.livery == "custom", "rally roundels painted on")
	if paint_mat:
		_check(paint_mat.get_shader_parameter("livery_mode") == 6 and paint_mat.get_shader_parameter("livery_number") == 27, "the roundels carry number 27")
	_check(String(_car.logbook[-1].text).contains("number 27"), "the service book notes the livery")
	var sprayed: Dictionary = _car.vehicle_state()
	_car.load_vehicle_state({"car_id": "pop_12"})
	_check(_car.finish == "" and _car.cosmetics.livery == "", "a state without them means the factory finish")
	if paint_mat:
		paint_mat = _car.get_node("Body")._materials.get("Paint")
		_check(is_equal_approx(paint_mat.get_shader_parameter("roughness"), stock_rough), "back to the model's own roughness")
	_car.load_vehicle_state(sprayed)
	_check(_car.finish == "metallic" and _car.custom_livery.get("number", 0) == 27, "coat and livery are saved with the car")
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


func _setups() -> void:
	var before: Dictionary = _car.tuning.duplicate()
	_car.set_tuning({"tyre_pressure": -0.5})
	_car.save_setup(1)
	_check(_car.has_setup(1) and not _car.has_setup(0), "a setup saves into its own slot")
	_car.set_tuning({})
	_check(_car.load_setup(1) and is_equal_approx(float(_car.tuning.get("tyre_pressure", 0.0)), -0.5),
		"using a saved setup brings its tuning back")
	_check(not _car.load_setup(0), "an empty slot changes nothing")
	var state: Dictionary = _car.vehicle_state()
	_car.setups = [{}, {}, {}]
	_car.load_vehicle_state(state)
	_check(_car.has_setup(1), "saved setups keep with the car")
	_car.setups = [{}, {}, {}]
	_car.set_tuning(before)


func _shelf() -> void:
	var garage := root.get_node("Garage")
	var shelf := _main.find_child("PartsShelf", true, false)
	_check(shelf != null and shelf.has_method("refresh"), "the carport has a parts shelf")
	if shelf == null:
		return
	var owned_before: PackedStringArray = garage.owned.duplicate()
	for id: String in ["wheels_alloy15", "gear_knob_wood", "roof_plain_rack"]:
		garage.owned.append("%s/%s" % [_car.car_id, id])
	shelf.refresh()
	var spares: Array = garage.spare_parts(_car)
	_check(spares.size() >= 3, "bought parts you haven't fitted are spares (%d)" % spares.size())
	_check(shelf.shown_count() == spares.size(), "the shelf shows each spare (%d)" % shelf.shown_count())
	var home := get_first_node_in_group(&"home_base") as Node3D
	var spot := home.find_child("CarportShelf", false, false) as Node3D if home else null
	_check(spot != null and spot.global_position.distance_to(home.spawn_transform(&"Spawn_Car").origin) < 3.5,
		"the shelf is in the carport by the car")
	_car.install_part(load("res://scripts/vehicle/parts_catalogue.gd").get_part(&"gear_knob_wood"))
	shelf.refresh()
	_check(shelf.shown_count() == spares.size() - 1, "a part leaves the shelf once it's fitted")
	_car.remove_part(&"gear_knob")
	garage.owned = owned_before
	shelf.refresh()


## Furniture ordered from the catalogue arrives the next morning.
func _furniture() -> void:
	var shop := _main.find_child("HomeFurniture", true, false)
	_check(shop != null and shop.spots.size() >= 10 and shop.items.size() >= 15, "there's a home catalogue")
	if shop == null:
		return
	var wallet := root.get_node("Wallet")
	wallet.balance = 1000
	_check(not shop.order("rug_jute", "Decor_Lamp_Lounge"), "a rug can't go where the lamp goes")
	_check(shop.order("rug_jute", "Decor_Rug_Lounge") and wallet.balance == 820, "ordering a rug takes the money")
	_check(not shop.owned.has("rug_jute"), "it isn't here yet")
	var home: Node3D = get_first_node_in_group(&"home_base")
	home.slept.emit(2)
	_check(shop.owned.has("rug_jute") and shop.placed.get("Decor_Rug_Lounge") == "rug_jute", "it arrives in the morning")
	_check(home.find_child("Furniture_Decor_Rug_Lounge", true, false) != null, "and it's down in the lounge")
	var old := home.find_child("Rug_Lounge", true, false) as Node3D
	_check(old == null or not old.visible, "in place of the old rug")
	_check(shop.place("rug_jute", "Decor_Rug_Bedroom") and not shop.placed.has("Decor_Rug_Lounge"), "it can move upstairs")
	_check(old == null or old.visible, "and the old rug comes back")
	_check(not shop.order("chair_eames_style", "Decor_Chair") or wallet.balance >= 0, "money is checked")
	wallet.balance = 10
	_check(not shop.order("lamp_arc", "Decor_Lamp_Lounge"), "you can't order what you can't afford")


## Songs heard on the radio go in the record crate, and play at home.
func _records() -> void:
	var crate := _main.find_child("Records", true, false)
	_check(crate != null, "there's a record crate")
	if crate == null:
		return
	_check(crate.records.size() >= 2, "it starts with the themes (%d)" % crate.records.size())
	var before: int = crate.records.size()
	crate.heard("cinquecento", "Spiaggia")
	crate.heard("cinquecento", "Spiaggia")
	crate.heard("nottefm", "Radio Cinquecento")
	_check(crate.records.size() == before + 1 and crate.has_record("mus_cinquecento_02"),
		"a song heard on the radio is added once (%d)" % crate.records.size())
	var home: Node3D = get_first_node_in_group(&"home_base")
	_check(home.find_child("Records_RecordPlayer", true, false) != null
		and home.find_child("Records_RecordCrate", true, false) != null, "the record player and crate are in the lounge")
	crate.play("mus_cinquecento_02")
	_check(crate.playing == "mus_cinquecento_02", "a record plays")
	crate.stop()
	_check(crate.playing == "", "and stops")
	var state: Dictionary = crate.save_state()
	_check(state.records.size() == crate.records.size(), "the crate is saved")


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
