extends Node
## Autoload "Audio": the one place the game talks to for sound.
##
## - Builds the audio bus layout at start-up (so no .tres needs editing).
## - Finds sounds by name: Audio.stream("car/car_horn_modern_tap") or a random
##   variant with Audio.variant("impact/imp_crash_medium") which picks one of
##   imp_crash_medium_01.._05. Files are found by scanning res://audio, so
##   replacing a file with your own recording (same name) just works.
## - One-shots: Audio.ui("ui_menu_move"), Audio.play_at("impact/imp_bump_light",
##   position), Audio.play_2d("car/car_radio_click", "Cabin").
## - Owns the radio (Audio.radio), the ambience/weather beds (Audio.ambience)
##   and menu/mission music (Audio.play_music, Audio.set_mission_intensity).
## - Audio.set_player_inside(true/false) switches the world to the muffled
##   "heard from inside the car" mix, and Audio.set_indoors(true/false) the
##   "heard from inside the townhouse" one (the street dull and far off).
## - Audio.set_player_driving(true/false): at the wheel. In the chase view
##   (not inside) the street keeps its outside sound, but the radio stays the
##   loudest thing and the storm ducks under it.

signal player_inside_changed(inside: bool)
signal player_driving_changed(driving: bool)

const ROOT := "res://audio"

## Bus name -> parent bus. Created in this order if they don't already exist.
const BUSES := [
	["Music", "Master"],
	["UI", "Master"],
	["Radio", "Master"],
	["Cabin", "Master"],     # inside-the-car sounds that are never muffled
	["World", "Master"],     # everything outside the cabin; muffled when inside
	["Engine", "World"],
	["Vehicles", "World"],   # other people's cars, buses and trains
	["Tyres", "World"],
	["SFX", "World"],
	["Ambience", "World"],
	["Weather", "World"],
]

var radio: Node
var hooks: Node
var ambience: Node

## Names that borrow another sound until a file of their own exists (a real
## file with the alias's name always wins, so dropping one in just works).
const ALIASES := {
	"field/bird_australian_magpie": "amb/amb_bird_magpie",
	"field/bird_laughing_kookaburra": "amb/amb_bird_kookaburra",
	"field/bird_australian_raven": "amb/amb_bird_raven",
	"field/flush": "traffic/traffic_wings_takeoff",
	"field/reel": "field/reel_loop",
	"field/splash": "field/splash_small",
}

var _index := {}            # "car/car_horn_modern_tap" -> "res://audio/car/car_horn_modern_tap.ogg"
var _variants := {}         # "impact/imp_crash_medium" -> [paths...]
var _cache := {}
var _last_variant := {}
var _inside := false
var _indoors := false
var _driving := false
var _base_db := {}          # mixed levels of the buses set_indoors() turns down
var _effects_db := 0.0      # the Effects slider, which also covers the Cabin and UI buses
var _car_db := 0.0          # the Your car slider: Engine, Tyres, Cabin
var _surround_db := 0.0     # the Weather and street slider: Ambience, Weather, Vehicles
var _world_lp: AudioEffectLowPassFilter
var _world_shelf: AudioEffectEQ6
var _radio_lp: AudioEffectLowPassFilter
var _engine_comp: AudioEffectCompressor
var _music_player: AudioStreamPlayer
var _music_name := ""
var _mission: AudioStreamSynchronized
var _ui_pool: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _listener: Node3D
var _listener_check := 0.0
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	_scan(ROOT)
	for key in _index:
		var base := _variant_base(key)
		if base != "":
			if not _variants.has(base):
				_variants[base] = []
			_variants[base].append(_index[key])
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui_pool.append(p)
	for i in 24:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 6.0
		p3.max_distance = 200.0
		p3.attenuation_filter_cutoff_hz = 9000.0
		add_child(p3)
		_pool_3d.append(p3)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	radio = preload("res://audio/scripts/radio.gd").new()
	radio.name = "Radio"
	add_child(radio)
	ambience = preload("res://audio/scripts/ambience_manager.gd").new()
	ambience.name = "Ambience"
	add_child(ambience)
	var display := preload("res://audio/scripts/radio_display.gd").new()
	display.name = "RadioDisplay"
	add_child(display)
	hooks = preload("res://audio/scripts/game_hooks.gd").new()
	hooks.name = "Hooks"
	add_child(hooks)
	var settings := get_node_or_null("/root/Settings")
	if settings and "volume_master" in settings:
		settings.changed.connect(apply_volume_settings)
		apply_volume_settings()


