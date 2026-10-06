extends CanvasLayer
## The workshop screen: buy and fit parts, tune the setup, respray the car.
## Pull up in a WorkshopSpot bay, stop, and press F / A. What's on offer
## depends on the spot: your carport does parts and tuning, the spray shop
## paint, servos fuel and the car wash. The game pauses while it's open.

const ACCENT := UiStyle.RED
const SLOT_NAMES := {
	"engine": "Engine", "intake": "Intake", "exhaust": "Exhaust", "gearbox": "Gearbox",
	"flywheel": "Flywheel", "diff": "Differential", "anti_roll": "Anti-roll bars",
	"suspension": "Suspension", "tyres": "Tyres", "wheels": "Wheels", "brakes": "Brakes",
	"weight": "Weight", "roof": "Roof", "lights": "Driving lights",
	"rear_rack": "Engine lid", "bumpers": "Bumpers", "towbar": "Tow bar", "mudflaps": "Mud flaps",
	"steering_wheel": "Steering wheel", "gear_knob": "Gear knob", "seat_covers": "Seat covers",
	"plate": "Number plate",
}
## Tab order; a spot shows the tabs for its kinds.
## "cars" lets you swap between cars you own; "dealer" also sells them.
## "extras" (trinkets and liveries you've earned) shows wherever parts,
## paint or your cars are.
const TAB_KINDS := ["parts", "tuning", "service", "paint", "fuel", "wash", "cars", "restore", "extras"]
const SLOT_TITLES := {"mirror": "Mirror", "dash": "Dash", "shelf": "Parcel shelf", "gear": "Gear lever", "glovebox": "Glovebox"}
const PLACE_NAMES := {"parts": "workshop", "tuning": "workshop", "paint": "paint booth",
	"dealer": "car yard", "cars": "garage", "restore": "restoration bench",
	"fuel": "servo", "wash": "car wash"}
## Below this speed (km/h) the prompt shows and the workshop opens.
const STOP_SPEED_KMH := 5.0
## A tap of F opens the workshop on release; holding it longer gets out of the car.
const TAP_SECONDS := 0.4

var _car: CarController
var _spot: WorkshopSpot
var _prompt: PromptChip
var _panel: PanelContainer
var _dim: ColorRect
var _title: Label
var _money: Label
var _tabs: TabContainer
var _parts_list: VBoxContainer
var _tuning_list: VBoxContainer
var _paint_list: VBoxContainer
## The spray shop's livery picks, kept while the screen is open.
var _livery_colour := 0
var _livery_number := 5
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

	_prompt = PromptChip.new()
	_prompt.place_bottom(112.0)
	root.add_child(_prompt)

	_dim = UiStyle.backdrop()
	root.add_child(_dim)

	var card := UiStyle.centred_card(root, Vector2(1000, 590))
	_panel = card[0]
	var box: VBoxContainer = card[1]

	var head: Array = UiStyle.header(box, "", "wrench", "", "Done")
	_title = head[0]
	var header: HBoxContainer = head[3]
	_close = head[2]
	_close.pressed.connect(close)
	# Money as a little cream tag by the Done button.
	var purse := PanelContainer.new()
	purse.theme_type_variation = &"WellPanel"
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var purse_row := HBoxContainer.new()
	purse_row.add_theme_constant_override("separation", 6)
	purse.add_child(purse_row)
	purse_row.add_child(UiStyle.icon_rect("money", 20, UiStyle.INK, UiStyle.GOOD))
	_money = UiStyle.label(purse_row, "")
	_money.autowrap_mode = TextServer.AUTOWRAP_OFF
	_money.add_theme_font_override("font", UiStyle.BOLD_FONT)
	header.add_child(purse)
	header.move_child(purse, header.get_child_count() - 2)

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

	var side_panel := PanelContainer.new()
	side_panel.theme_type_variation = &"WellPanel"
	side_panel.custom_minimum_size.x = 280
	body.add_child(side_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side_panel.add_child(side)
	var heading := Label.new()
	_car_name = heading
	heading.theme_type_variation = &"TitleLabel"
	heading.add_theme_font_size_override("font_size", 22)
	side.add_child(heading)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 14)
	side.add_child(_stats)
	_change = Label.new()
	_change.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_change.add_theme_color_override("font_color", UiStyle.GOOD)
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
		key.add_theme_color_override("font_color", UiStyle.INK_2)
		_stats.add_child(key)
		var value := Label.new()
		value.text = row[1]
		_stats.add_child(value)


