extends Node
## The car radio: Audio.radio.
##
## Stations:
##   Radio Cinquecento  daytime Italian lounge (res://audio/music/mus_cinquecento_*)
##   Notte FM           night lo-fi ambient    (mus_nottefm_*)
##   My Music           the player's own files from the Music folder
##   (after midnight a fourth, unlisted frequency carries the midnight station)
## plus Off.
##
## The built-in stations behave like real broadcasts: they keep "playing"
## while you're tuned elsewhere, so tuning back lands mid-song. During storms
## the storm re-arrangements (mus_storm_*) join the rotation.
##
## My Music: the game creates user://Music (next to the saves; see
## music_folder_path()). Players drop MP3, OGG or WAV files in; each
## subfolder becomes a playlist, and "All music" plays everything. Files are
## read at runtime, so no import step. Track names come from the file's tags
## when present, otherwise from the file name ("Artist - Title.mp3").
## Songs come mastered at all sorts of levels (most far louder than the
## stations), so each one is levelled to the stations as it plays: the
## MyMusic bus measures it, and the level is kept for next time
## (user://my_music_levels.cfg), so a song heard once starts right.
##
## Controls for the dash / steering-wheel buttons:
##   next_station(), previous_station(), set_station(id), turn_off()
##   next_track(), previous_track(), toggle_shuffle(), next_playlist()
## Signals: station_changed, now_playing (for the dash display).

signal station_changed(station_id: String, display_name: String)
signal now_playing(station_id: String, title: String, artist: String)
signal my_music_scanned(track_count: int, playlists: PackedStringArray)

const MUSIC_DIR := "user://Music"
const AUDIO_EXT := ["mp3", "ogg", "wav"]
const MIDNIGHT_ID := "midnight"

var stations := [
	{"id": "cinquecento", "name": "Radio Cinquecento", "prefix": "mus_cinquecento_"},
	{"id": "nottefm", "name": "Notte FM", "prefix": "mus_nottefm_"},
	{"id": "mymusic", "name": "My Music", "prefix": ""},
]
var station_index := -1          # -1 = off
var shuffle := true
var storm := false               # set by the ambience manager from the weather
var after_midnight := false      # set by the ambience manager from the clock
var volume_db := 0.0

# My Music state
var playlists := {}              # playlist name -> Array of absolute file paths
var playlist_names := PackedStringArray()
var playlist := "All music"
var _order: Array = []
var _pos := -1

var _player: AudioStreamPlayer
var _static: AudioStreamPlayer
var _outside_trim := 0.0
var _duck_db := 0.0
var _duck_tween: Tween
var _clock := 0.0                # broadcast clock for the built-in stations
var _broadcast := {}             # station+block -> {"tracks": [...], "lengths": [...], "block": ...}
var _on_air := {}                # station id -> where its broadcast is: key, index, started, item, length
var _programmes := {}            # station id -> parsed programme_<id>.json
var _last_pips := -1
var _pips_playing := false
var _current_title := ""
var _current_artist := ""

