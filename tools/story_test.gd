extends SceneTree
## The story core and its first late-city events, quickly:
##
##   - Story: acts, choices (and that bad ones are refused), flags, the Nights
##     log once per id, saving and loading.
##   - LateCity: only one event at a time, the deck and the look, presence,
##     the bird flicker levels by act.
##   - The other house: opening the front door from outside after midnight
##     turns the inside to 1979 (today's things hidden, the walls papered, the
##     Dorans' things in), opening it from inside doesn't, the drawing can be
##     taken, and stepping out and shutting the door gives your house back.
##   - The empty road: the parcel job turns up, the road empties (sound, then
##     everything but the road), leaving the road brings the world back, and
##     on a second go the parcel is signed for and the world comes back.
##   - The people: messages on the answering machine (left once, by act and
##     day, played and marked heard, saved), the porch light switch and the
##     twenty-to-three check (choice 1), the thirteen (choice 2), the endings,
##     the act cards, the midnight station's finds as a challenge stat, and
##     that things can't be used through a wall.
##   - Batch 3: the headlight flash, the stopped clock, the minimap passenger,
##     the lookouts answering, the station knowing where you are, the repeat
##     street, looking out of the window (1979, then nothing), and the house
##     through the door in act 3 (abandoned, with the tape on the stairs).
##   - Act 4: the house turns, a different one each time: the darkroom (a
##     print of somewhere you haven't been goes in your album), the river,
##     the lane (stepping in puts you down the lane; walking home ends it)
##     and the shed (stepping in puts you in the shed; its door brings you
##     back to the hall).
##   - Act 4, part 2: finding Robyn (asking around Fremantle, her door, the
##     Polaroid, choice 3) and the tapes that run ahead (the tape, the reel
##     job next morning, the cat on the fence, done).
##   - The 1979 street: on William Street after midnight the shops get their
##     old names and the traffic turns into 1979 cars, and at the end of the
##     street it's all now again.
##   - The finale: the shed opens and its calendar says July 1979; the 11th
##     comes round a week later (the messages before it, the card, Dee and
##     Skylab, the river lights and the rain going up); choice 4 at M.'s
##     table (Half Light, City of Light, Night Drive 13, Lights Out), the
##     drive into the lights on Riverside Drive (The Late City), and a missed
##     11th coming round again.
##   - The endings and what each leaves behind: the regulars' lights and the
##     late city gone (City of Light), fewer lights (Half Light), Mick's 500 L
##     at dawn and 1979 every night (Night Drive 13), the late city fading
##     (Lights Out), and the house in 1979, the credits and always night (The
##     Late City).
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/story_test.gd -- --no-save
##
## `from=N` runs the set-up (stage 0) and then stages N onwards, e.g. from=8
## for just the finale.
##
## Exits with code 1 if any check fails.

