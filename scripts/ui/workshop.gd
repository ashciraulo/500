extends CanvasLayer
## The workshop screen: buy and fit parts, tune the setup, respray the car.
## Pull up in a WorkshopSpot bay, stop, and press F / A. What's on offer
## depends on the spot: your carport does parts and tuning, the spray shop
## paint, servos fuel and the car wash. The game pauses while it's open.

const ACCENT := Color(0.6, 0.85, 0.8)
const SLOT_NAMES := {
	"engine": "Engine", "intake": "Intake", "exhaust": "Exhaust", "gearbox": "Gearbox",
	"suspension": "Suspension", "tyres": "Tyres", "wheels": "Wheels", "brakes": "Brakes",
	"weight": "Weight", "roof": "Roof", "lights": "Driving lights",
}
## Tab order; a spot shows the tabs for its kinds.
## "cars" lets you swap between cars you own; "dealer" also sells them.
## "extras" (trinkets and liveries you've earned) shows wherever parts,
## paint or your cars are.
const TAB_KINDS := ["parts", "tuning", "service", "paint", "fuel", "wash", "cars", "restore", "extras"]
const SLOT_TITLES := {"mirror": "Mirror", "dash": "Dash", "shelf": "Parcel shelf", "gear": "Gear lever"}
const PLACE_NAMES := {"parts": "workshop", "tuning": "workshop", "paint": "paint booth",
	"dealer": "car yard", "cars": "garage", "restore": "restoration bench",
	"fuel": "servo", "wash": "car wash"}
## Below this speed (km/h) the prompt shows and the workshop opens.
const STOP_SPEED_KMH := 5.0
## A tap of F opens the workshop on release; holding it longer gets out of the car.
const TAP_SECONDS := 0.4

var _car: CarController
var _spot: WorkshopSpot
var _prompt: Label
var _panel: PanelContainer
var _dim: ColorRect
var _title: Label
var _money: Label
var _tabs: TabContainer
var _parts_list: VBoxContainer
var _tuning_list: VBoxContainer
var _paint_list: VBoxContainer
var _fuel_list: VBoxContainer
var _wash_list: VBoxContainer
var _service_list: VBoxContainer
var _cars_list: VBoxContainer
var _restore_list: VBoxContainer
var _extras_list: VBoxContainer
var _car_name: Label
var _stats: GridContainer
var _change: Label
var _close: Button
var _check_timer := 0.0
var _press_ms := -1


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_open(false)


func _process(delta: float) -> void:
	if _panel.visible:
		return
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.2
		_spot = _find_spot()
	_prompt.visible = _spot != null and not get_tree().paused
	if _prompt.visible:
		_prompt.text = "%s\nF / A: use the %s" % [_spot.display_name,
			PLACE_NAMES.get(_spot.kinds[0] if not _spot.kinds.is_empty() else "parts", "workshop")]


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif not _panel.visible and _spot and not get_tree().paused:
		if event.is_action_pressed("interact"):
			_press_ms = Time.get_ticks_msec()
		elif event.is_action_released("interact") and _press_ms >= 0:
			if Time.get_ticks_msec() - _press_ms < TAP_SECONDS * 1000.0:
				open(_spot)
				get_viewport().set_input_as_handled()
			_press_ms = -1


## Open the workshop for a spot (the smoke test calls this directly).
func open(spot: WorkshopSpot) -> void:
	_spot = spot
	_car = get_tree().get_first_node_in_group(&"player_car") as CarController
	if _car == null:
		return
	_set_open(true)


func close() -> void:
	_set_open(false)


func is_open() -> bool:
	return _panel.visible


func _find_spot() -> WorkshopSpot:
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	if car == null or not car.player_controlled or car.speed_kmh() > STOP_SPEED_KMH:
		return null
	for spot in get_tree().get_nodes_in_group(&"workshop_spots"):
		if (spot as WorkshopSpot).contains(car.global_position):
			return spot
	return null


