extends Node
## The game's event sounds: jobs and time trials, money, the garage, fuel,
## the car wash, cargo rattling in the back, and menu clicks. It listens to
## the other autoloads' signals (Jobs, SaveGame) and the player's car, so none
## of that code needs audio calls. Created by the Audio autoload as
## Audio.hooks.
##
## Jingles for things that happened (a discovery, a challenge or tier done, a
## job paid or called off, a fresh job board, dawn and dusk, saving) belong to
## the Notices autoload, which plays each one as its card appears, so none
## plays with nothing on screen.
##
## Music during jobs: deliveries keep the radio on until time runs short (the
## last 30% of the par time), when the mission tension loop fades in and
## builds; time trials play the time-trial loop from the start line. The radio
## dips under both and comes back after.

## Share of a delivery's par time after which the tension music starts.
const TENSION_FROM := 0.7
## Seconds of ticks before each trial medal time runs out.
const TICK_SECONDS := 5
## Ignore events this long after a load, when saved state replays its signals.
const QUIET_AFTER_LOAD_S := 1.5

var _car: Node
var _jobs: Node
var _quiet_until := 0.0
var _music := ""             # "", "tension" or "trial"
var _last_tick := -1
var _last_fuel := -1.0
var _last_dirt := -1.0
var _last_look := {}         # the car's paint, livery and finish, to hear the spray shop
var _was_paused := false
var _phone: Node
var _workshop: Node
var _phone_open := false
var _workshop_open := false
var _room_tone: AudioStreamPlayer
var traffic: Node            # traffic_audio.gd, once the city's TrafficManager turns up
var _map: Node               # the Perth map streamer, when the real map is loaded
var _pois_loaded := false    # its points of interest handed to the place ambience
var _home: Node
var home_audio: Node         # home_audio.gd: the quiet lane, indoors, the fridge and clock
var _zone_timer := 0.0
var _look_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_quiet_until = _now() + QUIET_AFTER_LOAD_S
	var root := get_tree().root
	var jobs := root.get_node_or_null("Jobs")
	_jobs = jobs
	if jobs and jobs.has_signal("job_started"):
		jobs.job_started.connect(_on_job_started)
		jobs.job_stage_changed.connect(_on_job_stage)
		jobs.job_completed.connect(_on_job_completed)
		jobs.job_abandoned.connect(_on_job_abandoned)
	var save := root.get_node_or_null("SaveGame")
	if save and save.has_signal("loaded"):
		save.loaded.connect(func(_p) -> void: _quiet_until = _now() + QUIET_AFTER_LOAD_S)
	get_tree().node_added.connect(_on_node_added)
	_room_tone = AudioStreamPlayer.new()
	_room_tone.bus = "Ambience"
	_room_tone.volume_db = -10.0
	add_child(_room_tone)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## False while saved state is still loading, so loading doesn't jingle.
func _loud() -> bool:
	return _now() >= _quiet_until


func _ui(sound_name: String, volume_db := 0.0) -> void:
	if _loud():
		Audio.ui(sound_name, volume_db)


func _process(delta: float) -> void:
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = 1.0
		_find_nodes()
	_update_pause()
	_update_panels()
	if get_tree().paused:
		return
	_update_job_music()
	_update_car()
	_update_zone(delta)


# ---------------------------------------------------------------------------
# Dawn and dusk
# ---------------------------------------------------------------------------

## Hours the light turns (Perth: first light about 6, dusk about 19).
const DAWN_HOUR := 6
const DUSK_HOUR := 19


## The music cue for the hour just begun ("" for none). Notices plays it with
## its "First light" or "The sun's going down" card.
static func light_cue(hour: int) -> String:
	match hour:
		DAWN_HOUR:
			return "mus_field_dawn"
		DUSK_HOUR:
			return "mus_field_dusk"
	return ""


# ---------------------------------------------------------------------------
# Jobs and time trials
# ---------------------------------------------------------------------------

func _on_job_started(_job: Dictionary) -> void:
	_ui("ui_job_accepted")
	_last_tick = -1


func _on_job_stage(job: Dictionary) -> void:
	match job.get("stage", ""):
		"to_dropoff":
			# Loaded up: the cargo goes in the back.
			_ui("ui_checkpoint")
			if _car:
				Audio.play_at("car/car_boot_close", _car.global_position, -4.0)
		"racing":
			if int(job.get("checkpoint", 0)) <= 1:
				_ui("ui_countdown_tick_final")
				_set_job_music("trial")
			else:
				_ui("ui_checkpoint")


