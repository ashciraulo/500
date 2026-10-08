extends CanvasLayer
## The player's phone: the job board, career progress and a few stats.
## Tab / X (gamepad) opens and closes it. The game pauses while it's open.

var _panel: PanelContainer
var _dim: ColorRect
var _tabs: TabContainer
var _jobs_list: VBoxContainer
var _progress_list: VBoxContainer
var _leads_list: VBoxContainer
var _stats_box: VBoxContainer
var _close: Button
var _roadside: Button
var _clock: Label


func _ready() -> void:
	layer = 9
	add_to_group(&"phone")  # Notices watches for it opening
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
	_dim = UiStyle.backdrop()
	root.add_child(_dim)

	# The handset: a dark bezel round a cream screen.
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	UiStyle.animate(_panel)
	var bezel := UiStyle.box(UiStyle.NIGHT, UiStyle.INK, 3, 34, 12)
	bezel.content_margin_top = 14
	bezel.content_margin_bottom = 22
	bezel.shadow_color = UiStyle.SHADOW
	bezel.shadow_offset = Vector2(6, 8)
	bezel.shadow_size = 1
	_panel.add_theme_stylebox_override("panel", bezel)
	root.add_child(_panel)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PAPER, Color.TRANSPARENT, 0, 22, 14))
	_panel.add_child(screen)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 600)
	box.add_theme_constant_override("separation", 8)
	screen.add_child(box)
	# Status bar: the time, then signal and battery.
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_clock = UiStyle.label(bar, "", "", 13)
	_clock.add_theme_font_override("font", UiStyle.BOLD_FONT)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var network := UiStyle.label(bar, "4G", "", 12)
	network.add_theme_font_override("font", UiStyle.BOLD_FONT)
	network.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(UiStyle.icon_rect("signal", 16))
	bar.add_child(UiStyle.icon_rect("battery", 16, UiStyle.INK, UiStyle.GOOD))
	var head: Array = UiStyle.header(box, "Phone", "phone", "Jobs, leads and how you're going", "Close")
	_close = head[2]
	_close.pressed.connect(toggle)
	# The full map, for gamepads (keyboards have M).
	var map := Button.new()
	map.text = "Map"
	map.icon = UiStyle.icon("pin", 18, UiStyle.INK, Vector2.ZERO, UiStyle.TEAL)
	map.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	map.pressed.connect(func() -> void:
		var map_screen := get_tree().get_first_node_in_group(&"map_screen")
		if map_screen:
			toggle()
			map_screen.open())
	(head[3] as HBoxContainer).add_child(map)
	(head[3] as HBoxContainer).move_child(map, _close.get_index())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_jobs_list = _scroll_tab("Jobs")
	_progress_list = _scroll_tab("Progress")
	_leads_list = _scroll_tab("Leads & fun")
	var stats_tab := _scroll_tab("Car & stats")
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	stats_tab.add_child(_stats_box)
	_roadside = Button.new()
	_roadside.text = "Call roadside assist ($%d, brings %d L)" % [Garage.ROADSIDE_PRICE, Garage.ROADSIDE_LITRES]
	_roadside.theme_type_variation = &"PrimaryButton"
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
	_clock.text = GameClock.time_string()
	_refresh_jobs()
	_refresh_progress()
	_refresh_leads()
	_refresh_stats()


func _refresh_jobs() -> void:
	_clear(_jobs_list)
	if not Jobs.active.is_empty():
		_text(_jobs_list, "Current job", 18, UiStyle.TEAL)
		_text(_jobs_list, Jobs.objective_text())
		var abandon := Button.new()
		abandon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		abandon.text = "Drop this job"
		abandon.pressed.connect(func() -> void:
			Jobs.abandon()
			_refresh())
		_jobs_list.add_child(abandon)
		_jobs_list.add_child(HSeparator.new())
	_text(_jobs_list, "On offer", 18, UiStyle.TEAL)
	if Jobs.offers.is_empty():
		_text(_jobs_list, "Nothing going right now. Check back later.", 15, UiStyle.INK_2)
	for job in Jobs.offers:
		_offer(job)