var _quitting := false
var _main: Node
var _car  # CarController
var _player: Node3D
var _home  # HomeBase
var _failures: Array[String] = []
var _stage := 0
var _frames := 0
var _other  # OtherHouse
var _road  # EmptyRoad
## The late-city scripts, loaded once the autoloads they use are up (naming
## their classes here would compile them before that).
var _ER: GDScript
var _H79: GDScript
var _OH: GDScript
var _route := PackedVector3Array()
var _runs := 0
var _run_from := 0


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_ER = load("res://scripts/world/late_city/empty_road.gd")
		_H79 = load("res://scripts/world/late_city/house_1979.gd")
		_OH = load("res://scripts/world/late_city/other_house.gd")
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_player = _main.get_node_or_null("LoFi/SubViewport/World/Player") as Node3D
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		return false
	_frames += 1
	var story := root.get_node("Story")
	var late := root.get_node("LateCity")
	var clock := root.get_node("GameClock")
	match _stage:
		0:  # The story's state.
			if _frames < 90:
				return false
			_home = get_first_node_in_group(&"home_base")
			_other = _main.find_child("OtherHouse", true, false)
			_road = _main.find_child("EmptyRoad", true, false)
			_check(_home != null and _other != null and _road != null, "the townhouse, the other house and the empty road are set up")
			if _home == null or _other == null or _road == null:
				return _finish()
			_check(story.act() == 1, "a new game is act 1 (%d)" % story.act())
			story.make_choice(&"porch_light", &"on")
			_check(story.choice(&"porch_light") == &"on", "a choice is remembered")
			story.make_choice(&"porch_light", &"sideways")
			_check(story.choice(&"porch_light") == &"on", "a choice that isn't one is refused")
			_check(story.log_night(&"test_night", "A test night."), "a night goes in the log")
			_check(not story.log_night(&"test_night", "Again."), "only once per id")
			story.set_flag(&"test_flag")
			var saved: Dictionary = story.save_state()
			story.load_state({})
			_check(story.choice(&"porch_light") == &"" and not story.flag(&"test_flag"), "loading an empty save clears it")
			story.load_state(saved)
			_check(story.choice(&"porch_light") == &"on" and story.flag(&"test_flag") and story.has_night(&"test_night"),
				"and loading the save brings it back")
			for a in range(1, 6):
				story.act_override = a
				_check(late.flicker_level() == a - 1, "act %d: bird flicker level %d" % [a, a - 1])
			story.act_override = 0
			clock.set_time(14.0)
			_check(late.presence() == 0.0, "no late city by day")
			_check(not late.allowed_now(), "no events at 2 pm")
			clock.set_time(1.0)
			_check(late.begin(&"a"), "an event can begin")
			_check(not late.begin(&"b"), "but not two at once")
			_check(late.presence() == 1.0, "presence is full while it runs")
			late.end(&"a")
			_check(not late.active(), "and it ends")
			_next()
		1:  # Out of the car, on foot at the front door, at one in the morning.
			if _frames == 1:
				_car.global_transform = _home.spawn_transform(&"Spawn_Car") if _home.has_marker(&"Spawn_Car") else _car.global_transform
				_player.call("get_out")
			elif _frames == 150:
				_check(_player.get("in_car") == false, "out of the car")
				_put_player(_home.spawn_transform(&"Spawn_Front").origin + Vector3.UP * 0.1)
				clock.set_time(1.0)
			elif _frames == 160:
				_other.force = true
				var interior := _home.get_node("Interior") as Node3D
				_check(interior.visible, "today's furniture is in")
				_check(_home.toggle_door(&"Door_Front"), "the front door opens")
				_check(_other.is_active(), "and inside it's 1979")
				_check(late.event == &"other_house", "the late city is running the other house")
				_check(_other.portal_mode == 1, "from the doorstep, it's 1979 only through the door (mode %d)" % _other.portal_mode)
				_check(_sided(interior, 1) > 0 and _sided(interior, 0) == 0, "today's furniture shows only where 1979 doesn't (%d sided, %d not)" % [_sided(interior, 1), _sided(interior, 0)])
				_check(_home.find_child("House1979", false, false) != null, "the Dorans' things are in")
				_check(_retinted() > 0, "the walls and floors have a 1979 side (%d surfaces)" % _retinted())
				_check(story.has_night(&"other_house_1979"), "it's in the Nights log")
				_check(_other.interact_hint() == "Take the drawing", "the drawing on the fridge can be taken")
				var today := get_nodes_in_group(&"interactables").filter(func(n: Node) -> bool:
					return n != _other and _other._in_box(n.interact_point(), 0.0))
				_check(today.is_empty() and not _home.find_child("AnsweringMachine", false, false).is_in_group(&"interactables"),
					"today's things (the cat's bowl, the answering machine) can't be used in 1979 (%d can)" % today.size())
				_other.interact()
				_check(story.flag(&"drawing_1979"), "taking it is remembered")
			elif _frames == 200:
				# Walk in, then back out and shut the door.
				_put_player(_home.to_global(_H79.at(Vector3(2.5, 3.0, 0.2))))
			elif _frames == 240:
				_check(_other.is_active() and _other.portal_mode == 2, "all 1979 once you're inside (mode %d)" % _other.portal_mode)
				_put_player(_home.spawn_transform(&"Spawn_Front").origin + Vector3.UP * 0.1)
			elif _frames == 250:
				_home.toggle_door(&"Door_Front")
			elif _frames == 300:
				_check(not _other.is_active(), "out and the door shut: it's your house again")
				_check(_home.find_child("AnsweringMachine", false, false).is_in_group(&"interactables"), "and today's things can be used again")
				_check(_sided(_home.get_node("Interior"), 1) == 0 and _other.portal_mode == 0, "today's furniture is plain again")
				_check(_retinted() == 0, "and the walls are yours")
				_check(not late.active(), "the late city has let go")
				# Opening from inside never does it.
				_put_player(_home.to_global(_H79.at(Vector3(1.0, 1.5, 0.2))))
			elif _frames == 320:
				_home.toggle_door(&"Door_Front")
				_check(not _other.is_active(), "opening the door from inside changes nothing")
				_home.toggle_door(&"Door_Front")
				_other.force = false
				_next()
		2:  # The parcel for M. Doran turns up on the board late at night.
			if _frames == 1:
				clock.set_time(23.0)
				_road.force = true
				story.load_state({})
				_road._maybe_offer()
				var job := _story_job()
				_check(not job.is_empty(), "the parcel job is on the board")
				_check(root.get_node("Jobs").offers.size() > 0 and root.get_node("Jobs").offers[0] == job, "at the top")
				var md: MapData = MapData.shared()
				md.wait()
				var street := md.street_at(_ER.DROPOFF)
				_check(street == "May Drive", "it goes to May Drive ('%s')" % street)
				_route = md.routes.find(Vector3(-912.0, 67.0, 926.0), Vector2.ZERO, _ER.DROPOFF).get("points", PackedVector3Array())
				_check(_route.size() > 2, "there's a way there by road")
				if _route.size() < 3 or job.is_empty():
					return _finish()
				_player.call("get_in")
			elif _frames == 360:
				_check(_player.get("in_car") == true and _car.player_controlled, "back in the car")
				_start_run()
				_run_from = _frames
			elif _frames > 360:
				return _road_run(late, story)
		3:  # The people, the answering machine, choices 1 and 2.
			var switch: Node = _home.find_child("PorchSwitch", false, false)
			if _frames == 1:
				_people(story, clock)
				# The porch switch is the plate by the front door, on the hinge
				# side: with the door open the door covers it, shut you can use it.
				# Not from outside, and not through a wall.
				if not _home.is_door_open(&"Door_Front"):
					_home.toggle_door(&"Door_Front")
				_put_player(_home.to_global(_H79.at(Vector3(0.9, 1.0, 0.2))))
			elif _frames == 60:
				_player.face(switch.interact_point())
			elif _frames == 62:
				var t: Array = _player._target()
				_check(t[0] == "door" and t[1] == &"Door_Front", "with the front door open, the door covers the porch switch (%s)" % [t[0]])
				_home.toggle_door(&"Door_Front")
			elif _frames == 110:
				_player.face(switch.interact_point())
			elif _frames == 112:
				var t: Array = _player._target()
				_check(t[0] == "thing" and t[1] == switch, "with it shut, the porch switch can be used from the hall (%s)" % [t[0]])
				_check(switch.interact_hint().begins_with("Porch light"), "and says it's the porch light ('%s')" % switch.interact_hint())
				var plate: Node3D = _home.find_child("Dress_Switch_Front*", true, false)
				_check(plate != null and not plate.is_visible_in_tree(), "the house's own plate makes way for it")
				_home.toggle_door(&"Door_Front")
				_put_player(_home.to_global(_H79.at(Vector3(0.9, -1.6, 0.2))))
			elif _frames == 160:
				_player.face(switch.interact_point())
			elif _frames == 162:
				_check(_player._nearest_thing() != switch, "but not from the step outside")
				_home.toggle_door(&"Door_Front")
				_put_player(_home.to_global(_H79.at(Vector3(0.3, -0.35, 0.2))))
			elif _frames == 220:
				_player.face(switch.interact_point())
			elif _frames == 222:
				var d: float = _player.global_position.distance_to(switch.interact_point())
				_check(_player._nearest_thing() != switch, "nor through the wall from the porch with the door shut (%.1f m away)" % d)
				_next()
		4:  # Batch 3: the events that come later in the story.
			if _frames == 1:
				_later_events(story, late, clock)
				_player.call("get_out")
			elif _frames == 150:
				# Act 3: through the door, the house is empty and sheeted.
				story.act_override = 3
				clock.set_time(1.0)
				_put_player(_home.spawn_transform(&"Spawn_Front").origin + Vector3.UP * 0.1)
			elif _frames == 170:
				_other.force = true
				_home.toggle_door(&"Door_Front")
				_check(_other.is_active() and _other.form == &"abandoned", "act 3: through the door the house is abandoned ('%s')" % _other.form)
				_check(_home.find_child("HouseAbandoned", false, false) != null, "the sheets and leaves are in")
				_check(_other.interact_hint() == "Pick up the cassette", "the tape on the stairs can be picked up ('%s')" % _other.interact_hint())
				_other.interact()
				_check(story.has_night(&"stairs_tape") and root.get_node("Discoveries").has("mystery/stairs_tape"),
					"picking it up is a clue and a night")
				_check(_other.interact_hint() == "", "and it's only there once")
			elif _frames == 180:
				_home.toggle_door(&"Door_Front")
			elif _frames == 230:
				_check(not _other.is_active() and _home.find_child("HouseAbandoned", false, false) == null, "door shut: your house again")
				_other.force = false
				story.act_override = 0
				_next()
		5:
			if _act_4(story, clock):
				_next()
		6:
			if _robyn_and_tapes(story, clock):
				_next()
		7:
			if _street_1979(story, clock):
				_next()
		8:
			if _finale(story, clock):
				_next()
		9:
			if _endings(story, clock):
				_next()
		10:
			return _finish()
	return false


