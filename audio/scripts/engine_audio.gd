class_name EngineAudio
extends Node3D
## Engine sound for one car. Add as a child of the vehicle (or point
## `vehicle_path` at it) and set `engine_set` to a folder in res://audio/engine
## ("fire12", "fire12sport", "tjet", "classic", "electric", ...).
##
## How it works: every eng_<set>_onload_<rpm> / _offload_<rpm> loop gets its
## own 3D player. Each frame the two loops either side of the current RPM are
## crossfaded (equal power) and pitch-shifted by rpm / loop_rpm, and the
## on-load and off-load sets are crossfaded by throttle. For electric sets the
## numbers in the file names are km/h and road speed drives the crossfade.
##
## The vehicle is `vehicle_path`, or else the nearest ancestor with
## get_telemetry() (the game's CarController; see docs/HOOKS.md), whose rpm,
## throttle, engine_load, gear and speed_kmh drive the sound and whose
## gear_changed signal plays the clunk. Any other node works too if it has
## rpm / throttle / gear / speed_kmh properties. With no vehicle, set rpm,
## throttle and speed_kmh on this node directly.

@export var engine_set := "fire12"
@export var vehicle_path: NodePath
@export var volume_db := 0.0
@export var unit_size := 10.0
@export var max_distance := 250.0
## Classic gearboxes clunk louder; also picks classic or modern gear sounds.
@export var classic_gearbox := false
## Overrun pops and crackles (automatic for sport/straight exhausts and Abarths).
@export var pops := -1.0
## Turbo spool and blow-off (automatic for T-Jet and TwinAir sets).
@export var turbo := -1.0
## Play the start-up sound when the scene starts (otherwise already running).
@export var start_on_ready := true
## Swap engine_set when the car's engine or exhaust part changes (the car's
## parts_changed signal; see ENGINE_PARTS and EXHAUST_PARTS).
@export var follow_parts := true

## Car id (data/cars/cars.json) -> its engine set, for the car's
## car_changed signal. Cars not listed keep the set they have.
const CAR_SETS := {
	"pop_12": "fire12", "hybrid_10": "fire12", "lounge_14": "fire14",
	"twinair_09": "twinair", "abarth_500": "tjet", "abarth_595_turismo": "tjet",
	"abarth_595_comp": "tjetsport", "abarth_695_tributo": "tjetsport",
	"abarth_695_biposto": "tjetstraight", "e_500e_2013": "electric",
	"e_500e_2020": "electric", "abarth_500e": "abarthe",
	"classic_nuova": "classic", "classic_d": "classic", "classic_giardiniera": "classicflat",
	"classic_500f": "classic", "classic_500l": "classic", "classic_500r": "classic",
	"classic_jolly": "classic", "classic_sport": "classicsport",
	"classic_abarth_595": "classicabarth", "classic_abarth_695": "classicabarthsport",
}

## Engine part id -> engine family. Parts not listed keep the current family
## (an ECU remap or a stock engine sounds like what's fitted).
const ENGINE_PARTS := {
	"engine_stock": "", "engine_1_4_swap": "fire14", "engine_tjet": "tjet",
}
## Exhaust part id -> exhaust variant suffix ("" = stock). With no exhaust
## part fitted, the suffix engine_set started with stays.
const EXHAUST_PARTS := {
	"exhaust_stock": "", "exhaust_sport": "sport", "exhaust_twin": "sport",
	"exhaust_abarth_quad": "straight",
	# The barn-find Abarth megaphone: classics only (modern cars have no
	# megaphone set, so they keep their stock note).
	"exhaust_abarth_classic": "megaphone",
}

var rpm := 0.0
var throttle := 0.0
var speed_kmh := 0.0
var gear := 1
var running := false

var _vehicle: Node
var _on: Array = []    # [[rpm, AudioStreamPlayer3D], ...] sorted by rpm
var _off: Array = []
var _load := 0.0
var _master := 0.0     # 0..1 fade for start-up / shut-down
var _idle := 850.0
var _redline := 6000.0
var _electric := false
var _oneshot: AudioStreamPlayer3D
var _limiter: AudioStreamPlayer3D
var _spool: AudioStreamPlayer3D
var _avas: AudioStreamPlayer3D
var _whine: AudioStreamPlayer3D
var _boost := 0.0
var _last_throttle := 0.0
var _last_gear := 1
var _pop_timer := 0.0
var _fade_tween: Tween
var _was_running := true
var _base_family := "fire12"
var _base_suffix := ""
var _auto_pops := true
var _auto_turbo := true