## One job on offer: what it is in bold, where from and to, the details small,
## and the pay by the button.
func _offer(job: Dictionary) -> void:
	var well := PanelContainer.new()
	well.theme_type_variation = &"WellPanel"
	_jobs_list.add_child(well)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	well.add_child(row)
	var is_trial: bool = not job.get("lift", false) and job.get("type", "") != "delivery"
	row.add_child(UiStyle.icon_rect("flag" if is_trial else ("pin" if job.get("lift", false) else "car"), 24, UiStyle.INK, UiStyle.TEAL))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := ""
	var route := ""
	var details := PackedStringArray()
	if is_trial:
		title = String(job.title)
		route = "For %s" % Jobs.CLASS_NAMES.get(job.get("class", "t0"), "any car")
		details.append("%d checkpoints" % (job.route.size() - 1))
		details.append("%.1f km" % float(job.km))
		details.append("gold %s" % Jobs._clock(job.medal_times.gold))
		var record: Dictionary = Jobs.trial_records.get(job.trial_id, {})
		if record.has("best"):
			details.append("your best %s" % Jobs._clock(record.best))
	else:
		var cargo := String(job.cargo).get_slice(",", 0)
		title = ("Lift: %s" if job.get("lift", false) else "%s") % cargo
		title = title.left(1).to_upper() + title.substr(1)
		route = "%s  to  %s" % [_place(job.pickup), _place(job.dropoff)]
		details.append("%.1f km" % float(job.km))
		if job.get("fragile", false):
			details.append("fragile")
		var bonus := Jobs.weather_bonus()
		if not job.get("lift", false) and bonus > 1.0:
			details.append("+%d%% in this weather" % roundi((bonus - 1.0) * 100.0))
	UiStyle.label(text, title).add_theme_font_override("font", UiStyle.BOLD_FONT)
	UiStyle.label(text, route, "", 14, UiStyle.INK_2)
	var line := "  ·  ".join(details)
	UiStyle.label(text, line.left(1).to_upper() + line.substr(1), "NoteLabel", 13)
	if not is_trial:
		var pay := UiStyle.label(row, "$%s" % _number(int(job.pay)), "", 18)
		pay.add_theme_font_override("font", UiStyle.BOLD_FONT)
		pay.autowrap_mode = TextServer.AUTOWRAP_OFF
		pay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var take := Button.new()
	take.text = "Take it"
	take.pressed.connect(func() -> void:
		Jobs.accept(job)
		toggle())
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(take)


func _place(id: String) -> String:
	var s: Variant = Jobs.site(id)
	return String(s.label()) if s else id


func _refresh_progress() -> void:
	_clear(_progress_list)
	var tier := Progression.current_tier()
	if tier.is_empty():
		_text(_progress_list, "Every tier done. Perth is yours; just drive.")
		return
	_text(_progress_list, "Tier %d: %s" % [Progression.tier_index + 1, tier.title], 18, UiStyle.TEAL)
	_text(_progress_list, tier.blurb)
	var next_cars := Progression.cars_unlocked_at(Progression.tier_index + 1)
	if not next_cars.is_empty():
		var names := PackedStringArray()
		for car in next_cars:
			names.append("%s ($%s)" % [car.name, _number(car.price)])
		_text(_progress_list, "Unlocks at the car yard: %s" % ", ".join(names), 14, UiStyle.RED)
	for challenge in tier.challenges:
		var done := Progression.is_done(challenge)
		var value := Progression.get_stat(challenge.stat)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(UiStyle.icon_rect("check_on" if done else "check_off", 22, UiStyle.INK, UiStyle.GOOD))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(row)
		var title := UiStyle.label(row, challenge.title)
		title.add_theme_font_override("font", UiStyle.BOLD_FONT)
		UiStyle.label(row, "%s  (%s of %s)" % [challenge.description,
			_number(minf(value, challenge.target)), _number(challenge.target)], "NoteLabel")
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = Progression.progress(challenge)
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		row.add_child(bar)
		_progress_list.add_child(line)


func _refresh_leads() -> void:
	_clear(_leads_list)
	var leads := Classics.open_leads()
	_text(_leads_list, "Barn finds  ·  %d of %d" % [Classics.found_count(), Classics.barn_finds().size()], 18)
	if leads.is_empty():
		_text(_leads_list, "No whispers yet. Try the Roe Street meet on Friday or Saturday night.", 14, UiStyle.INK_2)
	for lead: Dictionary in leads:
		var car := CarCatalogue.get_car(lead.car)
		_rumour(_leads_list, String(lead.rumour), "%s. Probably a %s." % [String(lead.where).left(1).to_upper() + String(lead.where).substr(1), car.get("name", "classic")])

	var parts := FoundPart.entries()
	var found := 0
	for entry: Dictionary in parts:
		if Discoveries.has("part/" + String(entry.part)):
			found += 1
	_text(_leads_list, "Rare parts  ·  %d of %d" % [found, parts.size()], 18)
	for entry: Dictionary in parts:
		if not Discoveries.has("part/" + String(entry.part)):
			_rumour(_leads_list, String(entry.get("rumour", "")), "")

	var cuttings := HomeLife.cutting_entries()
	var taken := 0
	for entry: Dictionary in cuttings:
		if Discoveries.has("cutting/" + String(entry.id)):
			taken += 1
	_text(_leads_list, "Cuttings  ·  %d of %d" % [taken, cuttings.size()], 18)
	for entry: Dictionary in cuttings:
		if not Discoveries.has("cutting/" + String(entry.id)):
			_rumour(_leads_list, String(entry.get("rumour", "")), "")
	_text(_leads_list, "Take one from the plant, then water it at home each day.", 14, UiStyle.INK_2)

	_text(_leads_list, "Out and about", 18)
	var golds := 0
	for record: Dictionary in Activities.parking.values():
		if record.get("medal", "") == "gold":
			golds += 1
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_leads_list.add_child(grid)
	for row: Array in [
		["camera", "Photo spots", "%d of %d" % [Activities.photo_spots_found(), Activities.PHOTO_SPOTS_TOTAL], "Blue PHOTO signs, then P · %d in the album" % Activities.photos.size()],
		["car", "Parking", "%d gold" % golds, "Yellow PARK signs"],
		["flag", "Scenic drives", str(Progression.get_stat("scenic_drives")), "Green SCENIC DRIVE signs"],
		["pin", "Lifts given", str(Progression.get_stat("lifts_given")), "On the job board"],
		["star", "Trains beaten", "%d of %d" % [Progression.get_stat("trains_beaten"), Progression.get_stat("trains_raced")], "Get past the front of one"],
	]:
		grid.add_child(UiStyle.icon_rect(row[0], 22, UiStyle.INK, UiStyle.TEAL))
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", -2)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(names)
		UiStyle.label(names, row[1]).add_theme_font_override("font", UiStyle.BOLD_FONT)
		UiStyle.label(names, row[3], "NoteLabel", 13)
		var value := UiStyle.label(grid, row[2])
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var mystery := get_tree().root.find_child("Mystery", true, false)
	if mystery and mystery.has_method("notes"):
		_text(_leads_list, "After midnight", 18)
		for line in mystery.notes():
			_text(_leads_list, line, 13 if line.begins_with("  ") else 15)
	var relaxed := CheckButton.new()
	relaxed.text = "Relaxed cruising: lighter traffic, no jobs"
	relaxed.button_pressed = Activities.relaxed
	relaxed.toggled.connect(func(on: bool) -> void:
		Activities.set_relaxed(on)
		Jobs.refresh_offers())
	_leads_list.add_child(relaxed)


