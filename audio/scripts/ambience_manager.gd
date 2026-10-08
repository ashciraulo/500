extends Node
## Ambience and weather sound: Audio.ambience.
##
## - Zone beds: set_zone("kingspark") crossfades to that zone's bed for the
##   weather and time, and sprinkles that zone's one-shots (birds, dogs,
##   far trains) around the listener in 3D. Sirens aren't sprinkled: the
##   city's TrafficManager sends a few emergency calls a day (traffic_audio). In order of preference:
##   amb_<zone>_rain (raining), amb_<zone>_dawn (05:00-07:00),
##   amb_<zone>_late (01:00-05:00), then amb_<zone>_day / _night, skipping
##   any that don't exist. A change of rain or time crossfades it again.
## - Weather: rain beds outside and on the roof (inside the car), wind,
##   thunder after lightning, cicadas on clear days.
##
## - Home: within HOME_RADIUS of the townhouse the zone is "home", a quiet
##   back lane (zone_here()). Indoors (Audio.set_indoors) the street and the
##   weather come through the walls and rain is heard on the windows.
##
## - Places: close-up detail for a point of interest (a beach, a lookout,
##   bush, Elizabeth Quay, the river bank, a car park) over the zone bed,
##   heard from the place itself (a 3D source at the nearest one of each
##   kind) as the listener comes within its radius. See update_places().
##
## Weather and time come from the Weather and GameClock autoloads (rain,
## wind, lightning signal, time_of_day). Without them (tests, other scenes)
## they can be pushed in with set_weather() / set_time_of_day().