func _people(story: Node, clock: Node) -> void:
	var people := _main.find_child("StoryPeople", true, false)
	var machine: Node = _home.find_child("AnsweringMachine", false, false)
	var switch: Node = _home.find_child("PorchSwitch", false, false)
	_check(people != null and machine != null and switch != null, "the answering machine and the porch switch are in the house")
	if people == null or machine == null or switch == null:
		return
	_check((people.messages as Array).size() >= 14, "the messages are loaded (%d)" % (people.messages as Array).size())
	story.load_state({})
	story.act_override = 1
	clock.set_time(10.0)
	_check(machine.interact_hint() == "", "nothing on the machine in a new game")
	# The first message turns up on its own.
	people.set("_last_left_day", -1)
	people._maybe_message()
	_check(story.has_message(&"kostas_welcome"), "Mrs Kostas says welcome on the first day")
	_check(story.unheard_messages() == 1, "one message waiting")
	people._maybe_message()
	_check(story.unheard_messages() == 1, "and only one a day")
	_check(not people.ready_to_leave({"act": 2}), "a later act's message waits for its act")
	_check(not people.ready_to_leave({"act": 1, "needs": ["deliveries:999"]}), "and messages wait for what they need")
	_check(not story.leave_message(&"kostas_welcome", "x", "y"), "a message is only left once")
	_check(machine.interact_hint() == "Play messages (1)", "the machine offers to play it ('%s')" % machine.interact_hint())
	machine.interact()
	_check(story.unheard_messages() == 0 and story.heard(&"kostas_welcome"), "playing it marks it heard")
	_check(machine.interact_hint() == "" or machine.interact_hint() == "Play the last message", "then it offers the last one again")
	var saved: Dictionary = story.save_state()
	story.load_state({})
	_check(story.messages.is_empty(), "loading an empty save clears the machine")
	story.load_state(saved)
	_check(story.heard(&"kostas_welcome"), "and the save brings the messages back, heard")
	# Choice 1: the porch light. A spot lights the step (the house's own omni
	# lamp there lit the hall through the wall).
	var spot: Variant = people.get("_porch_lamp")
	var omni: Variant = people.get("_house_lamp")
	_check(spot is SpotLight3D and omni is OmniLight3D and (omni as OmniLight3D).light_energy == 0.0, "the porch is lit by a spot, not the omni that lit the hall")
	_check(switch.interact_hint() == "Porch light: turn off", "the porch light is on to start with")
	switch.interact()
	_check(not people.porch_light_on and switch.interact_hint() == "Porch light: turn on", "the switch turns it off")
	switch.interact()
	_check(people.porch_light_on, "and on again")
	story.act_override = 3
	clock.set_time(1.0)
	_check(people.ready_to_leave({"act": 3, "late": true}), "late messages come after midnight")
	clock.set_time(14.0)
	_check(not people.ready_to_leave({"act": 3, "late": true}), "not in the afternoon")
	story.leave_message(&"porch_light", "No caller", "Leave the porch light on.", true)
	clock.set_time(2.75)
	people._maybe_porch_check()
	_check(story.choice(&"porch_light") == &"", "not checked the same night it was asked")
	story.message(&"porch_light").day = int(clock.day) - 2
	people._maybe_porch_check()
	_check(story.choice(&"porch_light") == &"on", "left on at twenty to three the next night: choice 1 is 'on'")
	_check(story.has_night(&"porch_light_on"), "and it's in the Nights log")
	# Choice 2: the thirteen to the buyer (the bird thread's lab pays).
	story.make_choice(&"thirteen", &"buyer")
	_check(story.has_night(&"thirteen_buyer"), "selling the thirteen is in the Nights log")
	# The endings.
	story.set_ending(&"lights_out")
	story.set_ending(&"sideways")
	_check(story.ending() == &"lights_out" and story.ending_day() == int(clock.day), "an ending is remembered, with its day")
	var with_ending: Dictionary = story.save_state()
	story.load_state({})
	_check(story.ending() == &"" and story.ending_day() == -1, "no ending in a new game")
	story.load_state(with_ending)
	_check(story.ending() == &"lights_out", "and the save keeps it")
	# The act cards.
	people.card_act = 1
	people._maybe_card()
	_check(int(people.card_act) == 3 and people.get("_card").showing(), "a new act shows its card (Side C)")
	story.act_override = 0
	# The midnight station's finds count for the story challenges.
	var progression := root.get_node("Progression")
	var discoveries := root.get_node("Discoveries")
	var clues: float = progression.get_stat("clues_found")
	discoveries.discover("mystery/polaroid")
	discoveries.discover("mystery/solved")
	_check(progression.get_stat("clues_found") == clues + 1.0, "a find counts as a clue, the ending doesn't (%.0f -> %.0f)" % [clues, progression.get_stat("clues_found")])
	var story_challenges := 0
	for tier: Dictionary in progression.tiers:
		for c: Dictionary in tier.challenges:
			if c.stat == "clues_found":
				story_challenges += 1
	_check(story_challenges == 5, "one story challenge in each tier (%d)" % story_challenges)


## The events of batch 3 that can be checked in one go: the headlight
## flash, the stopped clock, the minimap passenger, the lookouts answering,
## the station knowing where you are, the repeat street finding a street,
## and looking out of the window.
## Act 4: the house turns. True when it's done.
func _act_4(story: Node, clock: Node) -> bool:
	var front: Vector3 = _home.spawn_transform(&"Spawn_Front").origin
	var door_x: float = _home.to_local(front).x
	var hall: Vector3 = _home.to_global(_H79.at(Vector3(2.5, 3.0, 0.2)))
	var doorway: Vector3 = _home.to_global(_H79.at(Vector3(door_x, 0.4, 0.05)))
	var acts := root.get_node("Activities")
	match _frames:
		1:
			story.act_override = 4
			clock.set_time(1.0)
			_put_player(front + Vector3.UP * 0.1)
		20:
			_other.force = true
			_other.force_form = &"darkroom"
			_home.toggle_door(&"Door_Front")
			var room: Node = _home.find_child("HouseDarkroom", false, false)
			_check(_other.is_active() and _other.form == &"darkroom" and room != null, "act 4: the darkroom ('%s')" % _other.form)
			_check(room != null and room.takeable.size() == room.UNSEEN, "with prints of places you haven't been (%d)" % (room.takeable.size() if room else -1))
			_check(story.has_night(&"other_house_darkroom") and _retinted() > 0, "it's in the Nights log, and the walls have turned")
			_put_player(hall)
		60:
			_check(_other.portal_mode == 2, "all darkroom once you're inside (mode %d)" % _other.portal_mode)
			_check(_other.interact_hint() == "Take the print", "a print can be taken ('%s')" % _other.interact_hint())
			var had: int = acts.photos.size()
			_other.interact()
			_check(acts.photos.size() == had + 1 and story.flag(&"darkroom_print"), "it goes in the album (%d to %d)" % [had, acts.photos.size()])
			_check(story.has_night(&"darkroom_print"), "and in the Nights log")
			_put_player(front + Vector3.UP * 0.1)
		70:
			_home.toggle_door(&"Door_Front")
		120:
			_check(not _other.is_active() and _home.find_child("HouseDarkroom", false, false) == null and _retinted() == 0, "door shut: your house again")
			_other.force_form = &"river"
			_home.toggle_door(&"Door_Front")
			var river: Node = _home.find_child("HouseRiver", false, false)
			_check(_other.is_active() and river != null and river.birds.size() == 5, "the river, birds on the rail (%d)" % (river.birds.size() if river else -1))
			_check(_other.interact_hint() == "" and story.has_night(&"other_house_river"), "nothing to take, and it's in the Nights log")
		130:
			_home.toggle_door(&"Door_Front")
		180:
			_check(not _other.is_active() and _home.find_child("HouseRiver", false, false) == null, "and shut again")
			_other.force_form = &"lane"
			_home.toggle_door(&"Door_Front")
			_check(_other.is_active() and _retinted() == 0 and _other.portal_mode == 0, "the lane: from outside the house is only itself")
			_put_player(doorway)
		220:
			var away: float = _player.global_position.distance_to(front)
			_check(_other._moved and absf(away - _OH.LANE_ALONG) < 6.0, "stepping in puts you down the lane (%.0f m from the door)" % away)
			_check(not _home.is_door_open(&"Door_Front") and story.has_night(&"other_house_lane"), "the door's shut behind you, and it's in the Nights log")
			_check(_other.is_active(), "and it holds while you're there")
			_put_player(front + Vector3.UP * 0.1)
		240:
			_check(not _other.is_active() and story.has_night(&"lane_again"), "walking back to the front door ends it")
			_other.force_form = &"shed"
			_home.toggle_door(&"Door_Front")
			_put_player(doorway)
		280:
			var stand := _home.find_child("Shed_Ending", true, false) as Node3D
			var sheet := _home.find_child("Shed_Sheeted", true, false) as Node3D
			var d: float = _player.global_position.distance_to(stand.global_position)
			_check(_other._moved and d < 1.0, "stepping in puts you in the shed (%.1f m from the table)" % d)
			_check(not sheet.visible and _home.find_child("ShedNight", false, false) != null, "the sheet's off the table")
			_check(_other.interact_hint() == "Go back out" and story.has_night(&"other_house_shed"), "its door goes back out ('%s')" % _other.interact_hint())
			_player.face(_home.find_child("Shed_Door", true, false).global_position + Vector3.UP * 1.0)
		282:
			var t: Array = _player._target()
			_check(t[0] == "thing" and t[1] == _other, "looking at the shed door, it's the way out, not the lock (%s)" % [t[0]])
			var sheet := _home.find_child("Shed_Sheeted", true, false) as Node3D
			_player.interact()
			_check(not _other.is_active() and sheet.visible, "and out you come, the shed as it was")
			_check(_other._in_box(_player.global_position, 0.0), "into your own hall")
		290:
			_check(_home.find_child("ShedNight", false, false) == null, "the shed's things are gone")
			_other.force = false
			_other.force_form = &""
			_other.last_form = &"river"
			var picked := {}
			for i in 40:
				var f: StringName = _other._pick_form()
				picked[f] = true
			_check(not picked.has(&"river") and picked.size() == 3, "never the same one twice running (%s)" % [picked.keys()])
			var saved: Dictionary = _other.save_state()
			_other.last_form = &""
			_other.load_state(saved)
			_check(_other.last_form == &"river", "the last one is saved")
			story.act_override = 0
			return true
	return false


