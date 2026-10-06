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
## - With the Effects, Music and Radio sliders down, nothing but the menus'
##   sounds can still be heard (nothing bypasses them straight to Master).
## - Sirens: none sprinkled into the ambience, a few emergency calls per
##   in-game day (most of them far off), and a drive-by's siren stops once
##   it has gone past.
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
	_check_sliders()
	await _check_falloff()
	_check_sirens(traffic, ear)
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

## With the Effects, Music and Radio sliders all the way down, only menu (UI)
## sounds may still be heard: everything else must go through a bus one of
## those sliders turns down, not straight to Master (or a missing bus).
func _check_sliders() -> void:
	var settings: Node = root.get_node("Settings")
	var keep := {}
	for key in ["volume_effects", "volume_music", "volume_radio"]:
		keep[key] = settings.get(key)
		settings.set(key, 0.0)
	settings.apply()
	var loud := {}
	var players: Array = []
	players.append_array(_players_3d(root))
	players.append_array(_players_2d(root))
	for p in players:
		var chain := _bus_chain(p.bus)
		if chain.has("UI"):
			continue
		var gain := 0.0
		for b in chain:
			if b != "Master":
				gain += AudioServer.get_bus_volume_db(AudioServer.get_bus_index(b))
		if gain > -60.0:
			loud["%s (%s)" % [_label(p), " > ".join(chain)]] = true
	_check(loud.is_empty(), "every sound but the menus turns down with the Effects, Music or Radio slider"
			+ (" (%s)" % ", ".join(loud.keys()) if loud else ""))
	for key in keep:
		settings.set(key, keep[key])
	settings.apply()


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
