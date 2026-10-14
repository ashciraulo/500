extends SceneTree
## The title screen is the menu, not the game, and --no-save keeps its hands
## off your files:
##
##   - Behind the title screen nothing of the game exists: no world, no car,
##     no traffic, and the save isn't loaded (the money and the day are still
##     the defaults, though the footer shows the save's). Only the title
##     music plays, the clock stands still, nothing is saved (quitting from
##     the menu can't write a blank game over yours), and the menu doesn't
##     click at launch.
##   - Each menu opened or closed makes exactly one click: Settings on the
##     title and Esc back out of it, the phone on Tab, the pause menu on Esc
##     (not the button, the card and the pause all at once, and no map
##     rustle with the phone).
##   - Continue loads the save and builds the game: the money, the day and
##     the car where it was left, the engine turns over, the traffic moves,
##     and Side A's card shows a few seconds into play.
##   - With --no-save a save on disk isn't offered (New game just starts, no
##     "start again?"), delete_save() leaves the file alone, closing the
##     settings doesn't write settings.cfg, and photos don't go in user://photos.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/title_test.gd -- --no-save
##
## Uses its own save slot for the file checks, never your real save.
## Exits with code 1 if any check fails.

## A slot nobody plays on, for the --no-save file checks.
const TEST_SLOT := 97
## Frames the menu sits up for (at 60 fps).
const TITLE_FRAMES := 60 * 4
## The save Continue loads (on TEST_SLOT): the car left out on the lane.
const SAVED_CAR := Vector3(-34.1, 22.6, -16.7)
const SAVED_MONEY := 1234
const SAVED_DAY := 5
## Frames of play after Continue before Side A's card must have shown.
const PLAY_FRAMES := 60 * 9

