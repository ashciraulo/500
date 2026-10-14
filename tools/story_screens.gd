extends SceneTree
## Screenshots of the late-city events (STORY.md) for reviewing how they look:
## the other house (1979 behind your own front door) and the empty road on
## May Drive. Needs a display (or xvfb):
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/story_screens.gd -- --no-save shots=/tmp/story [only=house,road,people,empty,turns,robyn,tape,out,drive,street]

var _shots := "/tmp/story"
var _only := PackedStringArray()
var _main: Node
var _world: Node3D
var _car  # CarController
var _player: Node3D
var _home  # HomeBase
var _other  # OtherHouse
var _road  # EmptyRoad
## The late-city scripts, loaded once the autoloads they use are up (naming
## their classes here would compile them before that and log errors).
var _H79: GDScript
var _ER: GDScript
var _HA: GDScript
var _RS: GDScript
var _cam: Camera3D
var _route := PackedVector3Array()
var _door_x := 1.0
var _step := -1
var _frames := 0
var _steps: Array = []
var _creep := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=").split(",")
	DirAccess.make_dir_recursive_absolute(_shots)


func _want(what: String) -> bool:
	return _only.is_empty() or _only.has(what)


## The house's own frame (x across, y back from the street, z up) to world.
func _h(x: float, y: float, z: float) -> Vector3:
	return _home.to_global(_H79.at(Vector3(x, y, z)))


func _build_steps() -> void:
	if _want("house"):
		_house_steps()
	if _want("road"):
		_road_steps()
	if _want("people"):
		_people_steps()
	if _want("empty"):
		_empty_steps()
	if _want("turns"):
		_turns_steps()
	if _want("robyn"):
		_robyn_steps()
	if _want("tape"):
		_tape_steps()
	if _want("out"):
		_out_steps()
	if _want("drive"):
		_drive_steps()
	if _want("street"):
		_street_steps()


func _house_steps() -> void:
	var street := func() -> void: _look(_h(_door_x + 0.6, -9.0, 1.7), _h(_door_x + 0.8, 3.0, 2.2))
	var back := func() -> void: _look(_h(1.6, 15.2, 1.6), _h(2.2, 8.5, 1.1))
	_steps.append(["house_0_setup", func() -> void:
		_hour(1.0)
		_player.call("get_out"), 200, null, false])
	_steps.append(["house_01_street_door_shut", func() -> void:
		_hour(1.0)
		_put_player(_home.spawn_transform(&"Spawn_Front").origin)
		_door_x = _home.to_local(_home.spawn_transform(&"Spawn_Front").origin).x
		street.call(), 60])
	_steps.append(["house_02_back_glass_door_shut", back, 30])
	_steps.append(["house_03_street_door_open", func() -> void:
		street.call()
		_other.force = true
		_home.toggle_door(&"Door_Front"), 60])
	_steps.append(["house_04_back_glass_door_open", back, 30])
	_steps.append(["house_05_doorstep", func() -> void:
		_look(_h(_door_x, -1.6, 1.62), _h(_door_x + 0.3, 4.0, 1.2)), 30])
	_steps.append(["house_06_lounge", func() -> void:
		_look(_h(1.0, 0.5, 1.6), _h(4.6, 2.9, 0.6)), 60])
	_steps.append(["house_07_fire_and_telly", func() -> void:
		_look(_h(4.6, 1.0, 1.6), _h(0.6, 3.4, 0.6)), 40])
	_steps.append(["house_08_fridge_drawing", func() -> void:
		_look(_h(2.9, 8.7, 1.5), _h(2.5, 7.3, 1.3)), 40])
	_steps.append(["house_09_kitchen_calendar", func() -> void:
		_look(_h(3.5, 8.3, 1.75), _h(3.3, 7.02, 1.8)), 40])
	_steps.append(["house_10_dining", func() -> void:
		_look(_h(3.8, 9.4, 1.75), _h(1.4, 10.7, 0.75)), 40])
	_steps.append(["house_11_robyns_room", func() -> void:
		_look(_h(2.8, 8.8, 3.16 + 1.55), _h(1.0, 10.4, 3.16 + 0.4)), 40])
	_steps.append(["house_12_back_out_on_the_street", street, 40])
	_steps.append(["house_13_shut", func() -> void:
		_other.force = false
		_home.toggle_door(&"Door_Front"), 90, func() -> void: pass, false])
	_steps.append(["house_13_your_house_again", func() -> void:
		_look(_h(_door_x, -1.6, 1.62), _h(_door_x + 0.3, 4.0, 1.2))
		_home.toggle_door(&"Door_Front"), 60])


func _road_steps() -> void:
	_steps.append(["road_0_setup", func() -> void:
		_home.toggle_door(&"Door_Front")
		_put_player(_car.global_position + _car.global_transform.basis.x * -1.6)
		_player.call("get_in")
		_road.force = true
		_road._maybe_offer()
		var md := MapData.shared()
		_route = md.routes.find(Vector3(-912.0, 67.0, 926.0), Vector2.ZERO, _ER.DROPOFF).get("points", PackedVector3Array()), 200, null, false])
	_steps.append(["road_1_may_drive_before", func() -> void:
		_drive_view()
		_on_route(1100.0), 300])
	_steps.append(["road_2_the_city_fading", func() -> void:
		var traffic := _world.get_node_or_null("Traffic")
		if traffic:
			traffic.clear_all()
		_creep = true
		print("road starts: ", _road.start(), " ", _road.refused), 230])
	_steps.append(["road_3_only_the_road", func() -> void: pass, 200])
	_steps.append(["road_4_from_above", func() -> void:
		var back: Vector3 = -_car.global_transform.basis.z
		_look(_car.global_position - back * 14.0 + Vector3.UP * 9.0, _car.global_position + back * 30.0), 30])
	_steps.append(["road_5_the_house", func() -> void:
		var house := _road.find_child("LateHouse", true, false) as Node3D
		var at := _point_back(32.0)
		_look(at + Vector3.UP * 1.5, house.global_position + Vector3.UP * 1.6 if house else _ER.DROPOFF), 30])
	_steps.append(["road_6_the_letterbox", func() -> void:
		var at := _point_back(7.0)
		_look(at + Vector3.UP * 1.3, _ER.DROPOFF + Vector3.UP * 0.6), 30])
	_steps.append(["road_7_off_the_road", func() -> void:
		_creep = false
		_drive_view()
		var right: Vector3 = _car.global_transform.basis.x
		_car.teleport(Transform3D(_car.global_transform.basis, _car.global_position + right * 20.0 + Vector3.UP * 0.5)), 80])
	_steps.append(["road_8_city_back", func() -> void: pass, 240])


