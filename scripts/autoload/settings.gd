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
var affine_strength := 0.25
var softness := 0.5
var show_help := true
## Volume sliders, 0..1 (1 = as mixed). The Audio autoload applies them.
var volume_master := 1.0
var volume_music := 1.0
var volume_radio := 1.0
var volume_effects := 1.0


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
	if not config.has_section_key("settings", "lofi_preset"):
		# Saved before the filter strengths: the old look was harsh, so
		# start from the softer default rather than keep it.
		use_lofi_preset(RenderSettings.DEFAULT_PRESET)


func _keys() -> PackedStringArray:
	return PackedStringArray([
		"automatic_gearbox", "mouse_sensitivity", "day_length_minutes", "weather_choice",
		"clock_frozen", "lofi_enabled", "lofi_target_height", "dither_enabled",
		"vertex_snap_scale", "lofi_preset", "color_levels", "dither_strength", "affine_strength",
		"softness", "show_help",
		"volume_master", "volume_music", "volume_radio", "volume_effects",
	])
