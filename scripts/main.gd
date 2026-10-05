extends Node
## Root of the game scene. Owns the lo-fi framebuffer (a low-res SubViewport
## scaled up with nearest filtering) and the global dev/player hotkeys for
## weather, time and render settings.

@onready var _lofi: SubViewportContainer = $LoFi
@onready var _viewport: SubViewport = $LoFi/SubViewport
@onready var _post: ShaderMaterial = _lofi.material


func _ready() -> void:
	RenderSettings.changed.connect(_apply_render_settings)
	get_viewport().size_changed.connect(_apply_render_settings)
	_apply_render_settings()
	Settings.apply()


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
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_render_settings() -> void:
	var window_size := get_viewport().get_visible_rect().size
	_lofi.stretch_shrink = RenderSettings.shrink_for(int(window_size.y))
	_post.set_shader_parameter("dither_enabled", RenderSettings.dither_enabled and RenderSettings.lofi_enabled)
	_post.set_shader_parameter("color_levels", RenderSettings.color_levels if RenderSettings.lofi_enabled else 256.0)
	_post.set_shader_parameter("dither_strength", RenderSettings.dither_strength)
	_post.set_shader_parameter("softness", RenderSettings.softness if RenderSettings.lofi_enabled else 0.0)
	RenderSettings.set_framebuffer_size(Vector2i(window_size) / _lofi.stretch_shrink)