func _on_job_completed(job: Dictionary, pay: int, _summary: String) -> void:
	_set_job_music("")
	if job.get("type", "") == "trial":
		var record: Dictionary = _jobs.trial_records.get(job.get("trial_id", ""), {})
		if is_equal_approx(float(record.get("best", -1.0)), float(job.get("elapsed", -2.0))):
			_ui("ui_new_best_time")
	elif _car:
		Audio.play_at("car/car_boot_open", _car.global_position, -4.0)
	if pay > 0:
		get_tree().create_timer(0.8).timeout.connect(func() -> void: Audio.ui("ui_money_earned"))


func _on_job_abandoned(_job: Dictionary) -> void:
	_set_job_music("")


func _update_job_music() -> void:
	if _jobs == null or not "active" in _jobs:
		return
	var job: Dictionary = _jobs.active
	if job.is_empty():
		if _music != "":
			_set_job_music("")
		return
	var elapsed := float(job.get("elapsed", 0.0))
	if job.get("type", "") == "trial":
		if job.get("stage", "") == "racing":
			_medal_ticks(job, elapsed)
		return
	if job.get("stage", "") != "to_dropoff":
		return
	var par := float(job.get("par_seconds", 0.0))
	if par <= 0.0:
		return
	var r := elapsed / par
	if r >= TENSION_FROM and r < 1.0:
		_set_job_music("tension")
		Audio.set_mission_intensity(clampf((r - TENSION_FROM) / (1.0 - TENSION_FROM), 0.0, 1.0))
	elif r >= 1.0 and _music == "tension":
		# The quick bonus is gone; let it go back to being a drive.
		_set_job_music("")


## Clock ticks over the last seconds before the next medal time slips away.
func _medal_ticks(job: Dictionary, elapsed: float) -> void:
	var times: Dictionary = job.get("medal_times", {})
	for medal in ["gold", "silver", "bronze"]:
		var left := float(times.get(medal, 0.0)) - elapsed
		if left > 0.0:
			var s := ceili(left)
			if s <= TICK_SECONDS and s != _last_tick:
				_last_tick = s
				_ui("ui_countdown_tick_final" if s == 1 else "ui_countdown_tick", -6.0)
			return


func _set_job_music(which: String) -> void:
	if which == _music:
		return
	_music = which
	match which:
		"tension":
			Audio.start_mission_music(3.0)
		"trial":
			Audio.play_music("mus_timetrial_loop", 0.5)
		_:
			Audio.stop_music(2.0)
	Audio.radio.duck(which != "")


# ---------------------------------------------------------------------------
# The player's car: cargo, fuel, wash, workshop
# ---------------------------------------------------------------------------

func _find_nodes() -> void:
	if not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car")
		if _car:
			_last_fuel = -1.0
			_last_look = {}
			if _car.has_signal("car_changed"):
				_car.car_changed.connect(func(_id: String) -> void: _last_look = {})
			if _car.has_signal("impact"):
				_car.impact.connect(_on_impact)
			if _car.has_signal("parts_changed"):
				_car.parts_changed.connect(_on_part_fitted)
			if _car.has_signal("fuel_low"):
				_car.fuel_low.connect(func() -> void:
					Audio.play_at("car/car_dash_chime", _car.global_position, -6.0, "Cabin"))
	var scene_root := get_tree().root
	if not is_instance_valid(_phone):
		_phone = scene_root.find_child("Phone", true, false)
	if not is_instance_valid(_workshop):
		_workshop = scene_root.find_child("Workshop", true, false)
	if not is_instance_valid(_map):
		var m := scene_root.find_child("PerthMap", true, false)
		if m and m.has_method("get_home"):
			_map = m
			_pois_loaded = false
	if is_instance_valid(_map) and not is_instance_valid(_home):
		var h: Node = _map.get_home()
		if h and h.has_signal("door_toggled"):
			_home = h
			h.door_toggled.connect(_on_home_door)
			h.slept.connect(_on_slept)
			if h is Node3D:
				if is_instance_valid(home_audio):
					home_audio.queue_free()
				home_audio = preload("res://audio/scripts/home_audio.gd").new()
				home_audio.name = "HomeAudio"
				add_child(home_audio)
				home_audio.setup(h)
			# The shed opening is the mystery's big moment: lock, door and a held drone.
			h.shed_unlocked.connect(func() -> void:
				if Audio.has("oddity/odd_shed_unlock"):
					Audio.play_2d("oddity/odd_shed_unlock", "SFX")
				else:
					Audio.play_at("home/home_odd_door_creak", _home_pos(), -2.0))
	if not is_instance_valid(traffic):
		var tm := scene_root.find_child("Traffic", true, false)
		if tm and tm.has_signal("vehicle_spawned"):
			traffic = preload("res://audio/scripts/traffic_audio.gd").new()
			traffic.name = "TrafficAudio"
			add_child(traffic)
			traffic.setup(tm)


