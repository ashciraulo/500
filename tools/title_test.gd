extends SceneTree
## The title screen is quiet, and --no-save keeps its hands off your files:
##
##   - Behind the title screen nothing of the game starts: the car's engine
##     stays off (no start-up), the car settling onto the ground makes no
##     thud, Side A's card doesn't show however long the menu sits there, and
##     at night the classic idling at the end of the lane doesn't start, and
##     no menu clicks at launch (the phone and journal being built aren't
##     menus opening).
##   - Each menu opened or closed makes exactly one click: Settings on the
##     title and Esc back out of it, the phone on Tab, the pause menu on Esc
##     (not the button, the card and the pause all at once, and no map
##     rustle with the phone).
##   - Continue hands the game over: the engine turns over then, and Side A's
##     card shows a few seconds into play.
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
## Frames the menu sits up for (at 60 fps): longer than Side A's wait.
const TITLE_FRAMES := 60 * 10
## Frames of play after Continue before Side A's card must have shown.
const PLAY_FRAMES := 60 * 9

var _quitting := false
var _main: Node
var _title: CanvasLayer
var _engine: Node  # EngineAudio
var _people: Node  # StoryPeople
var _failures: Array[String] = []
var _frames := 0
var _stage := 0
var _engine_ran := false
var _thud := false
var _card_seen := false
var _lane_idle := false
## Menu clicks heard (ui_menu_*, ui_map_*), and since when we're listening.
var _clicks := 0
## Frames each open or close gets before its clicks are counted.
const CLICK_STEP_FRAMES := 20
## [what, how] pairs run one after another, each expected to click once.
var _click_steps: Array = []
var _click_step := 0
var _after_clicks := 0


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		# As main.gd adds it when the game is played (tests skip it).
		_title = load("res://scripts/ui/title_screen.gd").new()
		_title.name = "TitleScreen"
		_main.add_child(_title)
		_engine = _main.get_node("LoFi/SubViewport/World/Car/Audio/Engine")
		# Night, when the lane's oddity would start up within earshot.
		root.get_node("GameClock").set_time(2.5)
		return false
	_frames += 1
	_watch()
	match _stage:
		0:
			if _frames < TITLE_FRAMES:
				return false
			_check(not _engine_ran, "the engine stays off behind the title screen")
			_check(not _thud, "no tyre thud as the car settles at launch")
			_check(not _card_seen, "Side A's card waits behind the title screen")
			_check(not _lane_idle, "the lane idle doesn't start behind the title screen")
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
			if not root.get_node("SaveGame").get("enabled"):
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


## Keep an eye on the engine, the tyres and the act card every frame.
func _watch() -> void:
	if _engine.get("running"):
		_engine_ran = true
	for p: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		var s: AudioStream = p.get("stream")
		if p.get("playing") and s and s.resource_path.contains("tyre_speed_bump"):
			_thud = true
		if p.get("playing") and s and s.resource_path.contains("_startup") and _stage == 0:
			_engine_ran = true
	for p: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		var s: AudioStream = p.get("stream")
		if p.get("playing") and s and (s.resource_path.contains("ui_menu_") or s.resource_path.contains("ui_map_")) \
				and not p.has_meta(&"title_test_heard"):
			p.set_meta(&"title_test_heard", true)
			_clicks += 1
		elif not p.get("playing") and p.has_meta(&"title_test_heard"):
			p.remove_meta(&"title_test_heard")
	var odd := _main.find_child("Oddities", true, false)
	if odd and odd.get("_idle") != null:
		_lane_idle = true
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
