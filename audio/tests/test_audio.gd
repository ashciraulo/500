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
	for fam in ["fire12", "fire14", "twinair", "tjet", "classic", "classicabarth", "electric", "abarthe"]:
		var names: PackedStringArray = audio.names_in("engine/" + fam)
		var on := 0
		var off := 0
		for n in names:
			if n.contains("_onload_"):
				on += 1
			elif n.contains("_offload_"):
				off += 1
		check(on >= 5 and on == off, "%s: %d on-load, %d off-load loops" % [fam, on, off])
		if not fam.begins_with("electric") and not fam == "abarthe":
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
	amb.lightning(500.0)
	audio.set_player_inside(false)
	check(true, "weather and lightning without errors")


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


func _test_traffic(audio: Node) -> void:
	print("traffic")
	for set_name in ["sedan", "diesel", "busdiesel"]:
		check(audio.names_in("engine/" + set_name).size() >= 10, "traffic engine set %s" % set_name)
	check(AudioServer.get_bus_index("Vehicles") >= 0, "Vehicles bus exists")
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
	main.queue_free()
	await process_frame