func _set_open(open_it: bool) -> void:
	_panel.visible = open_it
	_dim.visible = open_it
	_prompt.visible = false
	if not open_it:
		if is_inside_tree() and get_tree().paused:
			get_tree().paused = false
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = _spot.display_name
	_change.text = ""
	for i in TAB_KINDS.size():
		var shown: bool = _spot.offers(TAB_KINDS[i]) or (TAB_KINDS[i] == "cars" and _spot.offers("dealer")) \
			or (TAB_KINDS[i] == "service" and _spot.offers("parts")) \
			or (TAB_KINDS[i] == "extras" and (_spot.offers("parts") or _spot.offers("paint") or _spot.offers("cars")))
		_tabs.set_tab_hidden(i, not shown)
	for i in TAB_KINDS.size():
		if not _tabs.is_tab_hidden(i):
			_tabs.current_tab = i
			break
	_refresh()
	_close.grab_focus()


# --- Building the screen -----------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -170
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", ACCENT)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	root.add_child(_prompt)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.07, 0.96)
	style.border_color = Color(0.85, 0.65, 0.4)
	style.set_border_width_all(3)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(980, 580)
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 18)
	_money.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	header.add_child(_money)
	var gap := Control.new()
	gap.custom_minimum_size.x = 16
	header.add_child(gap)
	_close = Button.new()
	_close.text = "Done"
	_close.pressed.connect(close)
	header.add_child(_close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	box.add_child(body)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_tabs)
	_parts_list = _scroll_tab("Parts")
	_tuning_list = _scroll_tab("Tuning")
	_service_list = _scroll_tab("Service")
	_paint_list = _scroll_tab("Paint")
	_fuel_list = _scroll_tab("Fuel")
	_wash_list = _scroll_tab("Wash")
	_cars_list = _scroll_tab("Cars")
	_restore_list = _scroll_tab("Restore")
	_extras_list = _scroll_tab("Extras")

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 270
	side.add_theme_constant_override("separation", 10)
	body.add_child(side)
	var heading := Label.new()
	_car_name = heading
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", ACCENT)
	side.add_child(heading)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 14)
	side.add_child(_stats)
	_change = Label.new()
	_change.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_change.add_theme_color_override("font_color", Color(0.75, 0.95, 0.6))
	side.add_child(_change)


func _scroll_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


# --- Contents ----------------------------------------------------------------

func _refresh() -> void:
	_money.text = "$%s   %s" % [_number(Wallet.balance), GameClock.time_string()]
	_refresh_stats()
	_refresh_parts()
	_refresh_tuning()
	_refresh_service()
	_refresh_paint()
	_refresh_fuel()
	_refresh_wash()
	_refresh_cars()
	_refresh_restore()
	_refresh_extras()


func _refresh_stats() -> void:
	_car_name.text = CarCatalogue.get_car(_car.car_id).get("name", "Your car")
	var s := _car.get_stats()
	_clear(_stats)
	for row in [
		["Power", "%d kW" % roundi(s.power_kw)],
		["Torque", "%d Nm" % roundi(s.torque_nm)],
		["Weight", "%d kg" % roundi(s.mass_kg)],
		["Grip", "%.2f" % s.grip],
		["Brakes", "%d" % roundi(s.brake_force)],
		["Red line", "%d rpm" % roundi(s.limiter_rpm)],
		["Final drive", "%.2f" % s.final_drive],
		["Paint", _paint_name()],
		["Odometer", "%s km" % _number(_car.odometer_km)],
		["Charge" if _car.is_electric else "Fuel", "%.1f / %d %s" % [_car.fuel_litres, roundi(_car.tank_litres),
			"kWh" if _car.is_electric else "L"]],
		["Dirt", _dirt_text()],
	]:
		var key := Label.new()
		key.text = row[0]
		key.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68))
		_stats.add_child(key)
		var value := Label.new()
		value.text = row[1]
		_stats.add_child(value)