func _people_steps() -> void:
	var story := root.get_node("Story")
	var people := _main.find_child("StoryPeople", true, false)
	var machine := func() -> Node: return _home.find_child("AnsweringMachine", false, false)
	var bench := func() -> void: _look(_h(3.4, 9.6, 1.65), _h(4.4, 8.62, 1.2))
	_steps.append(["people_0_setup", func() -> void:
		_hour(21.0)
		story.load_state({})
		people.card_act = 5
		_player.call("get_out"), 200, null, false])
	_steps.append(["people_01_answering_machine", func() -> void:
		_put_player(_home.spawn_transform(&"Spawn_Front").origin)
		story.leave_message(&"kostas_welcome", "Thea Kostas, number 11", String(people.messages[0].text))
		story.leave_message(&"agency_rent", "Swan Property Management", String(people.messages[1].text))
		bench.call(), 45])
	_steps.append(["people_02_playing_a_message", func() -> void:
		machine.call().interact(), 120])
	_steps.append(["people_03_porch_switch_door_open", func() -> void:
		_home.toggle_door(&"Door_Front")
		_look(_h(1.4, 1.2, 1.6), _h(0.0, 1.57, 1.15)), 60])
	_steps.append(["people_03a_switch_close", func() -> void:
		_look(_h(1.1, 0.9, 1.6), _h(0.0, 1.57, 1.15)), 20])
	_steps.append(["people_03b_hall_porch_on", func() -> void:
		_home.toggle_door(&"Door_Front")
		_look(_h(1.2, 2.6, 1.6), _h(1.2, 0.0, 1.4)), 60])
	_steps.append(["people_03c_hall_porch_off", func() -> void:
		people.set_porch_light(false), 20])
	_steps.append(["people_04_act_card", func() -> void:
		people.set_porch_light(true)
		story.act_override = 2
		people.card_act = 1
		people._maybe_card()
		_look(_h(1.0, 0.5, 1.6), _h(4.6, 2.9, 0.6)), 100])
	_steps.append(["people_05_porch_light_on", func() -> void:
		_hour(1.0)
		story.act_override = 0
		_door_x = _home.to_local(_home.spawn_transform(&"Spawn_Front").origin).x
		_look(_h(_door_x + 1.2, -3.2, 1.6), _h(_door_x + 0.2, 0.0, 1.6)), 450])
	_steps.append(["people_06_porch_light_off", func() -> void:
		people.set_porch_light(false), 30])
	_steps.append(["people_07_three_knocks", func() -> void:
		people.set_porch_light(true)
		people.set("_blinks", 0.7 * 3.0), 34])


func _empty_steps() -> void:
	_steps.append(["empty_0_setup", func() -> void:
		_hour(1.0)
		_main.find_child("StoryPeople", true, false).card_act = 5
		_player.call("get_out"), 200, null, false])
	_steps.append(["empty_01_street_door_open", func() -> void:
		_put_player(_home.spawn_transform(&"Spawn_Front").origin)
		_door_x = _home.to_local(_home.spawn_transform(&"Spawn_Front").origin).x
		_other.force = true
		_other.force_form = &"abandoned"
		_home.toggle_door(&"Door_Front")
		_look(_h(_door_x + 0.6, -6.0, 1.7), _h(_door_x + 0.6, 3.0, 1.4)), 90])
	_steps.append(["empty_02_doorstep_leaves", func() -> void:
		_look(_h(_door_x, -1.2, 1.62), _h(_door_x + 0.1, 2.5, 0.3)), 30])
	_steps.append(["empty_03_switch_taped", func() -> void:
		_look(_h(0.9, 1.4, 1.5), _h(0.0, 1.57, 1.15)), 30])
	_steps.append(["empty_04_lounge_sheets", func() -> void:
		_look(_h(1.0, 0.5, 1.6), _h(4.6, 2.9, 0.6)), 40])
	_steps.append(["empty_05_lounge_back", func() -> void:
		_look(_h(4.6, 1.0, 1.6), _h(0.6, 3.4, 0.6)), 30])
	_steps.append(["empty_06_kitchen", func() -> void:
		_look(_h(3.5, 9.4, 1.75), _h(3.0, 7.0, 1.2)), 30])
	_steps.append(["empty_07_dining_chairs_up", func() -> void:
		_look(_h(3.8, 9.4, 1.75), _h(1.4, 10.7, 0.9)), 30])
	_steps.append(["empty_08_stairs_stain_tape", func() -> void:
		_look(_h(0.6, 10.6, 1.5), _h(0.4, 7.5, 1.0)), 30])
	_steps.append(["empty_09_tape_close", func() -> void:
		_look(_h(0.9, 9.1, 1.2), _h(_HA.TAPE_AT.x, _HA.TAPE_AT.y, _HA.TAPE_AT.z)), 30])
	_steps.append(["empty_10_upstairs_robyn", func() -> void:
		_look(_h(2.8, 8.8, 3.16 + 1.55), _h(1.0, 10.4, 3.16 + 0.4)), 30])
	_steps.append(["empty_11_upstairs_front", func() -> void:
		_look(_h(1.5, 3.6, 3.16 + 1.55), _h(4.3, 1.5, 3.16 + 0.3)), 30])
	_steps.append(["empty_12_shut", func() -> void:
		_other.force = false
		_look(_h(_door_x + 0.6, -6.0, 1.7), _h(_door_x + 0.6, 3.0, 1.4))
		_home.toggle_door(&"Door_Front"), 90, func() -> void: pass, false])
	_steps.append(["empty_13_gentle_lounge", func() -> void:
		root.get_node("Settings").set("strange_things", "gentle")
		_other.force = true
		_home.toggle_door(&"Door_Front")
		_look(_h(1.0, 0.5, 1.6), _h(4.6, 2.9, 0.6)), 90])
	_steps.append(["empty_14_gentle_hall", func() -> void:
		_look(_h(_door_x, -1.2, 1.62), _h(_door_x + 0.1, 2.5, 0.3)), 30])
	_steps.append(["empty_15_done", func() -> void:
		root.get_node("Settings").set("strange_things", "full")
		_other.force = false
		_look(_h(_door_x + 0.6, -6.0, 1.7), _h(_door_x + 0.6, 3.0, 1.4))
		_home.toggle_door(&"Door_Front"), 90, func() -> void: pass, false])