const FADE_S := 4.0
## The zone bed sits under the sounds that come from somewhere (traffic,
## people, places), so moving about is what you hear change.
const BED_DB := -4.0
## Rain on the roof (and on the windscreen, SCREEN_TRIM) sits well under the
## radio and engine in the cabin mix.
const ROOF_TRIM := 0.12
const SCREEN_TRIM := 0.1
## Rain on the windows indoors at home, at its loudest (a storm) about 0.2.
const WINDOW_RAIN := 0.15
## The wet bed comes in above RAIN_WET_ON and goes again below RAIN_WET_OFF
## (hysteresis, so rain hovering around 0.25 doesn't flap between beds).
const RAIN_WET_ON := 0.3
const RAIN_WET_OFF := 0.2

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
		["amb/amb_train_pass", "any", 90.0, 240.0],
	],
	"northbridge": [
		["amb/amb_dog_bark_far", "night", 60.0, 160.0],
	],
	# Home is for winding down: a magpie or a wagtail now and then, no more.
	"home": [
		["amb/amb_bird_magpie", "day", 50.0, 150.0],
		["amb/amb_bird_wagtail", "day", 70.0, 180.0],
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
## The townhouse (set by Audio.hooks once the map has it). Within HOME_RADIUS
## of it the zone is "home" rather than Northbridge's cafes and clubs.
var home_at := Vector3.INF
const HOME_RADIUS := 90.0

## Place layers (res://audio/amb/place/place_<type>_loop, _night_loop after
## dark). Places come from the map's points of interest (add_map_pois(), fed
## MapStreamer.get_pois() by Audio.hooks), from nodes in the "poi" group with
## meta "poi_type" (and optionally "radius", metres), or from add_place().
const PLACE_TYPES := ["beach", "surf", "lookout", "bush", "quay", "riverside", "carpark", "jetty", "groyne",
		"tackle_shop", "photo_lab", "wrong_cockatoos", "servo"]
const PLACE_RADIUS := 120.0
## The servos you can fill up at (MapStreamer builds them from this file):
## each one's forecourt is a "servo" place. The map's other servo POIs (the
## real ones without a bay) stay empty car parks at night, unless one of
## these stands within SERVO_NEAR of it.
const SERVOS_PATH := "res://data/world/servos.json"
const SERVO_RADIUS := 40.0
const SERVO_NEAR := 250.0
## Full volume inside this fraction of the radius, falling away with
## distance past it and silent a little past the radius (PLACE_REACH).
const PLACE_FULL := 0.35
const PLACE_REACH := 1.3
## Places are wide (a beach, a car park), so their sound pans only gently.
const PLACE_PANNING := 0.6
var _places: Array = []        # [type, Vector3, radius, night_only]
## Map POIs whose sound isn't given by their kind alone (map thread's ids).
const POI_PLACES := {
	"landmark_bell_tower": "quay", "landmark_elizabeth_quay_bridge": "quay",
	"quiet_point_fraser": "riverside", "quiet_mill_point_foreshore": "riverside",
	"quiet_matagarup_car_park": "riverside", "landmark_matagarup_bridge": "riverside",
	"quiet_lake_monger": "riverside", "landmark_state_war_memorial": "lookout",
	"fishing_north_mole": "groyne", "fishing_south_cottesloe_groyne": "groyne",
}
## Beaches open to the swell (the rest are the calmer Cottesloe end).
const SURF_SUBURBS := ["Trigg", "Scarborough", "City Beach", "Floreat"]
var _place_near := {}          # type -> [Vector3, radius] of the nearest one in reach
var _place_players := {}       # type -> AudioStreamPlayer3D at that place
var _place_night := {}         # type -> whether the night loop is loaded

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
	# Fremantle: the West End, the Fishing Boat Harbour and the port
	["fremantle", -10500.0, 12300.0, 1000.0],
	# Bold Park and Reabold Hill: the same banksia and tuart bush as Kings Park
	["kingspark", -7370.0, -610.0, 950.0],
	# Wetlands: Herdsman Lake, Lake Monger (Galup), Gwelup, Lake Claremont, Alfred Cove
	["wetland", -4630.0, -2910.0, 1150.0],
	["wetland", -2420.0, -1780.0, 560.0],
	["wetland", -5850.0, -7520.0, 420.0],
	["wetland", -7280.0, 3150.0, 420.0],
	["wetland", -3700.0, 9300.0, 650.0],
	# The ocean coast, Trigg to Leighton: circles centred just off the sand
	["beach", -9700.0, -8800.0, 480.0],
	["beach", -9720.0, -8000.0, 480.0],
	["beach", -9650.0, -7200.0, 480.0],
	["beach", -9550.0, -6400.0, 480.0],
	["beach", -9450.0, -5600.0, 480.0],
	["beach", -9380.0, -4800.0, 480.0],
	["beach", -9350.0, -4000.0, 480.0],
	["beach", -9380.0, -3200.0, 480.0],
	["beach", -9420.0, -2400.0, 480.0],
	["beach", -9450.0, -1600.0, 480.0],
	["beach", -9450.0, -800.0, 480.0],
	["beach", -9450.0, 0.0, 480.0],
	["beach", -9450.0, 800.0, 480.0],
	["beach", -9450.0, 1600.0, 480.0],
	["beach", -9480.0, 2400.0, 480.0],
	["beach", -9550.0, 3200.0, 480.0],
	["beach", -9620.0, 4000.0, 480.0],
	["beach", -9700.0, 4800.0, 480.0],
	["beach", -9780.0, 5600.0, 480.0],
	["beach", -9780.0, 6400.0, 480.0],
	["beach", -9720.0, 7200.0, 480.0],
	["beach", -9600.0, 8000.0, 480.0],
	["beach", -9500.0, 8800.0, 480.0],
	["beach", -9450.0, 9500.0, 480.0],
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
var _bed_key := ""       # zone|wet|period the current bed was picked for
var _wet := false        # rain bed wanted (see RAIN_WET_ON/OFF)
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
	# Indoors at home: rain on the windows (on SFX, so the walls don't dull it
	# twice: the recording is already heard through them).
	_layer("rain_windows", "home/home_rain_windows", "SFX")
	call_deferred("_update_bed", true)


## Register a place that isn't a node. night_only places (servos and
## drive-throughs as empty car parks) are silent by day.
func add_place(type: String, pos: Vector3, radius := PLACE_RADIUS, night_only := false) -> void:
	_places.append([type, pos, radius, night_only])


## The map's points of interest ({id, kind, suburb, p, at, ...}, from
## MapStreamer.get_pois()) as place layers: beaches, lookouts (Kings Park ones
## with the bush under the wind), the quay and the river by id, quiet spots
## as car parks, fillable servos as servos, other servos and drive-throughs
## as car parks at night.
func add_map_pois(pois: Array) -> void:
	var servos := servo_positions()
	for at in servos:
		add_place("servo", at, SERVO_RADIUS)
	for poi in pois:
		if not poi is Dictionary or not poi.has("at"):
			continue
		var id := String(poi.get("id", ""))
		var kind := String(poi.get("kind", ""))
		var at: Vector3 = poi["at"]
		var stop: Vector3 = poi.get("p", at)
		var kings_park := String(poi.get("suburb", "")) == "Kings Park" or id == "landmark_state_war_memorial"
		if POI_PLACES.has(id):
			add_place(POI_PLACES[id], at)
		elif kind == "beach":
			add_place("surf" if String(poi.get("suburb", "")) in SURF_SUBURBS else "beach", at, 150.0)
		elif kind == "lookout":
			add_place("lookout", at)
		if kings_park and kind in ["lookout", "landmark"]:
			add_place("bush", at)
		if kind in ["jetty", "fishing_spot", "fishing"] and not POI_PLACES.has(id):
			add_place("jetty", at, 70.0)
		elif kind in ["groyne", "mole", "breakwater"]:
			add_place("groyne", at, 90.0)
		elif kind in ["tackle_shop", "bait_shop"]:
			add_place("tackle_shop", at, 18.0)
		elif kind in ["photo_lab", "bird_lab"]:
			add_place("photo_lab", at, 18.0)
		if kind == "quiet_spot":
			add_place("carpark", stop, 60.0)
		elif kind == "servo" and servos.any(func(p: Vector3) -> bool: return p.distance_to(stop) < SERVO_NEAR):
			pass  # a servo you can fill up at is next to it, with its own sound
		elif kind == "servo" or kind == "drive_thru":
			add_place("carpark", stop, 60.0, true)


## Where the fillable servos' pump bays are (data/world/servos.json).
static func servo_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not FileAccess.file_exists(SERVOS_PATH):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SERVOS_PATH))
	if not data is Dictionary:
		return out
	for entry in data.get("servos", []):
		var p: Array = entry.get("position", [])
		if p.size() == 3:
			out.append(Vector3(p[0], p[1], p[2]))
	return out