func _refresh_parts() -> void:
	_clear(_parts_list)
	for slot in PartsCatalogue.SLOTS:
		_heading(_parts_list, SLOT_NAMES.get(String(slot), String(slot).capitalize()))
		var fitted: CarPart = _car.parts.get(slot)
		var choices := PartsCatalogue.for_car(slot, _car.car_id).filter(func(p: CarPart) -> bool:
			return not p.found_only or Garage.is_found(p))
		if choices.size() <= 1 and slot in [&"roof", &"lights"]:
			_text(_parts_list, "Nothing yet. Some parts can't be bought; they turn up around the city.")
			continue
		for part: CarPart in choices:
			var is_fitted := (fitted == null and part.is_stock()) or (fitted != null and fitted.id == part.id)
			var owned := Garage.owns(part, _car)
			var row := HBoxContainer.new()
			var text := VBoxContainer.new()
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var name_label := Label.new()
			name_label.text = part.display_name + ("" if owned else "   $%s" % _number(part.price))
			text.add_child(name_label)
			var desc := Label.new()
			desc.text = part.description
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.add_theme_font_size_override("font_size", 13)
			desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68))
			text.add_child(desc)
			row.add_child(text)
			var button := Button.new()
			button.custom_minimum_size.x = 150
			if is_fitted:
				button.text = "Fitted"
				button.disabled = true
			elif owned:
				button.text = "Fit (%s h)" % _hours(Garage.FIT_HOURS.get(String(slot), 1.0))
			else:
				button.text = "Buy and fit"
				button.disabled = not Wallet.can_afford(part.price)
			button.pressed.connect(_fit.bind(part))
			row.add_child(button)
			_parts_list.add_child(row)


func _refresh_tuning() -> void:
	_clear(_tuning_list)
	_text(_tuning_list, "Small tweaks, free to try. Some need the right parts fitted first.")
	var ids := _car.get_part_ids()
	for o in CarTuning.OPTIONS:
		var available := CarTuning.is_available(o, ids)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = o.label
		label.custom_minimum_size.x = 170
		row.add_child(label)
		var low := Label.new()
		low.text = o.low
		low.custom_minimum_size.x = 100
		low.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		low.add_theme_font_size_override("font_size", 13)
		row.add_child(low)
		var slider := HSlider.new()
		slider.min_value = o.min
		slider.max_value = o.max
		slider.step = o.step
		slider.value = float(_car.tuning.get(o.key, o.default))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.editable = available
		slider.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
		var key: String = o.key
		slider.value_changed.connect(func(v: float) -> void: _tune(key, v))
		row.add_child(slider)
		var high := Label.new()
		high.text = o.high if available else "needs %s" % _needs_text(o)
		high.custom_minimum_size.x = 170
		high.add_theme_font_size_override("font_size", 13)
		if not available:
			high.add_theme_color_override("font_color", Color(0.85, 0.55, 0.45))
		row.add_child(high)
		_tuning_list.add_child(row)
	var reset := Button.new()
	reset.text = "Back to the default setup"
	reset.pressed.connect(func() -> void:
		_car.set_tuning({})
		_refresh())
	_tuning_list.add_child(reset)