## Act 4: the house turns. The darkroom, the river, then the lane and the
## shed (stepped into for real, through the player's own eyes).
func _turns_steps() -> void:
	var street := func() -> void: _look(_h(_door_x + 0.6, -6.0, 1.7), _h(_door_x + 0.6, 3.0, 1.4))
	var doorstep := func() -> void: _look(_h(_door_x, -1.2, 1.62), _h(_door_x + 0.4, 4.0, 1.0))
	var open := func(form: StringName) -> void:
		_put_player(_home.spawn_transform(&"Spawn_Front").origin)
		_other.force = true
		_other.force_form = form
		_home.toggle_door(&"Door_Front")
		street.call()
	var shut := func() -> void:
		_other.force = false
		_put_player(_home.spawn_transform(&"Spawn_Front").origin)
		street.call()
		if _home.is_door_open(&"Door_Front"):
			_home.toggle_door(&"Door_Front")
	var eyes := func(feet: Vector3, target: Vector3) -> void:
		(_player.get("_camera") as Camera3D).current = true
		_player.call("teleport", feet, target)
	var print_at := func() -> Vector3:
		var room: Node = _other.get("_dressing")
		return room.face_at(room.takeable[0]) if room and not room.takeable.is_empty() else _h(3.0, 3.4, 1.8)
	_steps.append(["turns_0_setup", func() -> void:
		_hour(1.0)
		_main.find_child("StoryPeople", true, false).card_act = 5
		_door_x = _home.to_local(_home.spawn_transform(&"Spawn_Front").origin).x
		_player.call("get_out"), 200, func() -> void:
			# A few photos in the album, for the darkroom's lines.
			var shot := root.get_texture().get_image()
			for r: Rect2i in [Rect2i(0, 0, 1280, 720), Rect2i(0, 0, 640, 360), Rect2i(640, 0, 640, 360), Rect2i(320, 180, 640, 360)]:
				root.get_node("Activities").add_photo(shot.get_region(r)), false])
	# The darkroom.
	_steps.append(["turns_01_darkroom_street", func() -> void: open.call(&"darkroom"), 90])
	_steps.append(["turns_02_darkroom_doorstep", doorstep, 30])
	_steps.append(["turns_03_darkroom_lounge", func() -> void:
		_look(_h(1.0, 0.5, 1.6), _h(4.6, 2.9, 1.2)), 40])
	_steps.append(["turns_04_darkroom_kitchen", func() -> void:
		_look(_h(3.8, 9.4, 1.75), _h(1.4, 10.7, 1.4)), 30])
	_steps.append(["turns_05_darkroom_stairs", func() -> void:
		_look(_h(0.6, 10.6, 1.5), _h(0.4, 7.5, 1.4)), 30])
	_steps.append(["turns_06_darkroom_upstairs", func() -> void:
		_look(_h(2.8, 8.8, 3.16 + 1.55), _h(1.0, 10.4, 3.16 + 1.2)), 30])
	_steps.append(["turns_07_darkroom_print", func() -> void:
		var at: Vector3 = print_at.call()
		_look(at + _home.global_basis.z * 0.5 + Vector3.UP * 0.05, at), 30])
	_steps.append(["turns_08_darkroom_taken", func() -> void:
		_other.interact(), 40])
	_steps.append(["turns_09_darkroom_shut", shut, 90, null, false])
	# The river.
	_steps.append(["turns_10_river_street", func() -> void: open.call(&"river"), 90])
	_steps.append(["turns_11_river_doorstep", doorstep, 30])
	_steps.append(["turns_12_river_far_wall", func() -> void:
		_look(_h(3.6, 7.6, 1.6), _h(2.7, 11.9, 1.3)), 30])
	_steps.append(["turns_13_river_birds", func() -> void:
		_look(_h(2.6, 9.6, 2.4), _h(1.0, 7.0, 2.0)), 30])
	_steps.append(["turns_13b_river_bird_close", func() -> void:
		var bird: Node3D = _other.get("_dressing").birds[2]
		_look(bird.global_position + _home.global_basis.x * 1.1 + Vector3.UP * 0.25, bird.global_position), 30])
	_steps.append(["turns_14_river_lounge", func() -> void:
		_look(_h(1.0, 0.5, 1.6), _h(4.6, 2.9, 0.4)), 30])
	_steps.append(["turns_15_river_shut", shut, 90, null, false])
	# The lane: step in and you're down the lane, looking back.
	_steps.append(["turns_16_lane_street", func() -> void: open.call(&"lane"), 60])
	_steps.append(["turns_17_lane_step_in", func() -> void:
		eyes.call(_h(_door_x, 0.4, 0.05), _h(_door_x, 6.0, 1.6)), 60])
	_steps.append(["turns_18_lane_wide", func() -> void:
		var p: Vector3 = _player.global_position
		var front: Vector3 = _home.spawn_transform(&"Spawn_Front").origin
		_look(p + (p - front).normalized() * 6.0 + Vector3.UP * 3.0, front + Vector3.UP * 1.5), 30])
	_steps.append(["turns_19_lane_home", func() -> void:
		var front: Vector3 = _home.spawn_transform(&"Spawn_Front").origin
		eyes.call(front + _home.global_basis.z * 0.3, _h(_door_x, 3.0, 1.6)), 60])
	# The shed: step in and you're at its table.
	_steps.append(["turns_20_shed_street", func() -> void: open.call(&"shed"), 60, null, false])
	_steps.append(["turns_21_shed_step_in", func() -> void:
		eyes.call(_h(_door_x, 0.4, 0.05), _h(_door_x, 6.0, 1.6)), 60])
	_steps.append(["turns_22_shed_wide", func() -> void:
		var stand := (_home.find_child("Shed_Ending", true, false) as Node3D).global_position
		var table := (_home.find_child("Shed_Sheeted", true, false) as Node3D).global_position
		_look(stand + (stand - table).normalized() * 0.6 + Vector3.UP * 1.9, table + Vector3.UP * 0.8), 30])
	_steps.append(["turns_23_shed_door", func() -> void:
		var door := (_home.find_child("Shed_Door", true, false) as Node3D).global_position
		eyes.call(_player.global_position, door + Vector3.UP * 1.0), 30])
	_steps.append(["turns_24_back_in_the_hall", func() -> void:
		_other.interact(), 60])
	# For comparison: the same view of the shed solved (the mystery's own
	# ending), yard lamps on and the bulb at full.
	_steps.append(["turns_22b_shed_solved_compare", func() -> void:
		var mystery := _main.find_child("Mystery", true, false)
		mystery.call("_reveal", false)
		var stand := (_home.find_child("Shed_Ending", true, false) as Node3D).global_position
		var table := (_home.find_child("Shed_Sheeted", true, false) as Node3D).global_position
		_look(stand + (stand - table).normalized() * 0.6 + Vector3.UP * 1.9, table + Vector3.UP * 0.8), 30, func() -> void:
			var mystery := _main.find_child("Mystery", true, false)
			var props: Node = mystery.get("_shed_props")
			if props:
				props.queue_free()
			mystery.set("_shed_props", null)
			(_home.find_child("Shed_Sheeted", true, false) as Node3D).visible = true])
	_steps.append(["turns_25_done", func() -> void:
		_other.force = false
		_other.force_form = &"", 10, null, false])