## My Music levelling: what the songs measure on the MyMusic bus's meter
## (_measure(), about 1 dB over their LUFS) when they sit with the stations
## (whose songs are mastered to -16 LUFS), a first guess for a song not
## heard before (most are mastered about this much louder than that), how
## far a song may be turned up or down, and how long to listen before
## settling on a level.
const MY_MUSIC_TARGET_DB := -15.0
const MY_MUSIC_GUESS_DB := -7.0
const MY_MUSIC_TRIM_RANGE := Vector2(-20.0, 8.0)
const LEVEL_FIRST_S := 6.0
const LEVEL_SURE_S := 25.0
const LEVEL_FIRST_UP_DB := 3.0
const LEVEL_ENOUGH_S := 120.0    # listening longer than this changes nothing
const LEVELS_PATH := "user://my_music_levels.cfg"
const BLOCK_S := 0.4
var _mm_trim := 0.0              # dB on the current song
var _mm_trim_tween: Tween
var _mm_key := ""                # the current song's key in the levels file
var _mm_known := false           # its level came from the file
var _mm_settled := 0             # 0 guessing, 1 first level set, 2 sure
var _capture: AudioEffectCapture
var _blocks := PackedFloat32Array()   # mean square per BLOCK_S, the song's own (trim taken off)
var _block_sum := 0.0
var _block_n := 0
var _kw := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0])  # K-weighting filter state, left and right
## K-weighting at 48 kHz (BS.1770): the shelf, then the high-pass (b = 1, -2, 1).
const K_B1 := [1.53512485958697, -2.69169618940638, 1.19839281085285]
const K_A1 := [1.0, -1.69065929318241, 0.73248077421585]
const K_A2 := [1.0, -1.99004745483398, 0.99007225036621]
var _levels: ConfigFile


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Radio"
	add_child(_player)
	_player.finished.connect(_on_finished)
	_static = AudioStreamPlayer.new()
	_static.bus = "Radio"
	add_child(_static)
	var mm := AudioServer.get_bus_index("MyMusic")
	for e in (AudioServer.get_bus_effect_count(mm) if mm >= 0 else 0):
		if AudioServer.get_bus_effect(mm, e) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(mm, e)
	ensure_music_folder()
	var audio := get_parent()
	if audio and audio.has_method("radio_trim_db"):
		audio.player_inside_changed.connect(func(_inside: bool) -> void: _update_trim())
		audio.player_driving_changed.connect(func(_driving: bool) -> void: _update_trim())
		_outside_trim = audio.radio_trim_db()


## Where the player hears the radio from (in the car, at the wheel in the
## chase view, or outside): Audio.radio_trim_db().
func _update_trim() -> void:
	_outside_trim = get_parent().radio_trim_db()
	_apply_volume()


func _process(delta: float) -> void:
	_clock += delta
	if _capture:
		if _player.playing and _player.bus == &"MyMusic" and _blocks.size() * BLOCK_S < LEVEL_ENOUGH_S:
			_measure()
		else:
			_capture.clear_buffer()


# ---------------------------------------------------------------------------
# Tuning
# ---------------------------------------------------------------------------

func is_on() -> bool:
	return station_index >= 0


func current_station_id() -> String:
	if station_index < 0:
		return ""
	if station_index >= stations.size():
		return MIDNIGHT_ID
	return stations[station_index].id


func _dial() -> Array:
	## Stations on the dial right now (the midnight station only after midnight).
	var dial := []
	for i in stations.size():
		dial.append(i)
	if after_midnight and Audio.has("oddity/odd_midnight_station"):
		dial.append(stations.size())
	return dial


func next_station() -> void:
	_step_station(1)


func previous_station() -> void:
	_step_station(-1)


func _step_station(dir: int) -> void:
	var dial := _dial()
	var at := dial.find(station_index)
	at = 0 if at == -1 else posmod(at + dir, dial.size())
	_tune(dial[at])


func set_station(id: String) -> void:
	for i in stations.size():
		if stations[i].id == id:
			_tune(i)
			return
	if id == MIDNIGHT_ID:
		_tune(stations.size())


func turn_off() -> void:
	if station_index < 0:
		return
	_keep_level()
	station_index = -1
	_player.stop()
	Audio.play_2d("car/car_radio_off", "Cabin")
	station_changed.emit("", "Off")


func toggle_power() -> void:
	if is_on():
		turn_off()
	else:
		Audio.play_2d("car/car_radio_on", "Cabin")
		_tune(0, false)