func _refresh_paint() -> void:
	_clear(_paint_list)
	_text(_paint_list, "A full respray takes most of a day (%s h) and covers the sun-faded paint for good." % _hours(Garage.RESPRAY_HOURS))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_paint_list.add_child(grid)
	for i in Garage.PAINTS.size():
		var paint: Array = Garage.PAINTS[i]
		var button := Button.new()
		button.text = "%s\n$%s" % [paint[0], _number(paint[2])]
		button.custom_minimum_size = Vector2(200, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var swatch := StyleBoxFlat.new()
		swatch.bg_color = Color(0.15, 0.14, 0.13)
		swatch.border_color = paint[1]
		swatch.border_width_left = 26
		swatch.set_border_width(SIDE_TOP, 2)
		swatch.set_border_width(SIDE_BOTTOM, 2)
		swatch.set_border_width(SIDE_RIGHT, 2)
		swatch.content_margin_left = 34
		var hover := swatch.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.28, 0.26, 0.22)
		button.add_theme_stylebox_override("normal", swatch)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("focus", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("disabled", swatch)
		var current := _car.has_custom_paint() and _car.paint_color.is_equal_approx(Color(paint[1], 1.0))
		button.disabled = current or not Wallet.can_afford(paint[2])
		if current:
			button.text = "%s\nYour colour" % paint[0]
		button.pressed.connect(_respray.bind(i))
		grid.add_child(button)


func _refresh_fuel() -> void:
	_clear(_fuel_list)
	var price := Garage.fuel_price(_car)
	var unit := "kWh" if _car.is_electric else "litres"
	if _car.is_electric:
		_heading(_fuel_list, "Fast charger   $%.2f a kWh" % price)
		_text(_fuel_list, "Plug in and grab a coffee while it charges.")
	else:
		var cheapest: float = Garage.FUEL_PRICES.min()
		var note := "cheap day" if is_equal_approx(price, cheapest) else (
			"prices jumped today" if price >= 2.0 else "")
		_heading(_fuel_list, "Unleaded 91   $%.2f a litre" % price)
		_text(_fuel_list, "%s%s. Prices here run on a weekly cycle." % [Garage.weekday(),
			(", " + note) if note != "" else ""])
	var gauge := ProgressBar.new()
	gauge.max_value = 1.0
	gauge.value = _car.fuel_fraction()
	gauge.show_percentage = false
	gauge.custom_minimum_size.y = 14
	_fuel_list.add_child(gauge)
	_text(_fuel_list, "%.1f of %d %s in the %s." % [_car.fuel_litres, roundi(_car.tank_litres), unit,
		"battery" if _car.is_electric else "tank"])
	var space := _car.tank_litres - _car.fuel_litres
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_fuel_list.add_child(row)
	var fill := Button.new()
	fill.text = "%s  ($%d)" % ["Charge it up" if _car.is_electric else "Fill it up", Garage.fuel_cost(space, _car)]
	fill.disabled = space < 0.1 or Wallet.balance < 1
	fill.pressed.connect(_buy_fuel.bind(INF))
	row.add_child(fill)
	for dollars in [20, 50]:
		var button := Button.new()
		button.text = "$%d worth" % dollars
		button.disabled = space < 0.1 or not Wallet.can_afford(dollars)
		button.pressed.connect(_buy_fuel.bind(dollars / price))
		row.add_child(button)


func _refresh_cars() -> void:
	_clear(_cars_list)
	_heading(_cars_list, "Your cars")
	for id in Garage.owned_cars:
		var car := CarCatalogue.get_car(id)
		var row := HBoxContainer.new()
		var label := Label.new()
		var km: float = _car.odometer_km if id == _car.car_id else float(Garage.cars.get(id, {}).get("odometer_km", 0.0))
		label.text = "%s (%s)   %s km" % [car.name, car.years, _number(km)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size.x = 170
		if id == _car.car_id:
			button.text = "Driving it"
			button.disabled = true
		elif not CarCatalogue.is_drivable(car) or not Classics.can_drive(id):
			button.text = "Needs restoring"
			button.disabled = true
		else:
			button.text = "Take this one"
		button.pressed.connect(func() -> void:
			Garage.switch_car(id, _car)
			_change.text = "Swapped into the %s." % car.name
			_refresh_after_action())
		row.add_child(button)
		_cars_list.add_child(row)
	if not _spot.offers("dealer"):
		_text(_cars_list, "New cars come from the car yard once your career opens them up.")
		return
	for tier in range(0, 5):
		var for_sale := CarCatalogue.for_sale().filter(func(c: Dictionary) -> bool: return int(c.tier) == tier)
		if for_sale.is_empty():
			continue
		_heading(_cars_list, "Tier %d%s" % [tier + 1, "" if Progression.tier_index >= tier else "   (locked)"])
		for car in for_sale:
			var row := HBoxContainer.new()
			var text := VBoxContainer.new()
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var name_label := Label.new()
			name_label.text = "%s (%s)   %d kW   $%s" % [car.name, car.years, car.power_kw, _number(car.price)]
			text.add_child(name_label)
			var blurb := Label.new()
			blurb.text = car.blurb
			blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			blurb.add_theme_font_size_override("font_size", 13)
			blurb.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68))
			text.add_child(blurb)
			row.add_child(text)
			var button := Button.new()
			button.custom_minimum_size.x = 170
			var blocker := Garage.car_blocker(car.id)
			button.text = "Buy it" if blocker == "" else blocker[0].to_upper() + blocker.substr(1)
			button.disabled = blocker != ""
			var id: String = car.id
			button.pressed.connect(func() -> void:
				if Garage.buy_car(id, _car):
					_change.text = "Bought the %s. Your old car's waiting at home." % CarCatalogue.get_car(id).name
				_refresh_after_action())
			row.add_child(button)
			_cars_list.add_child(row)