var _quitting := false
var _boot: Node
var _booted := false
var _main: Node
var _title: CanvasLayer
var _clock_at := 0.0
var _engine: Node  # EngineAudio
var _people: Node  # StoryPeople
var _failures: Array[String] = []
var _frames := 0
var _stage := 0
var _card_seen := false
## Menu clicks heard (ui_menu_*, ui_map_*), and since when we're listening.
var _clicks := 0
## Frames each open or close gets before its clicks are counted.
const CLICK_STEP_FRAMES := 20
## [what, how] pairs run one after another, each expected to click once.
var _click_steps: Array = []
var _click_step := 0
var _after_clicks := 0
var _no_save := true
var _keep_slot := 1


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if not _booted:
		_booted = true
		_write_test_save()
		# As the game starts when it's played: the title screen, the save on
		# disk only read.
		_boot = load("res://scenes/boot.tscn").instantiate()
		_boot.set("with_title", true)
		root.add_child(_boot)
		_title = _boot.get_node("TitleScreen")
		_clock_at = float(root.get_node("GameClock").get("time_of_day"))
		return false
	_frames += 1
	if _main == null and _stage == 2:
		_main = root.get_node_or_null("Main")
		if _main == null:
			return false
		_engine = _main.get_node("LoFi/SubViewport/World/Car/Audio/Engine")
		_check(_car_from_save(), "Continue puts the car where the save left it")
		_frames = 0
	_watch()
	match _stage:
		0:
			if _frames < TITLE_FRAMES:
				return false
			_check(root.get_node_or_null("Main") == null and get_first_node_in_group(&"player_car") == null,
					"no world and no car behind the title screen")
			_check(get_first_node_in_group(&"traffic") == null, "no traffic behind the title screen")
			_check(int(root.get_node("Wallet").get("balance")) != SAVED_MONEY and int(root.get_node("GameClock").get("day")) != SAVED_DAY,
					"the save isn't loaded behind the title screen")
			var footer := String((_title.get("_root") as TitleArt).footer)
			_check(footer.contains("Day %d" % SAVED_DAY) and footer.contains("1,234"), "the footer shows the save's day and money (%s)" % footer)
			_check(is_equal_approx(float(root.get_node("GameClock").get("time_of_day")), _clock_at), "the clock stands still behind the title screen")
			var heard: Array = []
			for bus in _playing():
				if not _muted(bus):
					heard.append(bus)
			_check(heard == ["Music"], "only the title music is heard behind the title screen (%s)" % [heard])
			var before := FileAccess.get_file_as_string(_save_path())
			root.get_node("SaveGame").call("save_game")
			_check(FileAccess.get_file_as_string(_save_path()) == before, "nothing is saved from the title screen")
			_check(_clicks == 0, "no menu clicks at launch (heard %d)" % _clicks)
			_click_steps = [
				["Settings on the title", func() -> void: _title_button("Settings").pressed.emit()],
				["Esc out of the settings over the title", func() -> void: _key(KEY_ESCAPE)],
			]
			_start_clicks(1)
		1:
			_title.call("_continue_game")
			_card_seen = false
			_frames = 0
			_stage = 2
		2:
			if _frames == 30:
				_check(bool(_engine.get("running")), "the engine turns over on Continue")
				_check(int(root.get_node("Wallet").get("balance")) == SAVED_MONEY and int(root.get_node("GameClock").get("day")) == SAVED_DAY,
						"Continue loads the save's money and day")
				_check(not _muted("Car") and not _muted("Ambience") and not _muted("SFX"), "the car, the street and the effects are heard once you play")
				var traffic := get_first_node_in_group(&"traffic")
				_check(traffic != null and traffic.can_process(), "the traffic moves once you play")
				# Nothing more of the test save gets written.
				root.get_node("SaveGame").set("enabled", false)
			if _frames < PLAY_FRAMES and (not _card_seen or _frames <= 30):
				return false
			_check(_card_seen, "Side A's card shows once you're playing")
			_check(_people != null and int(_people.get("card_act")) == 1, "Side A's card is marked shown")
			_click_steps = [
				["the phone opening on Tab", func() -> void: _key(KEY_TAB)],
				["the phone closing on Tab", func() -> void: _key(KEY_TAB)],
				["the pause menu opening on Esc", func() -> void: _key(KEY_ESCAPE)],
				["the pause menu closing on Esc", func() -> void: _key(KEY_ESCAPE)],
			]
			_start_clicks(3)
		3:
			_remove_test_save()
			if _no_save:
				_files_left_alone()
			return _finish()
		99:
			_run_clicks()
	return false


## Run _click_steps, then carry on at stage `next`.
func _start_clicks(next: int) -> void:
	_click_step = 0
	_after_clicks = next
	_frames = 0
	_stage = 99


func _run_clicks() -> void:
	if _click_step >= _click_steps.size():
		_frames = 0
		_stage = _after_clicks
		return
	var step: Array = _click_steps[_click_step]
	if _frames == 1:
		_clicks = 0
		(step[1] as Callable).call()
	elif _frames >= CLICK_STEP_FRAMES:
		_check(_clicks == 1, "one click for %s (heard %d)" % [step[0], _clicks])
		_click_step += 1
		_frames = 0


## The buses of every sound playing anywhere.
func _playing() -> Array:
	var buses: Array = []
	for p: Node in root.find_children("*", "AudioStreamPlayer", true, false) \
			+ root.find_children("*", "AudioStreamPlayer3D", true, false):
		if p.get("playing") and not buses.has(String(p.get("bus"))):
			buses.append(String(p.get("bus")))
	return buses


## Muted, or going through a muted bus.
func _muted(bus: String) -> bool:
	var i := AudioServer.get_bus_index(bus)
	while i > 0:
		if AudioServer.is_bus_mute(i):
			return true
		i = AudioServer.get_bus_index(AudioServer.get_bus_send(i))
	return false


