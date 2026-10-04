extends Node
## Ambience and weather sound: Audio.ambience.
##
## - Zone beds: set_zone("kingspark") crossfades to amb_kingspark_day or
##   amb_kingspark_night (whichever matches the time), and sprinkles that
##   zone's one-shots (birds, dogs, trains...) around the listener in 3D.
## - Weather: rain beds outside and on the roof (inside the car), wind,
##   thunder after lightning, cicadas on clear days.
##
## Weather and time come from the Weather and GameClock autoloads (rain,
## wind, lightning signal, time_of_day). Without them (tests, other scenes)
## they can be pushed in with set_weather() / set_time_of_day().

const FADE_S := 4.0

## One-shots scattered over each zone's bed: [sound, when, min_gap_s, max_gap_s]
## where when is "day", "night" or "any". Names are variant sets in res://audio/amb.
const SPRINKLES := {
	"kingspark": [
		["amb/amb_bird_magpie", "day", 8.0, 25.0],
		["amb/amb_bird_kookaburra", "day", 40.0, 120.0],
		["amb/amb_bird_wagtail", "day", 20.0, 60.0],
		["amb/amb_bird_raven", "any", 30.0, 90.0],
	],
	"cbd": [
		["amb/amb_siren_distant", "any", 60.0, 180.0],
		["amb/amb_train_pass", "any", 90.0, 240.0],
	],
	"northbridge": [
		["amb/amb_siren_distant", "night", 40.0, 120.0],
		["amb/amb_dog_bark_far", "night", 60.0, 160.0],
	],
	"suburbs": [
		["amb/amb_dog_bark_far", "any", 25.0, 80.0],
		["amb/amb_bird_magpie", "day", 15.0, 45.0],
		["amb/amb_bird_raven", "any", 30.0, 90.0],
		["amb/amb_bird_wagtail", "day", 25.0, 70.0],
	],
	"river": [
		["amb/amb_bird_raven", "any", 40.0, 120.0],
		["amb/amb_train_pass", "any", 120.0, 300.0],
	],
	"freeway": [
		["amb/amb_train_pass", "any", 60.0, 160.0],
	],
}

var zone := "cbd"

## Rough areas of the Perth map slice (map/, world metres, x east and z
## south, origin at Little Shenton Lane), as [zone, centre_x, centre_z,
## radius]. The tightest match wins; anywhere else is "suburbs". zone_at()
## reads these; Audio.hooks calls it as the player moves.
const ZONE_AREAS := [
	["northbridge", 350.0, 150.0, 650.0],
	["cbd", 450.0, 950.0, 650.0],
	["kingspark", -1700.0, 1700.0, 950.0],
	["river", 300.0, 2450.0, 800.0],
	["river", -700.0, 2650.0, 650.0],
	["river", 1500.0, 2300.0, 700.0],
	["river", 2500.0, 1700.0, 600.0],
]
var rain := 0.0          # 0..1
var storm := 0.0         # 0..1
var wind := 0.2          # 0..1
var is_night := false
var time_of_day := 12.0  # hours
var hot_day := true      # cicadas (summer); set false in cooler months
var fabric_roof := false # 500C / classics: softer, drummier rain inside

var _bed_a: AudioStreamPlayer
var _bed_b: AudioStreamPlayer
var _bed_name := ""
var _layers := {}        # layer id -> AudioStreamPlayer
var _sprinkle_timers := {}
var _source: Node
var _pushed := false     # set_weather() was called: stop polling autoloads


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_bed_a = _new_player("Ambience")
	_bed_b = _new_player("Ambience")
	# Weather layers. Outside beds go through World (muffled inside the car);
	# roof beds go to Cabin and are only heard inside.
	_layer("rain_light_out", "weather/weather_rain_light_outside", "Weather")
	_layer("rain_heavy_out", "weather/weather_rain_heavy_outside", "Weather")
	_layer("rain_light_roof", "weather/weather_rain_light_roof_metal", "Cabin")
	_layer("rain_heavy_roof", "weather/weather_rain_heavy_roof_metal", "Cabin")
	_layer("rain_light_fabric", "weather/weather_rain_light_roof_fabric", "Cabin")
	_layer("rain_heavy_fabric", "weather/weather_rain_heavy_roof_fabric", "Cabin")
	_layer("rain_screen", "weather/weather_rain_windscreen", "Cabin")
	_layer("wind", "weather/weather_wind_bed", "Weather")
	_layer("cicadas", "weather/weather_cicadas", "Ambience")
	call_deferred("_update_bed", true)