func _refresh_restore() -> void:
	_clear(_restore_list)
	if Classics.projects.is_empty():
		_heading(_restore_list, "Restoration bench")
		_text(_restore_list, "Nothing on the bench. Classic 500s turn up as rumours: at the Friday and Saturday night meet, and as your career grows. Find the wreck and it comes here.")
	for id: String in Classics.projects:
		var car := CarCatalogue.get_car(id)
		_heading(_restore_list, "%s (%s)  %d%% restored%s" % [car.get("name", id), car.get("years", ""),
			roundi(Classics.condition(id) * 100.0), "" if Classics.can_drive(id) else "  (not driveable yet)"])
		var next := Classics.next_stage(id)
		for stage: Dictionary in Classics.stages():
			var done := Classics.is_stage_done(id, stage.id)
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = "%s %s%s" % ["[done]" if done else "[    ]", stage.title, "" if done else "   $%s, %s" % [_number(Classics.stage_price(id, stage)), _hours(stage.hours) + " h work"]]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.62) if done else Color.WHITE)
			row.add_child(label)
			if not done and not next.is_empty() and next.id == stage.id:
				var button := Button.new()
				button.custom_minimum_size.x = 170
				button.text = "Do it"
				button.disabled = Wallet.balance < Classics.stage_price(id, stage)
				var stage_id: String = stage.id
				button.pressed.connect(func() -> void:
					if Classics.do_stage(id, stage_id):
						_change.text = stage.text
						_car.apply_paint_refresh()
					_refresh_after_action())
				row.add_child(button)
			_restore_list.add_child(row)
		if next.is_empty() and not Classics.is_restored(id):
			_text(_restore_list, "Every stage done. How do you want it?")
			for kind: String in Classics.finishes():
				var f: Dictionary = Classics.finishes()[kind]
				var row := HBoxContainer.new()
				var label := Label.new()
				var price := roundi(float(f.price) * Classics.cost_scale(id))
				label.text = "%s: %s   $%s" % [f.title, f.text, _number(price)]
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(label)
				var button := Button.new()
				button.custom_minimum_size.x = 170
				button.text = "Finish it"
				button.disabled = Wallet.balance < price
				button.pressed.connect(func() -> void:
					if Classics.choose_finish(id, kind):
						_car.apply_paint_refresh()
						_change.text = "The %s is finished: %s." % [car.get("name", id), f.title.to_lower()]
					_refresh_after_action())
				row.add_child(button)
				_restore_list.add_child(row)
		elif Classics.is_restored(id):
			_text(_restore_list, "Finished: %s." % Classics.finishes()[Classics.finish(id)].title)