## Radio keys work anywhere (see project.godot input map: radio_*).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("radio_power"):
		radio.toggle_power()
	elif event.is_action("radio_next_station"):
		if radio.is_on():
			radio.next_station()
		else:
			radio.toggle_power()
	elif event.is_action("radio_previous_station"):
		if radio.is_on():
			radio.previous_station()
		else:
			radio.toggle_power()
	elif event.is_action("radio_next_track"):
		radio.next_track()
	elif event.is_action("radio_next_playlist"):
		radio.next_playlist()


## The node the player hears from: the current 3D camera. The game renders
## through a SubViewport, so look for whichever Camera3D is current.
func listener() -> Node3D:
	if is_instance_valid(_listener) and _listener is Camera3D and (_listener as Camera3D).current:
		return _listener
	var now := Time.get_ticks_msec() / 1000.0
	if now - _listener_check < 1.0 and is_instance_valid(_listener):
		return _listener
	_listener_check = now
	_listener = get_viewport().get_camera_3d()
	if _listener == null:
		for c in get_tree().root.find_children("*", "Camera3D", true, false):
			if (c as Camera3D).current:
				_listener = c
				break
	return _listener


# ---------------------------------------------------------------------------
# Bus layout
# ---------------------------------------------------------------------------

func _build_buses() -> void:
	# default_bus_layout.tres already holds this layout; this keeps the game
	# working if that file is missing or out of date.
	for pair in BUSES:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx == -1:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, pair[0])
		if AudioServer.get_bus_send(idx) != pair[1]:
			AudioServer.set_bus_send(idx, pair[1])
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, lim)
	# World: muffled when the listener is inside the car (low-pass plus a
	# little low-end lift, the way a closed cabin sounds).
	var world := AudioServer.get_bus_index("World")
	if AudioServer.get_bus_effect_count(world) == 0:
		_world_lp = AudioEffectLowPassFilter.new()
		_world_lp.cutoff_hz = 1400.0
		_world_lp.resonance = 0.6
		AudioServer.add_bus_effect(world, _world_lp)
		_world_shelf = AudioEffectEQ6.new()
		_world_shelf.set_band_gain_db(0, 4.0)   # 32 Hz
		_world_shelf.set_band_gain_db(1, 3.0)   # 100 Hz
		_world_shelf.set_band_gain_db(4, -3.0)  # 3.2 kHz
		_world_shelf.set_band_gain_db(5, -6.0)  # 10 kHz
		AudioServer.add_bus_effect(world, _world_shelf)
	else:
		_world_lp = AudioServer.get_bus_effect(world, 0) as AudioEffectLowPassFilter
	for bus in ["Vehicles", "Tyres", "Engine"]:
		_base_db[bus] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
	# Engine: the loops run from about -45 LUFS at idle to -22 pulling hard,
	# so a compressor evens them out: the idle comes up over the rain and
	# cruising stays under the radio. The tone still says how hard it's working.
	var eng := AudioServer.get_bus_index("Engine")
	if AudioServer.get_bus_effect_count(eng) == 0:
		_engine_comp = AudioEffectCompressor.new()
		_engine_comp.threshold = ENGINE_COMP_THRESHOLD_DB
		_engine_comp.ratio = ENGINE_COMP_RATIO
		_engine_comp.gain = ENGINE_COMP_GAIN_DB
		_engine_comp.attack_us = 5000.0
		_engine_comp.release_ms = 300.0
		AudioServer.add_bus_effect(eng, _engine_comp)
	else:
		_engine_comp = AudioServer.get_bus_effect(eng, 0) as AudioEffectCompressor
	# Tyres: the roar sits at its cap close up, but layers, road joints and cat's
	# eyes stack on it at speed; this holds the bus near the cruising level so
	# the radio stays on top. Kerbs and bumps still punch through (5 ms attack).
	var tyres := AudioServer.get_bus_index("Tyres")
	if AudioServer.get_bus_effect_count(tyres) == 0:
		var comp := AudioEffectCompressor.new()
		comp.threshold = TYRES_COMP_THRESHOLD_DB
		comp.ratio = TYRES_COMP_RATIO
		comp.attack_us = 5000.0
		comp.release_ms = 300.0
		AudioServer.add_bus_effect(tyres, comp)
	# Ambience and Weather: dulled through the walls when you're indoors at home.
	for bus in INDOOR_DULLED:
		var i := AudioServer.get_bus_index(bus)
		if AudioServer.get_bus_effect_count(i) == 0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 800.0
			lp.resonance = 0.5
			AudioServer.add_bus_effect(i, lp)
	# Radio: a small car stereo. Band-limited, a touch of drive, compressed.
	var r := AudioServer.get_bus_index("Radio")
	if AudioServer.get_bus_effect_count(r) == 0:
		var hpf := AudioEffectHighPassFilter.new()
		hpf.cutoff_hz = 140.0
		AudioServer.add_bus_effect(r, hpf)
		_radio_lp = AudioEffectLowPassFilter.new()
		_radio_lp.cutoff_hz = 7500.0
		AudioServer.add_bus_effect(r, _radio_lp)
		var eq := AudioEffectEQ6.new()
		eq.set_band_gain_db(1, 2.5)   # 100 Hz door-speaker thump
		eq.set_band_gain_db(3, 2.0)   # 1 kHz honk
		eq.set_band_gain_db(5, -8.0)  # 10 kHz
		AudioServer.add_bus_effect(r, eq)
		var dist := AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_CLIP
		dist.pre_gain = 2.0
		dist.drive = 0.08
		dist.post_gain = -2.0
		AudioServer.add_bus_effect(r, dist)
		var comp := AudioEffectCompressor.new()
		comp.threshold = -18.0
		comp.ratio = 3.0
		AudioServer.add_bus_effect(r, comp)
	else:
		_radio_lp = AudioServer.get_bus_effect(r, 1) as AudioEffectLowPassFilter
	_apply_inside()


