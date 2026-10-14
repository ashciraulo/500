class_name Endings
extends Node3D
## The five endings (STORY.md section 9): the scene each one plays on the
## night of the 11th (Finale.chosen), and what each leaves behind afterwards
## (Story.ending()). The game carries on after every one of them.
##
##   City of Light   the regulars' lights come on, far side of the city first,
##                   down to the river; the lights over the river lift off
##                   the water and go up; Mick's last tape. Afterwards the
##                   late city is gone and the river lights with it, the
##                   wrong birds stop flickering, and Dee plays a song for
##                   Mick the next night.
##   Half Light      only some of the lights come on; the lights over the
##                   river rise a little and settle back. Nothing's resolved
##                   (Finale brings the 11th round again).
##   Night Drive 13  at dawn a 1971 500 L is parked at the end of the lane:
##                   Mick's, yours now. Afterwards every night after midnight
##                   is 1979: the traffic, the sodium light.
##   Lights Out      the red lights go out (Finale). Afterwards the late city
##                   fades over a few nights (LateCity.gone()) and the midnight station is only
##                   static (with, if the thirteen was sold, a very faint
##                   voice some nights).
##   The Late City   you go in after him: the house from the lane in 1979,
##                   porch light on, two little cars in the carport, then the
##                   credits. Afterwards it's always night, and always 1979.
##
## Added by GameplayPlaces. Saved under "endings".

## Seconds between one lit house and the next as the city lights up.
const LIGHT_EVERY := 0.18
## Only houses this close to you (m) get a lamp to see, and only those
## within LAMP_NEAR light up round them.
const LIGHT_NEAR := 2500.0
const LAMP_NEAR := 700.0
## How far the river lights rise: away for good, or a little and back.
const RISE_AWAY := 320.0
const RISE_HALF := 22.0
## Night Drive 13's 500 L turns up at dawn, and the late city every night
## from midnight to LATE_TO.
const DAWN_H := 6.0
const LATE_TO := 4.5
## The Late City: the night never ends. From DAY_FROM it's evening again.
const DAY_FROM := 4.5
const EVENING := 20.0
const MICK_PAINT := Color(0.86, 0.8, 0.62)
## The Late City: how far down the lane (m) the carport is seen from.
const LANE_BACK := 13.0
const MICK_CAR := "classic_500l"
const WARM := Color(1.0, 0.78, 0.48)
const CREDITS := [
	"NIGHT DRIVE",
	"",
	"Mick Doran went out on the night of 11 July 1979",
	"and didn't come home.",
	"",
	"You went in after him.",
	"",
	"Made by Ash",
	"",
	"Map data from OpenStreetMap contributors",
	"Built with Godot",
	"",
	"Thanks for leaving the light on.",
]
const CREDITS_SECONDS := 26.0

## Night Drive 13: the day the L turns up at dawn, and whether it has.
var dawn_day := -1
var mick_left := false
## City of Light: the night Dee plays Mick's song (and has she).
var song_night := -1
var song_played := false
## Tests and screenshots: skip waiting between the steps of a scene.
var fast := false

var _finale: Finale
var _people: StoryPeople
var _car: CarController
var _home: Node3D
var _card: ActCard
var _queue: Array = []     # [seconds to wait, Callable]
var _wait := 0.0
var _left_on: Array[Node3D] = []
var _left_on_until := -1.0  # game hours since day 0
var _old: Traffic1979
var _mick: Node3D
var _second: Node3D        # The Late City: the other little car in the carport
var _fade: ColorRect
var _credits: VBoxContainer
var _scene_cam: Camera3D
var _return_cam: Camera3D
var _check := 0.0
var _static_night := -1
var _radio: Object


func _ready() -> void:
	name = "Endings"
	SaveGame.register("endings", self)
	_card = ActCard.new()
	add_child(_card)
	_build_overlay()
	_setup.call_deferred()


func _exit_tree() -> void:
	SaveGame.unregister("endings")


