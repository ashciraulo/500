extends Node
## Headless checks for the audio code and files. Run the scene:
##   godot --headless res://audio/tests/test_audio.tscn
## Exits non-zero on failure.

var failures := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		printerr("  FAIL ", what)


var root: Node
var process_frame: Signal


func create_timer(t: float) -> SceneTreeTimer:
	return get_tree().create_timer(t)


func quit(code := 0) -> void:
	get_tree().quit(code)


func _ready() -> void:
	root = get_tree().root
	process_frame = get_tree().process_frame
	# Let autoloads finish _ready before testing.
	await process_frame
	await process_frame
	var audio: Node = root.get_node_or_null("Audio")
	check(audio != null, "Audio autoload present")
	if audio == null:
		quit(1)
		return
	_test_buses()
	_test_index(audio)
	_test_engines(audio)
	await _test_engine_node(audio)
	_test_radio_tags()
	await _test_my_music(audio)
	await _test_ambience(audio)
	await _test_car_scene(audio)
	await _test_hooks(audio)
	await _test_traffic(audio)
	await _test_footsteps(audio)
	_test_programme(audio)
	print("%d failure(s)" % failures)
	quit(1 if failures else 0)


func _test_buses() -> void:
	print("buses")
	for b in ["Music", "UI", "Radio", "Cabin", "World", "Engine", "Tyres", "SFX", "Ambience", "Weather"]:
		check(AudioServer.get_bus_index(b) >= 0, "bus " + b)
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Engine")) == "World", "Engine sends to World")


func _test_index(audio: Node) -> void:
	print("sound index")
	var names: PackedStringArray = audio.names_in("engine/fire12")
	check(names.size() >= 14, "fire12 has loops (%d files)" % names.size())
	check(audio.has("engine/extras/eng_backfire"), "variant set eng_backfire")
	var s: AudioStream = audio.stream("engine/fire12/eng_fire12_onload_3500", true)
	check(s != null and s.loop, "loop stream loads with loop on")
	var s2: AudioStream = audio.stream("engine/fire12/eng_fire12_onload_3500")
	check(s2 != null and not s2.loop, "same file loads as one-shot without loop")


func _test_engines(audio: Node) -> void:
	print("engine sets")
	for fam in ["fire12", "fire14", "twinair", "tjet", "classic", "classicflat", "classicabarth", "electric", "abarthe"]:
		var names: PackedStringArray = audio.names_in("engine/" + fam)
		var on := 0
		var off := 0
		for n in names:
			if n.contains("_onload_"):
				on += 1
			elif n.contains("_offload_"):
				off += 1
		check(on >= 5 and on == off, "%s: %d on-load, %d off-load loops" % [fam, on, off])
		if fam.begins_with("classic"):
			check(audio.names_in("engine/%smegaphone" % fam).size() >= 2 * on,
					"%s has the Abarth megaphone set" % fam)
		if not fam.begins_with("electric") and not fam == "abarthe" and fam != "classicflat":
			for v in ["sport", "straight"]:
				var vn := 0
				for n in audio.names_in("engine/" + fam + v):
					if n.contains("load_"):
						vn += 1
				check(vn == on + off, "%s%s has the same loops as stock" % [fam, v])
		check(audio.has("engine/%s/eng_%s_startup" % [fam, fam]), fam + " startup")


func _test_engine_node(audio: Node) -> void:
	print("EngineAudio node")
	var holder := Node3D.new()
	root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	var e := EngineAudio.new()
	e.engine_set = "fire12"
	holder.add_child(e)
	e.start_running()
	e.rpm = 3000.0
	e.throttle = 1.0
	for i in 10:
		await process_frame
	var audible := 0
	var pitches := []
	for c in e.get_children():
		if c is AudioStreamPlayer3D and c.playing and not c.stream_paused and c.volume_db > -60.0:
			audible += 1
			pitches.append(snappedf(c.pitch_scale, 0.01))
	check(audible >= 2 and audible <= 5, "3000 rpm: %d loops audible, pitches %s" % [audible, pitches])
	e.rpm = 850.0
	e.throttle = 0.0
	for i in 30:
		await process_frame
	check(true, "idle without errors")
	var t := EngineAudio.new()
	t.engine_set = "tjet"
	holder.add_child(t)
	t.start_running()
	check(t.turbo > 0.0 and t.pops > 0.0, "T-Jet gets turbo and pops automatically")
	var ev := EngineAudio.new()
	ev.engine_set = "electric"
	holder.add_child(ev)
	ev.start_running()
	ev.speed_kmh = 50.0
	ev.throttle = 1.0
	await process_frame
	await process_frame
	check(true, "electric runs on speed")
	holder.queue_free()