## Choice 3: Robyn's door in Arundel Street, Fremantle, and knocking.
func _robyn_steps() -> void:
	var robyn := func() -> Node: return _main.find_child("Robyn", true, false)
	var door := func() -> Node3D: return robyn.call().get("_house")
	var front := func(back: float, up: float) -> Vector3:
		var d: Node3D = door.call()
		return d.global_transform * Vector3(0.0, up, back)
	_steps.append(["robyn_0_setup", func() -> void:
		_hour(18.0)
		root.get_node("Story").act_override = 4
		robyn.call().step = robyn.call().KNOWN
		_player.call("get_in"), 30, null, false])
	_steps.append(["robyn_0_drive", func() -> void:
		var r: Node = robyn.call()
		_car.teleport(Transform3D(Basis.looking_at(Vector3(0.765, 0, -0.644), Vector3.UP), r.ROAD_AT + Vector3(0.765, 0, -0.644) * -8.0 + Vector3.UP * 1.0)), 240, null, false])
	_steps.append(["robyn_01_street", func() -> void:
		_look(front.call(11.0, 1.6) + Vector3(0.765, 0, -0.644) * -5.0, front.call(0.0, 1.4)), 40])
	_steps.append(["robyn_02_door", func() -> void:
		_look(front.call(3.2, 1.6), front.call(0.0, 1.2)), 30])
	_steps.append(["robyn_03_on_foot", func() -> void:
		_player.call("get_out"), 150, null, false])
	_steps.append(["robyn_04_knock_hint", func() -> void:
		(_player.get("_camera") as Camera3D).current = true
		var feet: Vector3 = front.call(1.6, 0.0)
		_player.call("teleport", feet, front.call(0.0, 1.3)), 60])
	_steps.append(["robyn_05_knock", func() -> void:
		root.get_node("Discoveries").discover("mystery/polaroid")
		root.get_node("Notices").clear()
		robyn.call().knock(), 120])
	_steps.append(["robyn_06_she_talks", func() -> void: pass, 14 * 60])
	_steps.append(["robyn_07_door_open_side", func() -> void:
		_look(front.call(2.6, 1.5) + (door.call() as Node3D).global_basis.x * 2.0, front.call(0.0, 1.1)), 30])
	_steps.append(["robyn_08_night", func() -> void:
		# The clock jumps here; what she said is still queued from the afternoon.
		(robyn.call().get("_lines") as Array).clear()
		root.get_node("Notices").clear()
		_hour(22.0)
		_look(front.call(9.0, 1.7), front.call(0.0, 1.4)), 60])
	_steps.append(["robyn_09_done", func() -> void:
		root.get_node("Story").act_override = 0, 10, null, false])


