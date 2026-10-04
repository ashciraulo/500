class_name CarSounds
extends Node3D
## Everything the car does besides its engine and tyres: horn, wipers,
## handbrake, indicators, doors, and telling Audio whether the player is
## inside (the camera sits at the driver's seat) so the world gets muffled.
##
## Add as a child of the car (under its "Audio" node). The car is found as
## the nearest ancestor with get_telemetry(); see docs/HOOKS.md.

## "modern" (2013 Pop and the other new 500s), "classic" or "abarth".
@export_enum("modern", "classic", "abarth") var style := "modern"
## Door sounds: "modern", "abarth", "classic", "suicide" (the rear-hinged
## early classics) or "none" for a car with no doors (the Jolly).
@export_enum("modern", "abarth", "classic", "suicide", "none") var door_family := "modern"
## Push-button start instead of a key (New 500e, Abarth 500e).
@export var push_start := false
## Electric: key "off" plays the power-down chime instead of nothing.
@export var electric := false
## Player input (horn) only for the car the player drives.
@export var player_controlled := true
## Distance from the driver's seat within which the camera counts as inside.
@export var inside_radius := 1.4

var indicator_on := false: set = set_indicator

var _car: Node
var _seat: Node3D
var _horn: AudioStreamPlayer3D
var _wipers: AudioStreamPlayer3D
var _indicator: AudioStreamPlayer3D
var _buffet: AudioStreamPlayer3D
var _wiper_speed := 0
var _handbrake_up := false
var _squeak_timer := 0.0


func _ready() -> void:
	_car = EngineAudio.find_vehicle(self, NodePath())
	if _car:
		_seat = _car.get_node_or_null("DriverSeat") as Node3D
		if "player_controlled" in _car:
			player_controlled = bool(_car.player_controlled)
		if _car.has_signal("car_changed"):
			_car.connect("car_changed", _on_car_changed)
		if "car_id" in _car:
			_on_car_changed(String(_car.car_id))
	_horn = _player("SFX", 9.0)
	_wipers = _player("Cabin", 2.0)
	_indicator = _player("Cabin", 2.0)
	_buffet = _player("Weather", 4.0)
	_buffet.stream = Audio.stream("weather/weather_wind_buffet", true)


## Cars with rear-hinged "suicide" doors, and the doorless beach car.
const SUICIDE_DOORS := ["classic_nuova", "classic_sport", "classic_d", "classic_giardiniera"]
const NO_DOORS := ["classic_jolly"]
const PUSH_START := ["e_500e_2020", "abarth_500e"]


## Horn, doors and indicator follow the car: classics meep, Abarths blare.
func _on_car_changed(car_id: String) -> void:
	if car_id.begins_with("classic_"):
		style = "classic"
	elif car_id.begins_with("abarth"):
		style = "abarth"
	else:
		style = "modern"
	door_family = style
	if car_id in SUICIDE_DOORS:
		door_family = "suicide"
	elif car_id in NO_DOORS:
		door_family = "none"
	push_start = car_id in PUSH_START
	electric = car_id.begins_with("e_") or car_id == "abarth_500e"