func _refresh_parts() -> void:
	_clear(_parts_list)
	for slot in PartsCatalogue.SLOTS:
		var fitted: CarPart = _car.parts.get(slot)
		var choices := PartsCatalogue.for_car(slot, _car.car_id).filter(func(p: CarPart) -> bool:
			return not p.found_only or Garage.is_found(p))
		# Slots this car has nothing for (a lid rack on a Pop) stay out of the list.
		if not slot in [&"roof", &"lights"] and PartsCatalogue.for_car(slot, _car.car_id).all(func(p: CarPart) -> bool: return p.is_stock()):
			continue
		_heading(_parts_list, SLOT_NAMES.get(String(slot), String(slot).capitalize()))
		if choices.size() <= 1 and slot in [&"roof", &"lights"]:
			_text(_parts_list, "Nothing yet. Some parts turn up around the city.")
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
			desc.add_theme_color_override("font_color", UiStyle.INK_2)
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
	_text(_tuning_list, "Free to fiddle with. Some need parts fitted first.")
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
			high.add_theme_color_override("font_color", UiStyle.RED)
		row.add_child(high)
		_tuning_list.add_child(row)
	_heading(_tuning_list, "Saved setups")
	_text(_tuning_list, "One for each kind of drive.")
	for i in CarController.SETUP_NAMES.size():
		var slot := i
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = CarController.SETUP_NAMES[i]
		name_label.custom_minimum_size.x = 170
		row.add_child(name_label)
		var info := Label.new()
		info.text = _setup_summary(_car.setups[i]) if _car.has_setup(i) else "Empty"
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", UiStyle.INK_2)
		row.add_child(info)
		var save := Button.new()
		save.text = "Overwrite" if _car.has_setup(i) else "Save here"
		save.pressed.connect(func() -> void:
			_car.save_setup(slot)
			_refresh())
		row.add_child(save)
		var use := Button.new()
		var in_use: bool = _car.has_setup(i) and _car.setups[i] == _car.tuning
		use.text = "In use" if in_use else "Use"
		use.disabled = not _car.has_setup(i) or in_use
		use.pressed.connect(func() -> void:
			_car.load_setup(slot)
			_refresh())
		row.add_child(use)
		_tuning_list.add_child(row)
	var reset := Button.new()
	reset.text = "Reset to standard"
	reset.pressed.connect(func() -> void:
		_car.set_tuning({})
		_refresh())
	_tuning_list.add_child(reset)
	var pad := get_tree().root.find_child("Skidpad", true, false)
	if pad:
		_heading(_tuning_list, "Skidpad")
		var mine: Dictionary = pad.best_for(String(_car.car_id))
		_text(_tuning_list, "Try the setup on the skidpad out the back." + (
			"" if mine.is_empty() else " Best: %.2f g, %.1f s a lap." % [mine.g, mine.lap]))
		var go := Button.new()
		go.text = "Take it to the skidpad"
		go.pressed.connect(func() -> void:
			close()
			pad.start(_car))
		_tuning_list.add_child(go)


## "tyre pressure soft, grippy; damping tight" style summary of a saved setup, defaults left out.
func _setup_summary(values: Dictionary) -> String:
	var bits: PackedStringArray = []
	for o in CarTuning.OPTIONS:
		if values.has(o.key) and not is_equal_approx(float(values[o.key]), float(o.default)):
			bits.append("%s %s" % [o.label.to_lower(), o.low if float(values[o.key]) < float(o.default) else o.high])
	return "; ".join(bits) if not bits.is_empty() else "Default setup"


func _refresh_paint() -> void:
	_clear(_paint_list)
	_text(_paint_list, "A full respray takes %s hours." % _hours(Garage.RESPRAY_HOURS))
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
		# A paint chip: the colour down the left, on a cream card.
		var swatch := UiStyle.box(UiStyle.PAPER_2, paint[1], 2, 8, 8)
		swatch.border_width_left = 30
		swatch.content_margin_left = 40
		var hover := swatch.duplicate() as StyleBoxFlat
		hover.bg_color = UiStyle.SUN_LIGHT
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
	_refresh_finishes()
	_refresh_liveries()


func _refresh_finishes() -> void:
	_heading(_paint_list, "Clear coat")
	_text(_paint_list, "Gloss shines in the sun and rain. Matte never does.")
	for id: String in Garage.FINISHES:
		var coat: Array = Garage.FINISHES[id]
		var on: bool = _car.finish == id
		_paint_list.add_child(_extra_row("%s   $%s, %s h" % [coat[0], _number(coat[1]), _hours(coat[2])],
			"On it now" if on else "Lay it down", on or not Wallet.can_afford(coat[1]), func() -> void:
				if Garage.apply_finish(_car, id):
					_change.text = "%s laid down." % coat[0]))