func _refresh_extras() -> void:
	_clear(_extras_list)
	var liveries := Progression.earned_cosmetics("livery")
	var trinkets := Progression.earned_cosmetics("trinket")
	if liveries.is_empty() and trinkets.is_empty():
		_heading(_extras_list, "Extras")
		_text(_extras_list, "Nothing yet. Trinkets and liveries come from kilometres on the clock and nights at the car meet. Next at %s km." % _number(float(Progression.next_mileage_reward().get("km", 0))))
		return
	_heading(_extras_list, "Livery")
	var current: String = _car.cosmetics.get("livery", "")
	for item: Dictionary in [{"id": "", "title": "None, just the paint"}] + liveries:
		var id: String = item.id
		_extras_list.add_child(_extra_row(item.title, "On" if id == current else "Use it", id == current, func() -> void:
			_car.set_livery(id)
			_change.text = "Livery: %s." % item.title.to_lower()))
	if not trinkets.is_empty():
		_heading(_extras_list, "Trinkets")
		_text(_extras_list, "One per spot: the mirror, the dash, the parcel shelf and the gear lever.")
	for item: Dictionary in trinkets:
		var id: String = item.id
		var fitted := _car.has_trinket(id)
		_extras_list.add_child(_extra_row("%s (%s)" % [item.title, SLOT_TITLES.get(item.get("slot", ""), "")],
			"Take it off" if fitted else "Fit it", false, func() -> void:
				_car.toggle_trinket(id)
				_change.text = ("Fitted: %s." if _car.has_trinket(id) else "Took off: %s.") % item.title.to_lower()))