## Act 4, part 2: Robyn (choice 3) and the tapes that run ahead. True when done.
func _robyn_and_tapes(story: Node, clock: Node) -> bool:
	var robyn: Node = _main.find_child("Robyn", true, false)
	var tape: Node = _main.find_child("TapeAhead", true, false)
	var jobs := root.get_node("Jobs")
	match _frames:
		1:
			_check(robyn != null and tape != null, "Robyn and the tapes are in the world")
			if robyn == null or tape == null:
				return true
			story.act_override = 4
			clock.set_time(13.0)
			story.leave_message(&"kostas_robyn", "Thea", "She still sends a card from Fremantle.")
			story.message(&"kostas_robyn").heard = true
		5:
			_check(robyn.step == robyn.ASKING, "after Thea's message you can ask around for Robyn")
			_check(String(robyn.challenge_card().get("title", "")) == "Robyn, in Fremantle", "and the card says so")
			robyn.ask("delivery")
			_check(robyn.step == robyn.ASKING and String(robyn.challenge_card().line).contains("Fishing Boat Harbour"),
				"a delivery to the markets points you to the harbour")
			robyn.ask("harbour")
			_check(robyn.step == robyn.KNOWN and story.has_night(&"robyn_street"), "the harbour knows her street")
			_check(String(robyn.challenge_card().get("title", "")) == "Arundel Street, Fremantle", "the card says where")
			# On foot in Arundel Street.
			_player.call("get_in")
		20:
			_car.teleport(Transform3D(Basis.looking_at(Vector3(0.765, 0, -0.644), Vector3.UP), robyn.ROAD_AT + Vector3.UP * 1.0))
		120:
			_player.call("get_out")
		300:
			var door: Node3D = robyn.get("_house")
			_check(door != null, "her front door is on the cottage")
			if door == null:
				story.act_override = 0
				return true
			var from_road: float = Vector2(door.global_position.x - robyn.ROAD_AT.x, door.global_position.z - robyn.ROAD_AT.z).length()
			_check(from_road > 5.0 and from_road < 16.0, "on the wall across the footpath (%.1f m from the road)" % from_road)
			_check(robyn.interact_hint() == "Knock", "you can knock ('%s')" % robyn.interact_hint())
			(root.get_node("Discoveries").get("_found") as Dictionary).erase("mystery/polaroid")
			robyn.knock()
			_check(robyn.step == robyn.KNOWN and story.has_night(&"robyn_no_answer"), "without the Polaroid nobody answers")
			clock.set_time(23.0)
			robyn.knock()
			_check(robyn.step == robyn.KNOWN, "nor this late")
			clock.set_time(13.0)
			root.get_node("Discoveries").discover("mystery/polaroid")
			robyn.knock()
			_check(robyn.step == robyn.FOUND and story.choice(&"robyn") == &"found", "with it she opens the door: choice 3, found")
			_check(story.flag(&"gave_polaroid") and story.has_night(&"robyn_found"), "the Polaroid's hers now, and it's in the Nights log")
			_check(robyn.challenge_card().is_empty(), "and the card's done")
			var saved: Dictionary = robyn.save_state()
			robyn.load_state({})
			robyn.load_state(saved)
			_check(robyn.step == robyn.FOUND, "it's saved")
		400:
			# The tapes: a cassette in the deck at night...
			_player.call("get_in")
			clock.set_time(23.5)
			tape.force = true
			_check(tape.maybe_play(), "a tape in the deck at night")
			_check(not (tape.pending as Dictionary).is_empty() and story.has_night(StringName("tape_ahead_%d" % clock.day)), "describing a drive, in the Nights log")
			_check(not tape.maybe_play(), "only one tape at a time")
			_check(not jobs.offers.any(func(j: Dictionary) -> bool: return j.get("story", "") == "tape_ahead"), "not on the board yet")
			# ...and the morning after, the job he described.
			tape.due_day = clock.day
			clock.set_time(7.0)
		420:
			var offered: Array = jobs.offers.filter(func(j: Dictionary) -> bool: return j.get("story", "") == "tape_ahead")
			_check(offered.size() == 1 and jobs.offers[0] == offered[0], "next morning it's at the top of the board")
			if offered.is_empty():
				tape.force = false
				story.act_override = 0
				return true
			_check(String(offered[0].get("icon", "")) == "reel", "with a reel by it")
			_check(String(offered[0].pickup) == String(tape.pending.pickup) and String(offered[0].dropoff) == String(tape.pending.dropoff), "the same drive as the tape")
			jobs.accept(offered[0])
			jobs.active.stage = "to_dropoff"
			jobs._stage_changed()
			var drop: Node3D = jobs.site(String(jobs.active.dropoff))
			_car.teleport(Transform3D(Basis(), drop.global_position + drop.global_basis.z * 30.0 + Vector3.UP * 1.5))
		500:
			var cat: Node3D = tape.get("_cat")
			_check(cat != null and cat.find_child("Cat", false, false) != null, "near the drop-off, a ginger cat on a fence")
			var job: Dictionary = jobs.active.duplicate()
			jobs.abandon()
			jobs.job_completed.emit(job, 40, "Delivered.")
			_check(tape.get("_cat") == null and (tape.pending as Dictionary).is_empty(), "done: the cat's gone, nothing waiting")
			_check(story.has_night(StringName("tape_ahead_done_%d" % clock.day)), "exactly as he said, in the Nights log")
			tape.force = false
			story.act_override = 0
			return true
	return false


## The 1979 street, on William Street in Northbridge.
func _street_1979(story: Node, clock: Node) -> bool:
	var st: Node = _main.find_child("Street1979", true, false)
	match _frames:
		1:
			_check(st != null, "the 1979 street is in the world")
			if st == null:
				return true
			# Dressing a car and undressing it again.
			var old: Node = load("res://scripts/world/late_city/traffic_1979.gd").new()
			root.add_child(old)
			var body := Node3D.new()
			var own := MeshInstance3D.new()
			own.name = "Mesh"
			body.add_child(own)
			root.add_child(body)
			old.dress(body, &"sedan", 7, null)
			_check(not own.visible and body.get_node_or_null(^"Late1979") != null, "a car can be dressed as a 1979 one")
			old.undress(body)
			_check(own.visible and body.get_node_or_null(^"Late1979") == null, "and undressed")
			body.free()
			old.free()
			story.act_override = 4
			clock.set_time(1.0)
			if _player.get("in_car") == false:
				_player.call("get_in")
		30:
			var path := _william_street()
			_check(path.size() >= 2, "William Street goes through Northbridge (%d points)" % path.size())
			if path.size() < 2:
				story.act_override = 0
				return true
			var cum := TrafficGraph.cumulative(path)
			var t := TrafficGraph.tangent_at(path, cum, 10.0)
			var dir := Vector3(t.x, 0.0, t.z).normalized()
			_car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), TrafficGraph.point_at(path, cum, 10.0) + TrafficGraph.left_of(dir) * -1.8 + Vector3.UP))
		330:
			st.force = true
			_check(st._ready_to_start(), "a street of shops ahead (%s, %d shops)" % [st.street, (st.shops as Array).size()])
			_check((st.shops as Array).size() >= 3, "with shopfronts found on its walls")
			_check(st.begin() and root.get_node("LateCity").event == &"street_1979", "the deck clicks on")
		420:
			_check(st.turned, "and the street turns")
			var root3d: Node3D = st.get("_root")
			_check(root3d != null and root3d.visible and root3d.get_child_count() > 0, "the shops have their old names (%d)" % (root3d.get_child_count() if root3d else 0))
			var venues: Array = st.get("_venues")
			_check(venues.all(func(v: Node3D) -> bool: return not v.visible), "today's venue fronts are gone (%d)" % venues.size())
			var old: Node = st.get("_old")
			_check(old != null and old.count() > 0, "the cars are 1979 cars (%d)" % (old.count() if old else 0))
			_check(st.extra > 0, "and more of them come along the street (%d)" % st.extra)
			var pairs: Array = old.models() if old else []
			var own_hidden := pairs.all(func(pair: Array) -> bool:
				var m: Node3D = (pair[0] as Node3D).get_node_or_null(^"Model")
				return m == null or not m.visible)
			_check(own_hidden, "and today's cars under them are hidden")
			# Near the end of the street.
			var path: PackedVector3Array = st._path
			var cum: PackedFloat32Array = st._cum
			var s: float = cum[cum.size() - 1] - 6.0
			var t := TrafficGraph.tangent_at(path, cum, s)
			var dir := Vector3(t.x, 0.0, t.z).normalized()
			_car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), TrafficGraph.point_at(path, cum, s) + TrafficGraph.left_of(dir) * -1.8 + Vector3.UP))
			st._at = maxi(path.size() - 20, 0)
			# Forced, it would only start again on what's left of the street.
			st.force = false
		480:
			_check(not st.running and root.get_node("LateCity").event == &"",
				"at the end of the street it's now again (%s)" % root.get_node("LateCity").event)
			_check(story.has_night(StringName("street_1979_%d" % clock.day)) and root.get_node("Discoveries").has("oddity/street_1979"), "it's in the Nights log")
			var leftover := 0
			for traffic: Node in get_nodes_in_group(&"traffic"):
				for body: Node in traffic.find_children("*", "Node3D", true, false):
					if body.name == &"Late1979" and not body.is_queued_for_deletion():
						leftover += 1
			_check(leftover == 0, "every car is today's again (%d left)" % leftover)
			var venues: Array = st.get("_venues")
			_check(venues.is_empty(), "and the venues are back")
			st.force = false
			story.act_override = 0
			return true
	return false