## The tapes that run ahead: the tape at night, the reel job next morning,
## the cat on the fence at the drop-off.
func _tape_steps() -> void:
	var tape := func() -> Node: return _main.find_child("TapeAhead", true, false)
	var jobs := func() -> Node: return root.get_node("Jobs")
	_steps.append(["tape_0_setup", func() -> void:
		var robyn := _main.find_child("Robyn", true, false)
		if robyn:
			(robyn.get("_lines") as Array).clear()
		root.get_node("Notices").clear()
		_hour(23.5)
		root.get_node("Story").act_override = 4
		_player.call("get_in")
		_drive_view(), 120, null, false])
	_steps.append(["tape_01_cassette", func() -> void:
		# Getting in at 23:30 in act 4 may have played it already (as it
		# would for a player): play it again here, where the shot can see it.
		root.get_node("Notices").clear()
		tape.call().pending = {}
		tape.call().last_day = -100
		tape.call().force = true
		print("tape plays: ", tape.call().maybe_play()), 90])
	_steps.append(["tape_02_mick", func() -> void: pass, 7 * 60])
	_steps.append(["tape_03_next_morning", func() -> void:
		root.get_node("Notices").clear()
		tape.call().due_day = root.get_node("GameClock").day
		_hour(7.5), 60, null, false])
	_steps.append(["tape_04_phone", func() -> void:
		var e := InputEventAction.new()
		e.action = &"phone"
		e.pressed = true
		Input.parse_input_event(e)
		var u := InputEventAction.new()
		u.action = &"phone"
		Input.parse_input_event(u), 60])
	_steps.append(["tape_05_take_it", func() -> void:
		var e := InputEventAction.new()
		e.action = &"phone"
		e.pressed = true
		Input.parse_input_event(e)
		var u := InputEventAction.new()
		u.action = &"phone"
		Input.parse_input_event(u)
		for job: Dictionary in jobs.call().offers:
			if job.get("story", "") == "tape_ahead":
				jobs.call().accept(job)
				break
		jobs.call().active.stage = "to_dropoff"
		jobs.call()._stage_changed()
		var drop: Node3D = jobs.call().site(String(jobs.call().active.dropoff))
		var from: Vector3 = drop.global_position + drop.global_basis.z * 25.0
		_car.teleport(Transform3D(Basis.looking_at(drop.global_position - from, Vector3.UP), from + Vector3.UP * 1.2)), 240])
	_steps.append(["tape_06_cat", func() -> void:
		var cat: Node3D = tape.call().get("_cat")
		if cat:
			_look(cat.global_position + cat.global_basis.z * 3.0 + Vector3.UP * 1.6, cat.global_position + Vector3.UP * 1.1), 30])
	_steps.append(["tape_07_cat_close", func() -> void:
		var cat: Node3D = tape.call().get("_cat")
		if cat:
			_look(cat.global_position + cat.global_basis.z * 1.3 + Vector3.UP * 1.45, cat.global_position + Vector3.UP * 1.3), 30])
	_steps.append(["tape_08_done", func() -> void:
		_drive_view()
		var job: Dictionary = jobs.call().active.duplicate()
		jobs.call().abandon()
		jobs.call().job_completed.emit(job, 40, "Delivered.")
		tape.call().force = false, 90])
	_steps.append(["tape_09_reset", func() -> void:
		root.get_node("Story").act_override = 0, 10, null, false])


