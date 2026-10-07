extends SceneTree
## Headless check that the game's sounds belong to places in the world and
## that sirens stay rare. In the running game on the Perth map:
##
## - Every 3D sound in the scene gets quieter with distance and goes silent
##   at its reach. Each distinct falloff setting is measured on the real
##   mixer: a test tone with the same settings, played in front of the
##   camera at 4 m (closer for the house's small sounds), half its reach and
##   just past it.
## - Nothing out in the world plays as a flat (2D) sound except the zone
##   beds and the weather, which are everywhere by nature.
## - With the Effects, Music and Radio sliders down, nothing can still be
##   heard, menu sounds included (nothing bypasses them straight to Master);
##   under Effects, Your car and Weather and street each turn down only their
##   own sounds (your engine is yours, traffic engines are the street's).
## - Sirens: none sprinkled into the ambience, a few emergency calls per
##   in-game day (most of them far off), and a drive-by's siren stops once
##   it has gone past.
## - In a storm, in the car (interior view) with the radio on, the radio sits
##   well over the rain on the roof, the wipers and the storm outside at
##   default levels; turning Effects down turns all of that down as heard
##   (after the World bus, which the Weather bus feeds) and leaves the radio.
##   At the wheel in the chase view the radio still sits over the storm. In
##   both views the idling engine is heard over the rain.
## - Driving at city speeds (about 50 km/h) with the radio on, in both views,
##   the radio sits over your own engine and tyres at default levels.
## - Menu clicks (opening the pause menu) sit with the game, not over it.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/sound_check.gd -- --no-save
##
## Exits with code 1 if any check fails. CI runs this.

const FPS := 60
## Quietest a sound may be at half its reach, relative to 4 m away (dB)
## (a fifth of its reach for sounds that carry less than 20 m).
const MIN_DROP_DB := 10.0
## Emergency calls allowed per in-game day, on average over a few days.
const MAX_SIRENS_PER_DAY := 5.0
## Buses that are "out in the world" (muffled inside the car).
const WORLD_BUSES := [&"World", &"Engine", &"Vehicles", &"Tyres", &"SFX", &"Ambience", &"Weather"]
## In a storm in the car, how far under the radio the cabin (rain on the roof,
## wipers) and the rain and wind outside must sit at loud moments (dB, 90th
## percentile of the meters over 8 s; thunder aside). The rain loops start at
## random points and have louder and quieter stretches, so readings swing by
## a few dB: these sit about 3 dB under the quietest of 8 tries.
const CABIN_UNDER_RADIO_DB := 5.0
const STORM_UNDER_RADIO_DB := 8.0
## The same for the rain and wind at the wheel in the chase view.
const CHASE_STORM_UNDER_RADIO_DB := 6.0
## How far the idling engine must sit over the rain (in the cabin and outside),
## in both views, so you hear your car without turning everything up.
const ENGINE_OVER_STORM_DB := 2.0
## Cruising at about 50 km/h with the radio on, how far your engine and your
## tyres must each sit under the radio (dB, mean of the meters; measured
## about 5-8 dB under, so 3 leaves room for the meters' swing).
const CAR_UNDER_RADIO_DB := 3.0
const CRUISE_KMH := 50.0
## The loudest a menu click may peak at (dB on the UI bus, at full volume;
## measured about -14, and -6.5 before the UI bus came down).
const MENU_CLICK_MAX_DB := -12.0

var _main: Node
var _audio: Node
var _world: Node3D
var _frame := 0
var _failures: Array[String] = []
var _probe: AudioStreamPlayer3D
var _probe_bus := -1


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_audio = root.get_node("Audio")
		_world = _main.get_node("LoFi/SubViewport/World")
		root.get_node("GameClock").set_time(21.5)
		_run.call_deferred()
	_frame += 1
	return false