func _new_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


func _layer(id: String, sound: String, bus: String) -> void:
	if not Audio.has(sound):
		return
	var s := Audio.stream(sound, true)
	if s == null:
		return
	var p := _new_player(bus)
	p.stream = s
	_layers[id] = p


# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

## Which ambience zone a world position is in (see ZONE_AREAS).
static func zone_at(pos: Vector3) -> String:
	var best := "suburbs"
	var best_r := 1.0
	for area in ZONE_AREAS:
		var r := Vector2(pos.x - area[1], pos.z - area[2]).length() / float(area[3])
		if r < best_r:
			best_r = r
			best = area[0]
	return best


func set_zone(new_zone: String) -> void:
	if new_zone == zone:
		return
	zone = new_zone
	_sprinkle_timers.clear()
	_update_bed()


func set_weather(rain_intensity: float, storm_amount: float, wind_amount := 0.2) -> void:
	_pushed = true
	rain = clampf(rain_intensity, 0.0, 1.0)
	storm = clampf(storm_amount, 0.0, 1.0)
	wind = clampf(wind_amount, 0.0, 1.0)


func set_time_of_day(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	var night := time_of_day < 6.0 or time_of_day >= 19.0
	if night != is_night:
		is_night = night
		_update_bed()


## Call when lightning flashes; thunder follows at the speed of sound.
func lightning(distance_m: float) -> void:
	var delay := distance_m / 343.0
	var close := distance_m < 1500.0
	var sound := "weather/weather_thunder_close" if close else "weather/weather_thunder_distant"
	var vol := 0.0 if close else -4.0 - distance_m / 2000.0
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		Audio.play_2d(sound, "Weather", vol))


func _poll_source() -> void:
	# The game's Weather and GameClock autoloads (see docs/HOOKS.md).
	var weather := get_node_or_null("/root/Weather")
	if weather:
		rain = clampf(float(weather.rain), 0.0, 1.0)
		# Light rain sits at ~0.35 and storms at 1.0: storm sound fades in above ~0.55.
		storm = clampf((rain - 0.55) / 0.35, 0.0, 1.0)
		wind = clampf(float(weather.wind), 0.0, 1.0)
		if not weather.is_connected("lightning", _on_weather_lightning):
			weather.connect("lightning", _on_weather_lightning)
	var clock := get_node_or_null("/root/GameClock")
	if clock:
		set_time_of_day(float(clock.time_of_day))
	if weather or clock:
		return
	# Otherwise a node in the "weather_source" group with the same fields.
	if _source == null or not is_instance_valid(_source):
		_source = get_tree().get_first_node_in_group("weather_source")
	if _source == null:
		return
	if "rain" in _source:
		rain = clampf(float(_source.rain), 0.0, 1.0)
		storm = clampf((rain - 0.55) / 0.35, 0.0, 1.0)
	if "time_of_day" in _source:
		set_time_of_day(float(_source.time_of_day))


func _on_weather_lightning(_strength: float, distance_m: float) -> void:
	lightning(distance_m)


# ---------------------------------------------------------------------------
# Mixing
# ---------------------------------------------------------------------------

