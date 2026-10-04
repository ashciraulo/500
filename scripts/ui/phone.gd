extends CanvasLayer
## The player's phone: the job board, career progress and a few stats.
## Tab / X (gamepad) opens and closes it. The game pauses while it's open.

var _panel: PanelContainer
var _dim: ColorRect
var _tabs: TabContainer
var _jobs_list: VBoxContainer
var _progress_list: VBoxContainer
var _stats_label: Label
var _close: Button


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_open(false)
	Jobs.offers_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if not _panel.visible and get_tree().paused:
		return  # Pause menu is open.
	_set_open(not _panel.visible)


func is_open() -> bool:
	return _panel.visible


func _set_open(open: bool) -> void:
	_panel.visible = open
	_dim.visible = open
	get_tree().paused = open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
		_close.grab_focus()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 0.96)
	style.border_color = Color(0.6, 0.85, 0.8)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 520)
	_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Phone"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close = Button.new()
	_close.text = "Close"
	_close.pressed.connect(toggle)
	header.add_child(_close)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_jobs_list = _scroll_tab("Jobs")
	_progress_list = _scroll_tab("Progress")
	var stats_tab := _scroll_tab("Car & stats")
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_tab.add_child(_stats_label)


func _scroll_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	return list


func _refresh() -> void:
	if not _panel.visible:
		return
	_refresh_jobs()
	_refresh_progress()
	_refresh_stats()


func _refresh_jobs() -> void:
	_clear(_jobs_list)
	if not Jobs.active.is_empty():
		_text(_jobs_list, "Current job", 18, Color(0.6, 0.85, 0.8))
		_text(_jobs_list, Jobs.objective_text())
		var abandon := Button.new()
		abandon.text = "Give up this job"
		abandon.pressed.connect(func() -> void:
			Jobs.abandon()
			_refresh())
		_jobs_list.add_child(abandon)
		_jobs_list.add_child(HSeparator.new())
	_text(_jobs_list, "On offer", 18, Color(0.6, 0.85, 0.8))
	if Jobs.offers.is_empty():
		_text(_jobs_list, "Nothing right now. Check back in a few hours.")
	for job in Jobs.offers:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = Jobs.describe(job)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var take := Button.new()
		take.text = "Take it"
		take.pressed.connect(func() -> void:
			Jobs.accept(job)
			toggle())
		row.add_child(take)
		_jobs_list.add_child(row)


func _refresh_progress() -> void:
	_clear(_progress_list)
	var tier := Progression.current_tier()
	if tier.is_empty():
		_text(_progress_list, "Every tier done. Perth is yours; just drive.")
		return
	_text(_progress_list, "Tier %d: %s" % [Progression.tier_index + 1, tier.title], 18, Color(0.6, 0.85, 0.8))
	_text(_progress_list, tier.blurb)
	for challenge in tier.challenges:
		var done := Progression.is_done(challenge)
		var value := Progression.get_stat(challenge.stat)
		var row := VBoxContainer.new()
		var label := Label.new()
		label.text = "%s %s: %s  (%s / %s)" % [
			"[x]" if done else "[ ]", challenge.title, challenge.description,
			_number(minf(value, challenge.target)), _number(challenge.target)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = Progression.progress(challenge)
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6
		row.add_child(bar)
		_progress_list.add_child(row)


func _refresh_stats() -> void:
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	var lines := PackedStringArray()
	lines.append("Money: $%s   (earned $%s all up)" % [_number(Wallet.balance), _number(Wallet.total_earned)])
	lines.append("Day %d, %s" % [GameClock.day, GameClock.time_string()])
	lines.append("Places discovered: %d" % Discoveries.all().size())
	lines.append("Deliveries: %d" % Progression.get_stat("deliveries"))
	if car:
		var stats := car.get_stats()
		lines.append("")
		lines.append("2013 Fiat 500 Pop, %.0f km on the clock" % car.odometer_km)
		lines.append("%.0f kW, %.0f Nm, %.0f kg" % [stats.power_kw, stats.torque_nm, stats.mass_kg])
		for part in car.parts.values():
			lines.append("  %s" % part.display_name)
	_stats_label.text = "\n".join(lines)


func _text(parent: Control, text: String, size := 15, color := Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


static func _number(value: float) -> String:
	var text := str(roundi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return text + out
