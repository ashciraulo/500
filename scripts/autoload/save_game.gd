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

const VERSION := 1
## Real seconds between autosaves.
@export var autosave_interval := 180.0

var slot := 1
## False with --no-save on the command line.
var enabled := true

var _sources := {}
## Sections read from disk, waiting for (or already given to) their owners.
var _pending := {}
var _autosave_timer := 0.0


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
		if enabled:
			save_game()
		get_tree().quit()


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
	# Keep sections whose owner isn't loaded right now (e.g. a garage scene).
	for section in _pending:
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
	# Future: upgrade older save versions here, one step at a time.
	return data


## Helpers for JSON, which has no Vector3 or Transform3D.
static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a.size() == 3 else Vector3.ZERO