func _run() -> void:
	await _wait(4.0)
	# The city's roads reach traffic as map tiles stream in, on worker threads
	# in real time: on a busy runner, wait for the ones round home first.
	var map: Node = _world.get_node_or_null("PerthMap")
	var traffic_node: Node = _world.get_node("Traffic")
	var give_up := _frame + 30 * FPS
	while _frame < give_up and ((map and map.loaded_tile_count() < 6) or not traffic_node._pending_networks.is_empty()):
		await process_frame
	var ear: Node3D = _audio.listener()
	_check(ear != null and ear is Camera3D and (ear as Camera3D).current, "the player hears from the game camera")
	var traffic: Node = _world.get_node("Traffic")
	var ta: Node = _audio.hooks.traffic
	_check(ta != null, "traffic sound is hooked up")
	# Bring out the sounds that only play now and then: a drive-by, a place,
	# a crowd, a far siren.
	var em = traffic.spawn_emergency(ear.global_position, &"ambulance")
	_check(em != null, "an ambulance can be sent on a call")
	_audio.ambience.add_place("carpark", ear.global_position + Vector3(20, 0, 0), 60.0)
	_audio.ambience.update_places(ear.global_position)
	if ta:
		ta._on_distant_siren(ear.global_position + Vector3(500, 0, 0))
		var people: Array[Vector3] = []
		for i in 9:
			people.append(ear.global_position + Vector3(30 + i, 0, 0))
		var group: Array = ta.crowd_at(people)
		_check(group[1] == 9 and (group[0] as Vector3).distance_to(ear.global_position) > 25.0,
				"a crowd is heard from where the people are (%.0f m away)" % (group[0] as Vector3).distance_to(ear.global_position))
	await _wait(1.0)
	_check_flat_sounds()
	await _check_sliders()
	await _check_falloff()
	await _check_storm_in_car()
	await _check_menu_clicks()
	_check_sirens(traffic, ear)
	await _check_radio_over_car(traffic)  # last: it drives the car away from home
	_finish()


# ---------------------------------------------------------------------------
# Falloff
# ---------------------------------------------------------------------------

func _check_falloff() -> void:
	print("falloff (tone at 4 m or a fifth of reach / half reach / past reach, dB):")
	AudioServer.add_bus()
	_probe_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_probe_bus, "Probe")
	AudioServer.set_bus_send(_probe_bus, "Master")
	# Everything else quiet, so the master limiter can't squash the probe.
	for b in ["Music", "UI", "Radio", "Cabin", "World"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(b), true)
	_probe = AudioStreamPlayer3D.new()
	_probe.stream = _tone()
	_probe.bus = &"Probe"
	_world.add_child(_probe)
	var seen := {}
	for p in _players_3d(root):
		if p == _probe:
			continue
		_check(p.max_distance > 0.0, "%s has a reach (max_distance %.0f)" % [_label(p), p.max_distance])
		var key := "%d|%.1f|%.0f|%.1f" % [p.attenuation_model, p.unit_size, p.max_distance, p.max_db]
		if seen.has(key) or p.max_distance <= 0.0:
			continue
		seen[key] = true
		_probe.attenuation_model = p.attenuation_model
		_probe.unit_size = p.unit_size
		_probe.max_distance = p.max_distance
		_probe.max_db = p.max_db
		_probe.panning_strength = p.panning_strength
		var near := await _level_at(minf(4.0, p.max_distance * 0.2))
		var half := await _level_at(p.max_distance * 0.5)
		var past := await _level_at(p.max_distance * 1.05)
		print("  %-44s unit %5.1f reach %5.0f m: %6.1f %6.1f %6.1f" % [_label(p), p.unit_size, p.max_distance, near, half, past])
		_check(near - half >= MIN_DROP_DB, "%s gets quieter with distance (%.1f dB down at %.0f m)" % [_label(p), near - half, p.max_distance * 0.5])
		_check(past < -80.0, "%s is silent past its reach (%.0f dB at %.0f m)" % [_label(p), past, p.max_distance * 1.05])
	_probe.stop()
	for b in ["Music", "UI", "Radio", "Cabin", "World"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(b), false)