## Act 5: the night of 11 July and choice 4.
var _fin  # Finale
var _fin_night := 0


func _finale(story: Node, clock: Node) -> bool:
	var mystery: Node = _main.find_child("Mystery", true, false)
	var people: Node = _main.find_child("StoryPeople", true, false)
	match _frames:
		1:
			_fin = _main.find_child("Finale", true, false)
			_check(_fin != null and mystery != null, "the finale is in the world")
			if _fin == null or mystery == null:
				return true
			_check(_fin.night_day == -1 and not _fin.is_night(), "no 11th before the shed's open")
			story.load_state({})
			story.act_override = 5
			clock.set_time(14.0)
			_car.teleport(_home.spawn_transform(&"Spawn_Car"))
		30:
			_player.call("get_out")
		150:
			_home.unlock_shed()
			if not _home.is_door_open(&"Shed_Door"):
				_home.toggle_door(&"Shed_Door")
			var centre: Vector3 = mystery._shed_centre()
			var door := _home.find_child("Shed_Door", true, false) as Node3D
			var feet := centre + (door.global_position - centre).normalized() * 1.2
			feet.y = _home.global_position.y + 0.05
			_player.teleport(feet, centre + Vector3.UP * 0.8)
		270:
			_check(mystery.is_solved, "walking into the shed opens it")
			_check(_fin.night_day == clock.day + _fin.DAYS_TO, "the 11th is a week away (day %d, today %d)" % [_fin.night_day, clock.day])
			var notes: PackedStringArray = mystery.notes()
			_check(notes.size() > 0 and "July 1979" in notes[0] and "in 7 days" in notes[0], "the phone says when ('%s')" % (notes[0] if notes.size() else ""))
			var table: Node = _fin.get("_table")
			_check(table != null and table.is_in_group(&"interactables"), "M.'s table can be used")
			if table == null:
				return true
			var page: Texture2D = null
			for mi: MeshInstance3D in mystery._shed_props.find_children("*", "MeshInstance3D", true, false):
				for i in mi.mesh.get_surface_count():
					var m := mi.get_active_material(i) as ShaderMaterial
					if m and m.resource_name.to_lower() == "sr_calendar":
						page = m.get_shader_parameter("albedo_texture")
			_check(page != null and page.resource_path == _fin.CALENDAR, "the calendar on the wall is turned to July")
			# Standing at the table, where the chair would be.
			var feet: Vector3 = table.to_global(Vector3(0.0, 0.05, -0.75))
			_player.teleport(feet, table.to_global(table.THINGS[&"mic"]))
		271:
			var table: Node = _fin.get("_table")
			_player.face(table.to_global(table.THINGS[&"mic"]))
		272:
			var table: Node = _fin.get("_table")
			_check(_player._nearest_thing() == table, "the table can be used from in the shed")
			_check(table.looked_at() == &"mic" and table.interact_hint() == "Microphone", "looking at the microphone ('%s')" % table.interact_hint())
			_player.face(table.to_global(table.THINGS[&"tx"]))
		274:
			var table: Node = _fin.get("_table")
			_check(table.looked_at() == &"tx" and table.interact_hint() == "Transmitter", "and at the transmitter ('%s')" % table.interact_hint())
			table.interact()
			_check(_fin.chose_on == -1 and story.choice(&"eleventh_july") == &"", "not the night yet: nothing happens")
			# Two days before the 11th, the messages start.
			_fin_night = _fin.night_day
			clock.day = _fin_night - 2
		310:
			_check(story.flag(&"eleventh_soon"), "two days before the 11th")
			var by_id := {}
			for m: Dictionary in people.messages:
				by_id[m.id] = m
			_check(people.ready_to_leave(by_id["kostas_july"]) and people.ready_to_leave(by_id["dee_skylab"]),
				"Thea and Dee leave their messages about the 11th")
			_check(not people.ready_to_leave(by_id["robyn_eleventh"]), "Robyn's only if you found her")
			_check(not people.ready_to_leave(by_id["eleventh_late"]), "the late one waits for the night")
			clock.day = _fin_night
			clock.set_time(19.0)
		340:
			_check(_fin.is_night() and story.flag(&"eleventh_night"), "the evening of the 11th is the night")
			_check(_fin.get("_card_day") == _fin_night, "a card says it's the 11th")
			var table: Node = _fin.get("_table")
			_player.face(table.to_global(table.THINGS[&"mic"]))
		342:
			var table: Node = _fin.get("_table")
			_check(table.interact_hint() == "Microphone: ask the city to leave its lights on", "the microphone ('%s')" % table.interact_hint())
			_player.face(table.to_global(table.THINGS[&"deck"]))
		344:
			var table: Node = _fin.get("_table")
			_check(table.interact_hint() == "Deck: the record key won't go down", "the deck won't record if the porch light wasn't answered ('%s')" % table.interact_hint())
			table.interact()
			table.interact()
			_check(_fin.chose_on == -1, "and pressing it does nothing")
			story.make_choice(&"porch_light", &"on")
			_check(table.interact_hint() == "Deck: record NIGHT DRIVE 13", "answered, it will ('%s')" % table.interact_hint())
			_player.face(table.to_global(table.THINGS[&"tx"]))
		346:
			var table: Node = _fin.get("_table")
			_check(table.interact_hint() == "Transmitter: switch it off for good", "the transmitter ('%s')" % table.interact_hint())
			# Lights on with too little of the city lit: Half Light.
			_check(_fin.lit() < _fin.lit_needed(), "not enough of the city is lit yet (%d of %d)" % [_fin.lit(), _fin.lit_needed()])
			var need: int = _fin.lit_needed()
			story.make_choice(&"thirteen", &"buyer")
			_check(_fin.lit_needed() == need + _fin.LIT_SOLD, "selling the thirteen means more of it needs to be")
			_fin.use_table(&"mic")
			_check(_fin.chose_on == -1 and _fin.table_hint(&"mic").begins_with("Again to be sure."), "once asks to be sure")
			_fin.use_table(&"mic")
			_check(story.choice(&"eleventh_july") == &"lights_on" and story.ending() == &"half_light", "twice: lights on, Half Light ('%s')" % story.ending())
			_check(not _fin.done() and _fin.chose_tonight(), "which isn't the end")
			_fin.use_table(&"tx")
			_fin.use_table(&"tx")
			_check(story.ending() == &"half_light", "and only once a night")
			clock.day = _fin_night + 1
			clock.set_time(4.0)
		380:
			_check(_fin.night_day == _fin_night + _fin.AGAIN and _fin.nights_missed == 0, "after the night the 11th comes round again (day %d)" % _fin.night_day)
			_check("comes round again" in _fin.notes_line(), "the phone says so ('%s')" % _fin.notes_line())
			# Missed altogether.
			_fin_night = _fin.night_day
			clock.day = _fin_night + 1
			clock.set_time(4.0)
		410:
			_check(_fin.nights_missed == 1 and _fin.night_day == _fin_night + _fin.AGAIN, "a missed 11th comes round again too")
			_check(story.has_night(StringName("eleventh_missed_%d" % _fin_night)), "and it's in the Nights log")
			_fin_night = _fin.night_day
			clock.day = _fin_night
			clock.set_time(21.0)
			# Enough of the city lit: City of Light.
			root.get_node("Progression").add_stat("deliveries", float(_fin.lit_needed()))
			_fin.choose(&"lights_on")
			_check(story.ending() == &"city_of_light" and _fin.done(), "lights on with the city lit: City of Light")
			_check(_fin.table_hint(&"mic") == "" and not _fin.is_night(), "and that's the end of the 11ths")
			# Night Drive 13.
			_fin_reset(story)
			_fin.use_table(&"deck")
			_fin.use_table(&"deck")
			_check(story.choice(&"eleventh_july") == &"tape_13" and story.ending() == &"night_drive_13", "recording the tape: Night Drive 13")
			# Lights Out.
			_fin_reset(story)
			_fin.use_table(&"tx")
			_fin.use_table(&"tx")
			_check(story.ending() == &"lights_out", "switching it off: Lights Out")
			var lamps := 0
			for mi: MeshInstance3D in mystery._shed_props.find_children("*", "MeshInstance3D", true, false):
				for i in mi.mesh.get_surface_count():
					var m := mi.get_active_material(i) as ShaderMaterial
					if m and m.resource_name == "Lamp" and float(m.get_shader_parameter("emission_energy")) > 0.0:
						lamps += 1
			_check(lamps == 0, "the red lights go out (%d still lit)" % lamps)
			_check("static" in mystery.notes()[0], "the phone says so ('%s')" % mystery.notes()[0])
			# Dee and Skylab.
			_fin_reset(story)
			var radio: Object = root.get_node("Audio").get("radio")
			if radio:
				radio.call("set_station", "nottefm")
				_fin._dee(1.0)
				_fin._dee(10.0)
				_check(int(_fin.get("_dee_said")) == 1, "Dee talks about Skylab on Notte FM")
			_fin.skylab()
			_check(_fin.get("_skylab") != null and root.get_node("Discoveries").has("oddity/skylab"), "Skylab comes down again")
		440:
			# Into the lights on Riverside Drive. First with the porch light off.
			_put_player(_car.global_position + _car.global_basis.x * 1.6 + Vector3.UP * 0.5)
		450:
			_player.call("get_in")
		520:
			_check(_player.get("in_car") == true, "back in the car")
			var at: Vector3 = _fin.get("_drive_in")
			var md: MapData = MapData.shared()
			md.wait()
			_check(md.street_at(at) == "Riverside Drive", "the lights come down on Riverside Drive ('%s')" % md.street_at(at))
			people.porch_light_on = false
			clock.day = _fin_night + 1
			clock.set_time(2.8)
			_car.teleport(Transform3D(Basis(), at + Vector3.UP * 1.2))
		600:
			_check(_fin.is_night() and not _fin.drive_in_open() and _fin.get("_road_lights") == null, "porch light off: they stay over the water")
			var odd: Node = _main.find_child("Oddities", true, false)
			var lights: Node3D = odd.get("_lights")
			_check(lights != null and lights.get_node_or_null(^"RainUp") != null, "in act 5 the rain over the river lights falls upwards")
			var big := 0
			if lights:
				for orb in lights.get_children():
					if orb is MeshInstance3D and orb.scale.x > 1.5:
						big += 1
			_check(big > 0, "and on the 11th they're bigger and brighter (%d)" % big)
			_check(_fin.get("_skylab") != null, "Skylab is still going over")
			_fin._move_skylab(20.0)
			_check(_fin.get("_skylab") == null, "and then it's gone")
			people.porch_light_on = true
		640:
			_check(story.choice(&"eleventh_july") == &"went_in" and story.ending() == &"late_city", "porch light on: into the lights, The Late City ('%s')" % story.ending())
			_check(story.has_night(&"eleventh_went_in") and _fin.get("_road_lights") == null, "in the Nights log, and the lights are gone")
			var state: Dictionary = _fin.save_state()
			_fin.load_state({})
			_check(_fin.night_day == -1, "loading an empty save clears it")
			_fin.load_state(JSON.parse_string(JSON.stringify(state)))
			_check(_fin.save_state() == state, "and it saves and loads")
			story.load_state({})
			story.act_override = 0
			clock.set_time(14.0)
			return true
	return false