## Something someone said, in pencil, with a printed note under it.
func _rumour(parent: Control, said: String, note: String) -> void:
	var well := PanelContainer.new()
	well.theme_type_variation = &"WellPanel"
	parent.add_child(well)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	well.add_child(box)
	var hand := UiStyle.label(box, "\"%s\"" % said, "HandLabel", 21)
	hand.add_theme_color_override("font_color", UiStyle.INK)
	if note != "":
		UiStyle.label(box, note, "NoteLabel", 13)


func _refresh_stats() -> void:
	_clear(_stats_box)
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	_text(_stats_box, "You", 18)
	var rows := [
		["Money", "$%s" % _number(Wallet.balance)],
		["Earned all up", "$%s" % _number(Wallet.total_earned)],
		["Driven", "%s km" % _number(Progression.get_stat("km_driven"))],
		["Deliveries", str(Progression.get_stat("deliveries"))],
		["Places found", str(Progression.get_stat("discoveries"))],
		["500 badges", "%d of %d" % [Collectible.found_count(), Collectible.TOTAL]],
	]
	var next := Progression.next_mileage_reward()
	if not next.is_empty():
		rows.append(["At %s km" % _number(next.km), next.title])
	_stat_rows(rows)
	if car:
		var stats := car.get_stats()
		var info := CarCatalogue.get_car(car.car_id)
		_text(_stats_box, String(info.get("name", car.car_id)), 18)
		var car_rows := [
			["Odometer", "%s km" % _number(car.odometer_km)],
			["Power", "%.0f kW, %.0f Nm" % [stats.power_kw, stats.torque_nm]],
			["Weight", "%.0f kg" % stats.mass_kg],
		]
		if car.is_electric:
			car_rows.append(["Battery", "%.1f of %d kWh" % [car.fuel_litres, roundi(car.tank_litres)]])
		else:
			car_rows.append(["Fuel", "%.1f of %d L" % [car.fuel_litres, roundi(car.tank_litres)]])
			car_rows.append(["Unleaded today", "$%.2f a litre" % Garage.fuel_price()])
		_stat_rows(car_rows)
		var fitted := PackedStringArray()
		for part in car.parts.values():
			fitted.append(part.display_name)
		if not fitted.is_empty():
			_text(_stats_box, "Fitted: " + ", ".join(fitted), 13, UiStyle.INK_2)
	if _roadside:
		_roadside.visible = car != null and car.fuel_litres < 1.0


func _stat_rows(rows: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	_stats_box.add_child(grid)
	for row: Array in rows:
		var key := UiStyle.label(grid, row[0])
		key.add_theme_color_override("font_color", UiStyle.INK_2)
		key.custom_minimum_size.x = 150
		var value := UiStyle.label(grid, row[1])
		value.add_theme_font_override("font", UiStyle.BOLD_FONT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _text(parent: Control, text: String, size := 15, color := UiStyle.INK) -> void:
	if size >= 18:  # a heading
		if parent.get_child_count() > 0:
			var gap := Control.new()
			gap.custom_minimum_size.y = 4
			parent.add_child(gap)
		UiStyle.section(parent, text, UiStyle.RED if color == UiStyle.TEAL else color)
		return
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
