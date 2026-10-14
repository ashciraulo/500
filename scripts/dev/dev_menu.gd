class_name DevMenu
extends CanvasLayer
## The dev menu (F4 while dev mode is on): try anything without playing the
## game through to it. Get any car, fit any part, the best field gear; set
## the money, time, weather, game speed and traffic; go anywhere; jump the
## career tier and the story's act, choices and ending, and ready its strange
## nights; keep snapshots of the game to go back to.
##
## Built in code like the workshop. Pauses the game while it's open; F4 or
## Esc closes it. What it changes is done by DevTools (and moves by DevMode).

signal closed

const TIME_PRESETS := [
	["Dawn", 5.8], ["Morning", 9.0], ["Noon", 12.0], ["Golden hour", 17.6],
	["Dusk", 18.6], ["Night", 21.5], ["Midnight", 0.25], ["Small hours", 2.5],
]
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]
## Traffic: [label, density_scale].
const TRAFFIC := [["None", 0.0], ["Normal", 1.0], ["Busy", 2.5]]
const LADDERS := [["modern", "Modern 500s"], ["electric", "Electric"], ["classic", "Classics"], ["period", "Others"]]
const SNAPSHOTS := 3
const SNAPSHOT_PATH := "user://dev_snapshot_%d.json"
## The late city's events that can be readied: [script class, name, where it happens].
const EVENTS := [
	["LookingOut", "Looking out", "At home after midnight, doors shut: look out a front window."],
	["OtherHouse", "The other house", "Late at night, open your front door from outside."],
	["EmptyRoad", "The empty road", "A late parcel job to May Drive, Kings Park."],
	["RepeatStreet", "Repeat Street", "Drive down a quiet street after midnight."],
	["StoppedClock", "The 2:40 clock", "Any late drive."],
	["MinimapPassenger", "The minimap passenger", "Any late drive, for a while."],
	["LookoutSignal", "Lookout signal", "Park at a Kings Park lookout, flash the lights (K) three times."],
	["StationVoice", "The station answers back", "The midnight station on the radio."],
	["Street1979", "The 1979 street", "Drive down a street of shops after midnight."],
	["TapeAhead", "The tapes run ahead", "A tape in the deck late at night, a job next morning."],
]

## Where snapshot n goes (tests point this elsewhere).
var snapshot_path := SNAPSHOT_PATH

var _dev: DevMode
var _tools: DevTools
var _root: Control
var _dim: ColorRect
var _panel: PanelContainer
var _tabs: TabContainer
var _lists := {}  # tab name -> VBoxContainer
var _status: Label
var _change: Label
var _coords: LineEdit
var _was_paused := false
var _events := {}  # script class -> node


func _init(dev: DevMode, tools: DevTools) -> void:
	_dev = dev
	_tools = tools


func _ready() -> void:
	layer = 61
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_open(false)


## F4 or Esc closes it. Here rather than UiStyle.close_keys, which would
## take Esc from the pause menu while this is shut.
func _input(event: InputEvent) -> void:
	if not is_open() or event.is_echo():
		return
	var key := event as InputEventKey
	if (key and key.pressed and key.keycode == DevMode.MENU_KEY) or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_set_open(true)


func close() -> void:
	if is_open():
		_set_open(false)


func toggle() -> void:
	_set_open(not is_open())


func is_open() -> bool:
	return _panel.visible


func _set_open(on: bool) -> void:
	var was := _panel.visible
	_panel.visible = on
	_dim.visible = on
	if on and not was:
		_was_paused = get_tree().paused
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_change.text = ""
		_refresh()
		(_tabs.get_tab_bar() as Control).grab_focus()
	elif was and not on:
		get_tree().paused = _was_paused
		closed.emit()


## Back to normal when dev mode goes off: normal game speed, and no strange
## night left readied.
func let_go() -> void:
	Engine.time_scale = 1.0
	for node: Node in _events.values():
		if is_instance_valid(node):
			node.set("force", false)


