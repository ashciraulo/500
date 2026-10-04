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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Radio"
	add_child(_player)
	_player.finished.connect(_on_finished)
	_static = AudioStreamPlayer.new()
	_static.bus = "Radio"
	add_child(_static)
	ensure_music_folder()
	var audio := get_parent()
	if audio and audio.has_signal("player_inside_changed"):
		audio.player_inside_changed.connect(func(inside: bool) -> void:
			_outside_trim = 0.0 if inside else -14.0
			_apply_volume())
		_outside_trim = 0.0 if audio.is_player_inside() else -14.0


func _process(delta: float) -> void:
	_clock += delta


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
		_player.stream = Audio.variant("oddity/odd_midnight_station")
		_player.volume_db = volume_db + _outside_trim + _duck_db
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
		_player.volume_db = volume_db + _outside_trim + _duck_db


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
	_player.stream = Audio.stream(st.item)
	_player.volume_db = volume_db + _outside_trim + _duck_db
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
				_player.volume_db = volume_db + _outside_trim + _duck_db
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
	_player.stream = s
	_player.volume_db = volume_db + _outside_trim + _duck_db
	_player.play()
	var tags := read_tags(path)
	_current_title = tags.title
	_current_artist = tags.artist
	now_playing.emit("mymusic", _current_title, _current_artist)


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