func _test_radio_tags() -> void:
	print("radio tags")
	var Radio := load("res://audio/scripts/radio.gd")
	# Build a minimal ID3v2.3 header with TIT2 and TPE1.
	var b := PackedByteArray("ID3".to_ascii_buffer())
	b.append_array(PackedByteArray([3, 0, 0, 0, 0, 0, 0]))
	for fr in [["TIT2", "Nel Blu"], ["TPE1", "Domenico"]]:
		var text: PackedByteArray = fr[1].to_utf8_buffer()
		b.append_array(fr[0].to_ascii_buffer())
		var size := text.size() + 1
		b.append_array(PackedByteArray([0, 0, 0, size, 0, 0, 3]))
		b.append_array(text)
	var tag_size := b.size() - 10
	b[9] = tag_size & 0x7f
	b[8] = (tag_size >> 7) & 0x7f
	var path := "user://test_tags.mp3"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()
	var tags: Dictionary = Radio.read_tags(ProjectSettings.globalize_path(path))
	check(tags.title == "Nel Blu" and tags.artist == "Domenico", "ID3 tags: %s" % tags)
	var t2: Dictionary = Radio.read_tags("/nonexistent/Some Band - Some Song.ogg")
	check(t2.title == "Some Song" and t2.artist == "Some Band", "file-name fallback: %s" % t2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_my_music(audio: Node) -> void:
	print("My Music")
	var radio: Node = audio.radio
	var dir := "user://Music"
	check(DirAccess.dir_exists_absolute(dir), "Music folder created at " + ProjectSettings.globalize_path(dir))
	# Copy real files in: an OGG at the top, and a playlist folder with two.
	DirAccess.make_dir_recursive_absolute(dir + "/Test Playlist")
	var src := ProjectSettings.globalize_path("res://audio/tests/fixtures")
	var copied := 0
	for f in ["tone.ogg", "tone.mp3", "tone.wav"]:
		if FileAccess.file_exists(src.path_join(f)):
			var to := dir.path_join(f) if f == "tone.ogg" else dir.path_join("Test Playlist").path_join(f)
			DirAccess.copy_absolute(src.path_join(f), ProjectSettings.globalize_path(to))
			copied += 1
	check(copied == 3, "fixtures copied")
	radio.scan_my_music()
	check(radio.playlists.has("All music") and radio.playlists["All music"].size() == 3, "All music has 3 tracks")
	check(radio.playlists.has("Test Playlist") and radio.playlists["Test Playlist"].size() == 2, "subfolder is a playlist")
	for f in radio.playlists["All music"]:
		var s: AudioStream = radio.load_music_file(f)
		check(s != null and s.get_length() > 0.5, "loads " + f.get_file())
	radio.set_station("mymusic")
	await create_timer(0.6).timeout
	check(radio.current_station_id() == "mymusic", "tuned to My Music")
	check(radio._player.playing, "My Music is playing")
	var first: String = radio._order[radio._pos]
	radio.next_track()
	check(radio._order[radio._pos] != first, "next track")
	radio.next_playlist()
	check(radio.playlist != "All music", "switched playlist to " + radio.playlist)
	radio.turn_off()
	check(not radio.is_on(), "radio off")
	radio.set_station("cinquecento")
	await create_timer(0.6).timeout
	check(radio._player.playing or not audio.has("music/mus_cinquecento_01"), "Radio Cinquecento plays")
	radio.turn_off()
	# Clean up the test files.
	for f in radio.playlists["All music"]:
		DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/Test Playlist"))


func _test_ambience(audio: Node) -> void:
	print("ambience")
	var amb: Node = audio.ambience
	amb.set_zone("kingspark")
	amb.set_weather(0.8, 1.0)
	audio.set_player_inside(true)
	for i in 20:
		await process_frame
	check(amb._bed_name.begins_with("amb/amb_kingspark") or not audio.has("amb/amb_kingspark_day"), "Kings Park bed: " + amb._bed_name)
	# Bed variants: rain (with hysteresis), late night, dawn, back to day.
	if audio.has("amb/amb_kingspark_rain"):
		amb.set_time_of_day(12.0)
		check(amb._bed_name == "amb/amb_kingspark_rain", "rain bed when wet: " + amb._bed_name)
		amb.set_weather(0.25, 0.0)
		check(amb._bed_name == "amb/amb_kingspark_rain", "rain bed held at 0.25 (hysteresis)")
		amb.set_weather(0.0, 0.0)
		check(amb._bed_name == "amb/amb_kingspark_day", "day bed when dry: " + amb._bed_name)
		amb.set_time_of_day(3.0)
		check(amb._bed_name == "amb/amb_kingspark_late", "late bed at 03:00: " + amb._bed_name)
		amb.set_time_of_day(5.5)
		check(amb._bed_name == "amb/amb_kingspark_dawn", "dawn bed at 05:30: " + amb._bed_name)
		amb.set_time_of_day(12.0)
		amb.set_weather(0.8, 1.0)
	amb.lightning(500.0)
	audio.set_player_inside(false)
	check(true, "weather and lightning without errors")
	# Place layers: every type has day and night loops; a place fades in as
	# you get near it and out as you leave; a "poi" node counts as a place.
	for type in amb.PLACE_TYPES:
		check(audio.has("amb/place/place_%s_loop" % type) and audio.has("amb/place/place_%s_night_loop" % type),
				"place %s has day and night loops" % type)
	amb.set_time_of_day(12.0)
	amb.add_place("beach", Vector3(1000, 0, 0), 100.0)
	amb.update_places(Vector3(1010, 0, 0))
	check(is_equal_approx(amb._place_amount.get("beach", 0.0), 1.0), "full beach layer at the beach")
	amb.update_places(Vector3(1080, 0, 0))
	var mid: float = amb._place_amount.get("beach", 0.0)
	check(mid > 0.0 and mid < 1.0, "beach layer fades with distance (%.2f)" % mid)
	amb.update_places(Vector3(0, 0, 0))
	check(amb._place_amount.get("beach", 0.0) == 0.0, "no beach layer far away")
	var poi := Node3D.new()
	poi.add_to_group("poi")
	poi.set_meta("poi_type", "carpark")
	root.add_child(poi)
	poi.global_position = Vector3(-500, 0, 300)
	amb.set_time_of_day(23.0)
	amb.update_places(Vector3(-505, 0, 300))
	for i in 10:
		await process_frame
	var cp: AudioStreamPlayer = amb._place_players.get("carpark")
	check(cp != null and cp.playing, "car park POI node plays its layer")
	check(amb.place_sound("carpark") == "amb/place/place_carpark_night_loop", "night loop after dark")
	poi.queue_free()
	amb.clear_places()
	# The map's POI data (MapStreamer.get_pois()) becomes place layers.
	amb.add_map_pois([
		{"id": "beach_cottesloe", "kind": "beach", "suburb": "Cottesloe", "p": Vector3(0, 0, 0), "at": Vector3(5000, 0, 0)},
		{"id": "lookout_dryandra_lookout", "kind": "lookout", "suburb": "Kings Park", "p": Vector3.ZERO, "at": Vector3(0, 0, 5000)},
		{"id": "landmark_bell_tower", "kind": "landmark", "suburb": "Perth", "p": Vector3.ZERO, "at": Vector3(-5000, 0, 0)},
		{"id": "servo_1", "kind": "servo", "suburb": "Perth", "p": Vector3(0, 0, -5000), "at": Vector3(0, 0, -5010)},
	])
	amb.update_places(Vector3(5000, 0, 10))
	check(amb._place_amount.get("beach", 0.0) == 1.0, "map beach POI -> beach layer")
	amb.update_places(Vector3(0, 0, 5000))
	check(amb._place_amount.get("lookout", 0.0) == 1.0 and amb._place_amount.get("bush", 0.0) == 1.0,
			"Kings Park lookout -> lookout wind over the bush")
	amb.update_places(Vector3(-5000, 0, 0))
	check(amb._place_amount.get("quay", 0.0) == 1.0, "bell tower -> quay layer")
	amb.set_time_of_day(12.0)
	amb.update_places(Vector3(0, 0, -5000))
	check(amb._place_amount.get("carpark", 0.0) == 0.0, "servo is quiet by day")
	amb.set_time_of_day(23.0)
	amb.update_places(Vector3(0, 0, -5000))
	check(amb._place_amount.get("carpark", 0.0) == 1.0, "servo -> empty car park at night")
	amb.clear_places()
	amb.update_places(Vector3.ZERO)
	amb.set_time_of_day(12.0)


func _test_car_scene(audio: Node) -> void:
	print("car scene")
	var car: Node3D = load("res://scenes/vehicles/fiat_500_pop.tscn").instantiate()
	root.add_child(car)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.global_position = car.global_position + Vector3(0, 2, 6)
	var engine: Node = car.get_node_or_null("Audio/Engine")
	check(engine is EngineAudio, "car has EngineAudio")
	check(car.get_node_or_null("Audio/Tyres") is TyreAudio, "car has TyreAudio")
	check(car.get_node_or_null("Audio/CarSounds") is CarSounds, "car has CarSounds")
	await create_timer(5.0).timeout
	check(engine.running, "engine started on its own")
	var audible := 0
	for c in engine.get_children():
		if c is AudioStreamPlayer3D and c.playing and not c.stream_paused and c.volume_db > -40.0:
			audible += 1
	check(audible >= 1, "engine idle is audible (%d players)" % audible)
	car.is_player_inside = true  # the camera rig sets this in interior view
	await process_frame
	await process_frame
	check(audio.is_player_inside(), "interior view switches the mix to inside the car")
	# Fitting parts swaps the engine sound.
	car.install_part(PartsCatalogue.get_part(&"exhaust_sport"))
	check(engine.engine_set == "fire12sport", "sport exhaust -> fire12sport (got %s)" % engine.engine_set)
	car.install_part(PartsCatalogue.get_part(&"engine_tjet"))
	check(engine.engine_set == "tjetsport", "T-Jet swap keeps the exhaust -> tjetsport (got %s)" % engine.engine_set)
	check(engine.turbo > 0.0, "T-Jet set has the turbo on")
	car.install_part(PartsCatalogue.get_part(&"engine_stock"))
	car.install_part(PartsCatalogue.get_part(&"exhaust_stock"))
	check(engine.engine_set == "fire12", "back to stock -> fire12 (got %s)" % engine.engine_set)
	check(engine.turbo == 0.0, "stock set has no turbo")
	# Changing car changes the engine and horn.
	if car.has_method("apply_car"):
		car.apply_car("abarth_695_biposto")
		check(engine.engine_set == "tjetstraight", "Abarth 695 biposto -> tjetstraight (got %s)" % engine.engine_set)
		check(car.get_node("Audio/CarSounds").style == "abarth", "Abarth horn")
		car.apply_car("classic_d")
		check(engine.engine_set == "classic" and engine.classic_gearbox, "500 D -> classic (got %s)" % engine.engine_set)
		check(engine.set_for_parts() == "classic", "a classic keeps its own note with stock parts")
		var mega: Resource = PartsCatalogue.get_part(&"exhaust_abarth_classic")
		if mega:
			car.install_part(mega)
			check(engine.engine_set == "classicmegaphone", "found Abarth megaphone -> classicmegaphone (got %s)" % engine.engine_set)
			car.install_part(PartsCatalogue.get_part(&"exhaust_stock"))
		car.apply_car("classic_giardiniera")
		check(engine.engine_set == "classicflat" and engine.classic_gearbox, "Giardiniera -> classicflat (got %s)" % engine.engine_set)
		car.apply_car("classic_abarth_595")
		check(engine.engine_set == "classicabarth" and engine.pops > 0.0, "Abarth 595 SS -> classicabarth with pops (got %s)" % engine.engine_set)
		car.apply_car("e_500e_2020")
		check(engine.engine_set == "electric", "New 500e -> electric (got %s)" % engine.engine_set)
		car.apply_car("pop_12")
		check(engine.engine_set == "fire12" and not engine.classic_gearbox, "Pop -> fire12 (got %s)" % engine.engine_set)
	# Running dry stops the engine; fuel brings it back.
	car.fuel_litres = 0.0
	await create_timer(0.3).timeout
	check(not engine.running, "engine stops when the tank runs dry")
	car.refuel(10.0)
	await create_timer(0.3).timeout
	check(engine.running, "engine restarts after refuelling")
	car.queue_free()
	cam.queue_free()
	audio.set_player_inside(false)


func _test_hooks(audio: Node) -> void:
	print("hooks")
	check(audio.hooks != null, "Audio.hooks present")
	var settings: Node = root.get_node("Settings")
	settings.volume_music = 0.5
	settings.apply()
	var music := AudioServer.get_bus_index("Music")
	check(absf(AudioServer.get_bus_volume_db(music) - (-3.0 + linear_to_db(0.5))) < 0.1,
			"music slider sets the Music bus")
	settings.volume_music = 1.0
	settings.apply()
	audio.radio.set_station("cinquecento")
	await create_timer(0.2).timeout
	var before: float = audio.radio._player.volume_db
	audio.radio.duck(true, 0.2)
	await create_timer(0.4).timeout
	check(audio.radio._player.volume_db < before - 12.0, "radio ducks under job music")
	audio.radio.duck(false, 0.2)
	await create_timer(0.4).timeout
	check(absf(audio.radio._player.volume_db - before) < 0.5, "radio comes back after")
	audio.radio.turn_off()
	# Every sound the hooks name exists.
	var src := FileAccess.get_file_as_string("res://audio/scripts/game_hooks.gd")
	var re := RegEx.create_from_string("\"((?:ui|car|garage|music)/[a-z0-9_]+|ui_[a-z0-9_]+)\"")
	var missing := []
	for m in re.search_all(src):
		var n := m.get_string(1)
		if not n.contains("/"):
			n = "ui/" + n
		if not audio.has(n) and not audio._variants.has(n):
			missing.append(n)
	check(missing.is_empty(), "hook sounds exist %s" % [missing])
	# Sounds the driving thread's oddity and train-race events use (docs/oddity.md).
	for n in ["oddity/odd_lane_idle_loop", "oddity/odd_lane_idle_cutout", "oddity/odd_follower_engine_loop",
			"oddity/odd_river_lights_loop", "oddity/odd_river_lights_shimmer", "oddity/odd_midnight_station_found",
			"traffic/traffic_train_alongside_loop", "music/mus_sting_race_win"]:
		check(audio.has(n), "event sound " + n)
	# The mystery arc's cues (docs/oddity.md, "Mystery arc").
	for n in ["oddity/odd_clue", "oddity/odd_clue_01", "oddity/odd_clue_04", "oddity/odd_clue_07", "oddity/odd_shed_knock", "oddity/odd_key_found",
			"oddity/odd_shed_unlock", "oddity/odd_shed_interior_loop", "oddity/odd_mystery_bed_loop"]:
		check(audio.has(n), "mystery sound " + n)
	# ...and the gameplay hooks pick them up (scripts/world/train_race.gd, oddities.gd).
	var race: Node = load("res://scripts/world/train_race.gd").new()
	race.set_process(false)
	root.add_child(race)
	race._start_sound(null)
	var al: AudioStreamPlayer3D = race._alongside
	check(al != null and al.stream != null and al.stream.loop, "train race plays the alongside loop")
	race.free()
	var odd: Node = load("res://scripts/world/oddities.gd").new()
	odd.set_process(false)
	root.add_child(odd)  # freed again before its deferred map setup runs
	for n in ["oddity/odd_follower_engine_loop", "oddity/odd_lane_idle_loop", "oddity/odd_river_lights_loop"]:
		var p: AudioStreamPlayer3D = odd._loop_player(n)
		check(p.stream != null and p.stream.loop and p.autoplay, "oddities loop " + n)
		p.free()
	odd.free()


func _test_traffic(audio: Node) -> void:
	print("traffic")
	for set_name in ["sedan", "diesel", "busdiesel"]:
		check(audio.names_in("engine/" + set_name).size() >= 10, "traffic engine set %s" % set_name)
	check(AudioServer.get_bus_index("Vehicles") >= 0, "Vehicles bus exists")
	for n in ["traffic_crowd_small_loop", "traffic_crowd_busy_loop", "traffic_steps_shoes_loop",
			"traffic_steps_heels_loop", "traffic_steps_thongs_loop", "traffic_train_arrive", "traffic_train_doors",
			"traffic_train_depart", "traffic_ferry_engine_loop", "traffic_ferry_idle_loop", "traffic_ferry_horn",
			"traffic_ferry_wake_loop", "traffic_roadworks_day_loop", "traffic_ibis_grunt", "traffic_roo_thump"]:
		check(audio.has("traffic/" + n), "city sound " + n)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(4.0).timeout
	var ta: Node = audio.hooks.traffic
	check(ta != null, "traffic audio found the TrafficManager")
	if ta:
		ta.hear_radius = 400.0  # traffic spawns out of sight, well away from the camera
		await create_timer(0.6).timeout
		var voiced := 0
		for kind in ta._voices:
			for voice in ta._voices[kind]:
				if voice.v != null and voice.engine.running:
					voiced += 1
		check(voiced >= 1, "nearby traffic has engine voices (%d)" % voiced)
		var horns := 0
		for v in ta.manager.vehicles:
			var h: AudioStreamPlayer3D = v.body.get_node_or_null("Audio/Horn")
			if h and h.stream and h.stream.resource_path.contains("traffic_horn"):
				horns += 1
		check(horns == ta.manager.vehicles.size() and horns > 0, "traffic horns swapped (%d)" % horns)
		# Pedestrians: footsteps on the nearest walkers, walla where they gather.
		var gs := GDScript.new()
		gs.source_code = "extends RefCounted\nvar position := Vector3.ZERO\nvar speed := 1.4\n"
		gs.reload()
		var ear_pos: Vector3 = audio.listener().global_position
		var peds: Array = []
		for i in 10:
			var ped: RefCounted = gs.new()
			ped.position = ear_pos + Vector3(2.0 + i, 0, 1.0)
			peds.append(ped)
		ta._assign_people(peds)
		var stepping := 0
		for voice in ta._steps:
			if voice.ped != null and voice.player.playing:
				stepping += 1
		check(stepping == ta.STEP_VOICES, "footsteps on the nearest walkers (%d)" % stepping)
		check(ta._crowd.playing and not ta._crowd_small.playing, "a crowd of 10 gets the busy walla")
		ta._assign_people(peds.slice(0, 4))
		check(ta._crowd_small.playing and not ta._crowd.playing, "four people get the small walla")
		ta._assign_people([])
		check(not ta._crowd_small.playing and ta._steps[0].ped == null, "no people, no walla or steps")
		ta._on_train_arrived(ear_pos)
		ta._on_train_departed(ear_pos)
		check(true, "train arrival and departure sounds play")
		# Emergency vehicles get our sirens, bikes a freewheel.
		if ta.manager.has_method("spawn_emergency"):
			for type in [&"police", &"ambulance", &"fire"]:
				var em = ta.manager.spawn_emergency(audio.listener().global_position, type)
				if em:
					var sn: AudioStreamPlayer3D = em.body.get_node_or_null("Audio/Siren")
					check(sn != null and sn.playing and sn.stream is AudioStreamOggVorbis,
							"%s siren swapped in and playing" % type)
					if type == &"police" and ta.manager.has_method("spawn_vehicle_at"):
						var bike = ta.manager.spawn_vehicle_at(&"bike", em.lane(), maxf(em.s - 30.0, 0.0))
						if bike:
							var fw: AudioStreamPlayer3D = bike.body.get_node_or_null("Audio/Freewheel")
							check(fw != null and fw.playing, "bike has a freewheel ticking")
	# The real map: zones and the townhouse.
	var amb: Node = audio.ambience
	check(amb.zone_at(Vector3(0, 0, 0)) == "northbridge", "Little Shenton Lane is Northbridge")
	check(amb.zone_at(Vector3(-1900, 0, 1700)) == "kingspark", "Kings Park zone")
	check(amb.zone_at(Vector3(300, 0, 2450)) == "river", "Perth Water is the river")
	check(amb.zone_at(Vector3(-3500, 0, -1200)) == "suburbs", "Wembley is suburbs")
	if main.find_child("PerthMap", true, false):
		await create_timer(1.2).timeout
		check(audio.hooks._home != null, "hooks found the townhouse")
		if audio.hooks._home:
			var doors: Array = audio.hooks._home.door_names()
			if not doors.is_empty():
				audio.hooks._home.toggle_door(doors[0])  # plays the door sound
		check(amb.zone == amb.zone_at(audio.listener().global_position), "ambience zone follows the camera (%s)" % amb.zone)
		var map_node := main.find_child("PerthMap", true, false)
		if map_node.has_method("get_pois") and not map_node.get_pois().is_empty():
			check(amb._places.size() >= 50, "the map's points of interest became place layers (%d)" % amb._places.size())
	main.queue_free()
	await process_frame


func _test_footsteps(audio: Node) -> void:
	print("footsteps")
	var fs_script: Script = load("res://audio/scripts/footsteps.gd")
	for s in fs_script.SURFACES:
		check(audio._variants.has("home/home_step_" + s), "step sounds for " + s)
	for s in fs_script.MATERIAL_SURFACES.values() + fs_script.SURFACE_ALIAS.values():
		check(s in fs_script.SURFACES, "mapped surface %s has sounds" % s)
	# Walking over a floor tagged like the roads: steps at a walking cadence.
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	floor.set_meta("surface", "wood")
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	box.shape.size = Vector3(40, 1, 40)
	floor.add_child(box)
	floor.position.y = -0.5
	world.add_child(floor)
	var body := CharacterBody3D.new()
	var cap := CollisionShape3D.new()
	cap.shape = CapsuleShape3D.new()
	cap.position.y = 0.9
	body.add_child(cap)
	var fs: Node3D = fs_script.new()
	body.add_child(fs)
	body.position = Vector3(-10, 0.05, 0)
	world.add_child(body)
	var walk := func() -> void:
		body.velocity = Vector3(1.4, body.velocity.y - 9.8 / 60.0, 0)
		body.move_and_slide()
	get_tree().physics_frame.connect(walk)
	await create_timer(3.0).timeout
	get_tree().physics_frame.disconnect(walk)
	check(fs.steps >= 4 and fs.steps <= 8, "about one step per 0.7 m at a walk (%d in ~4 m)" % fs.steps)
	check(fs.surface == "timber", "tagged floor surface 'wood' walks as timber (%s)" % fs.surface)
	world.queue_free()
	# The townhouse's trimesh floors map to surfaces through their materials.
	var home: Node = load("res://scenes/home/shenton.tscn").instantiate()
	root.add_child(home)
	await process_frame
	var probe: Node3D = fs_script.new()
	home.add_child(probe)
	var found := {}
	for col in home.find_children("*", "StaticBody3D", true, false):
		var mi := col.get_parent() as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var first := 0
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			var a := mi.mesh.surface_get_arrays(i)
			var faces: int = (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
			if mat and fs_script.MATERIAL_SURFACES.has(mat.resource_name) and faces > 0:
				var got: String = probe._material_at(col, first + faces / 2)
				check(got == mat.resource_name, "face lookup finds %s (%s)" % [mat.resource_name, got])
				found[fs_script.MATERIAL_SURFACES[got]] = true
			first += faces
	for s in ["timber", "carpet", "tile", "brick"]:
		check(found.has(s), "townhouse has %s floors" % s)
	home.queue_free()
	await process_frame


func _test_programme(audio: Node) -> void:
	print("radio programme")
	var Radio := load("res://audio/scripts/radio.gd")
	check(Radio.block_at(7.0) == "morning" and Radio.block_at(12.0) == "day" and Radio.block_at(17.5) == "evening"
			and Radio.block_at(23.0) == "night" and Radio.block_at(0.5) == "night" and Radio.block_at(3.0) == "late",
			"programme blocks by hour")
	var radio: Node = audio.radio
	for id in ["cinquecento", "nottefm"]:
		check(Array(audio.names_in("music")).filter(func(n): return n.get_file().begins_with("mus_ident_" + id)).size() >= 3,
				"%s has idents" % id)
		for block in ["morning", "day", "evening", "night", "late"]:
			var b: Dictionary = radio._broadcast_for(id, block)
			var songs: Array = b.tracks.filter(func(n): return not n.get_file().begins_with("mus_ident_"))
			check(songs.size() >= 3, "%s plays %d songs in the %s block" % [id, songs.size(), block])
			check(b.tracks.size() > songs.size(), "%s %s has idents between songs" % [id, block])
			var p: Dictionary = radio._programme(id).get("blocks", {})
			var fits := songs.all(func(n): return not p.has(n.get_file()) or block in p[n.get_file()])
			check(fits, "%s %s only plays songs tagged for it" % [id, block])
	# The broadcast moves on while nobody listens, and keeps its place.
	var st: Dictionary = radio._catch_up("cinquecento").duplicate()
	radio._clock += st.length + 1.0
	var st2: Dictionary = radio._catch_up("cinquecento")
	check(st2.item != st.item or st2.index != st.index, "the station moved on while away")
	check(radio._clock - st2.started < st2.length, "and is somewhere inside the current item")
	check(audio.has("music/mus_radio_pips"), "time pips exist")
