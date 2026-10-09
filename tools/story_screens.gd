extends SceneTree
## Screenshots of the late-city events (STORY.md) for reviewing how they look:
## the other house (1979 behind your own front door) and the empty road on
## May Drive. Needs a display (or xvfb):
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/story_screens.gd -- --no-save shots=/tmp/story [only=house,road,people]

var _shots := "/tmp/story"
var _only := PackedStringArray()
var _main: Node
var _world: Node3D
var _car: CarController
var _player: Node3D
var _home: HomeBase
var _other: OtherHouse
var _road: EmptyRoad
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
	return _home.to_global(House1979.at(Vector3(x, y, z)))


func _build_steps() -> void:
	if _want("house"):
		_house_steps()
	if _want("road"):
		_road_steps()
	if _want("people"):
		_people_steps()


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
		_route = md.routes.find(Vector3(-912.0, 67.0, 926.0), Vector2.ZERO, EmptyRoad.DROPOFF).get("points", PackedVector3Array()), 200, null, false])
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
		var back := -_car.global_transform.basis.z
		_look(_car.global_position - back * 14.0 + Vector3.UP * 9.0, _car.global_position + back * 30.0), 30])
	_steps.append(["road_5_the_house", func() -> void:
		var house := _road.find_child("LateHouse", true, false) as Node3D
		var at := _point_back(32.0)
		_look(at + Vector3.UP * 1.5, house.global_position + Vector3.UP * 1.6 if house else EmptyRoad.DROPOFF), 30])
	_steps.append(["road_6_the_letterbox", func() -> void:
		var at := _point_back(7.0)
		_look(at + Vector3.UP * 1.3, EmptyRoad.DROPOFF + Vector3.UP * 0.6), 30])
	_steps.append(["road_7_off_the_road", func() -> void:
		_creep = false
		_drive_view()
		var right := _car.global_transform.basis.x
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


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
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
		var fwd := -_car.global_transform.basis.z
		_car.linear_velocity = Vector3(fwd.x * 1.4, _car.linear_velocity.y, fwd.z * 1.4)
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			_home = get_first_node_in_group(&"home_base") as HomeBase
			_other = _main.find_child("OtherHouse", true, false) as OtherHouse
			_road = _main.find_child("EmptyRoad", true, false) as EmptyRoad
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
	var s := total - EmptyRoad.MIN_ROUTE - 20.0
	while s - 20.0 > total - back and MapData.shared().street_at(_point_at(cum, s - 20.0), 12.0) == EmptyRoad.STREET:
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