func _extra_row(title: String, action: String, disabled: bool, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := Button.new()
	button.custom_minimum_size.x = 170
	button.text = action
	button.disabled = disabled
	button.pressed.connect(func() -> void:
		on_press.call()
		_refresh_after_action())
	row.add_child(button)
	return row


func _refresh_wash() -> void:
	_clear(_wash_list)
	_heading(_wash_list, "Drive-through wash   $%d" % Garage.WASH_PRICE)
	_text(_wash_list, "Your car is %s. Customers tip a little more when the car's clean." % _dirt_text())
	var meter := ProgressBar.new()
	meter.max_value = 1.0
	meter.value = _car.dirt
	meter.show_percentage = false
	meter.custom_minimum_size.y = 14
	_wash_list.add_child(meter)
	var button := Button.new()
	button.text = "Run it through the wash"
	button.disabled = _car.dirt < 0.02 or not Wallet.can_afford(Garage.WASH_PRICE)
	button.pressed.connect(func() -> void:
		if Garage.wash(_car):
			_change.text = "Squeaky clean."
		_refresh_after_action())
	_wash_list.add_child(button)


## Wear on the tyres, pads and oil, and a job to put each one right.
func _refresh_service() -> void:
	_clear(_service_list)
	_heading(_service_list, "Servicing")
	_text(_service_list, "Tyres wear quicker when you slide them, pads when you brake hard. Old oil takes the edge off the engine. Doing it yourself takes a while.")
	for item: String in Garage.SERVICES:
		if item == "oil" and _car.is_electric:
			continue
		var job: Array = Garage.SERVICES[item]
		var worn: float = _car.wear.get(item, 0.0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_service_list.add_child(row)
		var name_label := Label.new()
		name_label.text = "%s: %s" % [item.capitalize(), _wear_text(item, worn)]
		name_label.custom_minimum_size.x = 230
		name_label.add_theme_color_override("font_color",
			Color(1.0, 0.6, 0.45) if worn >= CarController.WEAR_DUE else Color.WHITE)
		row.add_child(name_label)
		var meter := ProgressBar.new()
		meter.max_value = 1.0
		meter.value = 1.0 - worn
		meter.show_percentage = false
		meter.custom_minimum_size = Vector2(120, 14)
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(meter)
		var button := Button.new()
		button.text = "%s   $%d, %s" % [job[0], job[1], _hours_text(job[2])]
		button.disabled = worn < 0.02 or not Wallet.can_afford(job[1])
		button.pressed.connect(func() -> void:
			if Garage.service(_car, item):
				_change.text = "%s done. It's %s now." % [job[0], GameClock.time_string()]
			_refresh_after_action())
		row.add_child(button)


	_heading(_service_list, "Service book")
	if _car.logbook.is_empty():
		_text(_service_list, "Nothing written in it yet.")
	else:
		var recent := _car.logbook.slice(maxi(0, _car.logbook.size() - 8))
		recent.reverse()
		for entry: Dictionary in recent:
			_text(_service_list, "Day %d, %s km   %s" % [int(entry.day), _number(int(entry.km)), entry.text])


func _wear_text(item: String, worn: float) -> String:
	if worn < 0.15:
		return "like new"
	if worn < 0.5:
		return "fine"
	if worn < CarController.WEAR_DUE:
		return "getting worn"
	if worn < 0.98:
		return {"tyres": "nearly bald", "brakes": "pads squealing", "oil": "overdue"}.get(item, "due")
	return {"tyres": "bald", "brakes": "metal on metal", "oil": "black sludge"}.get(item, "worn out")


func _hours_text(hours: float) -> String:
	return "%d h" % hours if is_equal_approx(hours, roundf(hours)) else "%.1f h" % hours


# --- Actions -----------------------------------------------------------------

func _fit(part: CarPart) -> void:
	var before := _car.get_stats()
	var was_owned := Garage.owns(part, _car)
	if not Garage.buy_and_fit(part, _car):
		_change.text = "Can't afford the %s yet." % part.display_name
		return
	_change.text = ("Bought and fitted" if not was_owned else "Fitted") + " the %s.\n%s" % [
		part.display_name, _delta_text(before, _car.get_stats())]
	_refresh_after_action()


func _tune(key: String, value: float) -> void:
	var tuning := _car.tuning.duplicate()
	tuning[key] = value
	_car.set_tuning(tuning)
	_refresh_stats()


func _respray(index: int) -> void:
	if Garage.respray(_car, index):
		_change.text = "Resprayed in %s." % Garage.PAINTS[index][0]
	_refresh_after_action()


func _buy_fuel(litres: float) -> void:
	var cost_before := Wallet.balance
	var added := Garage.buy_fuel(_car, litres)
	if added > 0.0:
		_change.text = "Put in %.1f L for $%d." % [added, cost_before - Wallet.balance]
	_refresh_after_action()


func _refresh_after_action() -> void:
	var tab := _tabs.current_tab
	_refresh()
	_tabs.current_tab = tab
	_close.grab_focus()


# --- Helpers -----------------------------------------------------------------

func _delta_text(before: Dictionary, after: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in [["power_kw", "kW", 0], ["torque_nm", "Nm", 0], ["mass_kg", "kg", 0],
			["grip", "grip", 2], ["brake_force", "brakes", 0]]:
		var d: float = after[item[0]] - before[item[0]]
		if absf(d) < (0.005 if item[2] > 0 else 0.5):
			continue
		var fmt := "%+." + str(item[2]) + "f %s"
		parts.append(fmt % [d, item[1]])
	return ", ".join(parts) if not parts.is_empty() else "No change on paper; you'll feel it."


func _dirt_text() -> String:
	if _car.dirt < 0.1:
		return "spotless"
	if _car.dirt < 0.3:
		return "fairly clean"
	if _car.dirt < 0.6:
		return "dusty"
	return "filthy"


func _paint_name() -> String:
	if not _car.has_custom_paint():
		return "original (faded)"
	for paint in Garage.PAINTS:
		if _car.paint_color.is_equal_approx(Color(paint[1], 1.0)):
			return paint[0]
	return "custom"


func _needs_text(o: Dictionary) -> String:
	var names := PackedStringArray()
	for id in o.needs:
		var part := PartsCatalogue.get_part(id)
		names.append(part.display_name.to_lower() if part else id)
	return " or ".join(names)


func _heading(parent: Control, text: String) -> void:
	parent.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", ACCENT)
	parent.add_child(label)


func _text(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.78))
	parent.add_child(label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func _hours(h: float) -> String:
	return str(int(h)) if is_equal_approx(h, roundf(h)) else "%.1f" % h


static func _number(value: float) -> String:
	var text := str(roundi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return text + out