## Says what was done, and shows it.
func _did(text: String) -> void:
	_change.text = text
	_refresh()


func _process(_delta: float) -> void:
	if not is_open():
		return
	var car := _dev.car()
	_status.text = "%s\n$%s\nDay %d, %s %s\n%s\nTier %d, act %d\nGame speed %sx" % [
		CarCatalogue.get_car(car.car_id).get("name", car.car_id) if car else "",
		UiStyle.number(Wallet.balance), GameClock.day, Garage.weekday(), GameClock.time_string(),
		Weather.state_name(), mini(Progression.tier_index + 1, Progression.tiers.size()), Story.act(),
		_speed_text(Engine.time_scale)]


# --- Building ------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = UiStyle.backdrop()
	_root.add_child(_dim)
	var card := UiStyle.centred_card(_root, Vector2(1000, 580))
	_panel = card[0]
	var box: VBoxContainer = card[1]
	var head: Array = UiStyle.header(box, "Dev menu", "wrench", "Try anything without playing through to it.   F4 closes.", "Done")
	(head[2] as Button).pressed.connect(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	box.add_child(body)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_i: int) -> void: _refresh())
	body.add_child(_tabs)
	for tab in ["Cars", "Parts", "World", "Places", "Story", "Saves"]:
		_lists[tab] = _scroll_tab(tab)

	var side_panel := PanelContainer.new()
	side_panel.theme_type_variation = &"WellPanel"
	side_panel.custom_minimum_size.x = 240
	body.add_child(side_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side_panel.add_child(side)
	UiStyle.label(side, "Now", "SectionLabel").uppercase = true
	_status = UiStyle.label(side, "")
	_change = UiStyle.label(side, "")
	_change.add_theme_color_override("font_color", UiStyle.GOOD)
	_change.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(gap)
	var note := UiStyle.label(side, "Changes go into your save like anything else. Saves has a way round that.", "NoteLabel", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _scroll_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _refresh() -> void:
	if not is_open() or _dev.car() == null:
		return
	var tab := String(_tabs.get_current_tab_control().name)
	if not _lists.has(tab):
		return
	var list: VBoxContainer = _lists[tab]
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	match tab:
		"Cars": _fill_cars(list)
		"Parts": _fill_parts(list)
		"World": _fill_world(list)
		"Places": _fill_places(list)
		"Story": _fill_story(list)
		"Saves": _fill_saves(list)


# --- Cars ------------------------------------------------------------------------

func _fill_cars(list: VBoxContainer) -> void:
	var top := _row(list, "Any car is yours to drive at once. Classics come restored.")
	_button(top, "Every car", func() -> void: _did(_tools.give_all_cars()))
	var car := _dev.car()
	for ladder: Array in LADDERS:
		var cars := CarCatalogue.ladder(ladder[0])
		if cars.is_empty():
			continue
		_heading(list, ladder[1])
		for info: Dictionary in cars:
			var id := String(info.id)
			var tag := "driving it" if id == car.car_id else ("yours" if Garage.owns_car(id) else
				("tier %d" % (int(info.tier) + 1) if info.unlock == "tier" else String(info.unlock).replace("_", " ")))
			var row := _row(list, "%s (%s)" % [info.name, info.years], tag)
			if ladder[0] == "classic":
				var wreck := _button(row, "As a wreck", func() -> void: _did(_tools.give_wreck(id)))
				wreck.disabled = Classics.is_found(id)
			var drive := _button(row, "Driving it" if id == car.car_id else "Drive it", func() -> void: _drive(id))
			drive.disabled = id == car.car_id


func _drive(id: String) -> void:
	var on_foot := not _dev.player().in_car
	var said := _tools.give_car(id)
	if on_foot:
		_dev.queue(_dev.bring_car)
		said += " It's beside you."
	_did(said)


# --- Parts -------------------------------------------------------------------------

func _fill_parts(list: VBoxContainer) -> void:
	var car := _dev.car()
	var top := _row(list, "Parts for the %s. Fit is free and instant." % CarCatalogue.get_car(car.car_id).get("name", ""))
	_button(top, "All on the shelf", func() -> void: _did(_tools.own_all_parts()))
	_button(top, "For all my cars", func() -> void: _did(_tools.own_parts_every_car()))
	_button(top, "All stock", func() -> void: _did(_tools.all_stock()))
	var gear := _row(list, "Field gear and the journal")
	_button(gear, "Best field gear", func() -> void: _did(_tools.best_field_gear()))
	_button(gear, "Every bird seen", func() -> void: _did(_tools.see_all_birds()))
	var fitted := car.get_part_ids()
	for slot in PartsCatalogue.SLOTS:
		var parts := PartsCatalogue.for_car(slot, car.car_id)
		if parts.size() < 2:
			continue
		_heading(list, String(slot).capitalize())
		for part in parts:
			var on: bool = fitted.has(String(part.id)) or (part.is_stock() and not car.parts.has(slot))
			var note := "stock" if part.is_stock() else ("found in the city" if part.found_only else "$%s" % UiStyle.number(part.price))
			if not part.is_stock() and Garage.owns(part, car) and not on:
				note += ", yours"
			var button := _button(_row(list, part.display_name, note), "Fitted" if on else "Fit",
				func() -> void: _did(_tools.fit_part(part)))
			button.disabled = on


# --- World -------------------------------------------------------------------------

func _fill_world(list: VBoxContainer) -> void:
	_heading(list, "Money")
	var money := _row(list, "$%s in the bank" % UiStyle.number(Wallet.balance), "not counted as earnings")
	for amount: int in [1000, 10000, 100000]:
		_button(money, "+$%s" % UiStyle.number(amount), func() -> void: _did(_tools.add_money(amount)))
	_button(money, "None", func() -> void: _did(_tools.add_money(-Wallet.balance)))

	_heading(list, "Time")
	var times := _flow(list)
	for preset: Array in TIME_PRESETS:
		var hours: float = preset[1]
		_button(times, preset[0], func() -> void:
			GameClock.set_time(hours)
			_did("It's %s." % GameClock.time_string()))
	_button(times, "+1 hour", func() -> void:
		GameClock.advance(1.0)
		_did("It's %s." % GameClock.time_string()))
	_button(times, "Next morning", func() -> void:
		GameClock.advance(24.0 - GameClock.time_of_day + 8.0)
		_did("Day %d, %s." % [GameClock.day, GameClock.time_string()]))
	_check(list, "Stop the clock", GameClock.locked, func(on: bool) -> void:
		GameClock.set_locked(on)
		_did("The clock's stopped." if on else "The clock's running."))

	_heading(list, "Weather")
	var weather := _flow(list)
	for i in Weather.STATE_NAMES.size():
		var b := _button(weather, Weather.STATE_NAMES[i], func() -> void:
			Weather.set_state(i, true)
			_did("%s now." % Weather.STATE_NAMES[i]))
		b.disabled = Weather.state == i
	_check(list, "Keep this weather", Weather.locked, func(on: bool) -> void:
		Weather.set_locked(on)
		_did("The weather stays." if on else "The weather changes on its own."))

	_heading(list, "Game speed")
	var speeds := _flow(list)
	for s: float in SPEEDS:
		var b := _button(speeds, _speed_text(s) + "x", func() -> void:
			Engine.time_scale = s
			_did("Game speed %sx." % _speed_text(s)))
		b.disabled = is_equal_approx(Engine.time_scale, s)

	var traffic := get_tree().get_first_node_in_group(&"traffic")
	if traffic:
		_heading(list, "Traffic")
		for which: Array in [["Cars", "density_scale"], ["People", "pedestrian_scale"]]:
			var row := _row(list, which[0])
			for t: Array in TRAFFIC:
				var b := _button(row, t[0], func() -> void:
					traffic.set(which[1], t[1])
					_did("%s: %s." % [which[0], String(t[0]).to_lower()]))
				b.disabled = is_equal_approx(float(traffic.get(which[1])), float(t[1]))
		var more := _flow(list)
		_button(more, "Clear the streets", func() -> void:
			traffic.clear_all()
			_did("Everything on the roads and paths is gone (more come along)."))
		_button(more, "Siren past", func() -> void:
			_did("Here comes one." if traffic.spawn_emergency(_dev.here()) != null else "No main road near enough."))

	_heading(list, "Your car")
	var fix := _flow(list)
	_button(fix, "Fill up and fix", func() -> void: _did(_tools.fix_car()))
	_button(fix, "Back on its wheels", func() -> void:
		_dev.queue(_dev.car().reset_upright)
		_did("The car's upright."))


static func _speed_text(s: float) -> String:
	return str(s) if s < 1.0 else str(int(s))


# --- Places ------------------------------------------------------------------------

func _fill_places(list: VBoxContainer) -> void:
	var row := _row(list, "Type a spot (x, z or x, y, z), or press T on the map (M).")
	_coords = LineEdit.new()
	_coords.placeholder_text = "-57.5, 38.8"
	_coords.custom_minimum_size.x = 200
	_coords.text_submitted.connect(func(_t: String) -> void: _go_typed())
	row.add_child(_coords)
	_button(row, "Go", _go_typed)
	var who := "you and the car" if _dev.player().in_car else "you (the car stays put)"
	UiStyle.label(list, "Going takes %s." % who, "NoteLabel", 13)
	for group: Array in DevPlaces.gather(get_tree(), _dev.player().get_parent()):
		_heading(list, group[0])
		for place: Array in group[1]:
			var at: Vector3 = place[1]
			var go: Callable = place[3] if place.size() > 3 else Callable()
			_button(_row(list, place[0], place[2]), "Go", func() -> void:
				if go.is_valid():
					go.call()
				_go(at, place[0]))


func _go_typed() -> void:
	var nums: Array[float] = []
	for bit in _coords.text.replace(";", ",").split(",", false):
		if bit.strip_edges().is_valid_float():
			nums.append(bit.strip_edges().to_float())
	if nums.size() == 2:
		_go(Vector3(nums[0], NAN, nums[1]), "%.1f, %.1f" % [nums[0], nums[1]])
	elif nums.size() == 3:
		_go(Vector3(nums[0], nums[1], nums[2]), "%.1f, %.1f" % [nums[0], nums[2]])
	else:
		_did("Type two numbers (x, z) or three (x, y, z).")


func _go(at: Vector3, what: String) -> void:
	close()
	_dev.go_to(at, what)


# --- Story ---------------------------------------------------------------------------

func _fill_story(list: VBoxContainer) -> void:
	_heading(list, "Career tier and act")
	var tiers := _row(list, "Tier %d of %d, act %d" % [mini(Progression.tier_index + 1, Progression.tiers.size()),
		Progression.tiers.size(), Story.act()], "the act follows the tier")
	for i in Progression.tiers.size():
		var b := _button(tiers, str(i + 1), func() -> void: _did(_tools.set_tier(i)))
		b.disabled = Progression.tier_index == i
	var finish := _row(list, "Finish this tier's challenges", "moves you up the normal way")
	_button(finish, "Finish tier", func() -> void: _did(_tools.finish_tier())).disabled = Progression.current_tier().is_empty()

	_heading(list, "Jobs")
	var job := _row(list, Jobs.objective_text() if not Jobs.active.is_empty() else "Not on a job.")
	_button(job, "Finish the job", func() -> void: _did(_tools.finish_job())).disabled = Jobs.active.is_empty()
	_button(job, "New offers", func() -> void: _did(_tools.new_offers()))

	_heading(list, "Choices")
	for id: StringName in Story.CHOICES:
		var row := _row(list, String(id).capitalize(), String(Story.choice(id)) if Story.choice(id) != &"" else "not made")
		for value: StringName in Story.CHOICES[id] + [&""]:
			var b := _button(row, String(value).capitalize() if value != &"" else "Unmade",
				func() -> void: _did(_tools.set_choice(id, value)))
			b.disabled = Story.choice(id) == value

	_heading(list, "Ending")
	var endings := _flow(list)
	for id: StringName in Story.ENDINGS + [&""]:
		var b := _button(endings, String(id).capitalize() if id != &"" else "None",
			func() -> void: _did(_tools.set_ending(id)))
		b.disabled = Story.ending() == id

	_heading(list, "Strange nights")
	UiStyle.label(list, "Ready one and it happens the next time it can, whatever the act, night or odds.", "NoteLabel", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_find_events()
	for e: Array in EVENTS:
		var node: Node = _events.get(e[0])
		if node == null:
			continue
		var row := _row(list, e[1], e[2])
		var ready := CheckButton.new()
		ready.text = "Ready"
		ready.button_pressed = bool(node.get("force"))
		ready.toggled.connect(func(on: bool) -> void:
			node.set("force", on)
			_did("%s is %s." % [e[1], "ready" if on else "back to normal"]))
		row.add_child(ready)


## The late city's event nodes, by their script class.
func _find_events() -> void:
	_events.clear()
	var world := _dev.player().get_parent()
	var places := world.get_node_or_null(^"GameplayPlaces")
	for parent: Node in [world, places]:
		if parent == null:
			continue
		for child in parent.get_children():
			var script := child.get_script() as Script
			var id := String(script.get_global_name()) if script else ""
			if EVENTS.any(func(e: Array) -> bool: return e[0] == id):
				_events[id] = child


# --- Saves ---------------------------------------------------------------------------

func _fill_saves(list: VBoxContainer) -> void:
	_heading(list, "This run")
	var no_save := OS.get_cmdline_user_args().has("--no-save")
	var keep := _check(list, "Keep this run out of my save", not SaveGame.enabled, func(on: bool) -> void:
		SaveGame.enabled = not on
		_did("Nothing from now on is saved." if on else "Saving again, as normal."))
	keep.disabled = no_save
	if no_save:
		UiStyle.label(list, "This run started with --no-save, so it's never saved.", "NoteLabel", 13)
	_heading(list, "Snapshots")
	UiStyle.label(list, "A copy of the whole game to come back to. They work with saving off too.", "NoteLabel", 13)
	for i in range(1, SNAPSHOTS + 1):
		var path := snapshot_path % i
		var when := _snapshot_time(path)
		var row := _row(list, "Snapshot %d" % i, "saved %s" % when if when != "" else "empty")
		_button(row, "Save", func() -> void:
			_did("Snapshot %d saved." % i if SaveGame.save_to(path) else "Couldn't write the snapshot."))
		var load := _button(row, "Load", func() -> void:
			if SaveGame.load_from(path):
				close()
				_dev.say("Snapshot %d loaded." % i)
			else:
				_did("Couldn't read the snapshot."))
		load.disabled = when == ""


static func _snapshot_time(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return String(parsed.get("saved_at", "")).replace("T", " ") if parsed is Dictionary else ""


# --- Bits ----------------------------------------------------------------------------

func _heading(parent: Control, text: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		parent.add_child(gap)
	UiStyle.section(parent, text)


## A row: a label (and a grey note after it), then whatever buttons go on it.
func _row(parent: Control, text: String, note := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", -2)
	row.add_child(words)
	UiStyle.label(words, text).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if note != "":
		UiStyle.label(words, note, "NoteLabel", 13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return row


## Buttons that wrap onto more lines.
func _flow(parent: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	return flow


func _button(parent: Control, text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(pressed)
	parent.add_child(b)
	return b


func _check(parent: Control, text: String, on: bool, toggled: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(toggled)
	parent.add_child(c)
	return c
