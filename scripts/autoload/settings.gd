extends Node
## Player settings (autoload: Settings), saved to user://settings.cfg.
##
## Holds the choices made in the pause menu and pushes them into the systems
## that use them (GameClock, Weather, RenderSettings, the player's car).
## Loaded on start, saved whenever the pause menu closes.

signal changed

const PATH := "user://settings.cfg"
## Real minutes per in-game day offered in the menu.
const DAY_LENGTHS := [20, 40, 60, 90, 120]
## Menu and HUD size options: [name, scale on top of fitting the window].
const UI_SIZES := [["Small", 0.85], ["Normal", 1.0], ["Large", 1.2]]

var automatic_gearbox := false
var mouse_sensitivity := 0.0025
var day_length_minutes := 40
## -1 = natural weather, otherwise a Weather.State that stays locked.
var weather_choice := -1
var clock_frozen := false
var lofi_enabled := true
## Index into RenderSettings.PRESETS; the values below start from it and can
## then be tuned one by one.
var lofi_preset: int = RenderSettings.DEFAULT_PRESET
var lofi_target_height := 360
var dither_enabled := true
var vertex_snap_scale := 1.0
var color_levels := 64.0
var dither_strength := 0.35
var affine_strength := 0.0
var softness := 0.5
var show_help := true
var fullscreen := false
## Index into UI_SIZES: how big the menus and HUD are drawn.
var ui_size := 1
## Cozy mode: nothing odd happens at home (no intercom after midnight, no
## knocking back from the shed, no plant turned round). The main mystery
## still runs; its things still turn up in the cupboard.
var cozy_mode := false
## How strange the story's late-city events get: "full", or "gentle" (the
## scariest forms swap for softer ones; the story is the same).
var strange_things := "full"
## Volume sliders, 0..1 (1 = as mixed). The Audio autoload applies them,
## each to its own sounds: Everything, then your car (engine, tyres, horn,
## doors, the cabin), music and the radio (My Music too), the surroundings
## (birds, the street, traffic, the weather) and effects (menus and the rest).
var volume_master := 1.0
var volume_music := 1.0
var volume_ambient := 1.0
var volume_effects := 1.0
## Your car has room to go louder than the mix: as mixed half way (the
## Audio autoload's CAR_AS_MIXED), clearly over the radio at the top.
const VOLUME_CAR_DEFAULT := 0.5
var volume_car := VOLUME_CAR_DEFAULT
## Suggested routes to where you're going: 0 off, 1 on the minimap and the
## full map, 2 on the maps and as arrows on the road ahead.
var route_guide := 2


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	GameClock.seconds_per_day = day_length_minutes * 60.0
	GameClock.set_locked(clock_frozen)
	if weather_choice < 0:
		Weather.set_locked(false)
	else:
		Weather.set_state(weather_choice as Weather.State)
		Weather.set_locked(true)
	RenderSettings.lofi_enabled = lofi_enabled
	RenderSettings.target_height = lofi_target_height
	RenderSettings.dither_enabled = dither_enabled
	RenderSettings.vertex_snap_scale = vertex_snap_scale
	RenderSettings.color_levels = color_levels
	RenderSettings.dither_strength = dither_strength
	RenderSettings.affine_strength = affine_strength
	RenderSettings.softness = softness
	var window := get_tree().root if is_inside_tree() else null
	if window and DisplayServer.get_name() != "headless":
		if fullscreen and window.mode != Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_FULLSCREEN
		elif not fullscreen and window.mode == Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED
		# In a window the desktop compositor already keeps frames tear-free,
		# and vsync on top of it made a frame wait a whole extra refresh every
		# few seconds. So a window gets a frame cap at the screen's rate instead.
		var hz := DisplayServer.screen_get_refresh_rate(window.current_screen)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if fullscreen else DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0 if fullscreen else (roundi(hz) if hz > 0.0 else 60)
		window.content_scale_factor = float(UI_SIZES[clampi(ui_size, 0, UI_SIZES.size() - 1)][1])
	RenderSettings.apply()
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	if car:
		var mode := CarController.Transmission.AUTOMATIC if automatic_gearbox else CarController.Transmission.MANUAL
		if car.transmission != mode:
			car.set_transmission(mode)
	changed.emit()


## Pull in state the player changed with hotkeys, so saving keeps it.
func capture() -> void:
	clock_frozen = GameClock.locked
	weather_choice = Weather.state if Weather.locked else -1
	lofi_enabled = RenderSettings.lofi_enabled
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	if car:
		automatic_gearbox = car.transmission == CarController.Transmission.AUTOMATIC


## Set the look to one of RenderSettings.PRESETS (call apply() after).
func use_lofi_preset(index: int) -> void:
	lofi_preset = clampi(index, 0, RenderSettings.PRESETS.size() - 1)
	var preset: Dictionary = RenderSettings.PRESETS[lofi_preset]
	lofi_target_height = preset.target_height
	color_levels = preset.color_levels
	dither_strength = preset.dither_strength
	vertex_snap_scale = preset.vertex_snap_scale
	affine_strength = preset.affine_strength
	softness = preset.softness


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in _keys():
		config.set_value("settings", key, get(key))
	config.save(PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in _keys():
		set(key, config.get_value("settings", key, get(key)))
	if not config.has_section_key("settings", "volume_ambient"):
		_volumes_from_old_sliders(config)
	if not config.has_section_key("settings", "lofi_preset"):
		# Saved before the filter strengths: the old look was harsh, so
		# start from the softer default rather than keep it.
		use_lofi_preset(RenderSettings.DEFAULT_PRESET)
	# The menu has no affine slider, so it always follows the filter strength
	# (older saves kept Soft's old warp, which made the map's textures swim).
	lofi_preset = clampi(lofi_preset, 0, RenderSettings.PRESETS.size() - 1)
	affine_strength = RenderSettings.PRESETS[lofi_preset].affine_strength


## Saved before the four Sound sliders: Effects used to turn down the car and
## the street as well, with Your car and Weather and street under it, and
## Music and Radio were apart. Keep what each sound was heard at: the car and
## the surroundings take Effects times their old slider, and Music and radio
## takes the radio's (what plays while driving).
func _volumes_from_old_sliders(config: ConfigFile) -> void:
	if not config.has_section_key("settings", "volume_effects"):
		return
	var effects := clampf(float(config.get_value("settings", "volume_effects", 1.0)), 0.0, 1.0)
	var car := clampf(float(config.get_value("settings", "volume_car", 1.0)), 0.0, 1.0)
	var street := clampf(float(config.get_value("settings", "volume_surroundings", 1.0)), 0.0, 1.0)
	volume_ambient = effects * street
	volume_music = clampf(float(config.get_value("settings", "volume_radio", volume_music)), 0.0, 1.0)
	# The car slider is twice as steep in dB as the old one (as mixed at
	# VOLUME_CAR_DEFAULT), hence the square root.
	volume_car = VOLUME_CAR_DEFAULT * sqrt(effects * car)


func _keys() -> PackedStringArray:
	return PackedStringArray([
		"automatic_gearbox", "mouse_sensitivity", "day_length_minutes", "weather_choice",
		"clock_frozen", "lofi_enabled", "lofi_target_height", "dither_enabled",
		"vertex_snap_scale", "lofi_preset", "color_levels", "dither_strength", "affine_strength",
		"softness", "show_help", "fullscreen", "ui_size", "cozy_mode", "strange_things",
		"volume_master", "volume_music", "volume_ambient", "volume_effects",
		"volume_car", "route_guide",
	])
