class_name TitleScreen
extends CanvasLayer
## The title screen, on its own: a still of the Pop in the carport at dusk
## (art/ui/title_backdrop.png, drawn by tools/title_backdrop.gd) drifting
## slowly behind a quiet menu of Continue, New game, Settings and Quit.
##
## The game isn't running behind it. boot.gd shows it before anything of the
## game is built, and the save is only read for the footer, not loaded: no
## world, no car, no traffic, no birds or sprinklers. Continue loads the
## save and New game starts fresh, then boot.gd builds the game. The clock
## and the weather stand still while it's up, nothing is saved, and only the
## title music and the menu's clicks are heard (the Audio autoload's street
## and weather beds start up on their own, world or not).

signal started

const BACKDROP := "res://art/ui/title_backdrop.png"
## One slow drift across the backdrop and back (s), and how far in it's
## zoomed so the drift never shows an edge.
const DRIFT_SECONDS := 90.0
const DRIFT_ZOOM := 1.08

var _root: Control
var _menu: VBoxContainer
var _confirm: VBoxContainer
var _continue: Button
var _new: Button
var _backdrop: TextureRect
## The backdrop and the menu together, to fade as one.
var _stage: Control
var _drift := 0.0
## The clock's and the weather's locks as they were, put back on leaving.
var _clock_locked := false
var _weather_locked := false
var _left := false
## Buses that stay up: the title music and the menu's clicks (and the buses
## they go through). The rest are muted while the menu is up.
const HEARD_BUSES := [&"Master", &"MusicRadio", &"Music", &"Effects", &"UI"]
var _muted: Array[StringName] = []


## True while a title screen is up (other menus stand back).
static func is_showing(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(&"title_screen"):
		if (node as CanvasLayer).visible:
			return true
	return false


## Whether the game opens on the title screen: when it's played, not under a
## test script (`--script`), not a scene run on its own (the editor's Run
## Current Scene) and not with `-- --no-title`.
static func wanted() -> bool:
	if OS.get_cmdline_user_args().has("--no-title"):
		return false
	for arg in OS.get_cmdline_args():
		if arg == "--script" or arg == "-s" or (arg.ends_with(".tscn") and not arg.ends_with("boot.tscn")):
			return false
	return true


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"title_screen")
	SaveGame.hold = true
	_clock_locked = GameClock.locked
	_weather_locked = Weather.locked
	GameClock.locked = true
	Weather.locked = true
	for i in AudioServer.bus_count:
		var bus := AudioServer.get_bus_name(i)
		if bus not in HEARD_BUSES and not AudioServer.is_bus_mute(i):
			AudioServer.set_bus_mute(i, true)
			_muted.append(bus)
	_build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has_method("play_music"):
		audio.play_music("mus_main_theme", 3.0)
	(_continue if _continue.visible else _new).grab_focus()


func _exit_tree() -> void:
	if not _left:  # freed without a choice (a test, a screenshot)
		_hand_back()


func _process(delta: float) -> void:
	if _backdrop == null:
		return
	_drift += delta
	var size := get_viewport().get_visible_rect().size
	_backdrop.size = size * DRIFT_ZOOM
	var t := 0.5 - 0.5 * cos(TAU * _drift / DRIFT_SECONDS)
	_backdrop.position = -(size * (DRIFT_ZOOM - 1.0)) * Vector2(t, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	# Nothing else reacts while the menu is up, except the settings when
	# they're open over it.
	if not _left and _root.visible:
		get_viewport().set_input_as_handled()


# --- Choices -------------------------------------------------------------------------

func _continue_game() -> void:
	SaveGame.load_game()
	_leave()


func _new_game() -> void:
	if not SaveGame.has_save():
		_start_again()
		return
	_menu.visible = false
	_confirm.visible = true
	(_confirm.get_child(2) as Button).grab_focus()


## Start again: forget the save. Nothing of it was loaded, so everything is
## already at its defaults.
func _start_again() -> void:
	SaveGame.start_new()
	_leave()


func _settings() -> void:
	var menu := get_tree().root.find_child("PauseMenu", true, false)
	if menu == null:
		return
	_root.visible = false
	menu.open()
	if not menu.closed.is_connected(_on_settings_closed):
		menu.closed.connect(_on_settings_closed, CONNECT_ONE_SHOT)


func _on_settings_closed() -> void:
	_root.visible = true
	_menu.visible = true
	(_continue if _continue.visible else _new).grab_focus()


func _quit() -> void:
	SaveGame.quit_cleanly()  # nothing's live yet, so nothing is written


## Hand over to the game: clock and weather go again, music off, saving on.
## boot.gd builds the game when `started` goes. From here it's no longer the
## title, only a picture over the game's first frames (fade_out()).
func _leave() -> void:
	remove_from_group(&"title_screen")
	layer = 100  # over everything the game puts up
	_menu.visible = false
	_confirm.visible = false
	(_root as TitleArt).footer = "Loading..."
	_hand_back()
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has_method("stop_music"):
		audio.stop_music(2.0)
	started.emit()


## Cover the game's first frames (the camera finding its place, the HUD
## filling in), then fade away.
func fade_out() -> void:
	for i in 12:
		await get_tree().process_frame
	var tween := create_tween()
	tween.tween_property(_stage, ^"modulate:a", 0.0, 0.6)
	await tween.finished
	queue_free()


func _hand_back() -> void:
	_left = true
	SaveGame.hold = false
	GameClock.locked = _clock_locked
	Weather.locked = _weather_locked
	for bus in _muted:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_mute(i, false)
	_muted.clear()


# --- Building ------------------------------------------------------------------------

func _build() -> void:
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_backdrop = TextureRect.new()
	_backdrop.texture = load(BACKDROP)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_backdrop)
	# The look (wash, wordmark, buttons) is TitleArt's, over the backdrop.
	var art := TitleArt.new()
	_root = art
	_stage.add_child(art)

	var has_save := SaveGame.has_save()
	_menu = art.add_group()
	_continue = art.add_button("Continue", _continue_game, true, _menu)
	_continue.visible = has_save
	_new = art.add_button("New game", _new_game, not has_save, _menu)
	art.add_button("Settings", _settings, false, _menu)
	art.add_button("Quit", _quit, false, _menu)

	_confirm = art.add_group()
	_confirm.visible = false
	var ask := UiStyle.label(_confirm, "Start again with the Pop and an empty wallet?", "", 19, UiStyle.CREAM_TEXT)
	ask.add_theme_font_override("font", UiStyle.BOLD_FONT)
	ask.custom_minimum_size.x = 440
	UiStyle.label(_confirm, "Your save, garage and journal will be gone.", "", 0, Color(UiStyle.CREAM_TEXT, 0.7)).custom_minimum_size.x = 440
	art.add_button("Keep my game", func() -> void:
		_confirm.visible = false
		_menu.visible = true
		(_continue if _continue.visible else _new).grab_focus(), true, _confirm)
	art.add_button("Start again", _start_again, false, _confirm)

	art.footer = _footer_text(has_save)


func _footer_text(has_save: bool) -> String:
	if not has_save:
		return "A new game starts in the carport with the Pop."
	# From the save on disk: it isn't loaded until Continue.
	var day := int(SaveGame.peek("clock").get("day", 1))
	var money := int(SaveGame.peek("wallet").get("balance", Wallet.STARTING_BALANCE))
	return "Day %d, %s  ·  $%s" % [day, Garage.WEEKDAYS[(day - 1) % 7], UiStyle.number(money)]