func clear_places() -> void:
	_places.clear()


## The nearest place of each type within reach of pos, from the "poi"
## nodes and the added places. Audio.hooks calls this once a second.
func update_places(pos: Vector3) -> void:
	var near := {}
	var best := {}
	var all: Array = []
	for p in _places:
		if not (p[3] and not is_night):
			all.append(p)
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("poi"):
			if n is Node3D and n.has_meta("poi_type"):
				all.append([String(n.get_meta("poi_type")), (n as Node3D).global_position,
						float(n.get_meta("radius", PLACE_RADIUS)), false])
	for p in all:
		var type: String = p[0]
		if not PLACE_TYPES.has(type):
			continue
		var r: float = maxf(p[2], 1.0)
		var d := Vector2(pos.x - p[1].x, pos.z - p[1].z).length()
		# Nearest relative to its size, so a big beach beats a small car park.
		var rel := d / (r * PLACE_REACH)
		if rel < 1.0 and rel < best.get(type, INF):
			best[type] = rel
			near[type] = [p[1], r]
	_place_near = near


## How loud each place type is at pos (0..1): what the 3D falloff of its
## nearest place gives (tests and debugging).
func place_level(type: String, pos: Vector3) -> float:
	if not _place_near.has(type):
		return 0.0
	var at: Vector3 = _place_near[type][0]
	var r: float = _place_near[type][1]
	var d := at.distance_to(pos)
	var unit := r * PLACE_FULL
	return minf(1.0, unit / maxf(d, 0.001)) * maxf(0.0, 1.0 - d / (r * PLACE_REACH))