## The 1979 street: William Street, Northbridge, after midnight in act 4.
func _street_steps() -> void:
	var ev := {}
	var street := func() -> Node: return _main.find_child("Street1979", true, false)
	_steps.append(["street_0a_in_the_car", func() -> void:
		if _player.get("in_car") == false:
			_put_player(_car.global_position + _car.global_transform.basis.x * -1.6)
			_player.call("get_in"), 240, null, false])
	_steps.append(["street_0_setup", func() -> void:
		_hour(1.0)
		root.get_node("Story").act_override = 4
		_main.find_child("StoryPeople", true, false).card_act = 5
		var found := _william_street()
		ev.path = found.get("points", PackedVector3Array())
		var path: PackedVector3Array = ev.path
		print("1979 street path ", path.size(), " points")
		var cum := TrafficGraph.cumulative(path)
		var at := TrafficGraph.point_at(path, cum, 10.0)
		var t := TrafficGraph.tangent_at(path, cum, 10.0)
		var dir := Vector3(t.x, 0.0, t.z).normalized()
		_car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), at + TrafficGraph.left_of(dir) * -1.8 + Vector3.UP))
		_drive_view(), 300, null, false])
	_steps.append(["street_01_now", func() -> void:
		_car.headlights_on = true
		_car._update_lights()
		_creep = true, 60])
	_steps.append(["street_02_deck_clicks_on", func() -> void:
		var st = street.call()
		st.force = true
		print("1979 street ready: ", st._ready_to_start(), " shops ", st.shops.size(), " on ", st.street)
		print("1979 street begins: ", st.begin()), 600])
	_steps.append(["street_03_ahead", func() -> void:
		var st = street.call()
		print("1979 street turned: ", st.turned, " cars ", st._old.count() if st._old else -1, " shops ", st.shops.size(), " venues ", st._venues.size(), " extra ", st.extra)
		var at: Vector3 = TrafficGraph.point_at(st._path, st._cum, st._s + 2.0)
		var to: Vector3 = TrafficGraph.point_at(st._path, st._cum, st._s + 70.0)
		_look(at + Vector3.UP * 4.5, to + Vector3.UP * 1.0), 30])
	for k in 3:
		_steps.append(["street_0%d_shop_%d" % [4 + k, k], func() -> void:
			var st = street.call()
			var shops: Array = st.shops
			var pick := {}
			var seen := 0
			for shop: Dictionary in shops:
				if (shop.venue as bool) == (k == 2):
					if seen == k % 2:
						pick = shop
						break
					seen += 1
			if pick.is_empty() and not shops.is_empty():
				pick = shops[k % shops.size()]
			if not pick.is_empty():
				var at: Transform3D = pick.at
				_look(at.origin + at.basis.z * 8.5 + at.basis.x * 2.0 + Vector3.UP * 2.2, at.origin + Vector3.UP * 2.6), 30])
	# The old cars, from the street: the nearest moving one ahead, then a
	# parked one, each seen from the middle of the road beside it.
	var beside := func(st, body: Node3D, back: float) -> void:
		var p: Vector3 = body.global_position
		var best_s := 0.0
		var best_d := INF
		var s := 0.0
		var total: float = st._cum[st._cum.size() - 1]
		while s < total:
			var d: float = TrafficGraph.point_at(st._path, st._cum, s).distance_to(p)
			if d < best_d:
				best_d = d
				best_s = s
			s += 2.0
		var eye: Vector3 = TrafficGraph.point_at(st._path, st._cum, maxf(best_s - back, 0.0))
		_look(eye + Vector3.UP * 1.6, p + Vector3.UP * 0.8)
	_steps.append(["street_07_old_car", func() -> void:
		var st = street.call()
		var best: Node3D = null
		var d := INF
		for pair: Array in (st._old.models() if st._old else []):
			var body: Node3D = pair[0]
			var dd := body.global_position.distance_to(_car.global_position)
			if not String(body.name).begins_with("parked_") and body.visible and dd > 8.0 and dd < d:
				d = dd
				best = body
		if best:
			beside.call(st, best, 9.0)
			print("old moving car at ", int(d), " m"), 30])
	_steps.append(["street_08_parked", func() -> void:
		var st = street.call()
		var best: Node3D = null
		var d := INF
		for pair: Array in (st._old.models() if st._old else []):
			var body: Node3D = pair[0]
			var dd: float = st._distance_to_path(body.global_position)
			if String(body.name).begins_with("parked_") and body.visible and dd < d:
				d = dd
				best = body
		if best:
			beside.call(st, best, 7.0)
			print("old parked car ", int(d), " m off the street"), 30])
	_steps.append(["street_08b_down_the_street", func() -> void:
		var st = street.call()
		var at: Vector3 = TrafficGraph.point_at(st._path, st._cum, st._s + 120.0)
		var to: Vector3 = TrafficGraph.point_at(st._path, st._cum, st._s + 200.0)
		_look(at + Vector3.UP * 2.5, to + Vector3.UP * 1.0), 30])
	_steps.append(["street_09_drive_view", func() -> void:
		_drive_view(), 30])
	_steps.append(["street_10_to_the_end", func() -> void:
		var st = street.call()
		var total: float = st._cum[st._cum.size() - 1]
		var s := total - 18.0
		var t := TrafficGraph.tangent_at(st._path, st._cum, s)
		var dir := Vector3(t.x, 0.0, t.z).normalized()
		_car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), TrafficGraph.point_at(st._path, st._cum, s) + TrafficGraph.left_of(dir) * -1.8 + Vector3.UP))
		st._at = maxi(st._path.size() - 20, 0), 300, null, false])
	_steps.append(["street_11_now_again", func() -> void:
		var st = street.call()
		print("1979 street over: ", not st.running, " logged ", root.get_node("Story").has_night(StringName("street_1979_%d" % root.get_node("GameClock").day)),
			" found ", root.get_node("Discoveries").has("oddity/street_1979"))
		_creep = false
		st.force = false, 60])
	_steps.append(["street_12_reset", func() -> void:
		root.get_node("Story").act_override = 0, 10, null, false])


## William Street through Northbridge, up the strip of venues.
func _william_street() -> Dictionary:
	var g := MapData.shared().routes
	# From the bottom of the strip (by the Paddock) up past the venues.
	var start := Vector2(668.0, 75.0)
	var heading := (Vector2(509.0, 369.0) - start).normalized()
	var at := Vector3.ZERO
	var best_d := INF
	for r in g.road_pts.size():
		if g.road_names[r] != "William Street":
			continue
		for p: Vector3 in g.road_pts[r]:
			var d := Vector2(p.x, p.z).distance_to(start)
			if d < best_d:
				best_d = d
				at = p
	var found: Dictionary = _RS.street_ahead(at, heading, ["primary", "secondary", "tertiary"])
	print("william street: ", found.get("name", "?"), " from ", at)
	return found


func _out_steps() -> void:
	var looking := func() -> Node: return _main.find_child("LookingOut", true, false)
	var lounge := func() -> void: _look(_h(3.5, 2.4, 1.65), _h(3.3, -9.0, 1.0))
	var balcony := func() -> void: _look(_h(1.2, 1.6, 3.16 + 1.6), _h(2.6, -10.0, 1.4))
	_steps.append(["out_0_setup", func() -> void:
		_hour(1.0)
		_main.find_child("StoryPeople", true, false).card_act = 5
		_player.call("get_out"), 200, null, false])
	_steps.append(["out_00_lane_from_above", func() -> void:
		_put_player(_h(2.8, 2.6, 0.2))
		_look(_h(2.0, -2.0, 14.0), _h(2.0, -7.0, 0.0)), 60])
	_steps.append(["out_01_lane_today", func() -> void:
		lounge.call(), 30])
	_steps.append(["out_02_lane_1979", func() -> void:
		looking.call().force = true
		looking.call().begin(&"1979"), 90])
	_steps.append(["out_02b_lane_1979_above", func() -> void:
		_look(_h(2.0, -2.0, 14.0), _h(2.0, -7.0, 0.0)), 30])
	_steps.append(["out_02c_lane_1979_doorstep", func() -> void:
		_look(_h(3.5, -2.0, 1.65), _h(3.3, -12.0, 1.6)), 30])
	_steps.append(["out_03_lane_1979_upstairs", balcony, 30])
	_steps.append(["out_04_mick_car_close", func() -> void:
		_look(_h(1.0, -2.6, 1.4), _h(3.2, -5.4, 0.5)), 30])
	_steps.append(["out_05_door_opens", func() -> void:
		_home.toggle_door(&"Door_Front")
		lounge.call(), 60])
	_steps.append(["out_06_nothing", func() -> void:
		_home.toggle_door(&"Door_Front")
		looking.call().begin(&"nothing")
		lounge.call(), 240])
	_steps.append(["out_07_nothing_upstairs", balcony, 30])
	_steps.append(["out_08_nothing_back", func() -> void:
		_look(_h(2.6, 9.4, 1.55), _h(3.0, 18.0, 1.0)), 30])
	_steps.append(["out_09_nothing_inside", func() -> void:
		_look(_h(1.0, 0.5, 1.6), _h(4.6, 2.9, 0.6)), 30])
	_steps.append(["out_10_door_back", func() -> void:
		_home.toggle_door(&"Door_Front")
		lounge.call(), 60])
	_steps.append(["out_11_done", func() -> void:
		_home.toggle_door(&"Door_Front")
		looking.call().force = false, 30, null, false])