## Cargo shifts in the back when you hit something mid-delivery.
func _on_impact(strength: float) -> void:
	if _jobs == null or not "active" in _jobs:
		return
	var job: Dictionary = _jobs.active
	if job.is_empty() or job.get("stage", "") != "to_dropoff" or strength < 2.0:
		return
	var pos: Vector3 = _car.global_position
	if job.get("fragile", false):
		Audio.play_at("car/car_cargo_glass_smash" if strength > 6.0 else "car/car_cargo_glass_clink",
				pos, -2.0, "Cabin")
	else:
		Audio.play_at("car/car_cargo_boxes_slide", pos, -4.0, "Cabin")


func _on_part_fitted(slot: StringName, _part) -> void:
	if not _loud() or _car == null:
		return
	var pos: Vector3 = _car.global_position
	if slot == &"roof":
		Audio.play_at("garage/garage_rack_fit", pos, -2.0)
		return
	Audio.play_at("garage/garage_impact_wrench", pos, -4.0)
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		Audio.play_at("garage/garage_part_fitted", pos, -2.0))


## Fuel going in and the car coming out clean are watched rather than
## signalled, so the servo, roadside assist and anything later all sound.
func _update_car() -> void:
	if _car == null:
		return
	var fuel := float(_car.get("fuel_litres"))
	if _last_fuel >= 0.0 and fuel - _last_fuel > 0.3 and _loud():
		_fuel_sounds(fuel - _last_fuel)
	_last_fuel = fuel
	var dirt := float(_car.get("dirt"))
	if _last_dirt > 0.05 and dirt <= 0.01 and _loud():
		_wash_sounds()
	_last_dirt = dirt
	var look := {"paint": _car.get("paint_color"), "livery": _car.get("custom_livery"), "finish": _car.get("finish")}
	if not _last_look.is_empty() and look != _last_look and _loud():
		_spray_sounds(spray_kind(_last_look, look))
	_last_look = look.duplicate(true)


## What the spray shop just did, from the car's look before and after:
## "respray", "livery", "finish" or "".
static func spray_kind(before: Dictionary, after: Dictionary) -> String:
	if before.get("paint") != after.get("paint"):
		return "respray"
	if before.get("livery") != after.get("livery"):
		return "livery"
	if before.get("finish") != after.get("finish"):
		return "finish"
	return ""


## A respray: masked up, then the gun. A livery: tape and a rattle can. A
## clear coat: just the gun. Played flat, since you're at the shop's counter.
func _spray_sounds(kind: String) -> void:
	match kind:
		"respray":
			Audio.play_2d("garage/garage_masking_tape", "UI", -8.0)
			get_tree().create_timer(1.6).timeout.connect(func() -> void:
				Audio.play_2d("garage/garage_spray_gun", "UI", -6.0))
		"livery":
			Audio.play_2d("garage/garage_masking_tape", "UI", -8.0)
			get_tree().create_timer(1.6).timeout.connect(func() -> void:
				Audio.play_2d("garage/garage_spray_paint", "UI", -6.0))
		"finish":
			Audio.play_2d("garage/garage_spray_gun", "UI", -6.0)


func _fuel_sounds(litres: float) -> void:
	var pos: Vector3 = _car.global_position
	Audio.play_at("garage/garage_fuel_nozzle_in", pos)
	var flow := Audio.play_at("garage/garage_fuel_flow", pos, -2.0)
	var dur := clampf(litres / 12.0, 1.2, 3.5)
	get_tree().create_timer(dur).timeout.connect(func() -> void:
		if flow and flow.playing:
			flow.stop()
		Audio.play_at("garage/garage_fuel_nozzle_out", pos)
		Audio.play_at("garage/garage_servo_chime", pos, -6.0))


func _wash_sounds() -> void:
	var pos: Vector3 = _car.global_position
	var brushes := Audio.play_at("garage/garage_wash_brushes", pos, -2.0)
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if brushes and brushes.playing:
			brushes.stop()
		Audio.play_at("garage/garage_wash_drips", pos, -4.0))