func _ready() -> void:
	_vehicle = find_vehicle(self, vehicle_path)
	_base_family = family_of(engine_set)
	_base_suffix = engine_set.trim_prefix(_base_family)
	_auto_pops = pops < 0.0
	_auto_turbo = turbo < 0.0
	if _vehicle and _vehicle.has_signal("gear_changed"):
		_vehicle.connect("gear_changed", _on_gear_changed)
	if follow_parts and _vehicle and _vehicle.has_signal("parts_changed"):
		_vehicle.connect("parts_changed", func(_slot, _part) -> void: _apply_parts())
		if _vehicle.has_signal("car_changed"):
			_vehicle.connect("car_changed", set_car)
		if "car_id" in _vehicle and CAR_SETS.has(String(_vehicle.car_id)):
			_set_base(CAR_SETS[String(_vehicle.car_id)])
		engine_set = set_for_parts()
	build()
	if _vehicle:
		if start_on_ready:
			start_engine.call_deferred()
		else:
			start_running()


## vehicle_path if set, else the nearest ancestor with get_telemetry().
static func find_vehicle(from: Node, path: NodePath) -> Node:
	if not path.is_empty():
		return from.get_node_or_null(path)
	var n := from.get_parent()
	while n:
		if n.has_method("get_telemetry"):
			return n
		n = n.get_parent()
	return null


## (Re)build players for the current engine_set. Call after changing it at
## runtime (e.g. fitting a new exhaust).
func build() -> void:
	for pair in _on + _off:
		pair[1].queue_free()
	_on.clear()
	_off.clear()
	_electric = engine_set.begins_with("electric")
	var prefix := "engine/%s/eng_%s_" % [engine_set, engine_set]
	for sound_name in Audio.names_in("engine/" + engine_set):
		var rest := sound_name.trim_prefix(prefix)
		var bits := rest.split("_")
		if bits.size() == 2 and bits[1].is_valid_int() and bits[0] in ["onload", "offload"]:
			var p := _make_player(Audio.stream(sound_name, true))
			(_on if bits[0] == "onload" else _off).append([float(bits[1]), p])
	_on.sort_custom(func(a, b): return a[0] < b[0])
	_off.sort_custom(func(a, b): return a[0] < b[0])
	if _on.is_empty():
		push_warning("EngineAudio: no loops found for engine set '%s'" % engine_set)
		return
	_idle = _on[0][0]
	_redline = _on[-1][0]
	if _off.is_empty():
		_off = _on
	if not _oneshot:
		_oneshot = _make_player(null)
		_limiter = _make_player(null)
		_whine = _make_player(Audio.stream("engine/extras/eng_gearbox_whine", true))
		_spool = _make_player(Audio.stream("engine/extras/eng_turbo_spool", true))
	var avas := "engine/%s/eng_%s_avas" % [engine_set, engine_set]
	if Audio.has(avas):
		if not _avas:
			_avas = _make_player(null)
		_avas.stream = Audio.stream(avas, true)
	elif _avas:
		_avas.stop()
		_avas.stream = null
	var lim := "engine/%s/eng_%s_limiter" % [engine_set, engine_set]
	_limiter.stream = Audio.stream(lim) if Audio.has(lim) else null
	var family := family_of(engine_set)
	if _auto_pops:
		pops = 1.0 if (engine_set.ends_with("sport") or engine_set.ends_with("straight")
				or engine_set.ends_with("megaphone") or family in ["tjet", "classicabarth"]) else 0.0
		if engine_set.ends_with("straight") or engine_set.ends_with("megaphone"):
			pops = 2.0
	if _auto_turbo:
		turbo = 1.0 if family in ["tjet", "twinair"] else 0.0
	if engine_set.begins_with("classic"):
		classic_gearbox = true


## Switch to the engine of another car (by cars.json id).
func set_car(car_id: String) -> void:
	if not CAR_SETS.has(car_id):
		return
	_set_base(CAR_SETS[car_id])
	_apply_parts()


func _set_base(set_name: String) -> void:
	_base_family = family_of(set_name)
	_base_suffix = set_name.trim_prefix(_base_family)
	classic_gearbox = set_name.begins_with("classic")


## Stop all sound at once, without the shut-down one-shot (for pooled AI
## engines being handed to another car). start_running() brings it back.
func silence() -> void:
	running = false
	_master = 0.0
	if _fade_tween:
		_fade_tween.kill()
	_set_loops_playing(false)
	if _limiter:
		_limiter.stop()


static func family_of(set_name: String) -> String:
	return set_name.trim_suffix("sport").trim_suffix("straight").trim_suffix("megaphone")