func _refresh_liveries() -> void:
	_heading(_paint_list, "Stripes and numbers")
	_text(_paint_list, "Pick a colour and a door number, then the job.")
	var colours := HBoxContainer.new()
	colours.add_theme_constant_override("separation", 6)
	_paint_list.add_child(colours)
	for i in Garage.LIVERY_COLOURS.size():
		var shade: Array = Garage.LIVERY_COLOURS[i]
		var chip := Button.new()
		chip.text = shade[0]
		chip.toggle_mode = true
		chip.button_pressed = i == _livery_colour
		var look := UiStyle.box(UiStyle.SUN_LIGHT if i == _livery_colour else UiStyle.PAPER_2,
			shade[1], 2, 6, 4)
		look.border_width_left = 16
		look.content_margin_left = 22
		look.content_margin_right = 8
		if i == _livery_colour:
			look.border_width_bottom = 4
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			chip.add_theme_stylebox_override(state, look)
		chip.add_theme_color_override("font_pressed_color", UiStyle.INK)
		chip.add_theme_color_override("font_hover_pressed_color", UiStyle.INK)
		chip.pressed.connect(func() -> void:
			_livery_colour = i
			_refresh_after_action())
		colours.add_child(chip)
	var number_row := HBoxContainer.new()
	var number_label := Label.new()
	number_label.text = "Door number"
	number_row.add_child(number_label)
	var number := SpinBox.new()
	number.min_value = 1
	number.max_value = 99
	number.value = _livery_number
	number.value_changed.connect(func(value: float) -> void: _livery_number = int(value))
	number_row.add_child(number)
	_paint_list.add_child(number_row)
	var current: Dictionary = _car.custom_livery if _car.cosmetics.get("livery", "") == "custom" else {}
	for mode: String in Garage.LIVERIES:
		var job: Array = Garage.LIVERIES[mode]
		var on: bool = current.get("mode", "") == mode
		_paint_list.add_child(_extra_row("%s   $%s, %s h%s" % [job[0], _number(job[1]), _hours(job[2]), "   (on it now)" if on else ""],
			"Paint it", not Wallet.can_afford(job[1]), func() -> void:
				if Garage.paint_livery(_car, mode, _livery_colour, _livery_number):
					_change.text = "%s, in %s." % [job[0], String(Garage.LIVERY_COLOURS[_livery_colour][0]).to_lower()]))


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
		_text(_fuel_list, "%s%s. Cheapest early in the week." % [Garage.weekday(),
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
		_text(_cars_list, "The car yard opens up as your career grows.")
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
			blurb.add_theme_color_override("font_color", UiStyle.INK_2)
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
		_text(_restore_list, "Nothing on the bench. Chase a barn-find rumour.")
	for id: String in Classics.projects:
		var car := CarCatalogue.get_car(id)
		_heading(_restore_list, "%s (%s)  %d%% restored%s" % [car.get("name", id), car.get("years", ""),
			roundi(Classics.condition(id) * 100.0), "" if Classics.can_drive(id) else "  (not driveable yet)"])
		var next := Classics.next_stage(id)
		for stage: Dictionary in Classics.stages():
			var done := Classics.is_stage_done(id, stage.id)
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = "%s %s%s" % ["Done:" if done else "To do:", stage.title, "" if done else "   $%s, %s" % [_number(Classics.stage_price(id, stage)), _hours(stage.hours) + " h work"]]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.add_theme_color_override("font_color", UiStyle.INK_3 if done else UiStyle.INK)
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
	if liveries.is_empty() and trinkets.is_empty() and _car.custom_livery.is_empty():
		_heading(_extras_list, "Extras")
		_text(_extras_list, "Nothing yet. Keep driving: the next one comes at %s km." % _number(float(Progression.next_mileage_reward().get("km", 0))))
		return
	_heading(_extras_list, "Livery")
	var current: String = _car.cosmetics.get("livery", "")
	var choices: Array = [{"id": "", "title": "None, just the paint"}]
	if not _car.custom_livery.is_empty():
		choices.append({"id": "custom", "title": "The spray shop's %s" % String(Garage.LIVERIES.get(_car.custom_livery.get("mode", ""), ["livery"])[0]).to_lower()})
	for item: Dictionary in choices + liveries:
		var id: String = item.id
		_extras_list.add_child(_extra_row(item.title, "On" if id == current else "Use it", id == current, func() -> void:
			_car.set_livery(id)
			_change.text = "Livery: %s." % item.title.to_lower()))
	if not trinkets.is_empty():
		_heading(_extras_list, "Trinkets")
		_text(_extras_list, "One for the mirror, dash, shelf, gear lever and glovebox.")
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
	_text(_wash_list, "It's %s. A clean car gets better tips." % _dirt_text())
	var meter := ProgressBar.new()
	meter.max_value = 1.0
	meter.value = _car.dirt
	meter.show_percentage = false
	meter.custom_minimum_size.y = 14
	_wash_list.add_child(meter)
	var button := Button.new()
	button.text = "Wash it"
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
	_text(_service_list, "Slides wear tyres, hard stops wear pads, old oil slows you.")
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
			UiStyle.RED if worn >= CarController.WEAR_DUE else UiStyle.INK)
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
	var coat := ""
	if _car.finish != "":
		coat = ", " + String(Garage.FINISHES.get(_car.finish, ["custom coat"])[0]).to_lower()
	if not _car.has_custom_paint():
		return "original (faded)" + coat
	for paint in Garage.PAINTS:
		if _car.paint_color.is_equal_approx(Color(paint[1], 1.0)):
			return paint[0] + coat
	return "custom" + coat


func _needs_text(o: Dictionary) -> String:
	var names := PackedStringArray()
	for id in o.needs:
		var part := PartsCatalogue.get_part(id)
		names.append(part.display_name.to_lower() if part else id)
	return " or ".join(names)


func _heading(parent: Control, text: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		parent.add_child(gap)
	UiStyle.section(parent, text)


func _text(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", UiStyle.INK_2)
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
