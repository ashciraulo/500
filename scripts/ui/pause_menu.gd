extends CanvasLayer
## Pause menu: pick the weather and time of day (or let them run naturally),
## day length, gearbox, lo-fi options and mouse sensitivity. Esc / Start opens
## and closes it. Built in code; works with mouse, keyboard and gamepad.

signal closed

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
var _strength: OptionButton
var _softness: HSlider
var _pixels: HSlider
var _dither: CheckBox
var _fullscreen: CheckBox
var _ui_size: OptionButton
var _wobble: HSlider
var _mouse: HSlider
var _volumes := {}
var _cozy: CheckBox
var _resume: Button
## Opened from the title screen: Back instead of Resume, and the game stays paused.
var _from_title := false
var _heading: Label
var _was_paused := false
var _game_only: Array[Button] = []  # hidden when opened from the title screen
var _save_button: Button
var _actions: HBoxContainer  # save, unstick and quit: hidden from the title screen
var _subtitle: Label
var _syncing := false
## The settings columns scroll when they don't fit the screen (a big HUD size).
var _scroll: ScrollContainer
var _columns: HBoxContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false
	get_viewport().size_changed.connect(func() -> void:
		if _panel.visible:
			_fit_height())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and (_panel.visible or not TitleScreen.is_showing(get_tree())):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _panel.visible:
		close()
	else:
		open()


func open() -> void:
	_from_title = TitleScreen.is_showing(get_tree())
	_was_paused = get_tree().paused
	Settings.capture()
	_sync_from_settings()
	_panel.visible = true
	_dim.visible = not _from_title
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_save_button.text = "Save game"
	for button in _game_only:
		button.visible = not _from_title
	_actions.visible = not _from_title
	_subtitle.visible = not _from_title
	_resume.text = "Back" if _from_title else "Back to the road"
	_heading.text = "Settings" if _from_title else "Paused"
	_fit_height()
	_resume.grab_focus()


## Lets the columns take what height the screen has (after the header and the
## buttons) and scroll past that, then re-centres the card on its new size.
func _fit_height() -> void:
	_scroll.custom_minimum_size.y = 0.0
	var rest := _panel.get_combined_minimum_size().y
	var room := get_viewport().get_visible_rect().size.y - rest - 16.0
	_scroll.custom_minimum_size.y = clampf(_columns.get_combined_minimum_size().y, 0.0, maxf(room, 160.0))
	_panel.reset_size()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func close() -> void:
	_panel.visible = false
	_dim.visible = false
	get_tree().paused = _was_paused
	Settings.save_settings()
	closed.emit()


func is_open() -> bool:
	return _panel.visible