## The engine set the vehicle's fitted parts call for, e.g. "fire12sport".
func set_for_parts() -> String:
	var family := _base_family
	var suffix := _base_suffix
	if _vehicle and "parts" in _vehicle:
		var parts: Dictionary = _vehicle.parts
		if parts.has(&"engine"):
			var f: String = ENGINE_PARTS.get(String(parts[&"engine"].id), "")
			if f != "":
				family = f
		if parts.has(&"exhaust"):
			suffix = EXHAUST_PARTS.get(String(parts[&"exhaust"].id), "")
	var want := family + suffix
	return want if Audio.names_in("engine/" + want).size() > 0 else family


func _apply_parts() -> void:
	var want := set_for_parts()
	if want == engine_set:
		return
	engine_set = want
	build()
	if running:
		_set_loops_playing(true)


func _make_player(s: AudioStream) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "Engine"
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.volume_db = -80.0
	p.attenuation_filter_cutoff_hz = 12000.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(p)
	return p


## Turn the key: start-up one-shot, then the loops fade in under its tail.
func start_engine() -> void:
	if running:
		return
	running = true
	rpm = _idle
	var s := Audio.stream("engine/%s/eng_%s_startup" % [engine_set, engine_set])
	var delay := 0.0
	if s:
		_oneshot.stream = s
		_oneshot.volume_db = volume_db
		_oneshot.play()
		delay = maxf(s.get_length() - 0.35, 0.0)
	_set_loops_playing(true)
	_fade_master(1.0, 0.35, delay)


## Turn the key off: loops fade quickly under the shut-down one-shot.
func stop_engine() -> void:
	if not running:
		return
	running = false
	var s := Audio.stream("engine/%s/eng_%s_shutdown" % [engine_set, engine_set])
	if s:
		_oneshot.stream = s
		_oneshot.volume_db = volume_db
		_oneshot.play()
	_fade_master(0.0, 0.25, 0.0)
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if not running:
			_set_loops_playing(false))


## For AI traffic and the "follower": engine already running, no start-up.
func start_running() -> void:
	running = true
	rpm = _idle
	_set_loops_playing(true)
	_master = 1.0