func _setup() -> void:
	_finale = get_parent().get_node_or_null(^"Finale") as Finale
	if _finale:
		_finale.chosen.connect(_on_chosen)
	_people = get_parent().get_node_or_null(^"StoryPeople") as StoryPeople
	var audio := get_node_or_null(^"/root/Audio")
	_radio = audio.get("radio") if audio else null


func _on_chosen(_choice: StringName, ending: StringName) -> void:
	match ending:
		&"city_of_light":
			_city(1.0)
		&"half_light":
			_city(clampf(float(_finale.lit()) / float(maxi(_finale.lit_needed(), 1)), 0.1, 0.9))
		&"night_drive_13":
			_night_drive_13()
		&"lights_out":
			_then(4.0, func() -> void: _card.show_text("THE END", "Lights Out"))
		&"late_city":
			_late_city()


## Whether a scene is still playing.
func playing() -> bool:
	return not _queue.is_empty() or _scene_cam != null


## Do the next steps of the scene `seconds` from now.
func _then(seconds: float, step: Callable) -> void:
	_queue.append([seconds, step])


func _process(delta: float) -> void:
	_run_queue(delta)
	if _credits and _credits.visible:
		_credits.position.y -= delta * (get_viewport().get_visible_rect().size.y + _credits.size.y) / CREDITS_SECONDS
	if TitleScreen.is_showing(get_tree()):
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
	_afterwards()


func _run_queue(delta: float) -> void:
	while not _queue.is_empty():
		var step: Array = _queue[0]
		if not fast:
			step[0] = float(step[0]) - delta
			if float(step[0]) > 0.0:
				return
			delta = 0.0
		_queue.pop_front()
		(step[1] as Callable).call()


## Tests: play whatever's left of the scene now.
func finish_scene() -> void:
	var was := fast
	fast = true
	_run_queue(0.0)
	fast = was


# --- City of Light and Half Light -----------------------------------------------------

## `share` of the regulars' houses leave their lights on, the far side of the
## city first, down to the river. Then the river lights go up (all of them)
## or rise a little and settle back.
func _city(share: float) -> void:
	var river: Vector3 = _finale.get(&"_river")
	var sites: Array[Node3D] = []
	for s in Jobs.sites():
		if s is Node3D:
			sites.append(s)
	sites.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(river) > b.global_position.distance_to(river))
	var n := roundi(sites.size() * share)
	_left_on_until = (GameClock.day + (1 if GameClock.time_of_day >= 12.0 else 0)) * 24.0 + DAWN_H
	var full := share >= 1.0
	_then(3.0, func() -> void:
		Notices.post("All over the city, porch lights are coming on." if full else "Here and there across the city, a porch light comes on.", "odd"))
	for i in n:
		_then(LIGHT_EVERY, _leave_on.bind(sites[i]))
	_then(2.0, _river_rise.bind(full))
	if full:
		var robyn := Story.choice(&"robyn") == &"found"
		_then(14.0, func() -> void:
			if robyn:
				Activities.say("Robyn's at the river. She came after all. She doesn't say anything, and neither do you.")
			Activities.say("On the radio, under the hiss, a man's voice: \"Thanks for leaving the light on%s.\"" % (", Robbie" if robyn else ""))
			Story.log_night(&"mick_last_tape", "Mick's last tape: \"Thanks for leaving the light on.\""))
		_then(8.0, func() -> void: _card.show_text("THE END", "City of Light"))
	else:
		_then(10.0, func() -> void:
			Activities.say("The lights over the river rise a little, then settle back on the water. Not enough of the city is lit."))