func _player(bus: String, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.unit_size = unit
	p.max_distance = 120.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	if player_controlled:
		_update_inside()
		if Input.is_action_just_pressed("horn"):
			horn(true)
		elif Input.is_action_just_released("horn"):
			horn(false)
	_update_wipers(delta)
	if _car and _car.has_method("get_telemetry"):
		var t: Dictionary = _car.get_telemetry()
		# Wind buffeting rises with speed, more so on windy days.
		var w: float = clampf((float(t.get("speed_kmh", 0.0)) - 40.0) / 80.0, 0.0, 1.0) \
				* (0.4 + 0.6 * Audio.ambience.wind)
		if w > 0.01 and _buffet.stream:
			if not _buffet.playing:
				_buffet.play(randf() * _buffet.stream.get_length())
			_buffet.volume_db = linear_to_db(w) - 4.0
		elif _buffet.playing:
			_buffet.stop()
		var hb: float = t.get("handbrake", 0.0)
		if hb > 0.5 and not _handbrake_up:
			_handbrake_up = true
			Audio.play_at("car/car_handbrake_up", global_position, -6.0, "Cabin")
		elif hb < 0.2 and _handbrake_up:
			_handbrake_up = false
			Audio.play_at("car/car_handbrake_release", global_position, -8.0, "Cabin")


func _update_inside() -> void:
	if _car and "is_player_inside" in _car:
		Audio.set_player_inside(bool(_car.is_player_inside))
		return
	var cam: Node3D = Audio.listener()
	if cam == null or _seat == null:
		return
	Audio.set_player_inside(cam.global_position.distance_to(_seat.global_position) < inside_radius)


## Horn: hold to keep it sounding.
func horn(down: bool) -> void:
	if down:
		var s := "car/car_horn_modern_hold"
		if style == "classic":
			s = "car/car_horn_classic_meep"
		elif style == "abarth":
			s = "car/car_horn_abarth"
		_horn.stream = Audio.stream(s, style == "modern")
		_horn.play()
	elif _horn.playing and style == "modern":
		_horn.stop()
		Audio.play_at("car/car_horn_modern_tap", global_position, -12.0)  # release tail


## Wipers follow the rain: off, slow, fast. Call set_wipers() to override.
func _update_wipers(delta: float) -> void:
	var rain: float = Audio.ambience.rain
	var want := 0
	if rain > 0.6:
		want = 2
	elif rain > 0.05:
		want = 1
	if want != _wiper_speed:
		set_wipers(want)
	# On a drying screen the rubber starts to squeak now and then.
	if _wiper_speed > 0 and rain < 0.12:
		_squeak_timer -= delta
		if _squeak_timer <= 0.0:
			_squeak_timer = randf_range(2.5, 7.0)
			Audio.play_at("car/car_wiper_squeak", global_position, -10.0, "Cabin")


func set_wipers(speed: int) -> void:
	_wiper_speed = speed
	if speed == 0:
		_wipers.stop()
		return
	_wipers.stream = Audio.stream("car/car_wipers_fast" if speed == 2 else "car/car_wipers_slow", true)
	_wipers.volume_db = -15.0
	_wipers.play()


func set_indicator(on: bool) -> void:
	indicator_on = on
	if _indicator == null:
		return
	if on:
		_indicator.stream = Audio.stream("car/car_indicator_classic" if style == "classic" else "car/car_indicator_modern", true)
		_indicator.volume_db = -8.0
		_indicator.play()
	else:
		_indicator.stop()


## A door opening or shutting (slam = shut hard). heard_inside: 1 = from the
## driver's seat (duller, boomier, the cabin's air squeezed), 0 = from
## outside, -1 = wherever the camera is now.
func door(open: bool, slam := false, heard_inside := -1) -> void:
	if door_family == "none":
		return  # no doors to shut
	var inside := Audio.is_player_inside() if heard_inside < 0 else heard_inside == 1
	var action := "open" if open else ("slam" if slam else "close")
	var sound := "car/car_door_%s_%s%s" % [action, door_family, "_in" if inside else ""]
	if not Audio.has(sound):
		sound = "car/car_door_%s_%s" % ["open" if open else "close", "classic" if style == "classic" else "modern"]
	Audio.play_at(sound, _seat_pos(), (3.0 if slam else 0.0) - (2.0 if inside else 0.0),
			"Cabin" if inside else "SFX")


## Seatbelt: on = the tongue clicks into the buckle, off = the button,
## the webbing reeling back in and the tongue knocking the pillar.
func seatbelt(on: bool) -> void:
	Audio.play_at("car/car_seatbelt_click" if on else "car/car_seatbelt_unbuckle", _seat_pos(), -4.0, "Cabin")


## Ignition, in the order you'd do it:
##   "in"    key into the barrel (nothing on push-start cars)
##   "turn"  key to ON (push-start cars: the start button; classics: the key
##           then the starter lever between the seats)
##   "start" the classics' starter lever on its own
##   "ready" an electric car's ready-to-drive chime
##   "off"   key back (electric cars: the power-down chime)
##   "out"   key pulled, with the keyring swinging
## EngineAudio plays the engine's own start-up and shut-down.
func key(action: String) -> void:
	var sound := ""
	match action:
		"in":
			sound = "" if push_start else "car/car_ignition_key_in"
		"turn":
			sound = "car/car_start_button" if push_start else "car/car_ignition_key_turn"
			if style == "classic":
				get_tree().create_timer(0.45).timeout.connect(func() -> void:
					if is_inside_tree():
						Audio.play_at("car/car_starter_lever_classic", _seat_pos(), -3.0, "Cabin"))
		"start":
			sound = "car/car_starter_lever_classic" if style == "classic" else ""
		"ready":
			sound = "car/car_ev_ready_chime" if electric else ""
		"off":
			if electric:
				sound = "car/car_ev_power_off"
			elif not push_start:
				sound = "car/car_ignition_key_turn"
		"out":
			sound = "" if push_start else "car/car_ignition_key_out"
	if sound != "":
		Audio.play_at(sound, _seat_pos(), -6.0 if action in ["ready", "off"] and electric else -3.0, "Cabin")


## Phone buzz and ping (fine notices, messages). 2D on the UI bus.
func notify() -> void:
	Audio.ui("ui_phone_notify", -3.0)


func _seat_pos() -> Vector3:
	return _seat.global_position if _seat and _seat.is_inside_tree() else global_position