## Volume sliders from the Settings autoload, 0..1 on top of the mix's own
## bus levels (so 1 = as mixed, not 0 dB).
const SETTINGS_BUSES := {
	"volume_master": ["Master", 0.0], "volume_music": ["Music", -3.0],
	"volume_radio": ["Radio", -2.0], "volume_effects": ["World", 0.0],
}


func apply_volume_settings() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	for key in SETTINGS_BUSES:
		var idx := AudioServer.get_bus_index(SETTINGS_BUSES[key][0])
		if idx >= 0:
			var v := clampf(float(settings.get(key)), 0.0, 1.0)
			AudioServer.set_bus_volume_db(idx, SETTINGS_BUSES[key][1] + linear_to_db(maxf(v, 0.0001)))
	# Cabin sounds (rain on the roof, wipers, indicator, key) and menu sounds
	# are effects too, but skip World so they aren't muffled with the street:
	# _apply_inside() adds the Effects slider to their buses' own levels, and
	# the Your car / Weather and street sliders to the buses under it.
	_effects_db = _slider_db(settings, "volume_effects")
	_car_db = _slider_db(settings, "volume_car")
	_surround_db = _slider_db(settings, "volume_surroundings")
	_apply_inside()


static func _slider_db(settings: Node, key: String) -> float:
	var v = settings.get(key)
	return linear_to_db(maxf(clampf(float(v) if v != null else 1.0, 0.0, 1.0), 0.0001))


## The Engine bus compressor (see _build_buses): where it starts, how hard it
## holds the loud end down, and the make-up gain that lifts the idle.
const ENGINE_COMP_THRESHOLD_DB := -34.0
const ENGINE_COMP_RATIO := 3.0
const ENGINE_COMP_GAIN_DB := 9.0
## The Tyres bus compressor: where the roar stops growing with speed.
const TYRES_COMP_THRESHOLD_DB := -30.0
const TYRES_COMP_RATIO := 3.0