## The endings: each scene, played quickly, and what it leaves behind.
var _end  # Endings
var _end_lit := 0


func _endings(story: Node, clock: Node) -> bool:
	var late := root.get_node("LateCity")
	match _frames:
		1:
			_end = _main.find_child("Endings", true, false)
			_check(_end != null, "the endings are in the world")
			if _end == null or _fin == null:
				return true
			_end.finish_scene()
			_check(not _end.playing(), "a scene can be played through")
			# City of Light.
			_fin_reset(story)
			clock.day = _fin.night_day
			clock.set_time(23.0)
			_check(_fin.lit() >= _fin.lit_needed(), "enough of the city is lit")
			_fin.choose(&"lights_on")
			_check(_end.playing(), "City of Light plays")
			_end.finish_scene()
			_end_lit = _end.lights_left_on()
			_check(_end_lit > 0, "the regulars leave their lights on (%d)" % _end_lit)
			_check(story.has_night(&"mick_last_tape"), "Mick's last tape")
			_check(late.gone() and late.flicker_level() == 0 and not late.allowed_now(), "the late city is gone, the birds don't flicker")
			clock.day = _fin.night_day + 1
			clock.set_time(7.0)
		40:
			_check(_end.lights_left_on() == 0, "in the morning the lights are off again")
			var radio: Object = root.get_node("Audio").get("radio")
			clock.set_time(22.0)
			if radio:
				radio.call("set_station", "nottefm")
		80:
			if root.get_node("Audio").get("radio"):
				_check(_end.song_played and story.has_night(&"dee_song_for_mick"), "the next night Dee plays a song for Mick")
			# Half Light: fewer lights.
			_fin_reset(story)
			clock.day = _fin.night_day
			clock.set_time(23.0)
			_end._on_chosen(&"lights_on", &"half_light")
			_end.finish_scene()
			_check(_end.lights_left_on() > 0 and _end.lights_left_on() < _end_lit, "Half Light: only some lights (%d of %d)" % [_end.lights_left_on(), _end_lit])
			# Night Drive 13.
			_fin_reset(story)
			clock.set_time(23.0)
			_fin.choose(&"tape_13")
			_end.finish_scene()
			_check(_end.dawn_day == clock.day + 1 and not _end.mick_left, "the 500 L will be there at dawn")
			clock.day += 1
			clock.set_time(6.5)
		120:
			_check(_end.mick_left and _main.find_child("MicksCar", true, false) != null, "at dawn Mick's 500 L is at the end of the lane")
			var garage := root.get_node("Garage")
			_check(garage.owns_car("classic_500l") and root.get_node("Classics").can_drive("classic_500l"), "and it's yours to drive")
			_check(story.has_night(&"mick_home"), "in the Nights log")
			_check(not (_end.get("_old") != null and _end.get("_old").dressed), "the days are normal")
			clock.set_time(1.0)
		160:
			_check(_end.get("_old") != null and _end.get("_old").dressed, "after midnight the traffic's 1979")
			var st: Node = _main.find_child("Street1979", true, false)
			_check(not st._ready_to_start(), "so the 1979 street doesn't need to happen")
			clock.set_time(10.0)
		200:
			_check(not _end.get("_old").dressed, "and in the morning it's now again")
			# Lights Out: the late city fades over a few days.
			_fin_reset(story)
			clock.set_time(23.0)
			_fin.choose(&"switch_off")
			_end.finish_scene()
			_check(not late.gone(), "Lights Out: the late city doesn't go all at once")
			clock.day += late.FADE_DAYS + 1
			_check(late.gone() and late.flicker_level() == 0, "but it's gone a few days later")
			# The Late City.
			_fin_reset(story)
			clock.day = _fin.night_day + 1
			clock.set_time(2.8)
			_fin.choose(&"went_in")
			_check(_end.playing(), "The Late City plays")
		480:
			# The house from the lane, in 1979.
			var cam: Camera3D = (_main.get_node("LoFi/SubViewport") as Viewport).get_camera_3d()
			_check(cam != null and cam.name == &"LateCityCamera", "the house from the lane ('%s')" % (cam.name if cam else ""))
			_check(_main.find_child("SecondCar", true, false) != null, "two little cars in the carport")
			_check(_end.get("_old") != null and _end.get("_old").dressed, "1979")
			_end.finish_scene()
			_check(not _end.playing() and not _car.freeze, "after the credits you're back in the car")
			_check(story.has_night(&"late_city_credits"), "in the Nights log")
			clock.set_time(10.0)
		520:
			var carport: Transform3D = get_first_node_in_group(&"perth_map").get_spawn_transform()
			_check(absf(_car.global_position.y - carport.origin.y) < 0.8 and _car.linear_velocity.length() < 1.0,
				"the car is sitting in the carport, on the ground (%.2f m from its spot, %.1f m/s)" % [_car.global_position.distance_to(carport.origin), _car.linear_velocity.length()])
			_check(clock.time_of_day >= _end.EVENING - 0.01, "and it's always night (%.1f)" % clock.time_of_day)
			var state: Dictionary = _end.save_state()
			_end.load_state({})
			_end.load_state(JSON.parse_string(JSON.stringify(state)))
			_check(_end.save_state() == state, "the endings save and load")
			story.load_state({})
			story.act_override = 0
			clock.set_time(14.0)
		560:
			_check(not _end.get("_old").dressed, "with no ending, it's today again")
			return true
	return false


