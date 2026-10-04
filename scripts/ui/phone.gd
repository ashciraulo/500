extends CanvasLayer
## The player's phone: the job board, career progress and a few stats.
## Tab / X (gamepad) opens and closes it. The game pauses while it's open.

var _panel: PanelContainer
var _dim: ColorRect
var _tabs: TabContainer
var _jobs_list: VBoxContainer
var _progress_list: VBoxContainer
var _leads_list: VBoxContainer
var _stats_label: Label
var _close: Button
var _roadside: Button


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
		var car := get_tree().get_first_node_in_group(&"player_car") as CarController
		if car and car.fuel_litres < 1.0:
			_tabs.current_tab = 3  # Straight to roadside assist.
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
	_leads_list = _scroll_tab("Leads & fun")
	var stats_tab := _scroll_tab("Car & stats")
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_tab.add_child(_stats_label)
	_roadside = Button.new()
	_roadside.text = "Call roadside assist ($%d, brings %d L)" % [Garage.ROADSIDE_PRICE, Garage.ROADSIDE_LITRES]
	_roadside.visible = false
	_roadside.pressed.connect(func() -> void:
		var car := get_tree().get_first_node_in_group(&"player_car") as CarController
		if car:
			Garage.roadside_assist(car)
		_refresh())
	stats_tab.add_child(_roadside)


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
	_refresh_leads()
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
	var next_cars := Progression.cars_unlocked_at(Progression.tier_index + 1)
	if not next_cars.is_empty():
		var names := PackedStringArray()
		for car in next_cars:
			names.append("%s ($%s)" % [car.name, _number(car.price)])
		_text(_progress_list, "Finish this tier and the car yard will sell you: %s." % ", ".join(names), 14, Color(1.0, 0.88, 0.55))
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


func _refresh_leads() -> void:
	_clear(_leads_list)
	var accent := Color(0.6, 0.85, 0.8)
	_text(_leads_list, "Barn-find rumours", 18, accent)
	var leads := Classics.open_leads()
	if leads.is_empty():
		_text(_leads_list, "No leads right now. People talk at the Friday and Saturday night meet (Roe Street car park, 8 pm to 2 am), and word gets around as your career grows.")
	for lead: Dictionary in leads:
		var car := CarCatalogue.get_car(lead.car)
		_text(_leads_list, "%s: \"%s\"" % [String(lead.where)[0].to_upper() + String(lead.where).substr(1), lead.rumour])
		_text(_leads_list, "  Probably a %s. Stop next to it to claim it." % car.get("name", "classic"), 13, Color(0.7, 0.7, 0.68))
	_text(_leads_list, "Classics found: %d of %d" % [Classics.found_count(), Classics.barn_finds().size()], 14)

	_text(_leads_list, "Things to do", 18, accent)
	_text(_leads_list, "Photo spots: %d of %d. Press P for photo mode near a blue PHOTO sign. %d photos in the album." % [
		Activities.photo_spots_found(), Activities.PHOTO_SPOTS_TOTAL, Activities.photos.size()])
	var golds := 0
	for record: Dictionary in Activities.parking.values():
		if record.get("medal", "") == "gold":
			golds += 1
	_text(_leads_list, "Parking challenges: %d tried, %d gold. Look for the yellow PARK signs." % [Activities.parking.size(), golds])
	_text(_leads_list, "Scenic drives done: %d. Green SCENIC DRIVE signs start them." % Progression.get_stat("scenic_drives"))
	_text(_leads_list, "Lifts given: %d. Passengers show up on the job board." % Progression.get_stat("lifts_given"))
	_text(_leads_list, "Trains beaten: %d of %d raced. Drive alongside a moving train and get past the front." % [Progression.get_stat("trains_beaten"), Progression.get_stat("trains_raced")])
	var mystery := get_tree().root.find_child("Mystery", true, false)
	if mystery and mystery.has_method("notes"):
		_text(_leads_list, "After midnight", 18, accent)
		for line in mystery.notes():
			_text(_leads_list, line, 13 if line.begins_with("  ") else 15)
	var relaxed := CheckButton.new()
	relaxed.text = "Relaxed cruising (lighter traffic, no jobs)"
	relaxed.button_pressed = Activities.relaxed
	relaxed.toggled.connect(func(on: bool) -> void:
		Activities.set_relaxed(on)
		Jobs.refresh_offers())
	_leads_list.add_child(relaxed)


func _refresh_stats() -> void:
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	var lines := PackedStringArray()
	lines.append("Money: $%s   (earned $%s all up)" % [_number(Wallet.balance), _number(Wallet.total_earned)])
	lines.append("Day %d, %s" % [GameClock.day, GameClock.time_string()])
	lines.append("Places discovered: %d" % Progression.get_stat("discoveries"))
	lines.append("500 badges found: %d of %d" % [Collectible.found_count(), Collectible.TOTAL])
	lines.append("Driven in all: %s km" % _number(Progression.get_stat("km_driven")))
	var next := Progression.next_mileage_reward()
	if not next.is_empty():
		lines.append("Next mileage reward at %s km: %s" % [_number(next.km), next.title])
	lines.append("Deliveries: %d" % Progression.get_stat("deliveries"))
	if car:
		var stats := car.get_stats()
		lines.append("")
		var info := CarCatalogue.get_car(car.car_id)
		lines.append("%s (%s), %.0f km on the clock" % [info.get("name", car.car_id), info.get("years", ""), car.odometer_km])
		lines.append("%.0f kW, %.0f Nm, %.0f kg" % [stats.power_kw, stats.torque_nm, stats.mass_kg])
		if car.is_electric:
			lines.append("Battery %.1f of %d kWh" % [car.fuel_litres, roundi(car.tank_litres)])
		else:
			lines.append("Fuel %.1f of %d L, unleaded $%.2f today (%s)" % [
				car.fuel_litres, roundi(car.tank_litres), Garage.fuel_price(), Garage.weekday()])
		for part in car.parts.values():
			lines.append("  %s" % part.display_name)
	_stats_label.text = "\n".join(lines)
	if _roadside:
		_roadside.visible = car != null and car.fuel_litres < 1.0


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