## Peak level (dB, both channels) of the probe tone `metres` in front of the camera.
func _level_at(metres: float) -> float:
	var cam: Node3D = _audio.listener()
	_probe.global_position = cam.global_position - cam.global_transform.basis.z * metres
	_probe.play()
	await _wait(0.4)
	var peak := -200.0
	for i in 12:
		await process_frame
		peak = maxf(peak, maxf(AudioServer.get_bus_peak_volume_left_db(_probe_bus, 0),
				AudioServer.get_bus_peak_volume_right_db(_probe_bus, 0)))
	_probe.stop()
	await _wait(0.2)
	return peak


static func _tone() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	for i in rate:
		data.encode_s16(i * 2, int(sin(TAU * 441.0 * i / rate) * 16000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = rate
	return w


# ---------------------------------------------------------------------------
# Volume sliders
# ---------------------------------------------------------------------------

## With the Effects, Music and Radio sliders all the way down, nothing may
## still be heard, menu sounds included: everything must go through a bus one
## of those sliders turns down, not straight to Master (or a missing bus).
## Under Effects, Your car turns down exactly the player's car (engine, tyres,
## cabin) and Weather and street exactly the street, traffic and weather.
func _check_sliders() -> void:
	var players: Array = []
	players.append_array(_players_3d(root))
	players.append_array(_players_2d(root))
	var low := await _gains_with(players, {"volume_effects": 0.0, "volume_music": 0.0, "volume_radio": 0.0})
	players = players.filter(func(p) -> bool: return low.has(p))
	var loud: Array[String] = []
	for p in players:
		if low[p] > -60.0:
			loud.append("%s (%s)" % [_label(p), " > ".join(_bus_chain(p.bus))])
	_check(loud.is_empty(), "every sound, menus included, turns down with the Effects, Music or Radio slider"
			+ _first(loud))
	var ui: Array = players.filter(func(p) -> bool: return _bus_chain(p.bus).has("UI"))
	_check(not ui.is_empty() and ui.all(func(p) -> bool: return low[p] <= -60.0), "menu sounds follow the Effects slider")
	# The player's engine plays on Engine (Your car); traffic engines on Vehicles.
	var car: Node = _world.get_node("Car")
	var mine: Array = players.filter(func(p) -> bool: return p is AudioStreamPlayer3D and car.is_ancestor_of(p) and "engine_set" in p.get_parent())
	var traffic_engines: Array = players.filter(func(p) -> bool: return "engine_set" in p.get_parent() and not car.is_ancestor_of(p))
	_check(not mine.is_empty() and mine.all(func(p) -> bool: return p.bus == &"Engine"), "your car's engine plays on the Engine bus")
	_check(not traffic_engines.is_empty() and traffic_engines.all(func(p) -> bool: return p.bus == &"Vehicles"),
			"traffic engines play on the Vehicles bus, not your car's")
	await _check_sub_slider(players, "volume_car", ["Engine", "Tyres", "Cabin"], "Your car")
	await _check_sub_slider(players, "volume_surroundings", ["Ambience", "Weather", "Vehicles"], "Weather and street")


## A slider under Effects at 0 silences the sounds on `buses` and leaves
## every other sound exactly where it was.
func _check_sub_slider(players: Array, key: String, buses: Array, label: String) -> void:
	var before := await _gains_with(players, {})
	var after := await _gains_with(players, {key: 0.0})
	var wrong: Array[String] = []
	for p in players:
		if not (before.has(p) and after.has(p)):
			continue  # a one-shot that finished meanwhile
		var chain := _bus_chain(p.bus)
		var under := buses.any(func(b) -> bool: return chain.has(b))
		if (under and after[p] > -60.0) or (not under and absf(after[p] - before[p]) > 0.1):
			wrong.append("%s (%s, %.0f to %.0f dB)" % [_label(p), " > ".join(chain), before[p], after[p]])
	_check(wrong.is_empty(), "the %s slider turns down %s and nothing else" % [label, ", ".join(buses)]
			+ _first(wrong))


## The first few offenders, so a failure names them without a wall of text.
static func _first(names: Array) -> String:
	if names.is_empty():
		return ""
	var shown := ", ".join(PackedStringArray(names.slice(0, 4)))
	return " (%s%s)" % [shown, ", and %d more" % (names.size() - 4) if names.size() > 4 else ""]


## Each player's gain through its buses to Master (dB, faders only) with the
## given settings, which are put back afterwards.
func _gains_with(players: Array, values: Dictionary) -> Dictionary:
	var settings: Node = root.get_node("Settings")
	var keep := {}
	for key in values:
		keep[key] = settings.get(key)
		settings.set(key, values[key])
	settings.apply()
	await process_frame
	var out := {}
	for p in players:
		if not is_instance_valid(p):
			continue
		var gain := 0.0
		for b in _bus_chain(p.bus):
			if b != "Master":
				gain += AudioServer.get_bus_volume_db(AudioServer.get_bus_index(b))
		out[p] = gain
	for key in keep:
		settings.set(key, keep[key])
	settings.apply()
	return out


## The buses a player's sound goes through to Master; a missing bus plays
## straight into Master.
static func _bus_chain(bus: StringName) -> Array[String]:
	var out: Array[String] = []
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		out.append("missing bus " + String(bus))
		idx = 0
	while idx > 0 and out.size() < 16:
		out.append(AudioServer.get_bus_name(idx))
		idx = AudioServer.get_bus_index(AudioServer.get_bus_send(idx))
	out.append("Master")
	return out


# ---------------------------------------------------------------------------
# Flat sounds
# ---------------------------------------------------------------------------

## A flat (2D) player on a world bus is everywhere at once. Only the zone
## beds, the weather layers and the workshop's room tone may be.
func _check_flat_sounds() -> void:
	var amb: Node = _audio.ambience
	var allowed: Array = [amb._bed_a, amb._bed_b, _audio.hooks._room_tone]
	allowed.append_array(amb._layers.values())
	var flat: Array[String] = []
	for p in _players_2d(root):
		if p.playing and _on_world_bus(p.bus) and not allowed.has(p):
			flat.append(_label(p))
	_check(flat.is_empty(), "nothing in the world plays flat" + (" (%s)" % ", ".join(flat) if flat else ""))
	var places: Array = amb._place_players.values()
	_check(not places.is_empty() and places.all(func(p) -> bool: return p is AudioStreamPlayer3D),
			"place sounds are heard from the place")


func _on_world_bus(bus: StringName) -> bool:
	var b := bus
	for i in 8:
		if b in WORLD_BUSES:
			return true
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			return false
		b = AudioServer.get_bus_send(idx)
	return false


# ---------------------------------------------------------------------------
# The car in a storm
# ---------------------------------------------------------------------------

## Sits in the car in the interior view, then the chase view, in a storm with
## the radio on, and compares what each bus sends on. Weather feeds World, so it is heard after
## the World fader (the one the Effects slider moves); its own meter is not.
func _check_storm_in_car() -> void:
	var weather: Node = root.get_node("Weather")
	weather.set_state(weather.State.STORM, true)
	weather._seconds_until_lightning = 1e9  # no thunder in the middle of a reading
	var rig: Node = _world.get_node("CameraRig")
	if rig.mode != rig.Mode.INTERIOR:
		rig.toggle_mode()
	_audio.radio.set_station("cinquecento")
	await _wait(10.0)  # the rain and wipers fade in
	_check(_audio.is_player_inside(), "the interior view puts the player in the car")
	var loud: Dictionary = await _bus_levels(8.0)
	var radio: float = loud["Radio"]
	var cabin: float = loud["Cabin"]
	var storm: float = loud["Weather"] + AudioServer.get_bus_volume_db(AudioServer.get_bus_index("World"))
	print("storm in the car: radio %.1f dB, cabin %.1f dB, storm outside %.1f dB" % [radio, cabin, storm])
	_check(radio - cabin >= CABIN_UNDER_RADIO_DB,
			"in a storm the rain on the roof and the wipers sit under the radio (%.1f dB under)" % (radio - cabin))
	_check(radio - storm >= STORM_UNDER_RADIO_DB,
			"in a storm the rain and wind outside the car sit under the radio (%.1f dB under)" % (radio - storm))
	var engine: float = loud["Engine"] + AudioServer.get_bus_volume_db(AudioServer.get_bus_index("World"))
	print("  engine idling in the car: %.1f dB" % engine)
	_check(engine - maxf(cabin, storm) >= ENGINE_OVER_STORM_DB,
			"in a storm the idling engine is heard over the rain in the car (%.1f dB over)" % (engine - maxf(cabin, storm)))
	var settings: Node = root.get_node("Settings")
	var keep: float = settings.volume_effects
	settings.volume_effects = 0.1
	settings.apply()
	await _wait(1.0)
	var low: Dictionary = await _bus_levels(4.0)
	settings.volume_effects = keep
	settings.apply()
	var drops := {}
	for b in ["Radio", "Cabin", "World"]:
		drops[b] = loud[b] - low[b]
	print("Effects at 10%%: radio %.1f dB down, cabin %.1f dB down, world (storm, engine, street) %.1f dB down" % [drops["Radio"], drops["Cabin"], drops["World"]])
	_check(drops["Cabin"] >= 12.0 and drops["World"] >= 12.0,
			"Effects at 10%% turns the storm and the wipers down in the car (%.1f and %.1f dB)" % [drops["World"], drops["Cabin"]])
	_check(absf(drops["Radio"]) < 2.0, "Effects leaves the radio alone (%.1f dB)" % drops["Radio"])
	# Back to the chase view, still at the wheel: the street sounds like
	# outside again, but the storm ducks under the radio.
	rig.toggle_mode()
	await _wait(4.0)
	_check(not _audio.is_player_inside() and _audio.has_method("is_player_driving") and _audio.is_player_driving(),
			"the chase view hears the car from outside, at the wheel")
	var chase: Dictionary = await _bus_levels(8.0)
	var chase_storm: float = chase["Weather"] + AudioServer.get_bus_volume_db(AudioServer.get_bus_index("World"))
	print("storm in the chase view: radio %.1f dB, storm %.1f dB" % [chase["Radio"], chase_storm])
	_check(chase["Radio"] - chase_storm >= CHASE_STORM_UNDER_RADIO_DB,
			"in a storm in the chase view the rain and wind sit under the radio (%.1f dB under)" % (chase["Radio"] - chase_storm))
	var chase_engine: float = chase["Engine"] + AudioServer.get_bus_volume_db(AudioServer.get_bus_index("World"))
	print("  engine idling in the chase view: %.1f dB" % chase_engine)
	_check(chase_engine - chase_storm >= ENGINE_OVER_STORM_DB,
			"in a storm in the chase view the idling engine is heard over the rain (%.1f dB over)" % (chase_engine - chase_storm))
	weather.set_state(weather.State.CLEAR, true)


## Opens and shuts the pause menu (the card clicks, the pause clicks, focus
## ticks) and reads the loudest moment on the UI bus.
func _check_menu_clicks() -> void:
	var menu: Node = _main.get_node("PauseMenu")
	var peak := -100.0
	var ui := AudioServer.get_bus_index("UI")
	for step in 2:
		if step == 0:
			menu.open()
		else:
			menu.close()
		var until := _frame + FPS
		while _frame < until:
			await process_frame
			peak = maxf(peak, maxf(AudioServer.get_bus_peak_volume_left_db(ui, 0), AudioServer.get_bus_peak_volume_right_db(ui, 0)))
	_check(peak > -60.0 and peak <= MENU_CLICK_MAX_DB,
			"menu clicks sit with the game (peak %.1f dB, at most %.0f)" % [peak, MENU_CLICK_MAX_DB])


## Drives the car down a long straight road near home at about 50 km/h with
## the radio on, in the interior view and then the chase view, and compares
## the radio with your own engine and tyres as heard (Engine and Tyres feed
## World, so the World fader counts).
func _check_radio_over_car(traffic: Node) -> void:
	var car: RigidBody3D = _world.get_node("Car")
	var settings: Node = root.get_node("Settings")
	var auto: bool = settings.automatic_gearbox
	settings.automatic_gearbox = true
	settings.apply()
	var lane = null
	var best := INF
	for l in traffic.graph.lanes:
		if l.connector or l.length < 200.0 or l.pts.size() < 2:
			continue
		var a: Vector3 = l.pts[0]
		var b: Vector3 = l.pts[l.pts.size() - 1]
		if a.distance_to(b) < 0.98 * l.length or absf(a.y - b.y) > 0.03 * l.length:
			continue  # bends or climbs
		var d := a.distance_to(car.global_position)
		if d < best:
			best = d
			lane = l
	_check(lane != null, "there is a long straight road near home to drive down")
	if lane != null:
		print("  driving down a %.0f m road %.0f m from home" % [lane.length, best])
	if lane == null:
		return
	var rig: Node = _world.get_node("CameraRig")
	_audio.radio.set_station("cinquecento")
	for view in ["interior", "chase"]:
		if (rig.mode == rig.Mode.INTERIOR) != (view == "interior"):
			rig.toggle_mode()
		var a: Vector3 = lane.pts[0]
		var dir: Vector3 = (lane.pts[lane.pts.size() - 1] - a).normalized()
		car.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), a + Vector3.UP * 0.8)
		car.linear_velocity = dir * CRUISE_KMH / 3.6
		car.angular_velocity = Vector3.ZERO
		var levels: Dictionary = await _cruise(car, a, dir, 3.0)  # get settled
		levels = await _cruise(car, a, dir, 6.0)
		var wf := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("World"))
		var radio: float = levels["Radio"]
		var engine: float = levels["Engine"] + wf
		var tyres: float = levels["Tyres"] + wf
		print("cruising in the %s view at %.0f km/h: radio %.1f dB, engine %.1f dB, tyres %.1f dB"
				% [view, levels["kmh"], radio, engine, tyres])
		_check(levels["kmh"] > CRUISE_KMH - 15.0 and levels["kmh"] < CRUISE_KMH + 15.0,
				"the car cruises at about %.0f km/h in the %s view (%.0f)" % [CRUISE_KMH, view, levels["kmh"]])
		_check(radio - engine >= CAR_UNDER_RADIO_DB and radio - tyres >= CAR_UNDER_RADIO_DB,
				"cruising in the %s view the radio is heard over your engine and tyres (%.1f and %.1f dB over)"
				% [view, radio - engine, radio - tyres])
	for action in ["accelerate", "steer_left", "steer_right"]:
		Input.action_release(action)
	settings.automatic_gearbox = auto
	settings.apply()