## A save on TEST_SLOT for Continue to load, written whatever --no-save says
## (and taken away after).
func _write_test_save() -> void:
	var save_game: Node = root.get_node("SaveGame")
	_no_save = not save_game.get("enabled")
	_keep_slot = save_game.get("slot")
	save_game.set("slot", TEST_SLOT)
	save_game.set("enabled", true)
	save_game.set("live", false)
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2,
		"wallet": {"balance": SAVED_MONEY, "total_earned": SAVED_MONEY},
		"clock": {"day": SAVED_DAY, "time_of_day": 15.0},
		"car": {"position": [SAVED_CAR.x, SAVED_CAR.y, SAVED_CAR.z], "yaw": 0.0}}))
	f.close()
	save_game.set("_on_disk", save_game.call("_read", _save_path()))


func _remove_test_save() -> void:
	var save_game: Node = root.get_node("SaveGame")
	save_game.set("enabled", not _no_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))
	save_game.set("slot", _keep_slot)


func _save_path() -> String:
	return "user://save_%d.json" % TEST_SLOT


func _car_from_save() -> bool:
	var car := get_first_node_in_group(&"player_car") as Node3D
	if car == null:
		return false
	var at := car.global_position
	return Vector2(at.x - SAVED_CAR.x, at.z - SAVED_CAR.z).length() < 1.5


func _title_button(text: String) -> Button:
	for b: Node in _title.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


## A real key press and release, as the keyboard sends it.
func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)


## Count menu clicks, and once the game is up keep an eye on the act card.
func _watch() -> void:
	for p: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		var s: AudioStream = p.get("stream")
		if p.get("playing") and s and (s.resource_path.contains("ui_menu_") or s.resource_path.contains("ui_map_")) \
				and not p.has_meta(&"title_test_heard"):
			p.set_meta(&"title_test_heard", true)
			_clicks += 1
		elif not p.get("playing") and p.has_meta(&"title_test_heard"):
			p.remove_meta(&"title_test_heard")
	if _main == null:
		return
	if _people == null:
		_people = _main.find_child("StoryPeople", true, false)
	if _people:
		var card: Variant = _people.get("_card")
		if card and (card as CanvasLayer).visible:
			_card_seen = true


## --no-save: a save on disk is neither offered nor deleted, and the
## settings aren't written.
func _files_left_alone() -> void:
	var save_game: Node = root.get_node("SaveGame")
	var keep_slot: int = save_game.get("slot")
	save_game.set("slot", TEST_SLOT)
	var path: String = save_game.call("save_path")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"version\": 2}")
	f.close()
	_check(not save_game.call("has_save"), "--no-save: a save on disk isn't offered")
	save_game.call("delete_save")
	_check(FileAccess.file_exists(path), "--no-save: delete_save() leaves the file alone")
	_check(not save_game.call("save_game"), "--no-save: save_game() writes nothing")
	# The title's New game: straight into the game, no "start again?" that
	# would delete the save.
	var title: CanvasLayer = load("res://scripts/ui/title_screen.gd").new()
	root.add_child(title)
	_check(not (title.get("_continue") as Control).visible, "--no-save: no Continue on the title screen")
	title.call("_new_game")
	_check(not (title.get("_confirm") as Control).visible, "--no-save: New game doesn't ask to delete the save")
	_check(FileAccess.file_exists(path), "--no-save: New game leaves the save on disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	save_game.set("slot", keep_slot)

	var settings: Node = root.get_node("Settings")
	var cfg: String = settings.get("PATH")
	var before := FileAccess.get_file_as_string(cfg) if FileAccess.file_exists(cfg) else "<none>"
	var keep: String = settings.get("strange_things")
	settings.set("strange_things", "gentle" if keep == "full" else "full")
	settings.call("save_settings")
	settings.set("strange_things", keep)
	var after := FileAccess.get_file_as_string(cfg) if FileAccess.file_exists(cfg) else "<none>"
	_check(before == after, "--no-save: saving the settings leaves settings.cfg alone")

	var activities: Node = root.get_node("Activities")
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var entry: Dictionary = activities.call("add_photo", image)
	var photo := String(entry.get("file", ""))
	_check(not photo.begins_with(String(activities.get("PHOTO_DIR")) + "/"), "--no-save: a photo doesn't go in user://photos")
	if photo != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(photo))


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	print("TITLE ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
	return false
