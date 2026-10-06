extends Node
## Root of the game scene. Owns the lo-fi framebuffer (a low-res SubViewport
## scaled up with nearest filtering) and the global dev/player hotkeys for
## weather, time and render settings. Debug builds also get DevMode (F3).

@onready var _lofi: SubViewportContainer = $LoFi
@onready var _viewport: SubViewport = $LoFi/SubViewport
@onready var _post: ShaderMaterial = _lofi.material


func _ready() -> void:
	RenderSettings.changed.connect(_apply_render_settings)
	get_viewport().size_changed.connect(_apply_render_settings)
	_apply_render_settings()
	Settings.apply()
	if DevMode.available():
		var dev := DevMode.new()
		dev.name = "DevMode"
		add_child(dev)
	if _wants_title():
		var title := TitleScreen.new()
		title.name = "TitleScreen"
		add_child(title)


## The title screen shows when the game is played, not under a test script
## (`--script`) and not straight after New game restarted it (`-- --fresh`).
func _wants_title() -> bool:
	if OS.get_cmdline_user_args().has("--fresh") or OS.get_cmdline_user_args().has("--no-title"):
		return false
	var args := OS.get_cmdline_args()
	return not (args.has("--script") or args.has("-s"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weather_next"):
		Weather.cycle_state()
	elif event.is_action_pressed("weather_lock"):
		Weather.toggle_locked()
	elif event.is_action_pressed("time_forward"):
		GameClock.advance(1.0)
	elif event.is_action_pressed("time_lock"):
		GameClock.toggle_locked()
	elif event.is_action_pressed("toggle_lofi"):
		RenderSettings.toggle_lofi()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		Settings.fullscreen = not Settings.fullscreen
		Settings.apply()
		Settings.save_settings()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_render_settings() -> void:
	# The UI is laid out for 720p and scaled to the window (canvas_items
	# stretch), but the lo-fi framebuffer is sized from the window's real
	# pixels so each low-res pixel stays a whole number of screen pixels.
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size) if get_window().size.y > 0 else logical
	var shrink := RenderSettings.shrink_for(int(physical.y))
	var framebuffer := Vector2i((physical / shrink).floor())
	_lofi.stretch_shrink = 1
	_lofi.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lofi.position = Vector2.ZERO
	_lofi.size = Vector2(framebuffer)
	_lofi.scale = logical / Vector2(framebuffer)
	_post.set_shader_parameter("dither_enabled", RenderSettings.dither_enabled and RenderSettings.lofi_enabled)
	_post.set_shader_parameter("color_levels", RenderSettings.color_levels if RenderSettings.lofi_enabled else 256.0)
	_post.set_shader_parameter("dither_strength", RenderSettings.dither_strength)
	_post.set_shader_parameter("softness", RenderSettings.softness if RenderSettings.lofi_enabled else 0.0)
	RenderSettings.set_framebuffer_size(framebuffer)