func _fade_master(to: float, dur: float, delay: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_interval(delay)
	_fade_tween.tween_property(self, "_master", to, dur)


func _set_loops_playing(on: bool) -> void:
	for pair in _on + _off:
		var p: AudioStreamPlayer3D = pair[1]
		if on and not p.playing:
			# Random start points so the loops don't phase against each other.
			p.play(randf() * maxf(p.stream.get_length() - 0.1, 0.0))
		elif not on:
			p.stop()
	if not on:
		_whine.stop()
		_spool.stop()


func _on_gear_changed(new_gear: int) -> void:
	if new_gear == _last_gear:
		return
	_last_gear = new_gear
	var kind := "classic" if classic_gearbox else "modern"
	Audio.play_at("engine/extras/eng_gear_clunk_" + kind, global_position,
			volume_db - (2.0 if classic_gearbox else 8.0), "Engine")


func _read_vehicle() -> void:
	if _vehicle == null:
		return
	if _vehicle.has_method("get_telemetry"):
		var t: Dictionary = _vehicle.get_telemetry()
		rpm = float(t.get("rpm", rpm))
		# Load: the throttle, but also the engine pulling hard (engine_load);
		# engine braking (negative load) is the off-load sound.
		throttle = clampf(maxf(float(t.get("throttle", 0.0)), float(t.get("engine_load", 0.0))), 0.0, 1.0)
		speed_kmh = absf(float(t.get("speed_kmh", 0.0)))
		gear = int(t.get("gear", gear))
		if t.has("engine_running"):
			_follow_running(bool(t.engine_running))
		return
	if "rpm" in _vehicle:
		rpm = float(_vehicle.rpm)
	if "throttle" in _vehicle:
		throttle = clampf(float(_vehicle.throttle), 0.0, 1.0)
	if "speed_kmh" in _vehicle:
		speed_kmh = absf(float(_vehicle.speed_kmh))
	if "gear" in _vehicle:
		gear = int(_vehicle.gear)
		if not _vehicle.has_signal("gear_changed") and gear != _last_gear:
			_on_gear_changed(gear)
	if "engine_running" in _vehicle:
		_follow_running(bool(_vehicle.engine_running))


## The car says whether the engine runs (it cuts out when the tank is dry).
## Only acts on a change, so start_engine()/stop_engine() still work for cars
## that always report running.
func _follow_running(want: bool) -> void:
	if want == _was_running:
		return
	_was_running = want
	if want and not running:
		start_engine()
	elif not want and running:
		stop_engine()


func _process(delta: float) -> void:
	_read_vehicle()
	if _on.is_empty():
		return
	# Smooth the load so throttle stabs don't click (~80 ms).
	_load = lerpf(_load, throttle, 1.0 - exp(-delta / 0.08))
	var x := speed_kmh if _electric else maxf(rpm, _idle * 0.5)
	var on_w := sqrt(_load)
	var off_w := sqrt(1.0 - _load)
	var gain := _master if running or _master > 0.0 else 0.0
	_mix(_on, x, on_w * gain)
	_mix(_off, x, off_w * gain)
	_extras(delta, x)


func _mix(layers: Array, x: float, layer_gain: float) -> void:
	var n := layers.size()
	for i in n:
		var r: float = layers[i][0]
		var p: AudioStreamPlayer3D = layers[i][1]
		var w := 0.0
		if n == 1:
			w = 1.0
		elif x <= layers[0][0]:
			w = 1.0 if i == 0 else 0.0
		elif x >= layers[n - 1][0]:
			w = 1.0 if i == n - 1 else 0.0
		else:
			if i > 0 and x >= layers[i - 1][0] and x < r:
				var lo: float = layers[i - 1][0]
				w = sin((x - lo) / (r - lo) * PI * 0.5)
			elif i < n - 1 and x >= r and x < layers[i + 1][0]:
				var hi: float = layers[i + 1][0]
				w = cos((x - r) / (hi - r) * PI * 0.5)
		w *= layer_gain
		if w < 0.001:
			p.volume_db = -80.0
			p.stream_paused = true
			continue
		p.stream_paused = false
		p.volume_db = volume_db + linear_to_db(w)
		if _electric:
			# Speed points: pitch follows speed, but never to silence at 0 km/h.
			p.pitch_scale = clampf((x + 15.0) / (r + 15.0), 0.5, 2.0)
		else:
			p.pitch_scale = clampf(x / r, 0.5, 2.0)


func _extras(delta: float, x: float) -> void:
	if _electric:
		# Pedestrian warning tone below ~25 km/h, rising a little with speed.
		if _avas and _avas.stream:
			var w := clampf(1.0 - speed_kmh / 25.0, 0.0, 1.0) * (1.0 if running else 0.0)
			if w > 0.01:
				if not _avas.playing:
					_avas.play()
				_avas.volume_db = volume_db - 6.0 + linear_to_db(w)
				_avas.pitch_scale = 1.0 + speed_kmh / 40.0
			elif _avas.playing:
				_avas.stop()
		return
	if not running:
		_limiter.stop()
		return
	var rpm_norm := clampf((x - _idle) / (_redline - _idle), 0.0, 1.0)
	# Rev limiter.
	if x >= _redline * 0.985 and _load > 0.6:
		if not _limiter.playing and _limiter.stream:
			_limiter.volume_db = volume_db
			_limiter.play()
	elif _limiter.playing and x < _redline * 0.95:
		_limiter.stop()
	# Gearbox whine: faint in gear, loud in reverse, follows road speed.
	if _whine.stream:
		var whine_w := (0.5 if gear == -1 else 0.06) * clampf(speed_kmh / 30.0, 0.0, 1.0)
		if whine_w > 0.002:
			if not _whine.playing:
				_whine.play()
			_whine.volume_db = volume_db + linear_to_db(whine_w)
			_whine.pitch_scale = clampf(speed_kmh / (15.0 if gear == -1 else 60.0), 0.3, 3.0)
		elif _whine.playing:
			_whine.stop()
	# Turbo: boost builds with load and revs, spool follows it, and a sharp
	# lift-off at boost gives a blow-off or flutter.
	if turbo > 0.0 and _spool.stream:
		var target := clampf(_load * (rpm_norm * 1.4 - 0.15), 0.0, 1.0)
		_boost = lerpf(_boost, target, 1.0 - exp(-delta / (0.5 if target > _boost else 0.15)))
		if _boost > 0.02:
			if not _spool.playing:
				_spool.play()
			_spool.volume_db = volume_db - 10.0 + linear_to_db(_boost * turbo)
			_spool.pitch_scale = 0.6 + 0.7 * _boost
		elif _spool.playing:
			_spool.stop()
		if _last_throttle > 0.7 and throttle < 0.2 and _boost > 0.45:
			var which := "engine/extras/eng_blowoff" if randf() < 0.5 else "engine/extras/eng_turbo_flutter"
			Audio.play_at(which, global_position, volume_db - 6.0, "Engine")
	# Overrun pops: throttle shut at decent revs.
	if pops > 0.0 and _load < 0.15 and x > _idle * 2.5:
		_pop_timer -= delta
		if _pop_timer <= 0.0:
			_pop_timer = randf_range(0.08, 0.6) / pops
			if randf() < 0.5 * pops * rpm_norm:
				Audio.play_at("engine/extras/eng_backfire", global_position, volume_db - 4.0, "Engine", 0.15)
	_last_throttle = throttle