func _tune(index: int, with_static := true) -> void:
	_keep_level()
	station_index = index
	_player.stop()
	_pips_playing = false
	if with_static:
		Audio.play_2d("car/car_radio_station_change", "Cabin")
		var s := Audio.stream("car/car_radio_tuning_sweep")
		if s:
			_static.stream = s
			_static.volume_db = volume_db - 6.0 + _outside_trim + _duck_db
			_static.play()
	var id := current_station_id()
	var display: String = "" if id == MIDNIGHT_ID else stations[index].name
	if id == MIDNIGHT_ID:
		display = "%.1f" % randf_range(87.6, 88.1)  # just a frequency, no name
	station_changed.emit(id, display)
	# Let the static sweep cover the gap, then bring the station in.
	get_tree().create_timer(0.35 if with_static else 0.0).timeout.connect(func() -> void:
		if current_station_id() == id:
			_start_station())


func _start_station() -> void:
	var id := current_station_id()
	if id == "mymusic":
		scan_my_music()
		if _order.is_empty():
			_current_title = "Music folder is empty"
			_current_artist = ""
			now_playing.emit(id, _current_title, "")
			return
		_play_my_music(maxi(_pos, 0))
	elif id == MIDNIGHT_ID:
		_player.bus = &"Radio"
		_player.stream = Audio.variant("oddity/odd_midnight_station")
		_player.volume_db = _level()
		_player.play()
		now_playing.emit(id, "", "")
	else:
		_play_broadcast(id)


## Dip the radio under job music (on) or bring it back (off).
func duck(on: bool, fade_s := 2.0) -> void:
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck, _duck_db, -18.0 if on else 0.0, fade_s)


func _set_duck(db: float) -> void:
	_duck_db = db
	_apply_volume()


func _apply_volume() -> void:
	if _player:
		_player.volume_db = _level()


## The radio player's level: the radio's own, where you hear it from, the
## duck under job music and, on My Music, the song's levelling.
func _level() -> float:
	return volume_db + _outside_trim + _duck_db + (_mm_trim if _player.bus == &"MyMusic" else 0.0)


# ---------------------------------------------------------------------------
# Built-in stations: a continuous broadcast you tune into
# ---------------------------------------------------------------------------

## Time-of-day programme blocks (game hours). Each station's
## audio/music/programme_<id>.json tags its tracks with the blocks they suit.
const BLOCKS := [["late", 1.0], ["morning", 5.0], ["day", 10.0], ["evening", 16.0], ["night", 20.0]]
## An ident between songs every this many songs.
const IDENT_EVERY := 2
## Game hours with the time pips before the next song.
const PIP_HOURS := [6, 12, 18]


static func block_at(hours: float) -> String:
	var h := fposmod(hours, 24.0)
	var block: String = BLOCKS[BLOCKS.size() - 1][0]  # 20:00-01:00 wraps
	for b in BLOCKS:
		if h >= float(b[1]):
			block = b[0]
	return block


func _hours() -> float:
	var clock := get_node_or_null("/root/GameClock")
	return float(clock.get("time_of_day")) if clock else 12.0


func _programme(id: String) -> Dictionary:
	if not _programmes.has(id):
		var p := {}
		var path := "res://audio/music/programme_%s.json" % id
		if FileAccess.file_exists(path):
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				p = data
		_programmes[id] = p
	return _programmes[id]


## The station's running order for this block: its tracks that suit the
## block, in a fixed shuffled order, with an ident after every IDENT_EVERY
## songs (and the storm arrangements mixed in during storms).
func _broadcast_for(id: String, block := "") -> Dictionary:
	if block == "":
		block = block_at(_hours())
	var key := "%s_%s%s" % [id, block, "_storm" if storm else ""]
	if _broadcast.has(key):
		return _broadcast[key]
	var prefix: String = ""
	for s in stations:
		if s.id == id:
			prefix = s.prefix
	var blocks: Dictionary = _programme(id).get("blocks", {})
	var all := []
	var tracks := []
	for n in Audio.names_in("music"):
		var f := n.get_file()
		if f.begins_with(prefix):
			all.append(n)
			# Untagged tracks play in every block.
			if not blocks.has(f) or block in blocks[f]:
				tracks.append(n)
	if tracks.size() < 3:
		tracks = all
	if storm:
		for n in Audio.names_in("music"):
			if n.get_file().begins_with("mus_storm_"):
				tracks.append(n)
	# A fixed shuffled running order per station and block, like a playlist on air.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for i in range(tracks.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = tracks[i]
		tracks[i] = tracks[j]
		tracks[j] = t
	var idents := []
	for n in Audio.names_in("music"):
		if n.get_file().begins_with("mus_ident_" + id):
			idents.append(n)
	var items := []
	for i in tracks.size():
		items.append(tracks[i])
		if not idents.is_empty() and (i + 1) % IDENT_EVERY == 0:
			items.append(idents[(i / IDENT_EVERY + rng.randi()) % idents.size()])
	var lengths := []
	for t in items:
		var st := Audio.stream(t)
		lengths.append(st.get_length() if st else 0.0)
	var b := {"tracks": items, "lengths": lengths, "block": block}
	_broadcast[key] = b
	return b