## Holds about CRUISE_KMH along a straight line from `a` (throttle and a
## little steering, like a player) for `seconds`, returning each bus's mean
## meter level (dB) and the mean speed ("kmh").
func _cruise(car: RigidBody3D, a: Vector3, dir: Vector3, seconds: float) -> Dictionary:
	var sums := {}
	var kmh := 0.0
	var n := 0
	var until := _frame + int(seconds * FPS)
	while _frame < until:
		await process_frame
		var v := car.linear_velocity.length() * 3.6
		Input.action_release("accelerate")
		if v < CRUISE_KMH - 4.0:
			Input.action_press("accelerate", 0.7)
		elif v < CRUISE_KMH:
			Input.action_press("accelerate", 0.3)
		var ahead := a + dir * ((car.global_position - a).dot(dir) + 15.0)
		var steer := clampf((car.global_transform.affine_inverse() * ahead).x * 0.15, -1.0, 1.0)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if absf(steer) > 0.02:
			Input.action_press("steer_right" if steer > 0.0 else "steer_left", absf(steer))
		kmh += v
		n += 1
		for i in AudioServer.bus_count:
			var b := AudioServer.get_bus_name(i)
			var db := maxf(-100.0, maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0)))
			sums[b] = sums.get(b, 0.0) + db_to_linear(db)
	var out := {"kmh": kmh / maxf(n, 1)}
	for b in sums:
		out[b] = linear_to_db(maxf(sums[b] / maxf(n, 1), 1e-5))
	return out


