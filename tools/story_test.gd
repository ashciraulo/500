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
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/story_test.gd -- --no-save
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
				# You can use things you can see, but not through a wall: from
				# the hall with the front door open, yes; from outside, no.
				if not _home.is_door_open(&"Door_Front"):
					_home.toggle_door(&"Door_Front")
				_put_player(_home.to_global(_H79.at(Vector3(1.2, 1.4, 0.2))))
			elif _frames == 60:
				_player.face(switch.interact_point())
			elif _frames == 62:
				var t: Array = _player._target()
				_check(t[0] == "thing" and t[1] == switch, "the porch switch can be used from the hall with the front door open (%s)" % [t[0]])
				_put_player(_home.to_global(_H79.at(Vector3(0.9, -1.6, 0.2))))
			elif _frames == 80:
				_player.face(switch.interact_point())
			elif _frames == 82:
				_check(_player._nearest_thing() != switch, "but not from the step outside")
				_home.toggle_door(&"Door_Front")
				_put_player(_home.to_global(_H79.at(Vector3(0.3, -0.35, 0.2))))
			elif _frames == 140:
				_player.face(switch.interact_point())
			elif _frames == 142:
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