## Tune into the broadcast where it is now. Each station keeps its own place:
## songs carry on while you listen elsewhere, so coming back lands mid-song,
## and when the programme block changes the station moves to the new block's
## running order after the song that was on.
func _play_broadcast(id: String) -> void:
	var st := _catch_up(id)
	if st.is_empty():
		return
	_player.bus = &"Radio"
	_player.stream = Audio.stream(st.item)
	_player.volume_db = _level()
	_player.play(clampf(_clock - st.started, 0.0, maxf(st.length - 0.05, 0.0)))
	_announce(id, st.item)


## Where the station's broadcast is at _clock: {block, index, item, started, length}.
func _catch_up(id: String) -> Dictionary:
	var b := _broadcast_for(id)
	var n: int = b.tracks.size()
	if n == 0:
		return {}
	var st: Dictionary = _on_air.get(id, {})
	if st.is_empty():
		# First listen: somewhere into the running order, different per station.
		var total := 0.0
		for l in b.lengths:
			total += l
		var t := fmod(float(absi(hash(id)) % 997), maxf(total, 1.0))
		var i := 0
		while i < n - 1 and t >= b.lengths[i]:
			t -= b.lengths[i]
			i += 1
		st = {"block": b.block, "index": i, "item": b.tracks[i], "started": _clock - t,
				"length": maxf(b.lengths[i], 0.5)}
	var guard := 0
	while _clock - st.started >= st.length and guard < 256:
		guard += 1
		st.started += st.length
		if st.block != b.block:
			st.block = b.block
			st.index = 0
		else:
			st.index = (int(st.index) + 1) % n
		st.index = int(st.index) % n
		st.item = b.tracks[st.index]
		st.length = maxf(b.lengths[st.index], 0.5)
	_on_air[id] = st
	return st


func _announce(id: String, track_name: String) -> void:
	var file := track_name.get_file()
	if file.begins_with("mus_ident_") or file.begins_with("mus_radio_pips"):
		# Between songs: the dash shows the station name.
		_current_title = ""
		for s in stations:
			if s.id == id:
				_current_title = s.name
	else:
		# Built-in tracks are named mus_<station>_NN; show their title if they have one.
		var titles: Dictionary = _programme(id).get("titles", {})
		_current_title = titles.get(file, file.trim_prefix("mus_").replace("_", " ").capitalize())
	_current_artist = ""
	now_playing.emit(id, _current_title, _current_artist)


func _on_finished() -> void:
	var id := current_station_id()
	if id == "mymusic":
		next_track()
	elif id == MIDNIGHT_ID:
		_start_station()
	elif id != "":
		var st: Dictionary = _on_air.get(id, {})
		if _pips_playing:
			# The next song starts after the pips.
			_pips_playing = false
			if not st.is_empty():
				st.started = _clock
		elif not st.is_empty():
			st.started = minf(st.started, _clock - st.length)  # this song is over
			_catch_up(id)
			# The time signal on the hour, before the next song.
			var hour := int(_hours())
			if hour in PIP_HOURS and hour != _last_pips and Audio.has("music/mus_radio_pips"):
				_last_pips = hour
				_pips_playing = true
				_player.stream = Audio.stream("music/mus_radio_pips")
				_player.volume_db = _level()
				_player.play()
				_announce(id, "mus_radio_pips")
				return
		_play_broadcast(id)