## Settings menu hook: linear volume 0..1 for a bus ("Master", "Music", "Radio", ...).
func set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func get_bus_volume(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(idx)) if idx >= 0 else 0.0


## Buses heard through the townhouse walls (low-passed indoors), and how far
## down each one goes. SFX stays as it is: the house's own sounds are on it.
const INDOOR_DULLED := ["Ambience", "Weather"]
const INDOOR_DB := {"Ambience": -10.0, "Weather": -6.0, "Vehicles": -12.0, "Tyres": -12.0, "Engine": -8.0}


func set_player_inside(inside: bool) -> void:
	if inside == _inside:
		return
	_inside = inside
	_apply_inside()
	player_inside_changed.emit(inside)


func is_player_inside() -> bool:
	return _inside


## At the wheel of the player's car (CarSounds sets it), in either view.
func set_player_driving(driving: bool) -> void:
	if driving == _driving:
		return
	_driving = driving
	_apply_inside()
	player_driving_changed.emit(driving)


func is_player_driving() -> bool:
	return _driving


## The radio's trim for where the player hears it from: in the car, at the
## wheel in the chase view (a touch down and duller, still over the street),
## or on foot outside (faint, through the glass).
func radio_trim_db() -> float:
	if _inside:
		return 0.0
	return CHASE_RADIO_DB if _driving else -14.0


## On foot inside the townhouse (Audio.hooks sets it as you come and go).
func set_indoors(indoors: bool) -> void:
	if indoors == _indoors:
		return
	_indoors = indoors
	_apply_inside()


func is_indoors() -> bool:
	return _indoors


## Menu clicks and notices: the files are mastered hot, so the UI bus sits
## down here to match the game around it (still under the Effects slider).
const UI_DB := -14.0

## Cabin bus level in the car and heard from outside it, before the Effects
## slider. In the car it sits under the radio.
const CABIN_DB := -6.0
const CABIN_OUT_DB := -20.0
## At the wheel in the chase view: the radio's trim and tone, and how far the
## rain and wind (and a little, the street) duck so the radio stays on top.
const CHASE_RADIO_DB := -3.0
const CHASE_RADIO_LP_HZ := 4000.0
const CHASE_WEATHER_DB := -22.0
const CHASE_AMBIENCE_DB := -6.0


func _apply_inside() -> void:
	var world := AudioServer.get_bus_index("World")
	AudioServer.set_bus_effect_enabled(world, 0, _inside)
	AudioServer.set_bus_effect_enabled(world, 1, _inside)
	# Out of the car the radio is faint and dull, coming through the glass;
	# at the wheel in the chase view only a little duller.
	var chase := _driving and not _inside
	if _radio_lp:
		_radio_lp.cutoff_hz = 7500.0 if _inside else (CHASE_RADIO_LP_HZ if chase else 1200.0)
	# Cabin sounds (indicator, wipers, rain on the roof) are distant from outside.
	# The radio applies its own trim (radio.gd asks radio_trim_db() on the signals).
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Cabin"), (CABIN_DB if _inside else CABIN_OUT_DB) + _effects_db + _car_db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), UI_DB + _effects_db)
	# Inside, the street and the weather drop well under the radio and engine.
	var levels := {"Ambience": -9.0 if _inside else (CHASE_AMBIENCE_DB if chase else 0.0), "Weather": -18.0 if _inside else (CHASE_WEATHER_DB if chase else -4.0),
			"Vehicles": _base_db.get("Vehicles", 0.0), "Tyres": _base_db.get("Tyres", 0.0),
			"Engine": _base_db.get("Engine", 0.0)}
	# Indoors at home the street is through the walls: dull and well down.
	var home := _indoors and not _inside
	for bus in INDOOR_DB:
		levels[bus] += INDOOR_DB[bus] if home else 0.0
	for bus in ["Engine", "Tyres"]:
		levels[bus] += _car_db
	for bus in ["Ambience", "Weather", "Vehicles"]:
		levels[bus] += _surround_db
	for bus in levels:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), levels[bus])
	for bus in INDOOR_DULLED:
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(bus), 0, home)