func _process(_delta: float) -> void:
	if _panel.visible:
		_time_label.text = "Time of day: %s" % GameClock.time_string()
		_subtitle.text = "Day %d, %s  ·  %s  ·  %s  ·  $%s" % [GameClock.day, Garage.weekday(), GameClock.time_string(),
			Weather.state_name(), UiStyle.number(Wallet.balance)]


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dim = UiStyle.backdrop()
	_dim.visible = false
	root.add_child(_dim)

	var card := UiStyle.centred_card(root, Vector2(820, 0))
	_panel = card[0]
	var box: VBoxContainer = card[1]

	var head: Array = UiStyle.header(box, "Paused", "car", " ", "")
	_heading = head[0]
	_subtitle = head[1]
	_resume = Button.new()
	_resume.text = "Back to the road"
	_resume.theme_type_variation = &"PrimaryButton"
	_resume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resume.pressed.connect(close)
	(head[3] as HBoxContainer).add_child(_resume)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	box.add_child(_scroll)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(columns)
	_columns = columns
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for column in [left, right]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 7)
		columns.add_child(column)

	_section(left, "World")
	_weather = _option(left, "Weather", ["Natural", "Clear", "Light rain", "Storm"], func(i: int) -> void:
		Settings.weather_choice = i - 1
		Settings.apply())
	var clock_row := HBoxContainer.new()
	left.add_child(clock_row)
	_time_label = UiStyle.label(clock_row, "", "NoteLabel")
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_freeze = _check(clock_row, "Stop the clock", func(on: bool) -> void:
		Settings.clock_frozen = on
		Settings.apply())
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 5)
	presets.add_theme_constant_override("v_separation", 5)
	left.add_child(presets)
	for preset in TIME_PRESETS:
		var hours: float = preset[1]
		var chip := _button(presets, preset[0], func() -> void: GameClock.set_time(hours))
		chip.add_theme_font_size_override("font_size", 13)
	var lengths: Array[String] = []
	for minutes in Settings.DAY_LENGTHS:
		lengths.append("%d min" % minutes)
	_day_length = _option(left, "A day lasts", lengths, func(i: int) -> void:
		Settings.day_length_minutes = Settings.DAY_LENGTHS[i]
		Settings.apply())

	_cozy = _check(left, "Cozy mode: nothing odd at home", func(on: bool) -> void:
		Settings.cozy_mode = on
		Settings.apply())

	_section(right, "Look")
	_fullscreen = _check(right, "Full screen (F11)", func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply())
	var sizes: Array[String] = []
	for size in Settings.UI_SIZES:
		sizes.append(size[0])
	_ui_size = _option(right, "Menu and HUD size", sizes, func(i: int) -> void:
		Settings.ui_size = i
		Settings.apply())
	_lofi = _check(right, "Lo-fi filter", func(on: bool) -> void:
		Settings.lofi_enabled = on
		Settings.apply())
	var strengths: Array[String] = []
	for preset in RenderSettings.PRESETS:
		strengths.append(preset.name)
	_strength = _option(right, "Filter strength", strengths, func(i: int) -> void:
		Settings.use_lofi_preset(i)
		Settings.apply()
		_sync_from_settings())
	_softness = _slider(right, "Pixel edges (soft to crisp)", 0.0, 1.0, 0.05, func(v: float) -> void:
		Settings.softness = 1.0 - v
		Settings.apply())
	_pixels = _slider(right, "Detail (chunky to fine)", 160, 480, 20, func(v: float) -> void:
		Settings.lofi_target_height = int(v)
		Settings.apply())
	_dither = _check(right, "Dithering", func(on: bool) -> void:
		Settings.dither_enabled = on
		Settings.apply())
	_wobble = _slider(right, "Wobble", 0.1, 1.0, 0.05, func(v: float) -> void:
		# Lower snap scale = coarser grid = more wobble, so invert the slider.
		Settings.vertex_snap_scale = 1.1 - v
		Settings.apply())

	_section(right, "Driving")
	_gearbox = _option(right, "Gearbox", ["Manual", "Automatic"], func(i: int) -> void:
		Settings.automatic_gearbox = i == 1
		Settings.apply())
	_mouse = _slider(right, "Mouse look", 0.0005, 0.006, 0.0005, func(v: float) -> void:
		Settings.mouse_sensitivity = v)

	_section(left, "Sound")
	for pair in [["volume_master", "Everything"], ["volume_effects", "Effects"],
			["volume_car", "Your car"], ["volume_surroundings", "Weather and street"],
			["volume_music", "Music"], ["volume_radio", "Radio"]]:
		var key: String = pair[0]
		_volumes[key] = _slider(left, pair[1], 0.0, 1.0, 0.05, func(v: float) -> void:
			Settings.set(key, v)
			Settings.apply())
	# The My Music folder button sits on the Music row to keep the menu short.
	var folder := _button(_volumes["volume_music"].get_parent(), "My Music folder", func() -> void:
		var audio := get_node_or_null("/root/Audio")
		if audio:
			audio.radio.open_music_folder())
	folder.add_theme_font_size_override("font_size", 13)
	folder.tooltip_text = "Open My Music: put your own songs here for the radio"
	folder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	folder.get_parent().move_child(folder, 1)

	# In the car: back on its wheels. On foot: back up the drop you fell down,
	# or back along the way you walked (else home to the front gate).
	var unstick := func() -> void:
		var walker := get_tree().get_first_node_in_group(&"player_on_foot") as OnFoot
		if walker and not walker.in_car:
			walker.get_unstuck()
		else:
			var car := get_tree().get_first_node_in_group(&"player_car") as CarController
			if car:
				car.reset_upright()
		close()
	var rule := HSeparator.new()
	box.add_child(rule)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	var save_button := _button(actions, "Save game", func() -> void: pass)
	save_button.pressed.connect(func() -> void:
		save_button.text = "Saved" if SaveGame.save_game() else "Saving is off (--no-save)")
	_save_button = save_button
	_game_only.append(save_button)
	_actions = actions
	actions.visibility_changed.connect(func() -> void: rule.visible = actions.visible)
	_game_only.append(_button(actions, "Get unstuck", unstick))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_game_only.append(_button(actions, "Save and quit to desktop", func() -> void:
		Settings.save_settings()
		SaveGame.quit_cleanly()))


func _sync_from_settings() -> void:
	_syncing = true
	_weather.select(Settings.weather_choice + 1)
	_freeze.button_pressed = Settings.clock_frozen
	_cozy.button_pressed = Settings.cozy_mode
	_day_length.select(maxi(0, Settings.DAY_LENGTHS.find(Settings.day_length_minutes)))
	_gearbox.select(1 if Settings.automatic_gearbox else 0)
	_mouse.value = Settings.mouse_sensitivity
	_lofi.button_pressed = Settings.lofi_enabled
	_fullscreen.button_pressed = Settings.fullscreen
	_ui_size.select(clampi(Settings.ui_size, 0, Settings.UI_SIZES.size() - 1))
	_strength.select(Settings.lofi_preset)
	_softness.value = 1.0 - Settings.softness
	_pixels.value = Settings.lofi_target_height
	_dither.button_pressed = Settings.dither_enabled
	_wobble.value = 1.1 - Settings.vertex_snap_scale
	for key in _volumes:
		_volumes[key].value = Settings.get(key)
	_syncing = false


func _section(parent: Control, text: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		parent.add_child(gap)
	UiStyle.section(parent, text)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := UiStyle.label(row, text)
	label.add_theme_color_override("font_color", UiStyle.INK_2)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row


func _option(parent: Control, text: String, items: Array, action: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.custom_minimum_size.x = 170
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
	slider.custom_minimum_size.x = 170
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			action.call(v))
	_row(parent, text).add_child(slider)
	return slider