# ---------------------------------------------------------------------------
# My Music
# ---------------------------------------------------------------------------

static func music_folder_path() -> String:
	return ProjectSettings.globalize_path(MUSIC_DIR)


func ensure_music_folder() -> void:
	if not DirAccess.dir_exists_absolute(MUSIC_DIR):
		DirAccess.make_dir_recursive_absolute(MUSIC_DIR)
		var f := FileAccess.open(MUSIC_DIR.path_join("README.txt"), FileAccess.WRITE)
		if f:
			f.store_string("Put your own music here: MP3, OGG or WAV files.\n"
					+ "Each folder you make in here becomes a playlist on the car radio's My Music station.\n"
					+ "Tune to My Music in the car; new files are picked up the next time you tune in.\n")


## Settings menu "Open folder" button.
func open_music_folder() -> void:
	ensure_music_folder()
	OS.shell_open(music_folder_path())


## Re-read the Music folder. Keeps the current track if it's still there.
func scan_my_music() -> void:
	var current: String = _order[_pos] if _pos >= 0 and _pos < _order.size() else ""
	playlists = {}
	var all: Array = []
	_collect(MUSIC_DIR, all)
	all.sort()
	playlists["All music"] = all
	var d := DirAccess.open(MUSIC_DIR)
	if d:
		for sub in d.get_directories():
			var files: Array = []
			_collect(MUSIC_DIR.path_join(sub), files)
			if not files.is_empty():
				files.sort()
				playlists[sub] = files
	playlist_names = PackedStringArray(playlists.keys())
	if not playlists.has(playlist):
		playlist = "All music"
	_build_order()
	if current != "":
		var at := _order.find(current)
		if at >= 0:
			_pos = at
	my_music_scanned.emit(all.size(), playlist_names)


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension().to_lower() in AUDIO_EXT:
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)


func _build_order() -> void:
	_order = (playlists.get(playlist, []) as Array).duplicate()
	if shuffle:
		_order.shuffle()
	_pos = 0 if not _order.is_empty() else -1


func next_playlist() -> void:
	if playlist_names.is_empty():
		scan_my_music()
	if playlist_names.is_empty():
		return
	var i := playlist_names.find(playlist)
	playlist = playlist_names[posmod(i + 1, playlist_names.size())]
	_build_order()
	if current_station_id() == "mymusic" and not _order.is_empty():
		_play_my_music(0)


func toggle_shuffle() -> void:
	shuffle = not shuffle
	var current: String = _order[_pos] if _pos >= 0 and _pos < _order.size() else ""
	_build_order()
	if current != "" and _order.has(current):
		# Keep playing what's on; the new order continues after it.
		_order.erase(current)
		_order.insert(0, current)
		_pos = 0


func next_track() -> void:
	if current_station_id() != "mymusic" or _order.is_empty():
		return
	_play_my_music((_pos + 1) % _order.size())


func previous_track() -> void:
	if current_station_id() != "mymusic" or _order.is_empty():
		return
	# Like a CD player: restart the song unless it only just began.
	if _player.playing and _player.get_playback_position() > 4.0:
		_player.play(0.0)
		return
	_play_my_music(posmod(_pos - 1, _order.size()))


func _play_my_music(index: int, tries := 0) -> void:
	if _order.is_empty() or tries >= _order.size():
		return
	_pos = index
	var path: String = _order[_pos]
	var s := load_music_file(path)
	if s == null:
		push_warning("Radio: couldn't play %s, skipping" % path)
		_play_my_music((_pos + 1) % _order.size(), tries + 1)
		return
	_keep_level()
	_player.bus = &"MyMusic"
	_player.stream = s
	_start_level(path)
	_player.volume_db = _level()
	_player.play()
	var tags := read_tags(path)
	_current_title = tags.title
	_current_artist = tags.artist
	now_playing.emit("mymusic", _current_title, _current_artist)