# ---------------------------------------------------------------------------
# Finding sounds
# ---------------------------------------------------------------------------

func _scan(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := dir_path.path_join(f)
		if d.current_is_dir():
			if not f.begins_with(".") and f not in ["tools", "scripts", "docs", "tests"]:
				_scan(full)
		else:
			# In exported games only the .import/.remap files are listed.
			var real := f.trim_suffix(".import").trim_suffix(".remap")
			if real.get_extension() in ["ogg", "wav", "mp3"]:
				var path := dir_path.path_join(real)
				var key := path.trim_prefix(ROOT + "/").get_basename()
				# A hand-made .wav/.mp3 next to a generated .ogg of the same name wins.
				if not _index.has(key) or _index[key].get_extension() == "ogg":
					_index[key] = path
		f = d.get_next()
	d.list_dir_end()


func _variant_base(key: String) -> String:
	var parts := key.rsplit("_", true, 1)
	if parts.size() == 2 and parts[1].length() == 2 and parts[1].is_valid_int():
		return parts[0]
	return ""


## True if a sound (or a variant set) with this name exists.
func has(sound_name: String) -> bool:
	sound_name = _resolve(sound_name)
	return _index.has(sound_name) or _variants.has(sound_name)


## All sound names under a folder, e.g. names_in("engine/fire12").
func names_in(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k in _index.keys():
		if k.begins_with(folder + "/"):
			out.append(k)
	out.sort()
	return out


## Load a sound by name ("car/car_horn_modern_tap"). Returns null if missing.
func stream(sound_name: String, loop := false) -> AudioStream:
	sound_name = _resolve(sound_name)
	var path: String = _index.get(sound_name, "")
	if path == "":
		if _variants.has(sound_name):
			return variant(sound_name)
		push_warning("Audio: no sound named '%s'" % sound_name)
		return null
	return _load(path, loop)


## A random variant of base_name (base_name_01.._NN), never the same twice in a row.
func variant(base_name: String) -> AudioStream:
	base_name = _resolve(base_name)
	var list: Array = _variants.get(base_name, [])
	if list.is_empty():
		return stream(base_name) if _index.has(base_name) else null
	var i := randi() % list.size()
	if list.size() > 1 and i == _last_variant.get(base_name, -1):
		i = (i + 1) % list.size()
	_last_variant[base_name] = i
	return _load(list[i], false)


func _resolve(sound_name: String) -> String:
	if _index.has(sound_name) or _variants.has(sound_name):
		return sound_name
	return ALIASES.get(sound_name, sound_name)


func _load(path: String, loop: bool) -> AudioStream:
	var key := path + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = load(path)
	if s == null:
		return null
	if loop:
		s = s.duplicate()
		_set_loop(s, true)
	_cache[key] = s
	return s


static func _set_loop(s: AudioStream, on: bool) -> void:
	if s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = on
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate) if on else 0


# ---------------------------------------------------------------------------
# Playing one-shots
# ---------------------------------------------------------------------------

## UI sound, e.g. Audio.ui("ui_menu_move"). Name may omit the "ui/" folder.
func ui(sound_name: String, volume_db := 0.0) -> void:
	play_2d(sound_name if sound_name.contains("/") else "ui/" + sound_name, "UI", volume_db)


## Non-positional one-shot on a bus. Picks a random variant if name is a set.
func play_2d(sound_name: String, bus := "SFX", volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	sound_name = _resolve(sound_name)
	var s := variant(sound_name) if _variants.has(sound_name) else stream(sound_name)
	if s == null:
		return null
	var p: AudioStreamPlayer = null
	for c in _ui_pool:
		if not c.playing:
			p = c
			break
	if p == null:
		p = _ui_pool[0]
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	return p


## Positional one-shot in the world, with a little random pitch so repeats
## differ. unit_size is how far it stays at full volume and reach where it
## falls silent: the defaults suit something car-sized; pass bigger ones for
## things that carry (a train horn), smaller for little ones (a click).
func play_at(sound_name: String, pos: Vector3, volume_db := 0.0, bus := "SFX",
		pitch_jitter := 0.04, unit_size := 6.0, reach := 200.0) -> AudioStreamPlayer3D:
	sound_name = _resolve(sound_name)
	var s := variant(sound_name) if _variants.has(sound_name) else stream(sound_name)
	if s == null:
		return null
	var p: AudioStreamPlayer3D = null
	for c in _pool_3d:
		if not c.playing:
			p = c
			break
	if p == null:
		# All busy: cut short the one furthest from the listener (the one
		# least missed), not a random one.
		var ear := listener()
		var far := -1.0
		for c in _pool_3d:
			var d := c.global_position.distance_to(ear.global_position) if ear else 0.0
			if d > far:
				far = d
				p = c
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = reach
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.global_position = pos
	p.play()
	return p


# ---------------------------------------------------------------------------
# Quitting cleanly
# ---------------------------------------------------------------------------

## Quit the game with the audio shut down first. Use this instead of
## get_tree().quit(): every player is stopped and its stream let go, then the
## mixer gets a moment to drop the stopped playbacks before the engine tears
## down. Quitting with Ogg playbacks still in the mixer can crash on exit.
func quit_game(exit_code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	release_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	release_all()
	await get_tree().process_frame
	get_tree().quit(exit_code)


## For quitting only: pause the scene and the audio managers (so nothing
## restarts a loop), stop every audio player in the tree, drop its stream and
## empty the stream cache, so no Ogg playback or stream outlives its scene.
## The game stays silent and still afterwards.
func release_all() -> void:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
	for n in [radio, ambience, hooks]:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_DISABLED
	for p in _players_under(get_tree().root if is_inside_tree() else self):
		p.stop()
		p.stream = null
	_mission = null
	_music_name = ""
	_cache.clear()
	_last_variant.clear()


static func _players_under(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
			out.append(n)
		stack.append_array(n.get_children(true))
	return out


func _exit_tree() -> void:
	release_all()  # any other way out (tests, the engine closing the window)


# ---------------------------------------------------------------------------
# Menu, home and mission music (the car radio lives in radio.gd)
# ---------------------------------------------------------------------------

## Play a music track by name ("mus_main_theme"), crossfading from the last.
func play_music(track: String, fade_s := 1.5, loop := true) -> void:
	if track == _music_name and _music_player.playing:
		return
	var s := stream("music/" + track, loop)
	if s == null:
		return
	_music_name = track
	_fade_to(s, fade_s)


func stop_music(fade_s := 1.5) -> void:
	_music_name = ""
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -60.0, fade_s)
	tw.tween_callback(_music_player.stop)


## Mission music: base groove plus an intensity layer faded in by
## set_mission_intensity(0..1) as time runs low. Both stems stay in sync.
func start_mission_music(fade_s := 1.0) -> void:
	_mission = AudioStreamSynchronized.new()
	_mission.stream_count = 2
	_mission.set_sync_stream(0, stream("music/mus_mission_tension_base", true))
	_mission.set_sync_stream(1, stream("music/mus_mission_tension_intensity", true))
	_mission.set_sync_stream_volume(1, -60.0)
	_music_name = "mission"
	_fade_to(_mission, fade_s)


func set_mission_intensity(amount: float) -> void:
	if _mission:
		_mission.set_sync_stream_volume(1, linear_to_db(clampf(amount, 0.0001, 1.0)))


## Short stinger over whatever is playing: "complete", "failed", "tier_unlock", "new_car", "race_win".
func sting(which: String) -> void:
	play_2d("music/mus_sting_" + which, "Music")


func _fade_to(s: AudioStream, fade_s: float) -> void:
	var old := _music_player
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.stream = s
	p.volume_db = -60.0
	add_child(p)
	p.play()
	_music_player = p
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "volume_db", 0.0, fade_s).set_trans(Tween.TRANS_SINE)
	if old and old.playing:
		tw.tween_property(old, "volume_db", -60.0, fade_s)
	tw.chain().tween_callback(func() -> void:
		if old and old != _music_player:
			old.queue_free())