func _drive_steps() -> void:
	var events := {}
	_steps.append(["drive_0a_in_the_car", func() -> void:
		# After the house groups you're on foot, and the road events only run
		# while you're driving.
		if _player.get("in_car") == false:
			_put_player(_car.global_position + _car.global_transform.basis.x * -1.6)
			_player.call("get_in"), 240, null, false])
	_steps.append(["drive_0_setup", func() -> void:
		_hour(1.0)
		_main.find_child("StoryPeople", true, false).card_act = 5
		for n in ["RepeatStreet", "MinimapPassenger", "LookoutSignal", "StoppedClock", "StationVoice"]:
			events[n] = _main.find_child(n, true, false)
		var found := _long_street()
		events.path = found.get("points", PackedVector3Array())
		var path: PackedVector3Array = events.path
		print("repeat street on ", found.get("name", "?"), " ", path.size())
		var dir := path[3] - path[2]
		dir.y = 0.0
		_car.teleport(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), path[2] + Vector3.UP))
		_drive_view(), 240, null, false])
	_steps.append(["drive_01_repeat_street_ahead", func() -> void:
		_car.headlights_on = true
		_car._update_lights()
		var rs = events.RepeatStreet
		rs.force = true
		_creep = true
		print("repeat begins: ", rs._ready_to_start(), " ", rs.begin(), " on ", rs.street), 90])
	_steps.append(["drive_02_the_three", func() -> void:
		var rs = events.RepeatStreet
		var at := TrafficGraph.point_at(rs._path, rs._cum, rs._three_s - 22.0)
		var to := TrafficGraph.point_at(rs._path, rs._cum, rs._three_s)
		_look(at + Vector3.UP * 1.3, to + Vector3.UP * 1.5)
		rs._show(true), 60])
	_steps.append(["drive_03_the_three_close", func() -> void:
		var rs = events.RepeatStreet
		var man := rs._three.get_node_or_null(^"Man") as Node3D
		var lamp := rs._three.get_node(^"Lamp") as Node3D
		_look(lamp.global_position + (man.global_position - lamp.global_position) * 0.5 + Vector3.UP * 1.6 - rs._three.global_basis.z * -9.0, lamp.global_position + Vector3.UP * 1.5), 30])
	_steps.append(["drive_04_flash", func() -> void:
		_drive_view()
		_car.flash_lights(true), 20])
	_steps.append(["drive_05_through", func() -> void:
		_car.flash_lights(false)
		events.RepeatStreet.force = false
		_creep = false, 120])
	_steps.append(["drive_06a_to_trail_end", func() -> void:
		var path: PackedVector3Array = events.path
		var cum := TrafficGraph.cumulative(path)
		var end := minf(cum[cum.size() - 1] - 30.0, 320.0)
		var t := TrafficGraph.tangent_at(path, cum, end)
		_car.teleport(Transform3D(Basis.looking_at(Vector3(t.x, 0.0, t.z).normalized(), Vector3.UP), TrafficGraph.point_at(path, cum, end) + Vector3.UP)), 60, null, false])
	_steps.append(["drive_06_minimap_passenger", func() -> void:
		var mp = events.MinimapPassenger
		# A trail every 2 m along the street, as if just driven, up to the car.
		var path: PackedVector3Array = events.path
		var cum := TrafficGraph.cumulative(path)
		var end := minf(cum[cum.size() - 1] - 30.0, 320.0)
		var trail := PackedVector3Array()
		var s := 0.0
		while s <= end:
			trail.append(TrafficGraph.point_at(path, cum, s))
			s += 2.0
		mp._trail = trail
		mp.force = true
		mp.begin()
		mp._t = mp.ARRIVE + 0.5
		mp._gap = mp.FOLLOW, 120])
	_steps.append(["drive_07_stopped_clock", func() -> void:
		events.MinimapPassenger.force = false
		events.MinimapPassenger.finish()
		_hour(2.7)
		var sc = events.StoppedClock
		sc.force = true
		sc.begin()
		_hour(3.6), 90])
	_steps.append(["drive_08_clock_back", func() -> void:
		events.StoppedClock.force = false
		events.StoppedClock._let_go(), 120])
	_steps.append(["drive_09_station_here", func() -> void:
		root.get_node("Story").act_override = 3
		events.StationVoice.force = true
		# The line first: its first time is a discovery, and that card would
		# hurry it off. Then shown straight away, not queued behind the
		# clock's notice.
		var line: String = events.StationVoice.here_line()
		root.get_node("Notices").clear()
		root.get_node("Activities").say("Under the static, the calm voice: \"...%s...\"" % line), 120])
	for k in 2:
		_steps.append(["drive_%d0_lookout" % (k + 1), func() -> void:
			root.get_node("Story").act_override = 0
			var l: Dictionary = events.LookoutSignal.LOOKOUTS[k]
			var at: Vector3 = l.at
			var dir: Vector3 = (l.lights - at) * Vector3(1, 0, 1)
			_car.teleport(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), at + Vector3.UP * 4.0)), 240, null, false])
		_steps.append(["drive_%d1_lookout_view" % (k + 1), func() -> void:
			# From the edge of the scarp, where you'd pull up on the grass.
			var l: Dictionary = events.LookoutSignal.LOOKOUTS[k]
			var at: Vector3 = l.at
			var dir: Vector3 = ((l.lights - at) * Vector3(1, 0, 1)).normalized()
			var edge: Vector3 = at + dir * [60.0, 100.0][k]
			var q := PhysicsRayQueryParameters3D.create(edge + Vector3.UP * 60.0, edge + Vector3.DOWN * 60.0, ~MapTileLoader.LAYER_WATER)
			q.exclude = [_car.get_rid()]
			var hit: Dictionary = _car.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				edge.y = hit.position.y
			_look(edge + Vector3.UP * 1.6, l.lights), 30])
		_steps.append(["drive_%d2_lookout_answers" % (k + 1), func() -> void:
			var ls = events.LookoutSignal
			ls.force = true
			ls._here = ls.LOOKOUTS[k]
			ls.begin()
			ls._t = ls.BEAT + 0.1, 8])
		_steps.append(["drive_%d3_lookout_done" % (k + 1), func() -> void:
			events.LookoutSignal._t = 20.0, 60])