## Back to the night of the 11th with nothing chosen, the porch answered.
func _fin_reset(story: Node) -> void:
	story.load_state({})
	story.make_choice(&"porch_light", &"on")
	_fin.chose_on = -1


## William Street through Northbridge, up the strip of venues.
func _william_street() -> PackedVector3Array:
	var g := MapData.shared().routes
	var rs: GDScript = load("res://scripts/world/late_city/repeat_street.gd")
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
	var found: Dictionary = rs.street_ahead(at, heading, ["primary", "secondary", "tertiary"])
	return found.get("points", PackedVector3Array())


func _later_events(story: Node, late: Node, clock: Node) -> void:
	var events := {}
	for n in ["StoppedClock", "RepeatStreet", "MinimapPassenger", "LookoutSignal", "StationVoice", "LookingOut"]:
		events[n] = _main.find_child(n, true, false)
		_check(events[n] != null, "%s is in the world" % n)
	clock.set_time(1.0)
	# Inside, so opening the front door doesn't start the other house.
	_put_player(_home.to_global(_H79.at(Vector3(1.0, 1.5, 0.2))))
	# The headlight flash: on, brighter, then back as it was.
	var flashed := [false]
	var on_flash := func() -> void: flashed[0] = true
	_car.lights_flashed.connect(on_flash)
	var lights := _car.get_node_or_null("Headlights") as Node3D
	var was_on: bool = _car.headlights_on
	_car.flash_lights(true)
	_check(_car.flashing and flashed[0] and lights != null and lights.visible, "K flashes the headlights")
	_car.flash_lights(false)
	_check(not _car.flashing and lights.visible == was_on, "and lets them go")
	_car.lights_flashed.disconnect(on_flash)
	# The stopped clock: the dash and the phone say 02:40 while it runs.
	var sc: Node = events.StoppedClock
	sc.force = true
	_check(sc.begin(), "the stopped clock can start")
	_check(clock.shown_time_string() == "02:40" and clock.time_string() != "02:40", "the clocks say 02:40 (%s)" % clock.shown_time_string())
	sc._let_go()
	sc.force = false
	_check(clock.shown_time_string() == clock.time_string() and not late.active(), "and then the right time again")
	_check(story.has_night(&"stopped_clock"), "the stopped clock is in the Nights log")
	# The minimap passenger: a second arrow a way behind along the way you came.
	var mp: Node = events.MinimapPassenger
	var trail := PackedVector3Array()
	for i in 120:
		trail.append(_car.global_position + Vector3(0, 0, 2.0 * (120 - i)))
	mp._trail = trail
	mp.force = true
	_check(mp.begin(), "the minimap passenger can start")
	mp._gap = mp.FOLLOW
	mp._place()
	var shown: Vector2 = mp.shown
	var behind := shown.distance_to(Vector2(_car.global_position.x, _car.global_position.z)) if shown != Vector2.INF else -1.0
	_check(absf(behind - mp.FOLLOW) < 3.0, "the second arrow is %.0f m behind (%.0f)" % [mp.FOLLOW, behind])
	mp.finish()
	mp.force = false
	_check(mp.shown == Vector2.INF and mp.alpha == 0.0 and not late.active(), "and it's gone when it's over")
	# The lookouts: three flashes, and the lights answer; the first leaves a card.
	var ls: Node = events.LookoutSignal
	ls.force = true
	ls._here = ls.LOOKOUTS[0]
	_check(ls.begin(), "a lookout can answer")
	_check(ls._lights != null and ls._lights.get_child_count() == 2, "two lights out on the water")
	ls._answer_done()
	ls.force = false
	_check(ls.answered.has("fraser") and story.has_night(&"lookout_fraser") and root.get_node("Discoveries").has(ls.CLUE),
		"it's in the Nights log, and the card is a clue")
	_check(story.flag(&"photo_back_seat"), "and the photograph from the back seat is due (the bird thread's lab)")
	_check(ls._lights == null and not late.active(), "and the lights go")
	# The station knows where you are.
	story.act_override = 3
	var line: String = events.StationVoice.here_line()
	_check(line != "", "the voice on the midnight station says where you are ('%s')" % line)
	story.act_override = 0
	# The repeat street needs a long straight street: there's one near home.
	var g := MapData.shared().routes
	var found := {}
	for r in g.road_pts.size():
		if not g.road_kinds[r] in events.RepeatStreet.KINDS or g.road_names[r] == "" or g.road_pts[r][0].distance_to(_home.global_position) > 1500.0:
			continue
		var t := TrafficGraph.tangent_at(g.road_pts[r], g.road_cum[r], 1.0)
		found = events.RepeatStreet.street_ahead(g.road_pts[r][0], Vector2(t.x, t.z))
		if not found.is_empty():
			break
	_check(not found.is_empty(), "the repeat street finds a street near home (%s)" % found.get("name", "none"))
	# Looking out: the lane in 1979, then nothing; opening a door lets it go.
	var lo: Node = events.LookingOut
	lo.force = true
	_check(lo.begin(&"1979"), "looking out can start")
	_check(lo.form == &"1979" and _home.find_child("Lane1979", false, false) != null and (lo._glass as Array).size() > 0,
		"the lane is 1979, and the glass is clear (%d panes)" % (lo._glass as Array).size())
	var glass: Array = (lo._glass as Array)[0]
	_home.toggle_door(&"Door_Front")
	_check(lo.form == &"" and not late.active(), "opening the front door lets it go")
	_check((glass[0] as MeshInstance3D).get_surface_override_material(glass[1]) == glass[2], "and the glass is as it was")
	_home.toggle_door(&"Door_Front")
	_check(lo.begin(&"nothing"), "and nothing, from act 4")
	_check(lo._lit.size() > 0, "the house is kept lit (%d surfaces)" % lo._lit.size())
	lo.let_go()
	lo.force = false
	_check(lo._void == 0.0 and lo.form == &"" and not late.active(), "letting go brings the world back")


