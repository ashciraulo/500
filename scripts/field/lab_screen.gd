class_name LabScreen
extends CanvasLayer
## The counter at the Lake Street photo lab: develop the roll and sell the
## prints, and buy better binoculars and cameras. The game pauses while it's open.

const ACCENT := Color("a8456d")

var _panel: PanelContainer
var _dim: ColorRect
var _list: VBoxContainer
var _close: Button
var _last_result := {}


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_dim = UiStyle.backdrop()
	root.add_child(_dim)
	_panel = FieldUI.panel(ACCENT)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 480)
	_panel.add_child(box)
	var head: Array = UiStyle.header(box, "Lake Street Photo Lab", "camera", "Film, prints and binoculars")
	(head[0] as Label).add_theme_color_override("font_color", ACCENT)
	_close = head[2]
	_close.pressed.connect(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_last_result = {}
	refresh()
	_close.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("phone")):
		close()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	FieldUI.clear(_list)
	var roll := FieldJournal.roll
	if not _last_result.is_empty():
		UiStyle.section(_list, "Your prints", ACCENT)
		for p: Dictionary in _last_result.prints:
			var stars := UiStyle.stars(int(p.stars))
			if p.wrong:
				FieldUI.shop_row(_list, "%s  ·  %s" % [p.name, stars], "Came out blank. \"Odd, that. The rest of the roll's fine.\"")
			else:
				FieldUI.shop_row(_list, "%s  ·  %s  ·  $%d" % [p.name, stars, p.pay], "First print: the magazine pays extra" if p.first else "")
		var paid := UiStyle.label(_list, "Paid $%d, after $%d developing" % [_last_result.pay, _last_result.fee], "", 18)
		paid.add_theme_font_override("font", UiStyle.BOLD_FONT)
		paid.add_theme_color_override("font_color", UiStyle.GOOD)

	UiStyle.section(_list, "Your film", ACCENT)
	if roll.is_empty():
		FieldUI.shop_row(_list, "Nothing on it yet", "%d frames. Raise the binoculars (B) at a bird" % FieldJournal.roll_size())
	else:
		var value := 0
		for frame: Dictionary in roll:
			value += FieldJournal.print_value(frame)
		var develop := FieldUI.shop_row(_list, "%d of %d frames" % [roll.size(), FieldJournal.roll_size()],
			"About $%d in prints" % value, "Develop  $%d" % FieldJournal.DEVELOP_PRICE)
		develop.theme_type_variation = &"PrimaryButton"
		develop.pressed.connect(func() -> void:
			_last_result = FieldJournal.develop()
			Activities.say("Prints sold: $%d." % _last_result.pay)
			refresh())

	UiStyle.section(_list, "Behind the counter", ACCENT)
	_gear_row("binoculars", FieldJournal.BINOCULARS, FieldJournal.binoculars,
		func(g: Dictionary) -> String: return "See birds to %d m, %.0fx zoom" % [int(g.range), 72.0 / float(g.fov)])
	_gear_row("camera", FieldJournal.CAMERAS, FieldJournal.camera,
		func(g: Dictionary) -> String: return "%d frames a roll, easier to focus" % int(g.frames))
	_gear_row("lens", FieldJournal.LENSES, FieldJournal.lens,
		func(g: Dictionary) -> String: return "Birds %.1fx bigger in photos" % float(g.reach))
	_gear_row("film", FieldJournal.FILMS, FieldJournal.film,
		func(g: Dictionary) -> String: return "Sharp after dark" if float(g.night) >= 1.0 else "Copes with dusk")


func _gear_row(kind: String, list: Array, level: int, describe: Callable) -> void:
	if level + 1 >= list.size():
		FieldUI.shop_row(_list, list[level].name, "%s: the best they've got" % kind.capitalize())
		return
	var next: Dictionary = list[level + 1]
	var buy := FieldUI.shop_row(_list, next.name, "%s: %s" % [kind.capitalize(), describe.call(next).to_lower()],
		"$%d" % int(next.price), Wallet.can_afford(int(next.price)))
	buy.pressed.connect(func() -> void:
		if FieldJournal.upgrade(kind):
			Activities.say("New %s: %s." % [kind, next.name])
		refresh())