## A long straight-on residential street within a couple of km of home.
func _long_street() -> Dictionary:
	var g := MapData.shared().routes
	var home: Vector3 = _home.global_position
	var best := {}
	for r in g.road_pts.size():
		if not g.road_kinds[r] in _RS.KINDS or g.road_names[r] == "":
			continue
		var p := g.road_pts[r][0]
		if p.distance_to(home) > 1500.0:
			continue
		var t := TrafficGraph.tangent_at(g.road_pts[r], g.road_cum[r], 1.0)
		var found: Dictionary = _RS.street_ahead(p, Vector2(t.x, t.z))
		if found.is_empty():
			continue
		var cum := TrafficGraph.cumulative(found.points)
		if cum[cum.size() - 1] > 500.0:
			return found
	return best


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		_H79 = load("res://scripts/world/late_city/house_1979.gd")
		_ER = load("res://scripts/world/late_city/empty_road.gd")
		_HA = load("res://scripts/world/late_city/house_abandoned.gd")
		_RS = load("res://scripts/world/late_city/repeat_street.gd")
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		_player = _world.get_node_or_null("Player")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_frames = -240
		return false
	_frames += 1
	if _creep:
		# Rolling along at walking pace (standing still lets the road go).
		var fwd: Vector3 = -_car.global_transform.basis.z
		_car.linear_velocity = Vector3(fwd.x * 1.4, _car.linear_velocity.y, fwd.z * 1.4)
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			_home = get_first_node_in_group(&"home_base")
			_other = _main.find_child("OtherHouse", true, false)
			_road = _main.find_child("EmptyRoad", true, false)
			_cam = Camera3D.new()
			_cam.fov = 70.0
			_world.add_child(_cam)
			_build_steps()
			_next()
		return false
	if _step >= _steps.size():
		quit(0)
		return true
	if _frames >= int(_steps[_step][2]):
		var name: String = _steps[_step][0]
		if _steps[_step].size() < 5 or _steps[_step][4]:
			root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
			print("shot ", name)
		if _steps[_step].size() > 3 and _steps[_step][3] is Callable:
			(_steps[_step][3] as Callable).call()
		_next()
	return false


func _next() -> void:
	_step += 1
	_frames = 0
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()


func _hour(h: float) -> void:
	root.get_node("GameClock").set_time(h)


func _look(from: Vector3, to: Vector3) -> void:
	_cam.current = true
	_cam.global_position = from
	_cam.look_at(to)


func _drive_view() -> void:
	var cam := _world.get_node("CameraRig/Camera3D") as Camera3D
	cam.current = true


func _put_player(at: Vector3) -> void:
	_player.global_position = at + Vector3.UP * 0.1
	_player.set("velocity", Vector3.ZERO)


## Put the car on the route `back` metres before May Drive's end, facing along it.
func _on_route(back: float) -> void:
	var jobs := root.get_node("Jobs")
	for job: Dictionary in jobs.offers:
		if job.get("story", "") == "empty_road":
			jobs.accept(job)
			break
	jobs.active.stage = "to_dropoff"
	jobs._stage_changed()
	_hour(1.0)
	var cum := TrafficGraph.cumulative(_route)
	var total := cum[cum.size() - 1]
	var s: float = total - _ER.MIN_ROUTE - 20.0
	while s - 20.0 > total - back and MapData.shared().street_at(_point_at(cum, s - 20.0), 12.0) == _ER.STREET:
		s -= 20.0
	var i := 1
	while i < cum.size() - 1 and cum[i] < s:
		i += 1
	var p := _route[i - 1].lerp(_route[i], 0.5)
	var dir := _route[i] - _route[i - 1]
	dir.y = 0.0
	_car.teleport(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p + Vector3.UP * 1.0))


## A point on the route `back` metres before its end.
func _point_back(back: float) -> Vector3:
	var cum := TrafficGraph.cumulative(_route)
	var s := cum[cum.size() - 1] - back
	for i in range(1, cum.size()):
		if cum[i] >= s:
			var t := (s - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.01)
			return _route[i - 1].lerp(_route[i], t)
	return _route[_route.size() - 1]


func _point_at(cum: PackedFloat32Array, s: float) -> Vector3:
	for i in range(1, cum.size()):
		if cum[i] >= s:
			var t := (s - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.01)
			return _route[i - 1].lerp(_route[i], t)
	return _route[_route.size() - 1]