func place_sound(type: String) -> String:
	var night := "amb/place/place_%s_night_loop" % type
	var day := "amb/place/place_%s_loop" % type
	if is_night and Audio.has(night):
		return night
	return day if Audio.has(day) else (night if Audio.has(night) else "")


func _update_place_layers(delta: float) -> void:
	for type in PLACE_TYPES:
		var here = _place_near.get(type)
		var p: AudioStreamPlayer3D = _place_players.get(type)
		if p == null:
			if here == null:
				continue
			p = _new_place_player()
			_place_players[type] = p
		var amount := 1.0 if here != null else 0.0
		if here != null:
			var r: float = here[1]
			p.global_position = here[0] + Vector3.UP * 1.5
			p.unit_size = r * PLACE_FULL
			p.max_distance = r * PLACE_REACH
		var sound := place_sound(type)
		if sound == "":
			continue
		if p.stream == null or _place_night.get(type, false) != (sound.ends_with("_night_loop")):
			# Swap day/night while it's quiet, or with a short dip if it isn't.
			if p.playing and db_to_linear(p.volume_db) > 0.05:
				amount = 0.0
			else:
				p.stop()
				p.stream = Audio.stream(sound, true)
				_place_night[type] = sound.ends_with("_night_loop")
		# The distance falloff is the 3D player's; this only fades a place
		# in and out when it comes into reach or swaps day for night.
		var cur := db_to_linear(p.volume_db) if p.playing else 0.0
		var v := lerpf(cur, amount, 1.0 - exp(-delta / 1.5))
		if v < 0.002 and amount < 0.002:
			if p.playing:
				p.stop()
			continue
		if not p.playing and p.stream:
			p.volume_db = -60.0
			p.play(randf() * p.stream.get_length())
			v = 0.001
		p.volume_db = linear_to_db(maxf(v, 0.001))


func _new_place_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Ambience"
	p.volume_db = -80.0
	p.max_db = 0.0
	p.panning_strength = PLACE_PANNING
	p.attenuation_filter_cutoff_hz = 20500.0  # no extra muffling: the beds are already distant
	add_child(p)
	return p


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


## zone_at(), except close to home (see home_at).
func zone_here(pos: Vector3) -> String:
	if home_at != Vector3.INF and Vector2(pos.x - home_at.x, pos.z - home_at.z).length() < HOME_RADIUS:
		return "home"
	return zone_at(pos)


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
	_refresh_bed()