## Each run: drive up to ~1.2 km before May Drive's end, start the road,
## watch it empty, then leave it (first run), deliver (second run) or stop
## the car (third run).
func _road_run(late: Node, story: Node) -> bool:
	var f := _frames - _run_from
	# Creep along (standing still lets you go), except on the last run.
	if _runs == 2 and f >= 450 and f < 800:
		_car.linear_velocity = Vector3(0, _car.linear_velocity.y, 0)  # foot on the brake
	if f > 120 and f < 450:
		var fwd: Vector3 = -_car.global_transform.basis.z
		_car.linear_velocity = Vector3(fwd.x * 1.4, _car.linear_velocity.y, fwd.z * 1.4)
	if f == 120:
		_check(late.map_idle(), "the map has loaded round the car")
		var on := MapData.shared().street_at(_car.global_position, 12.0)
		_check(on == _ER.STREET, "on May Drive itself (%s, %.0f m to go)" % [on, _car.global_position.distance_to(_ER.DROPOFF)])
		# Nobody about (start() waits for a clear road; the game just tries again).
		var traffic := _main.find_child("Traffic", true, false)
		if traffic:
			traffic.clear_all()
		var started: bool = _road.start()
		_check(started, "the road can empty here (run %d%s)" % [_runs, "" if started else ": " + _road.refused])
		_check(late.event == &"empty_road", "the late city is running the empty road")
	elif f == 150:
		_check(_road.phase == _ER.Phase.SOUND_OUT, "first the sound goes")
		_check(late.mute_amount() > 0.05, "the street is quietening (%.2f)" % late.mute_amount())
	elif f == 450:
		_check(_road.phase == _ER.Phase.EMPTY, "then everything but the road")
		var map := get_first_node_in_group(&"perth_map") as Node3D
		_check(map != null and not map.visible, "the city is gone")
		_check(_car.visible and (_road.get("_car_lit") as Array).size() > 0, "but not your car, which stays lit")
		var ribbon := _road.find_child("EmptyRoadRibbon", true, false) as Node3D
		_check(ribbon != null and ribbon.visible and ribbon.get_child_count() > 10, "the road goes on, with its lamps")
		_check(_road.find_child("LateHouse", true, false) != null, "and there's a house by it")
		var hidden: Array = _road.get("_hidden_roads")
		_check(hidden.size() > 0, "the map's own road meshes are hidden under the ribbon (%d: %s)" % [hidden.size(), ", ".join(hidden.slice(0, 4).map(func(n: Node) -> String: return String(n.name)))])
		_check(is_equal_approx(_road.void_amount, 1.0), "the void is full")
		_check(late.mute_amount() > 0.95, "only the engine is left")
		if _runs == 2:
			pass  # Stop the car and wait.
		elif _runs == 0:
			# Leave the road: drive off into the dark.
			var right: Vector3 = (_car.global_transform.basis.x).normalized()
			_car.teleport(Transform3D(_car.global_transform.basis, _car.global_position + right * 20.0 + Vector3.UP * 0.5))
		else:
			# Pull up at the letterbox.
			_car.teleport(Transform3D(_car.global_transform.basis, _ER.DROPOFF + Vector3.UP * 0.8))
	elif f == 470 and _runs == 0:
		_check(_road.phase == _ER.Phase.FADE_IN, "off the road, the world comes back")
	elif f == 800 and _runs == 2:
		_check(_road.phase == _ER.Phase.FADE_IN or _road.phase == _ER.Phase.IDLE, "stopping the car lets you go too (phase %d, %.1f km/h)" % [_road.phase, _car.speed_kmh()])
		_next()
	elif f == (650 if _runs == 0 else 900) and _runs < 2:
		_check(_road.phase == _ER.Phase.IDLE, "and it's over")
		var map := get_first_node_in_group(&"perth_map") as Node3D
		_check(map != null and map.visible, "the city is back")
		_check(_road.void_amount == 0.0, "no void")
		_check(not late.active(), "the late city has let go")
		if _runs == 0:
			_check(story.has_night(&"empty_road_left"), "leaving it is in the Nights log")
			_check(not story.flag(&"empty_road_done"), "the parcel is still to go")
			_check(not _road.get("_armed"), "and it won't start again until you've left May Drive")
			_runs = 1
			_start_run()
			_run_from = _frames
		else:
			_check(story.flag(&"empty_road_done"), "the parcel was signed for")
			_check(story.has_night(&"empty_road"), "and it's in the Nights log")
			_check(root.get_node("Jobs").active.is_empty(), "the job is done")
			_runs = 2
			_start_run()
			_run_from = _frames
	return false


func _start_run() -> void:
	var jobs := root.get_node("Jobs")
	var job := _story_job()
	if job.is_empty() and jobs.active.get("story", "") != "empty_road":
		_road._maybe_offer()
		job = _story_job()
	if not job.is_empty():
		jobs.accept(job)
	if not jobs.active.is_empty():
		jobs.active.stage = "to_dropoff"
		jobs._stage_changed()
	root.get_node("GameClock").set_time(1.0)
	# 1.2 km back along the road from May Drive, facing along it.
	var cum := TrafficGraph.cumulative(_route)
	var total := cum[cum.size() - 1]
	# As far back along May Drive itself as it goes (up to ~1.2 km).
	var s: float = total - _ER.MIN_ROUTE - 20.0
	while s - 20.0 > total - 1200.0 and MapData.shared().street_at(_point_at(cum, s - 20.0), 12.0) == _ER.STREET:
		s -= 20.0
	var i := 1
	while i < cum.size() - 1 and cum[i] < s:
		i += 1
	var p := _route[i - 1].lerp(_route[i], 0.5)
	var dir := (_route[i] - _route[i - 1])
	dir.y = 0.0
	dir = dir.normalized()
	_car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), p + Vector3.UP * 1.0))


func _story_job() -> Dictionary:
	for job: Dictionary in root.get_node("Jobs").offers:
		if job.get("story", "") == "empty_road":
			return job
	return {}


func _put_player(at: Vector3) -> void:
	_player.global_position = at
	_player.set("velocity", Vector3.ZERO)


func _retinted() -> int:
	var shell: Node = _home.get_node("House")
	var n := 0
	for mi in _OH._meshes(shell):
		if mi.name != &"Late1979" or not mi.is_inside_tree() or mi.is_queued_for_deletion():
			continue
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			if m != null and m.has_meta(&"late_1979") and m.get_shader_parameter("late_side") == 2:
				n += 1
	return n


## Meshes inside the house (PS1 ones) whose surfaces are on `side` (0: plain).
func _sided(node: Node, side: int) -> int:
	var n := 0
	for mi in _OH._meshes(node):
		if not mi.is_visible_in_tree() or not _other._in_box(mi.global_transform * mi.get_aabb().get_center(), 0.0):
			continue
		var found := 0
		var ps1 := false
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as ShaderMaterial
			if m == null:
				continue
			ps1 = true
			var v: Variant = m.get_shader_parameter("late_side")
			found = int(v) if v != null else 0
		if ps1 and found == side:
			n += 1
	return n


func _next() -> void:
	_stage += 1
	_frames = 0
	if _stage == 1:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("from="):
				_stage = maxi(1, int(arg.get_slice("=", 1)))


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	print("STORY ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
	return false


func _point_at(cum: PackedFloat32Array, s: float) -> Vector3:
	for i in range(1, cum.size()):
		if cum[i] >= s:
			var t := (s - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.01)
			return _route[i - 1].lerp(_route[i], t)
	return _route[_route.size() - 1]
