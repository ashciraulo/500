extends CanvasLayer
## Pause menu: pick the weather and time of day (or let them run naturally),
## day length, gearbox, lo-fi options and mouse sensitivity. Esc / Start opens
## and closes it. Built in code; works with mouse, keyboard and gamepad.

const TIME_PRESETS := [
	["Dawn", 5.8], ["Morning", 9.0], ["Noon", 12.0], ["Afternoon", 15.5],
	["Golden hour", 17.6], ["Dusk", 18.6], ["Night", 21.5], ["Small hours", 2.5],
]

var _panel: PanelContainer
var _dim: ColorRect
var _weather: OptionButton
var _time_label: Label
var _freeze: CheckBox
var _day_length: OptionButton
var _gearbox: OptionButton
var _lofi: CheckBox
var _pixels: HSlider
var _dither: CheckBox
var _wobble: HSlider
var _mouse: HSlider
var _volumes := {}
var _resume: Button
var _save_button: Button
var _syncing := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _panel.visible:
		close()
	else:
		open()


func open() -> void:
	Settings.capture()
	_sync_from_settings()
	_panel.visible = true
	_dim.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_save_button.text = "Save game"
	_resume.grab_focus()


func close() -> void:
	_panel.visible = false
	_dim.visible = false
	get_tree().paused = false
	Settings.save_settings()


func is_open() -> bool:
	return _panel.visible


func _process(_delta: float) -> void:
	if _panel.visible:
		_time_label.text = "Time  %s" % GameClock.time_string()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	root.add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	style.border_color = Color(0.95, 0.85, 0.5)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_resume = _button(box, "Resume", close)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for column in [left, right]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 8)
		columns.add_child(column)

	_section(left, "World")
	_weather = _option(left, "Weather", ["Natural", "Clear", "Light rain", "Storm"], func(i: int) -> void:
		Settings.weather_choice = i - 1
		Settings.apply())
	_time_label = Label.new()
	left.add_child(_time_label)
	var presets := HFlowContainer.new()
	left.add_child(presets)
	for preset in TIME_PRESETS:
		var hours: float = preset[1]
		_button(presets, preset[0], func() -> void: GameClock.set_time(hours))
	_freeze = _check(left, "Freeze the clock", func(on: bool) -> void:
		Settings.clock_frozen = on
		Settings.apply())
	var lengths: Array[String] = []
	for minutes in Settings.DAY_LENGTHS:
		lengths.append("%d min" % minutes)
	_day_length = _option(left, "Day length (real time)", lengths, func(i: int) -> void:
		Settings.day_length_minutes = Settings.DAY_LENGTHS[i]
		Settings.apply())

	_section(left, "Driving")
	_gearbox = _option(left, "Gearbox", ["Manual", "Automatic"], func(i: int) -> void:
		Settings.automatic_gearbox = i == 1
		Settings.apply())
	_mouse = _slider(left, "Mouse look speed", 0.0005, 0.006, 0.0005, func(v: float) -> void:
		Settings.mouse_sensitivity = v)

	_section(right, "Look")
	_lofi = _check(right, "Lo-fi filter", func(on: bool) -> void:
		Settings.lofi_enabled = on
		Settings.apply())
	_pixels = _slider(right, "Chunkiness (lower = chunkier)", 160, 480, 20, func(v: float) -> void:
		Settings.lofi_target_height = int(v)
		Settings.apply())
	_dither = _check(right, "Dithering", func(on: bool) -> void:
		Settings.dither_enabled = on
		Settings.apply())
	_wobble = _slider(right, "Vertex wobble", 0.1, 1.0, 0.05, func(v: float) -> void:
		# Lower snap scale = coarser grid = more wobble, so invert the slider.
		Settings.vertex_snap_scale = 1.1 - v
		Settings.apply())

	_section(right, "Sound")
	for pair in [["volume_master", "Volume"], ["volume_effects", "Car and world"],
			["volume_music", "Music"], ["volume_radio", "Radio"]]:
		var key: String = pair[0]
		_volumes[key] = _slider(right, pair[1], 0.0, 1.0, 0.05, func(v: float) -> void:
			Settings.set(key, v)
			Settings.apply())
	_button(right, "Open My Music folder", func() -> void:
		var audio := get_node_or_null("/root/Audio")
		if audio:
			audio.radio.open_music_folder())

	_section(right, "")
	var car_reset := func() -> void:
		var car := get_tree().get_first_node_in_group(&"player_car") as CarController
		if car:
			car.reset_upright()
		close()
	var save_button := _button(right, "Save game", func() -> void: pass)
	save_button.pressed.connect(func() -> void:
		save_button.text = "Saved" if SaveGame.save_game() else "Saving is off (--no-save)")
	_save_button = save_button
	_button(right, "Put the car back on its wheels", car_reset)
	_button(right, "Save and quit to desktop", func() -> void:
		Settings.save_settings()
		SaveGame.quit_cleanly())


func _sync_from_settings() -> void:
	_syncing = true
	_weather.select(Settings.weather_choice + 1)
	_freeze.button_pressed = Settings.clock_frozen
	_day_length.select(maxi(0, Settings.DAY_LENGTHS.find(Settings.day_length_minutes)))
	_gearbox.select(1 if Settings.automatic_gearbox else 0)
	_mouse.value = Settings.mouse_sensitivity
	_lofi.button_pressed = Settings.lofi_enabled
	_pixels.value = Settings.lofi_target_height
	_dither.button_pressed = Settings.dither_enabled
	_wobble.value = 1.1 - Settings.vertex_snap_scale
	for key in _volumes:
		_volumes[key].value = Settings.get(key)
	_syncing = false


func _section(parent: Control, text: String) -> void:
	parent.add_child(HSeparator.new())
	if text != "":
		var label := Label.new()
		label.text = text
		label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
		parent.add_child(label)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	parent.add_child(row)
	return row


func _option(parent: Control, text: String, items: Array, action: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.custom_minimum_size.x = 160
	option.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			action.call(i))
	_row(parent, text).add_child(option)
	return option


func _check(parent: Control, text: String, action: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			action.call(on))
	parent.add_child(check)
	return check


func _slider(parent: Control, text: String, min_value: float, max_value: float, step: float, action: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size.x = 160
	slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			action.call(v))
	_row(parent, text).add_child(slider)
	return slider