# ---------------------------------------------------------------------------
# My Music levelling
# ---------------------------------------------------------------------------

func _start_level(path: String) -> void:
	if _levels == null:
		_levels = ConfigFile.new()
		_levels.load(LEVELS_PATH)
	_mm_key = "%s_%d" % [path.sha1_text().left(16), _file_size(path)]
	_mm_known = _levels.has_section_key("levels", _mm_key)
	_set_trim(MY_MUSIC_TARGET_DB - float(_levels.get_value("levels", _mm_key)) if _mm_known else MY_MUSIC_GUESS_DB, 0.0)
	_mm_settled = 2 if _mm_known else 0
	_blocks.clear()
	_block_sum = 0.0
	_block_n = 0
	if _capture:
		_capture.clear_buffer()


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0


## Reads what the MyMusic bus heard since last frame: K-weighted, the way a
## loudness meter hears (ITU-R BS.1770: a lift above 2 kHz and the deep bass
## taken out), mean square per BLOCK_S, with the player's level at the time
## taken back off, so a block says how loud the song itself is there.
func _measure() -> void:
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var buf := _capture.get_buffer(frames)
	var block := int(BLOCK_S * AudioServer.get_mix_rate())
	var off := db_to_linear(-2.0 * _player.volume_db) if _player.volume_db > -60.0 else 0.0
	var k := _kw
	for i in buf.size():
		var e := 0.0
		for c in 2:
			var x: float = buf[i].x if c == 0 else buf[i].y
			var o := c * 4
			# shelf
			var y1: float = K_B1[0] * x + k[o]
			k[o] = K_B1[1] * x - K_A1[1] * y1 + k[o + 1]
			k[o + 1] = K_B1[2] * x - K_A1[2] * y1
			# high-pass
			var y2: float = y1 + k[o + 2]
			k[o + 2] = -2.0 * y1 - K_A2[1] * y2 + k[o + 3]
			k[o + 3] = y1 - K_A2[2] * y2
			e += y2 * y2
		_block_sum += e
		_block_n += 1
		if _block_n >= block:
			if off > 0.0:
				_blocks.append(_block_sum / _block_n * off)
			_block_sum = 0.0
			_block_n = 0
	_kw = k
	var heard := _blocks.size() * BLOCK_S
	if _mm_settled == 0 and heard >= LEVEL_FIRST_S:
		# A song's first seconds are often its quiet intro, so this first
		# look only turns it up a little; down (a loud master) it goes now.
		_mm_settled = 1
		_set_trim(minf(MY_MUSIC_TARGET_DB - song_level(_blocks), _mm_trim + LEVEL_FIRST_UP_DB), 2.0)
	elif _mm_settled == 1 and heard >= LEVEL_SURE_S:
		_mm_settled = 2
		var want := MY_MUSIC_TARGET_DB - song_level(_blocks)
		if absf(want - _mm_trim) > 1.5:
			_set_trim(want, 3.0)


## How loud a song is from its blocks (dB): the mean of the blocks that
## aren't near-silence or well under the rest (the quiet bits of a song
## shouldn't make it louder), like a loudness meter's gating.
static func song_level(blocks: PackedFloat32Array) -> float:
	var sum := 0.0
	var n := 0
	for e in blocks:
		if e > 1e-7:  # -70 dB
			sum += e
			n += 1
	if n == 0:
		return MY_MUSIC_TARGET_DB - MY_MUSIC_GUESS_DB
	var gate := sum / n * 0.1  # 10 dB under the mean
	sum = 0.0
	n = 0
	for e in blocks:
		if e > maxf(gate, 1e-7):
			sum += e
			n += 1
	return 10.0 * log(sum / maxf(n, 1)) / log(10.0) if n > 0 else MY_MUSIC_TARGET_DB - MY_MUSIC_GUESS_DB