func _leave_on(site: Node3D) -> void:
	if not is_instance_valid(site):
		return
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(site.global_position) if cam else 0.0
	if d > LIGHT_NEAR:
		return
	var lamp := Node3D.new()
	lamp.name = "LeftOn"
	add_child(lamp)
	lamp.global_position = site.global_position + Vector3.UP * 2.6
	if d < LAMP_NEAR:
		var light := OmniLight3D.new()
		light.light_color = WARM
		light.light_energy = 1.6
		light.omni_range = 9.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 260.0
		light.distance_fade_length = 80.0
		lamp.add_child(light)
	var bulb := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.7, 0.7)
	bulb.mesh = box
	bulb.material_override = PS1Material.glowing(WARM, 2.5)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.visibility_range_end = LIGHT_NEAR
	lamp.add_child(bulb)
	_left_on.append(lamp)


func lights_left_on() -> int:
	return _left_on.size()


func _river_rise(away: bool) -> void:
	var odd := get_parent().get_node_or_null(^"Oddities")
	var lights := odd.get(&"_lights") as Node3D if odd else null
	if lights == null or not is_instance_valid(lights):
		return
	var tween := lights.create_tween()
	if away:
		tween.tween_property(lights, "global_position:y", lights.global_position.y + RISE_AWAY, 24.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(func() -> void:
			if odd.get(&"_lights") == lights:
				odd.set(&"_lights", null)
			lights.queue_free())
	else:
		var y := lights.global_position.y
		tween.tween_property(lights, "global_position:y", y + RISE_HALF, 5.0).set_trans(Tween.TRANS_SINE)
		tween.tween_property(lights, "global_position:y", y, 7.0).set_trans(Tween.TRANS_SINE)


# --- Night Drive 13 ------------------------------------------------------------------------

func _night_drive_13() -> void:
	dawn_day = GameClock.day + (1 if GameClock.time_of_day >= 12.0 else 0)
	mick_left = false
	_then(3.0, func() -> void:
		Activities.say("The tape runs out and the deck clicks off. A long way off, a little engine starts."))
	_then(4.0, func() -> void: _card.show_text("THE END", "Night Drive 13"))


## At dawn: Mick's 500 L at the end of the lane, cream, the keys in it.
func _mick_comes_home() -> void:
	mick_left = true
	if not Classics.is_found(MICK_CAR):
		var done: Array = []
		for s: Dictionary in Classics.stages():
			done.append(s.id)
		Classics.projects[MICK_CAR] = {"stages": done, "finish": "original"}
	Garage.add_car(MICK_CAR)
	_place_mick()
	Notices.post("At dawn there's a little 500 L parked at the end of the lane. 1971, cream, the keys in it. It's yours.", "odd")
	if Story.choice(&"robyn") == &"found":
		Activities.say("In Fremantle, Robyn's front door opens before anyone's knocked.")
	else:
		Activities.say("For a moment there's a man sitting in it, outside a house where nobody's waiting. Then there isn't.")
	Story.log_night(&"mick_home", "At dawn Mick's 500 L was parked at the end of the lane.")


func _place_mick() -> void:
	var mystery := get_parent().get_node_or_null(^"Mystery") as Mystery
	var at := mystery.lane_end() if mystery else Vector3.INF
	if at == Vector3.INF:
		return
	_mick = _little_car(MICK_PAINT)
	if _mick == null:
		return
	_mick.name = "MicksCar"
	add_child(_mick)
	var map := get_tree().get_first_node_in_group(&"perth_map")
	var out: Vector3 = (map.get_spawn_transform() as Transform3D).basis.z if map and map.has_method("get_spawn_transform") else Vector3.FORWARD
	_mick.global_position = at
	_mick.look_at(at + out, Vector3.UP)


## A 500 L like the 1979 traffic's, in `paint`.
func _little_car(paint: Color) -> Node3D:
	if not ResourceLoader.exists(Traffic1979.FIAT):
		return null
	var model := (load(Traffic1979.FIAT) as PackedScene).instantiate() as Node3D
	LateHouse.add_wheels(model)
	var open := model.get_node_or_null(^"Roof_Open") as Node3D
	if open:
		open.visible = false
	var mats := PS1Model.apply(model)
	var body := mats.get("Paint") as ShaderMaterial
	if body:
		body.set_shader_parameter("albedo_color", paint)
		body.set_shader_parameter("albedo_texture", null)
		body.set_shader_parameter("top_shade", 0.45)
	return model


# --- The Late City -------------------------------------------------------------------------

## The house from the lane in 1979, two little cars in the carport; the end card and the credits; then back in the car, in the late
## city for good.
func _late_city() -> void:
	_then(1.0, func() -> void: _fade_to(1.0, 2.0))
	_then(2.4, _late_house)
	_then(0.5, func() -> void: _fade_to(0.0, 2.5))
	_then(9.0, func() -> void: _card.show_text("THE END", "The Late City"))
	_then(7.0, func() -> void:
		_fade_to(0.8, 1.5)
		_credits.position.y = get_viewport().get_visible_rect().size.y
		_credits.visible = true)
	_then(CREDITS_SECONDS, func() -> void:
		_credits.visible = false
		_fade_to(1.0, 2.0))
	_then(2.4, _back_in_the_car)
	_then(0.5, func() -> void: _fade_to(0.0, 2.5))


func _late_house() -> void:
	GameClock.set_time(2.0 + 40.0 / 60.0)
	if _people:
		_people.porch_light_on = true
	_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
	if _home == null or _car == null:
		return
	var bay: Transform3D = _home.call("spawn_transform", &"Spawn_Car")
	_car.teleport(bay)
	_car.freeze = true
	_park_second(bay)
	_dress_1979(true)
	LateCity.fade_look(1.0, 0.5)
	_hud(false)
	# From down the lane, looking back at the carport and the house behind it
	# (the carport opens onto the lane, which runs out along the bay's -z).
	_return_cam = get_viewport().get_camera_3d()
	_scene_cam = Camera3D.new()
	_scene_cam.name = "LateCityCamera"
	_scene_cam.fov = 70.0
	add_child(_scene_cam)
	var side := bay.basis.x * 1.15
	_scene_cam.global_position = bay.origin - bay.basis.z * LANE_BACK + side + Vector3.UP * 2.2
	_scene_cam.look_at(bay.origin + bay.basis.z * 4.0 + side + Vector3.UP * 1.6, Vector3.UP)
	_scene_cam.current = true


## The other little car, beside yours in the carport.
func _park_second(bay: Transform3D) -> void:
	if _second and is_instance_valid(_second):
		return
	_second = _little_car(MICK_PAINT)
	if _second == null:
		return
	_second.name = "SecondCar"
	add_child(_second)
	_second.global_transform = Transform3D(bay.basis, bay.origin + bay.basis.x * 2.3 + Vector3.DOWN * 0.4)


func _back_in_the_car() -> void:
	if _scene_cam:
		_scene_cam.queue_free()
		_scene_cam = null
	if _return_cam and is_instance_valid(_return_cam):
		_return_cam.current = true
	if _car:
		_car.freeze = false
	_hud(true)
	LateCity.fade_look(0.0, 2.0)
	Story.log_night(&"late_city_credits", "I went in after him. It's 1979 now, and it's always night.")


## The HUD, the on-foot prompt and the carport's workshop prompt, out of
## the way of the scene.
func _hud(on: bool) -> void:
	var layers: Array = get_tree().get_nodes_in_group(&"hud")
	var walker := get_tree().root.find_child("Player", true, false)
	if walker and walker.get(&"_ui") is CanvasLayer:
		layers.append(walker.get(&"_ui"))
	layers.append(get_tree().root.find_child("Workshop", true, false))
	for layer in layers:
		if layer is CanvasLayer:
			(layer as CanvasLayer).visible = on


func _fade_to(to: float, seconds: float) -> void:
	_fade.visible = true
	var tween := _fade.create_tween()
	tween.tween_property(_fade, "color:a", to, seconds if not fast else 0.0)
	if to <= 0.0:
		tween.tween_callback(func() -> void: _fade.visible = false)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	layer.add_child(_fade)
	_credits = VBoxContainer.new()
	_credits.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits.add_theme_constant_override("separation", 10)
	_credits.visible = false
	for line: String in CREDITS:
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", UiStyle.HAND_FONT if line == CREDITS[0] else UiStyle.LCD_FONT)
		label.add_theme_font_size_override("font_size", 48 if line == CREDITS[0] else 24)
		label.add_theme_color_override("font_color", UiStyle.PAPER)
		_credits.add_child(label)
	layer.add_child(_credits)


# --- What each leaves behind ------------------------------------------------------------------

func _afterwards() -> void:
	var t := GameClock.day * 24.0 + GameClock.time_of_day
	if not _left_on.is_empty() and t >= _left_on_until and not playing():
		for lamp in _left_on:
			if is_instance_valid(lamp):
				lamp.queue_free()
		_left_on.clear()
	var ending := Story.ending()
	var h := GameClock.time_of_day
	match ending:
		&"city_of_light":
			_dee_song()
		&"night_drive_13":
			if not mick_left and dawn_day >= 0 and GameClock.day >= dawn_day and h >= DAWN_H and h < 20.0:
				_mick_comes_home()
			elif mick_left and _mick == null and GameClock.day == dawn_day and h < 20.0:
				_place_mick()
			elif _mick and (GameClock.day != dawn_day or h >= 20.0):
				_mick.queue_free()
				_mick = null
		&"lights_out":
			_static()
		&"late_city":
			# Always night: past the small hours it's evening again.
			if not playing() and h >= DAY_FROM and h < EVENING:
				GameClock.set_time(EVENING)
			if _home and _second == null and _home.has_method("spawn_transform"):
				_park_second(_home.call("spawn_transform", &"Spawn_Car"))
	var late_now := ending == &"late_city" or (ending == &"night_drive_13" and h >= 0.0 and h < LATE_TO)
	if not playing():
		_dress_1979(late_now)


## Night Drive 13 and The Late City: the city in 1979.
func _dress_1979(on: bool) -> void:
	if on and _old == null:
		_old = Traffic1979.new()
		_old.name = "Always1979"
		add_child(_old)
	if _old == null:
		return
	if on and not _old.dressed:
		_old.dress_all()
	elif not on and _old.dressed:
		_old.undress_all()


## City of Light: the next night, Dee plays a song for Mick.
func _dee_song() -> void:
	if song_played or _radio == null:
		return
	var night := Story.ending_day() + 1
	var h := GameClock.time_of_day
	if GameClock.day < night or h < 21.0:
		return
	if String(_radio.call("current_station_id")) != "nottefm" or not bool(_radio.call("is_on")):
		return
	song_played = true
	song_night = GameClock.day
	Activities.say("On Notte FM, Dee: \"This next one's for Mick Doran. Wherever you are, mate, the lights are on.\"")
	Story.log_night(&"dee_song_for_mick", "Dee played a song for Mick on Notte FM.")


## Lights Out: after midnight the station's only static. If the thirteen
## went to the buyer, some nights there's a very faint voice in it.
func _static() -> void:
	if _radio == null or GameClock.time_of_day >= LATE_TO:
		return
	if String(_radio.call("current_station_id")) != "midnight" or _static_night == GameClock.day:
		return
	_static_night = GameClock.day
	if Story.choice(&"thirteen") == &"buyer" and randf() < 0.35:
		Activities.say("Under the static, very faint: \"...Little Shenton Lane...\" Then only static.")
	else:
		Activities.say("Only static on the midnight station now.")


func save_state() -> Dictionary:
	return {"dawn_day": dawn_day, "mick_left": mick_left, "song_night": song_night, "song_played": song_played}


func load_state(data: Dictionary) -> void:
	dawn_day = int(data.get("dawn_day", -1))
	mick_left = bool(data.get("mick_left", false))
	song_night = int(data.get("song_night", -1))
	song_played = bool(data.get("song_played", false))