## Each bus's level at loud moments over `seconds`: the 90th percentile of
## its meter (dB, after its own fader).
func _bus_levels(seconds: float) -> Dictionary:
	var readings := {}
	var until := _frame + int(seconds * FPS)
	while _frame < until:
		await process_frame
		for i in AudioServer.bus_count:
			var b := AudioServer.get_bus_name(i)
			if not readings.has(b):
				readings[b] = []
			readings[b].append(maxf(-100.0, maxf(AudioServer.get_bus_peak_volume_left_db(i, 0),
					AudioServer.get_bus_peak_volume_right_db(i, 0))))
	var out := {}
	for b in readings:
		var r: Array = readings[b]
		r.sort()
		out[b] = r[int(r.size() * 0.9)]
	return out


# ---------------------------------------------------------------------------
# Sirens
# ---------------------------------------------------------------------------

func _check_sirens(traffic: Node, ear: Node3D) -> void:
	var sprinkled: Array[String] = []
	for zone in _audio.ambience.SPRINKLES:
		for entry in _audio.ambience.SPRINKLES[zone]:
			if String(entry[0]).contains("siren"):
				sprinkled.append(zone)
	_check(sprinkled.is_empty(), "no sirens sprinkled into the zone ambience" + (" (%s)" % ", ".join(sprinkled) if sprinkled else ""))
	# A drive-by's siren stops once its call is over.
	var em = traffic.spawn_emergency(ear.global_position, &"police")
	if em:
		_check(em.siren.playing, "a drive-by comes with its siren on")
		traffic.step_emergencies(ear.global_position, 80.0)
		_check(not em.siren.playing, "a drive-by's siren stops when its call is over")
	_check(traffic.emergencies.is_empty(), "no emergency left wailing")
	# A few days of calls, fast-forwarded (fixed dice, so it's the same every run).
	traffic._emergency_rng.seed = 500
	traffic._emergency_timer = -1.0
	var far := [0]
	var drive_by := [0]
	var count_far := func(_pos: Vector3, _type: StringName) -> void: far[0] += 1
	var count_drive := func(_body: Node3D, type: StringName) -> void:
		if type in [&"police", &"ambulance", &"fire"]:
			drive_by[0] += 1
	traffic.distant_siren.connect(count_far)
	traffic.vehicle_spawned.connect(count_drive)
	var days := 5
	var dt := 0.25
	var steps := int(days * float(root.get_node("GameClock").seconds_per_day) / dt)
	for i in steps:
		traffic.step_emergencies(ear.global_position, dt)
	traffic.distant_siren.disconnect(count_far)
	traffic.vehicle_spawned.disconnect(count_drive)
	var per_day := float(far[0] + drive_by[0]) / days
	print("sirens: %d far off and %d driving past over %d in-game days (%.1f a day)" % [far[0], drive_by[0], days, per_day])
	_check(per_day <= MAX_SIRENS_PER_DAY, "a few sirens a day at most (%.1f)" % per_day)
	_check(per_day >= 1.0, "sirens still happen (%.1f a day)" % per_day)
	_check(far[0] > drive_by[0], "most sirens are far off (%d far, %d drive-bys)" % [far[0], drive_by[0]])


# ---------------------------------------------------------------------------

func _players_3d(n: Node) -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for c in n.get_children(true):
		if c is AudioStreamPlayer3D:
			out.append(c)
		out.append_array(_players_3d(c))
	return out


func _players_2d(n: Node) -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for c in n.get_children(true):
		if c is AudioStreamPlayer:
			out.append(c)
		out.append_array(_players_2d(c))
	return out


func _label(p: Node) -> String:
	var parent := p.get_parent()
	var owner_name := String(parent.name) if parent else ""
	if parent and parent.name == &"Audio" and parent.get_parent():
		owner_name = String(parent.get_parent().name)
	return "%s/%s" % [owner_name.left(24), String(p.name).left(18)]


func _wait(seconds: float) -> void:
	var until := _frame + int(seconds * FPS)
	while _frame < until:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok or not what.contains(" has a reach"):
		print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("SOUND CHECK PASSED")
	else:
		print("SOUND CHECK FAILED (%d)" % _failures.size())
		for f in _failures:
			print("  - " + f)
	# Takes the game down before quitting (a plain quit() crashed on exit on Windows).
	root.get_node("SaveGame").quit_cleanly(0 if _failures.is_empty() else 1)