func _set_trim(db: float, fade_s: float) -> void:
	db = clampf(db, MY_MUSIC_TRIM_RANGE.x, MY_MUSIC_TRIM_RANGE.y)
	if _mm_trim_tween:
		_mm_trim_tween.kill()
	if fade_s <= 0.0:
		_mm_trim = db
		_apply_volume()
		return
	_mm_trim_tween = create_tween()
	_mm_trim_tween.tween_method(func(v: float) -> void:
		_mm_trim = v
		_apply_volume(), _mm_trim, db, fade_s)


## Keeps the level of the song that was playing, once enough of it was
## heard (the whole song counts, so it's better than the first guess).
func _keep_level() -> void:
	if _mm_key == "" or _blocks.size() * BLOCK_S < LEVEL_SURE_S:
		return
	var level := song_level(_blocks)
	if _mm_known:
		level = lerpf(float(_levels.get_value("levels", _mm_key, level)), level, 0.5)
	_levels.set_value("levels", _mm_key, snappedf(level, 0.1))
	_levels.save(LEVELS_PATH)
	_blocks.clear()


## Load an MP3, OGG or WAV from anywhere on disk. Returns null if unreadable.
static func load_music_file(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var s: AudioStream = null
	match path.get_extension().to_lower():
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			s = mp3
		"ogg":
			s = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			s = _load_wav(path)
	if s == null or s.get_length() <= 0.0:
		return null
	return s


static func _load_wav(path: String) -> AudioStreamWAV:
	# Godot 4.4+ reads any WAV natively; 4.3 needs this little RIFF reader,
	# which handles 8- and 16-bit PCM (by far the most common).
	var probe := AudioStreamWAV.new()
	if probe.has_method("load_from_file"):
		return probe.call("load_from_file", path)
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or b.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var fmt := -1
	var channels := 0
	var rate := 0
	var bits := 0
	var i := 12
	while i + 8 <= b.size():
		var id := b.slice(i, i + 4).get_string_from_ascii()
		var size := b.decode_u32(i + 4)
		var body := i + 8
		if id == "fmt ":
			fmt = b.decode_u16(body)
			channels = b.decode_u16(body + 2)
			rate = b.decode_u32(body + 4)
			bits = b.decode_u16(body + 14)
		elif id == "data" and fmt != -1:
			if fmt != 1 or bits not in [8, 16] or channels not in [1, 2]:
				push_warning("Radio: %s is %d-bit; on this Godot version only 8/16-bit WAVs play. Convert it, or use MP3/OGG." % [path.get_file(), bits])
				return null
			var w := AudioStreamWAV.new()
			w.mix_rate = rate
			w.stereo = channels == 2
			var pcm := b.slice(body, mini(body + size, b.size()))
			if bits == 8:
				# WAV 8-bit is unsigned; Godot expects signed.
				for k in pcm.size():
					pcm[k] = (pcm[k] + 128) & 0xff
				w.format = AudioStreamWAV.FORMAT_8_BITS
			else:
				w.format = AudioStreamWAV.FORMAT_16_BITS
			w.data = pcm
			return w
		i = body + size + (size & 1)
	return null


# ---------------------------------------------------------------------------
# Track names from tags (ID3v2 for MP3, Vorbis comments for OGG, RIFF INFO
# for WAV), falling back to "Artist - Title" in the file name.
# ---------------------------------------------------------------------------

static func read_tags(path: String) -> Dictionary:
	var tags := {"title": "", "artist": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var head := f.get_buffer(mini(f.get_length(), 262144))
		match path.get_extension().to_lower():
			"mp3":
				_id3(head, tags)
			"ogg":
				_vorbis_comments(head, tags)
			"wav":
				_riff_info(head, tags)
	if tags.title == "":
		var stem := path.get_file().get_basename()
		var parts := stem.split(" - ", false, 1)
		if parts.size() == 2:
			if tags.artist == "":
				tags.artist = parts[0].strip_edges()
			tags.title = parts[1].strip_edges()
		else:
			tags.title = stem.replace("_", " ").strip_edges()
	return tags


static func _id3(b: PackedByteArray, tags: Dictionary) -> void:
	if b.size() < 10 or b.slice(0, 3).get_string_from_ascii() != "ID3":
		return
	var ver := b[3]
	var size := (b[6] << 21) | (b[7] << 14) | (b[8] << 7) | b[9]
	var i := 10
	var end := mini(10 + size, b.size())
	while i + 10 <= end:
		var id := b.slice(i, i + 4).get_string_from_ascii()
		if id == "" or b[i] == 0:
			break
		var fsize := 0
		if ver >= 4:
			fsize = (b[i + 4] << 21) | (b[i + 5] << 14) | (b[i + 6] << 7) | b[i + 7]
		else:
			fsize = (b[i + 4] << 24) | (b[i + 5] << 16) | (b[i + 6] << 8) | b[i + 7]
		if fsize <= 0 or i + 10 + fsize > end:
			break
		if id == "TIT2" or id == "TPE1":
			var text := _id3_text(b.slice(i + 10, i + 10 + fsize))
			if id == "TIT2":
				tags.title = text
			else:
				tags.artist = text
		i += 10 + fsize


static func _id3_text(frame: PackedByteArray) -> String:
	if frame.is_empty():
		return ""
	var enc := frame[0]
	var data := frame.slice(1)
	var s := ""
	match enc:
		1:
			s = data.get_string_from_utf16()  # with BOM
		2:
			# UTF-16BE without BOM: swap to LE for Godot's decoder.
			var sw := PackedByteArray()
			for k in range(0, data.size() - 1, 2):
				sw.append(data[k + 1])
				sw.append(data[k])
			s = sw.get_string_from_utf16()
		3:
			s = data.get_string_from_utf8()
		_:
			s = data.get_string_from_ascii()
	return s.strip_edges().replace(char(0), "")


static func _vorbis_comments(b: PackedByteArray, tags: Dictionary) -> void:
	# The comment header is the second Vorbis packet: "\x03vorbis", vendor
	# string, then a count of "KEY=value" strings, all little-endian lengths.
	var marker := PackedByteArray([3, 118, 111, 114, 98, 105, 115])
	var at := _find(b, marker)
	if at < 0:
		return
	var i := at + 7
	if i + 4 > b.size():
		return
	var vendor_len := b.decode_u32(i)
	i += 4 + vendor_len
	if i + 4 > b.size():
		return
	var count := b.decode_u32(i)
	i += 4
	for _k in mini(count, 200):
		if i + 4 > b.size():
			return
		var l := b.decode_u32(i)
		i += 4
		if l <= 0 or i + l > b.size():
			return
		var kv := b.slice(i, i + l).get_string_from_utf8()
		i += l
		var eq := kv.find("=")
		if eq > 0:
			var key := kv.substr(0, eq).to_upper()
			if key == "TITLE":
				tags.title = kv.substr(eq + 1)
			elif key == "ARTIST":
				tags.artist = kv.substr(eq + 1)


static func _riff_info(b: PackedByteArray, tags: Dictionary) -> void:
	for pair in [["INAM", "title"], ["IART", "artist"]]:
		var at := _find(b, pair[0].to_ascii_buffer())
		if at >= 0 and at + 8 < b.size():
			var l := b.decode_u32(at + 4)
			if at + 8 + l <= b.size():
				tags[pair[1]] = b.slice(at + 8, at + 8 + l).get_string_from_utf8().strip_edges()


static func _find(hay: PackedByteArray, needle: PackedByteArray) -> int:
	var n := needle.size()
	var first := needle[0]
	var i := hay.find(first)
	while i >= 0 and i + n <= hay.size():
		if hay.slice(i, i + n) == needle:
			return i
		i = hay.find(first, i + 1)
	return -1