# ---------------------------------------------------------------------------
# The map and the townhouse
# ---------------------------------------------------------------------------

## On the real map the ambience follows where you are (city, Kings Park, the
## river...). On the test grid it stays as it is.
func _update_zone(delta: float) -> void:
	if not is_instance_valid(_map):
		return
	_zone_timer -= delta
	if _zone_timer > 0.0:
		return
	_zone_timer = 1.0
	# Points of interest for the place ambience, once the map's index is in.
	if not _pois_loaded and _map.has_method("get_pois"):
		var pois: Array = _map.get_pois()
		if not pois.is_empty():
			Audio.ambience.clear_places()
			Audio.ambience.add_map_pois(pois)
			_pois_loaded = true
	var ear: Node3D = Audio.listener()
	if ear:
		Audio.ambience.set_zone(Audio.ambience.zone_here(ear.global_position))
		Audio.ambience.update_places(ear.global_position)


func _home_pos() -> Vector3:
	return (_home as Node3D).global_position if _home is Node3D else Vector3.ZERO


func _on_home_door(door_name: StringName, open: bool) -> void:
	var door := (_home as Node).find_child(String(door_name), true, false) as Node3D
	var pos := door.global_position if door else _home_pos()
	# The heavy front door has its own sound; the gates latch like the inside doors.
	var kind := "front" if door_name == &"Door_Front" else "internal"
	Audio.play_at("home/home_%s_door_%s" % [kind, "open" if open else "close"], pos, -2.0)


func _on_slept(_day: int) -> void:
	Audio.play_at("home/home_bed_get_in", _home_pos(), -4.0)
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		Audio.play_2d("home/home_day_ends", "Music", -2.0))


# ---------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------

func _update_pause() -> void:
	var paused := get_tree().paused
	if paused != _was_paused:
		_was_paused = paused
		# Soft: most screens that pause also pop a card that clicks (UiStyle.animate).
		Audio.ui("ui_menu_select" if paused else "ui_menu_back", -12.0)


func _update_panels() -> void:
	var phone_open: bool = is_instance_valid(_phone) and _phone.has_method("is_open") and _phone.is_open()
	if phone_open != _phone_open:
		_phone_open = phone_open
		Audio.ui("ui_map_open" if phone_open else "ui_map_close", -4.0)
	var shop_open: bool = is_instance_valid(_workshop) and _workshop.has_method("is_open") and _workshop.is_open()
	if shop_open != _workshop_open:
		_workshop_open = shop_open
		if shop_open:
			_room_tone.stream = Audio.stream("garage/garage_room_tone", true)
			_room_tone.play()
			Audio.play_2d("garage/garage_ratchet", "UI", -10.0)
		else:
			_room_tone.stop()


## (Buttons tick and click through UiTheme; sliders tick here when let go.)
func _on_node_added(node: Node) -> void:
	if node.has_signal("got_in") and node.has_signal("got_out") and not node.get("plays_car_sounds"):  # OnFoot
		node.connect("got_in", _on_got_in)
		node.connect("got_out", _on_got_out)
	elif node is Slider:
		var s := node as Slider
		s.drag_ended.connect(func(_changed) -> void: Audio.ui("ui_menu_move", -8.0))


# ---------------------------------------------------------------------------
# Getting in and out of the car, and the phone
# ---------------------------------------------------------------------------

## Phone buzz and ping for fine notices and messages.
func phone_notify() -> void:
	Audio.ui("ui_phone_notify", -3.0)


func _player_car_sounds() -> Node:
	var car := get_tree().get_first_node_in_group(&"player_car")
	if car == null:
		return null
	return car.find_child("CarSounds", true, false)


func _after(seconds: float, cs: Node, fn: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(cs):
			fn.call())


## Until OnFoot plays its own get-in/out sequence through CarSounds (it sets
## plays_car_sounds), a short one here.
## In: the door opens (heard outside), shuts behind you (inside), belt on.
func _on_got_in() -> void:
	var cs := _player_car_sounds()
	if cs == null:
		return
	cs.door(true, false, 0)
	_after(0.9, cs, func() -> void: cs.door(false, false, 1))
	_after(1.6, cs, func() -> void: cs.seatbelt(true))


## Out: belt off, the door opens from inside and shuts behind you.
func _on_got_out() -> void:
	var cs := _player_car_sounds()
	if cs == null:
		return
	cs.seatbelt(false)
	_after(0.5, cs, func() -> void: cs.door(true, false, 1))
	_after(1.5, cs, func() -> void: cs.door(false, false, 0))
