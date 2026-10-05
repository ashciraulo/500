class_name TitleScreen
extends CanvasLayer
## The title screen: the game boots behind it, the camera drifts slowly round
## the parked car, and a quiet menu offers Continue, New game, Settings and
## Quit. Nothing moves the car or saves until you choose.
##
## main.gd adds it when the game is run for real (not under a test script,
## and not after New game restarted the game with `-- --fresh`).

signal started

## How long one slow lap round the car takes (s).
const ORBIT_SECONDS := 140.0
const ORBIT_RADIUS := 5.2
const ORBIT_HEIGHT := 1.5
const ACCENT := Color(0.95, 0.85, 0.5)
const QUIET := Color(0.78, 0.76, 0.7)

var _root: Control
var _menu: VBoxContainer
var _confirm: VBoxContainer
var _footer: Label
var _continue: Button
var _new: Button
var _orbit := 0.0
var _rig: Node
var _camera: Camera3D
var _car: CarController
var _hud: Node  # a CanvasLayer


## True while a title screen is up (other menus stand back).
static func is_showing(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(&"title_screen"):
		if (node as CanvasLayer).visible:
			return true
	return false


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"title_screen")
	SaveGame.hold = true
	_build()
	_take_over.call_deferred()


func _take_over() -> void:
	_car = get_tree().get_first_node_in_group(&"player_car") as CarController
	if _car:
		_car.player_controlled = false
		_orbit = _car.global_rotation.y + PI * 0.75
	_rig = get_tree().root.find_child("CameraRig", true, false)
	if _rig:
		_rig.set_process(false)
		_rig.set_physics_process(false)
		_camera = _rig.get_node_or_null(^"Camera3D") as Camera3D
	_hud = get_tree().get_first_node_in_group(&"hud")
	if _hud:
		_hud.set(&"visible", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has_method("play_music"):
		audio.play_music("mus_main_theme", 3.0)
	(_continue if _continue.visible else _new).grab_focus()


func _process(delta: float) -> void:
	if not visible or _camera == null or _car == null:
		return
	_orbit += TAU * delta / ORBIT_SECONDS
	var centre := _car.global_position + Vector3.UP * 0.5
	var eye := centre + Vector3(sin(_orbit), 0.0, cos(_orbit)) * ORBIT_RADIUS + Vector3.UP * ORBIT_HEIGHT
	# Keep the eye under the carport roof and out of walls: a little closer
	# when something is in the way.
	var space := _car.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(centre, eye, 1)
	query.exclude = [_car.get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
		eye = centre.lerp(hit.position, 0.85)
	_camera.global_transform = Transform3D(Basis(), eye).looking_at(centre, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	# Nothing behind the menu reacts while it's up (the phone, the radio, the
	# car), except the settings when they're open over it.
	if visible and _root.visible:
		get_viewport().set_input_as_handled()


# --- Choices -------------------------------------------------------------------------

func _continue_game() -> void:
	_leave()


func _new_game() -> void:
	if not SaveGame.has_save():
		_leave()
		return
	_menu.visible = false
	_confirm.visible = true
	(_confirm.get_child(2) as Button).grab_focus()


## Start again: forget the save and restart the game fresh, so every system
## starts from its defaults.
func _start_again() -> void:
	SaveGame.delete_save()
	SaveGame.enabled = false
	var args := OS.get_cmdline_args()
	args.append("--")
	for a in OS.get_cmdline_user_args():
		if a != "--fresh":
			args.append(a)
	args.append("--fresh")
	OS.set_restart_on_exit(true, args)
	SaveGame.quit_cleanly()


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
	if not SaveGame.has_save():
		SaveGame.enabled = false  # nothing played yet, nothing to keep
	SaveGame.quit_cleanly()


## Hand the game over: camera, car and HUD back, music off, saving on.
func _leave() -> void:
	visible = false
	SaveGame.hold = false
	if _rig:
		_rig.set_process(true)
		_rig.set_physics_process(true)
	if _car:
		_car.player_controlled = true
	if _hud:
		_hud.set(&"visible", true)
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has_method("stop_music"):
		audio.stop_music(2.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	started.emit()
	queue_free()


# --- Building ------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# A soft shadow down the left, where the words sit; the world shows through.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.02, 0.03, 0.88))
	gradient.set_color(1, Color(0.02, 0.02, 0.03, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(1, 0)
	texture.width = 256
	texture.height = 4
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.62
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var column := VBoxContainer.new()
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = 88
	column.offset_top = -190
	column.offset_right = 600
	column.add_theme_constant_override("separation", 6)
	_root.add_child(column)

	var title := Label.new()
	title.text = "Cinquecento"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "15 Little Shenton Lane, Northbridge"
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", QUIET)
	column.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 36
	column.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	column.add_child(_menu)
	var has_save := SaveGame.enabled and SaveGame.has_save()
	_continue = _item(_menu, "Continue", _continue_game)
	_continue.visible = has_save
	_new = _item(_menu, "New game", _new_game)
	_item(_menu, "Settings", _settings)
	_item(_menu, "Quit", _quit)

	_confirm = VBoxContainer.new()
	_confirm.visible = false
	_confirm.add_theme_constant_override("separation", 2)
	column.add_child(_confirm)
	var ask := Label.new()
	ask.text = "Start again from the Pop and an empty wallet?"
	ask.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
	_confirm.add_child(ask)
	var warn := Label.new()
	warn.text = "Your saved game, garage and journal will be gone."
	warn.add_theme_font_size_override("font_size", 15)
	warn.add_theme_color_override("font_color", QUIET)
	_confirm.add_child(warn)
	_item(_confirm, "Keep my game", func() -> void:
		_confirm.visible = false
		_menu.visible = true
		_continue.grab_focus())
	_item(_confirm, "Start again", _start_again)

	_footer = Label.new()
	_footer.anchor_top = 1.0
	_footer.anchor_bottom = 1.0
	_footer.offset_left = 88
	_footer.offset_top = -64
	_footer.offset_right = 900
	_footer.add_theme_font_size_override("font_size", 14)
	_footer.add_theme_color_override("font_color", Color(0.62, 0.6, 0.56))
	_footer.text = _footer_text(has_save)
	_root.add_child(_footer)


func _footer_text(has_save: bool) -> String:
	if not has_save:
		return "A new game starts in the carport with the Pop."
	var when := SaveGame.saved_at().replace("T", " ").left(16)
	var money := str(Wallet.balance)
	return "Day %d   ·   $%s   ·   saved %s" % [GameClock.day, money, when]


## A menu line: plain text that brightens and gets a marker when chosen.
func _item(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", QUIET)
	button.add_theme_color_override("font_hover_color", ACCENT)
	button.add_theme_color_override("font_focus_color", ACCENT)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_hover_pressed_color", ACCENT)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	button.focus_entered.connect(func() -> void: button.text = "›  " + text)
	button.focus_exited.connect(func() -> void: button.text = text)
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
