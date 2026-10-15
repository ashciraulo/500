extends SceneTree
## Listens to a new game's first minute or so: the game as New game builds
## it (in the car in the carport, 08:30, clear), and logs what is playing
## once a second (each player's sound, bus, level and distance) and how loud
## each Ambient bus is, and records what you hear (Master) to a .wav.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/ambient_listen.gd -- --no-save secs=60 wav=/tmp/listen.wav log=/tmp/listen.txt
##
## A tool for judging the mix by ear and eye; not a CI suite.

var _main: Node
var _audio: Node
var _secs := 60.0
var _wav := ""
var _log := ""
var _hour := 8.5
var _lines: PackedStringArray = []
var _rec: AudioEffectRecord
var _started := false


func _process(_delta: float) -> bool:
	if _main == null:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("secs="):
				_secs = float(arg.trim_prefix("secs="))
			elif arg.begins_with("wav="):
				_wav = arg.trim_prefix("wav=")
			elif arg.begins_with("log="):
				_log = arg.trim_prefix("log=")
			elif arg.begins_with("hour="):
				_hour = float(arg.trim_prefix("hour="))
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_audio = root.get_node("Audio")
		if _hour != 8.5:
			root.get_node("GameClock").set_time(_hour)
		_run.call_deferred()
	return false


func _run() -> void:
	# Real seconds: audio runs in real time whatever the frame rate.
	var t0 := Time.get_ticks_msec()
	_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, _rec)
	_rec.set_recording_active(true)
	var next := 0.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < _secs:
		var now := (Time.get_ticks_msec() - t0) / 1000.0
		if now >= next:
			_snapshot(now)
			next += 1.0
		await process_frame
	_rec.set_recording_active(false)
	var clip := _rec.get_recording()
	if clip and _wav != "":
		clip.save_to_wav(_wav)
	var text := "\n".join(_lines)
	if _log != "":
		var f := FileAccess.open(_log, FileAccess.WRITE)
		f.store_string(text)
	else:
		print(text)
	_audio.quit_game(0)


func _bus_db(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return -80.0
	return maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))


func _snapshot(t: float) -> void:
	var ear: Node3D = _audio.listener()
	var clock := root.get_node("GameClock")
	var line := "t=%5.1f %05.2fh zone=%s" % [t, clock.time_of_day, _audio.ambience.zone]
	for bus in ["Master", "Ambience", "Weather", "Outdoors", "Vehicles", "SFX", "Engine"]:
		line += " %s=%.0f" % [bus, _bus_db(bus)]
	_lines.append(line)
	for p in root.find_children("*", "AudioStreamPlayer", true, false):
		var a := p as AudioStreamPlayer
		if a.playing and a.stream:
			_lines.append("    2D %-12s %6.1f dB  %s" % [a.bus, a.volume_db, _name(a)])
	for p in root.find_children("*", "AudioStreamPlayer3D", true, false):
		var a := p as AudioStreamPlayer3D
		if a.playing and a.stream:
			var d := a.global_position.distance_to(ear.global_position) if ear else -1.0
			_lines.append("    3D %-12s %6.1f dB  %5.0f m  u%.1f r%.0f  %s" % [a.bus, a.volume_db, d, a.unit_size,
					a.max_distance, _name(a)])


## The sound's file, or where the player sits when its stream was built in code.
func _name(a: Node) -> String:
	var path: String = a.stream.resource_path.get_file()
	if path != "":
		return path
	for id in _audio.ambience._layers:
		if _audio.ambience._layers[id] == a:
			return "layer:" + id
	for type in _audio.ambience._place_players:
		if _audio.ambience._place_players[type] == a:
			return "place:" + type
	return "%s/%s" % [a.get_parent().name, a.name]
