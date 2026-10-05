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

var _root: Control
var _menu: VBoxContainer
var _confirm: VBoxContainer
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
	# The look (wash, wordmark, buttons) is TitleArt's; the world shows through.
	var art := TitleArt.new()
	_root = art
	add_child(art)

	var has_save := SaveGame.enabled and SaveGame.has_save()
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
	return "Day %d, %s  ·  $%s" % [GameClock.day, Garage.weekday(), UiStyle.number(Wallet.balance)]
