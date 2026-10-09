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
				_check(_visible_meshes(interior) == 0, "today's furniture is gone, bar the balcony pots outside (%d left: %s)" % [_visible_meshes(interior), _visible_names(interior)])
				_check(_home.find_child("House1979", false, false) != null, "the Dorans' things are in")
				_check(_retinted() > 0, "the walls and floors are 1979 (%d surfaces)" % _retinted())
				_check(story.has_night(&"other_house_1979"), "it's in the Nights log")
				_check(_other.interact_hint() == "Take the drawing", "the drawing on the fridge can be taken")
				_other.interact()
				_check(story.flag(&"drawing_1979"), "taking it is remembered")
			elif _frames == 200:
				# Walk in, then back out and shut the door.
				_put_player(_home.to_global(_H79.at(Vector3(2.5, 3.0, 0.2))))
			elif _frames == 240:
				_check(_other.is_active(), "still 1979 while you're inside")
				_put_player(_home.spawn_transform(&"Spawn_Front").origin + Vector3.UP * 0.1)
			elif _frames == 250:
				_home.toggle_door(&"Door_Front")
			elif _frames == 300:
				_check(not _other.is_active(), "out and the door shut: it's your house again")
				_check((_home.get_node("Interior") as Node3D).visible, "today's furniture is back")
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
		3:
			return _finish()
	return false


## Each run: drive up to ~1.2 km before May Drive's end, start the road,
## watch it empty, then leave it (first run) or deliver (second run).
func _road_run(late: Node, story: Node) -> bool:
	var f := _frames - _run_from
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
		if _runs == 0:
			# Leave the road: drive off into the dark.
			var right: Vector3 = (_car.global_transform.basis.x).normalized()
			_car.teleport(Transform3D(_car.global_transform.basis, _car.global_position + right * 20.0 + Vector3.UP * 0.5))
		else:
			# Pull up at the letterbox.
			_car.teleport(Transform3D(_car.global_transform.basis, _ER.DROPOFF + Vector3.UP * 0.8))
	elif f == 470 and _runs == 0:
		_check(_road.phase == _ER.Phase.FADE_IN, "off the road, the world comes back")
	elif f == (650 if _runs == 0 else 900):
		_check(_road.phase == _ER.Phase.IDLE, "and it's over")
		var map := get_first_node_in_group(&"perth_map") as Node3D
		_check(map != null and map.visible, "the city is back")
		_check(_road.void_amount == 0.0, "no void")
		_check(not late.active(), "the late city has let go")
		if _runs == 0:
			_check(story.has_night(&"empty_road_left"), "leaving it is in the Nights log")
			_check(not story.flag(&"empty_road_done"), "the parcel is still to go")
			_runs = 1
			_start_run()
			_run_from = _frames
		else:
			_check(story.flag(&"empty_road_done"), "the parcel was signed for")
			_check(story.has_night(&"empty_road"), "and it's in the Nights log")
			_check(root.get_node("Jobs").active.is_empty(), "the job is done")
			_next()
	return false


func _start_run() -> void:
	var jobs := root.get_node("Jobs")
	var job := _story_job()
	if job.is_empty() and jobs.active.get("story", "") != "empty_road":
		_road._maybe_offer()
		job = _story_job()
	if not job.is_empty():
		jobs.accept(job)
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
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(i)
			if m != null and m.has_meta(&"late_1979"):
				n += 1
	return n


func _visible_meshes(node: Node) -> int:
	var n := 0
	for mi in _OH._meshes(node):
		if mi.is_visible_in_tree() and _other._in_box(mi.global_transform * mi.get_aabb().get_center(), 0.0):
			n += 1
	return n


func _visible_names(node: Node) -> String:
	var out := PackedStringArray()
	for mi in _OH._meshes(node):
		if mi.is_visible_in_tree() and _other._in_box(mi.global_transform * mi.get_aabb().get_center(), 0.0):
			var c: Vector3 = mi.global_transform * mi.get_aabb().get_center()
			out.append("%s %s" % [mi.name, _home.to_local(c)])
	return ", ".join(out)


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
