extends Node
## Save and load (autoload: SaveGame).
##
## Anything that wants to be saved registers itself with a section name and
## implements two methods:
##   func save_state() -> Dictionary
##   func load_state(data: Dictionary) -> void
## Registering after the save was read (e.g. the car, created with the scene)
## applies its section straight away, so load order doesn't matter.
##
## The save is JSON at user://save_<slot>.json, written on demand, every few
## minutes while driving, and when the game closes. Run with `-- --no-save`
## to neither load nor write saves (the smoke test does this).

signal saved(path: String)
signal loaded(path: String)

## 2: the real Perth map replaced the test grid, so older car positions point
## at empty space.
const VERSION := 2
## Real seconds between autosaves.
@export var autosave_interval := 180.0

var slot := 1
## False with --no-save on the command line.
var enabled := true

var _sources := {}
## Sections read from disk, waiting for (or already given to) their owners.
var _pending := {}
var _autosave_timer := 0.0
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = not OS.get_cmdline_user_args().has("--no-save")
	get_tree().auto_accept_quit = false
	if enabled:
		load_from(save_path())


func _process(delta: float) -> void:
	if not enabled or get_tree().paused:
		return
	_autosave_timer += delta
	if _autosave_timer >= autosave_interval:
		_autosave_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_cleanly()


## Save, then take the game down while the engine is still running: stop
## every sound, free the scene (the map waits for its loaders, traffic breaks
## its reference cycles) and quit a few frames later. Quitting with all of it
## still up left sounds and meshes to be freed after the audio and render
## servers had gone, which crashed on exit on Windows.
func quit_cleanly(exit_code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	if enabled:
		save_game()
	var tree := get_tree()
	# Nothing processes from here on, so nothing starts a sound again (some
	# autoloads process always, so turning the root off isn't enough).
	for node in tree.root.find_children("*", "", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	_stop_sounds()
	# Everything under the root that isn't an autoload: the game scene (or a
	# test's copy of it).
	for child in tree.root.get_children():
		if not ProjectSettings.has_setting("autoload/" + child.name):
			child.queue_free()
	for i in 4:
		await tree.process_frame
	# The audio side knows its own players, streams and caches best.
	var audio := tree.root.get_node_or_null(^"Audio")
	if audio and audio.has_method("quit_game"):
		audio.quit_game(exit_code)
		return
	# The audio thread lets go of stopped sounds on its next mix, which takes
	# real time, not frames.
	OS.delay_msec(250)
	await tree.process_frame
	tree.quit(exit_code)


func _stop_sounds() -> void:
	var root := get_tree().root
	for player in root.find_children("*", "AudioStreamPlayer", true, false) \
			+ root.find_children("*", "AudioStreamPlayer2D", true, false) \
			+ root.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()


func save_path() -> String:
	return "user://save_%d.json" % slot


func has_save() -> bool:
	return FileAccess.file_exists(save_path())


func register(section: String, source: Object) -> void:
	_sources[section] = source
	if _pending.has(section) and source.has_method("load_state"):
		source.load_state(_pending[section])


func unregister(section: String) -> void:
	_sources.erase(section)


func save_game() -> bool:
	if not enabled:
		return false
	return save_to(save_path())


func save_to(path: String) -> bool:
	var data := {"version": VERSION, "saved_at": Time.get_datetime_string_from_system()}
	# Keep sections whose owner isn't loaded right now (e.g. a garage scene),
	# but not the loaded file's version or saved_at.
	for section in _pending:
		if not data.has(section):
			data[section] = _pending[section]
	for section in _sources:
		var source: Object = _sources[section]
		if is_instance_valid(source) and source.has_method("save_state"):
			data[section] = source.save_state()
	_pending = data.duplicate(true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	saved.emit(path)
	return true


func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("Save %s is unreadable; starting fresh." % path)
		return false
	_pending = _migrate(parsed)
	for section in _sources:
		if _pending.has(section) and _sources[section].has_method("load_state"):
			_sources[section].load_state(_pending[section])
	loaded.emit(path)
	return true


## Forget everything and start a new game on this slot.
func delete_save() -> void:
	_pending = {}
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))


func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version < 2 and data.get("car") is Dictionary:
		# Saved on the test grid: keep the car, start it at home.
		data.car.erase("position")
		data.car.erase("yaw")
	data.version = VERSION
	return data


## Helpers for JSON, which has no Vector3 or Transform3D.
static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a.size() == 3 else Vector3.ZERO
