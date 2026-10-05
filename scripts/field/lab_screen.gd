class_name LabScreen
extends CanvasLayer
## The counter at the Lake Street photo lab: develop the roll and sell the
## prints, and buy better binoculars and cameras. The game pauses while it's open.

const ACCENT := Color(0.95, 0.6, 0.78)

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
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)
	_panel = FieldUI.panel(ACCENT)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 500)
	_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	FieldUI.label(header, "Lake Street Photo Lab", 22, ACCENT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close = Button.new()
	_close.text = "Close"
	_close.pressed.connect(close)
	header.add_child(_close)
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
		FieldUI.label(_list, "Your prints", 18, ACCENT)
		for p: Dictionary in _last_result.prints:
			var stars := "*".repeat(int(p.stars))
			if p.wrong:
				FieldUI.label(_list, "  %s  %s: came out blank. \"Odd, that. The rest of the roll's fine.\"" % [p.name, stars], 14, Color(0.75, 0.7, 0.8))
			else:
				FieldUI.label(_list, "  %s  %s   $%d%s" % [p.name, stars, p.pay, "   (first print of one: the magazine pays extra)" if p.first else ""], 14)
		FieldUI.label(_list, "Developing $%d. You take home $%d." % [_last_result.fee, _last_result.pay], 16, Color(1, 0.9, 0.6))
		_list.add_child(HSeparator.new())
	FieldUI.label(_list, "The roll in your camera", 18, ACCENT)
	if roll.is_empty():
		FieldUI.label(_list, "Nothing on it yet. %d frames to fill: find birds, raise the binoculars (B) and take your time." % FieldJournal.roll_size())
	else:
		var value := 0
		for frame: Dictionary in roll:
			value += FieldJournal.print_value(frame)
		FieldUI.label(_list, "%d of %d frames used. Roughly $%d in prints, before the first-print bonuses." % [roll.size(), FieldJournal.roll_size(), value])
		var develop := Button.new()
		develop.text = "Develop and sell the prints ($%d to develop)" % FieldJournal.DEVELOP_PRICE
		develop.pressed.connect(func() -> void:
			_last_result = FieldJournal.develop()
			Activities.say("Prints sold: $%d." % _last_result.pay)
			refresh())
		_list.add_child(develop)
	_list.add_child(HSeparator.new())
	FieldUI.label(_list, "Gear", 18, ACCENT)
	_gear_row("binoculars", FieldJournal.BINOCULARS, FieldJournal.binoculars,
		func(g: Dictionary) -> String: return "sees birds to %d m, zooms to %.0fx" % [int(g.range), 72.0 / float(g.fov)])
	_gear_row("camera", FieldJournal.CAMERAS, FieldJournal.camera,
		func(g: Dictionary) -> String: return "%d frames a roll, an easier focus dial" % int(g.frames))
	_list.add_child(HSeparator.new())
	FieldUI.label(_list, "Journal: %d of %d species seen, %d photographed. $%d from prints so far." % [
		FieldJournal.seen_count(), FieldJournal.species_total(), FieldJournal.photographed_count(), FieldJournal.money_from_prints], 14, Color(0.8, 0.8, 0.78))


func _gear_row(kind: String, list: Array, level: int, describe: Callable) -> void:
	FieldUI.label(_list, "%s: %s" % [kind.capitalize(), list[level].name], 15)
	if level + 1 >= list.size():
		FieldUI.label(_list, "  The best they've got.", 13, Color(0.7, 0.7, 0.68))
		return
	var next: Dictionary = list[level + 1]
	var row := HBoxContainer.new()
	FieldUI.label(row, "  Next: %s, %s." % [next.name, describe.call(next)], 13, Color(0.8, 0.8, 0.78)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buy := Button.new()
	buy.text = "Buy $%d" % int(next.price)
	buy.disabled = not Wallet.can_afford(int(next.price))
	buy.pressed.connect(func() -> void:
		if FieldJournal.upgrade(kind):
			Activities.say("New %s: %s." % [kind, next.name])
		refresh())
	row.add_child(buy)
	_list.add_child(row)