func _update_bed(instant := false) -> void:
	var want := "amb/amb_%s_%s" % [zone, "night" if is_night else "day"]
	if not Audio.has(want):
		want = "amb/amb_" + zone  # zones with one bed for both (e.g. tunnel)
	if want == _bed_name or not Audio.has(want):
		return
	var s := Audio.stream(want, true)
	if s == null:
		return
	_bed_name = want
	var incoming := _bed_b if _bed_a.playing and _bed_a.volume_db > -60.0 else _bed_a
	var outgoing := _bed_a if incoming == _bed_b else _bed_b
	incoming.stream = s
	incoming.volume_db = -60.0
	incoming.play(randf() * incoming.stream.get_length())
	var dur := 0.01 if instant else FADE_S
	var tw := create_tween().set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_property(outgoing, "volume_db", -80.0, dur)
	tw.chain().tween_callback(outgoing.stop)
	var radio: Node = get_parent().get("radio") if get_parent() else null
	if radio:
		radio.after_midnight = time_of_day < 3.0


func _process(delta: float) -> void:
	if not _pushed:
		_poll_source()
	var inside: bool = Audio.is_player_inside()
	var light := clampf(rain * 2.0, 0.0, 1.0) * (1.0 - storm)
	var heavy := maxf(storm, clampf(rain * 2.0 - 1.0, 0.0, 1.0))
	_set_layer("rain_light_out", light * (0.5 if inside else 1.0), delta)
	_set_layer("rain_heavy_out", heavy * (0.5 if inside else 1.0), delta)
	var roof := 0.0 if fabric_roof else 1.0
	_set_layer("rain_light_roof", light * roof * (1.0 if inside else 0.0), delta)
	_set_layer("rain_heavy_roof", heavy * roof * (1.0 if inside else 0.0), delta)
	_set_layer("rain_light_fabric", light * (1.0 - roof) * (1.0 if inside else 0.0), delta)
	_set_layer("rain_heavy_fabric", heavy * (1.0 - roof) * (1.0 if inside else 0.0), delta)
	_set_layer("rain_screen", maxf(light, heavy) * 0.6 * (1.0 if inside else 0.0), delta)
	_set_layer("wind", 0.15 + 0.85 * maxf(wind, storm), delta)
	var clear_day := (1.0 if not is_night and hot_day else 0.0) * (1.0 - clampf(rain * 3.0, 0.0, 1.0))
	_set_layer("cicadas", clear_day * (1.0 if zone in ["kingspark", "suburbs"] else 0.35), delta)
	var radio: Node = get_parent().get("radio") if get_parent() else null
	if radio:
		radio.storm = storm > 0.5
		radio.after_midnight = time_of_day < 3.0
	_sprinkle(delta)


func _set_layer(id: String, amount: float, delta: float) -> void:
	var p: AudioStreamPlayer = _layers.get(id)
	if p == null:
		return
	# Smooth ~2 s so weather changes fade rather than snap.
	var cur := db_to_linear(p.volume_db) if p.playing else 0.0
	var target := clampf(amount, 0.0, 1.0)
	var v := lerpf(cur, target, 1.0 - exp(-delta / 2.0))
	if v < 0.002 and target < 0.002:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.volume_db = -60.0
		p.play(randf() * p.stream.get_length())
		v = 0.001
	p.volume_db = linear_to_db(maxf(v, 0.001))


func _sprinkle(delta: float) -> void:
	var list: Array = SPRINKLES.get(zone, [])
	if list.is_empty():
		return
	var cam: Node3D = Audio.listener()
	if cam == null:
		return
	for entry in list:
		var key: String = entry[0]
		if (entry[1] == "day" and is_night) or (entry[1] == "night" and not is_night):
			continue
		if not _sprinkle_timers.has(key):
			_sprinkle_timers[key] = randf_range(entry[2], entry[3]) * 0.5
		_sprinkle_timers[key] -= delta
		if _sprinkle_timers[key] <= 0.0:
			_sprinkle_timers[key] = randf_range(entry[2], entry[3])
			if rain > 0.6 and key.contains("bird"):
				continue  # birds keep quiet in heavy rain
			var ang := randf() * TAU
			var dist := randf_range(25.0, 90.0)
			var pos := cam.global_position + Vector3(cos(ang) * dist, randf_range(3.0, 15.0), sin(ang) * dist)
			Audio.play_at(key, pos, randf_range(-6.0, 0.0), "Ambience", 0.06)