func set_time_of_day(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	is_night = time_of_day < 6.0 or time_of_day >= 19.0
	_refresh_bed()


## "dawn" (05:00-07:00), "late" (01:00-05:00), else "night" or "day".
func bed_period() -> String:
	if time_of_day >= 5.0 and time_of_day < 7.0:
		return "dawn"
	if time_of_day >= 1.0 and time_of_day < 5.0:
		return "late"
	return "night" if is_night else "day"


func _update_wet() -> void:
	if _wet and rain < RAIN_WET_OFF:
		_wet = false
	elif not _wet and rain > RAIN_WET_ON:
		_wet = true


## Re-picks the bed when the wet state (with hysteresis) or the time period
## changed. Cheap when nothing changed, so it runs every frame.
func _refresh_bed() -> void:
	_update_wet()
	var key := "%s|%s|%s" % [zone, _wet, bed_period()]
	if key != _bed_key and _bed_key != "":
		_update_bed()


## The bed to play now: the most specific one that exists.
func _pick_bed() -> String:
	var base := "amb/amb_" + zone
	var period := bed_period()
	var tries: Array[String] = []
	if _wet:
		tries.append(base + "_rain")
	if period == "dawn" or period == "late":
		tries.append(base + "_" + period)
	tries.append(base + ("_night" if is_night else "_day"))
	tries.append(base)  # zones with one bed for everything (e.g. tunnel)
	for t in tries:
		if Audio.has(t):
			return t
	return ""


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
		_refresh_bed()
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
	_refresh_bed()


func _on_weather_lightning(_strength: float, distance_m: float) -> void:
	lightning(distance_m)


# ---------------------------------------------------------------------------
# Mixing
# ---------------------------------------------------------------------------

func _update_bed(instant := false) -> void:
	_update_wet()
	_bed_key = "%s|%s|%s" % [zone, _wet, bed_period()]
	var want := _pick_bed()
	if want == "" or want == _bed_name:
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
	tw.tween_property(incoming, "volume_db", BED_DB, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_property(outgoing, "volume_db", -80.0, dur)
	tw.chain().tween_callback(outgoing.stop)
	var radio: Node = get_parent().get("radio") if get_parent() else null
	if radio:
		radio.after_midnight = time_of_day < 3.0


func _process(delta: float) -> void:
	if not _pushed:
		_poll_source()
	var inside: bool = Audio.is_player_inside()
	var indoors: bool = Audio.is_indoors() and not inside
	var light := clampf(rain * 2.0, 0.0, 1.0) * (1.0 - storm)
	var heavy := maxf(storm, clampf(rain * 2.0 - 1.0, 0.0, 1.0))
	var out := 0.5 if inside else (0.4 if indoors else 1.0)
	_set_layer("rain_light_out", light * out, delta)
	_set_layer("rain_heavy_out", heavy * out, delta)
	# A soft patter: home is the quiet place, so even a storm stays under the
	# storm outside (was 0.5, the loudest thing in the house).
	_set_layer("rain_windows", maxf(light, heavy * 1.4) * WINDOW_RAIN * (1.0 if indoors else 0.0), delta)
	var roof := 0.0 if fabric_roof else 1.0
	_set_layer("rain_light_roof", light * roof * ROOF_TRIM * (1.0 if inside else 0.0), delta)
	_set_layer("rain_heavy_roof", heavy * roof * ROOF_TRIM * (1.0 if inside else 0.0), delta)
	_set_layer("rain_light_fabric", light * (1.0 - roof) * ROOF_TRIM * (1.0 if inside else 0.0), delta)
	_set_layer("rain_heavy_fabric", heavy * (1.0 - roof) * ROOF_TRIM * (1.0 if inside else 0.0), delta)
	_set_layer("rain_screen", maxf(light, heavy) * SCREEN_TRIM * (1.0 if inside else 0.0), delta)
	_set_layer("wind", (0.15 + 0.85 * maxf(wind, storm)) * out, delta)
	var clear_day := (1.0 if not is_night and hot_day else 0.0) * (1.0 - clampf(rain * 3.0, 0.0, 1.0))
	_set_layer("cicadas", clear_day * (1.0 if zone in ["kingspark", "suburbs"] else 0.35), delta)
	var radio: Node = get_parent().get("radio") if get_parent() else null
	if radio:
		radio.storm = storm > 0.5
		radio.after_midnight = time_of_day < 3.0
	_sprinkle(delta)
	_update_place_layers(delta)


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
			if key.contains("train") and _real_trains():
				continue  # the city's own trains are running: no phantom ones
			# Somewhere off in the trees or the next street, falling away
			# with distance like anything else.
			var ang := randf() * TAU
			var dist := randf_range(30.0, 110.0)
			var pos := cam.global_position + Vector3(cos(ang) * dist, randf_range(3.0, 15.0), sin(ang) * dist)
			Audio.play_at(key, pos, randf_range(-6.0, 0.0), "Ambience", 0.06, 10.0, 260.0)


## True when the city's traffic (with its trains) has sound of its own.
func _real_trains() -> bool:
	var hooks: Node = get_parent().get("hooks") if get_parent() else null
	var ta = hooks.get("traffic") if hooks else null
	return ta is Node and is_instance_valid(ta) and ta.manager != null and "trains_enabled" in ta.manager \
			and bool(ta.manager.trains_enabled)
