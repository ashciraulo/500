class_name TackleScreen
extends CanvasLayer
## The counter at the Mends Street bait and tackle: the anglers' club weighs
## in the esky and pays by the kilo, a bag of ice keeps the catch fresh, and
## better rods, bigger eskies and a crab net are on the wall. The game pauses
## while it's open.

const ACCENT := UiStyle.TEAL

var _panel: PanelContainer
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
	var dim := UiStyle.backdrop()
	root.add_child(dim)
	_panel = FieldUI.panel(ACCENT)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 560)
	_panel.add_child(box)
	var head: Array = UiStyle.header(box, "Mends Street Bait & Tackle", "fish", "Bait, ice and a set of scales")
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
	if not _last_result.is_empty():
		UiStyle.section(_list, "Weigh-in", ACCENT)
		for f: Dictionary in _last_result.fish:
			var tags := PackedStringArray()
			if f.first:
				tags.append("new to the board!")
			if float(f.fresh) < 0.99:
				tags.append("gone soft")
			var note := ", ".join(tags)
			FieldUI.shop_row(_list, "%s  ·  %.0f cm, %.2f kg  ·  $%d" % [f.name, float(f.cm), float(f.kg), int(f.pay)],
				note.left(1).to_upper() + note.substr(1))
		var paid := UiStyle.label(_list, "Paid $%d" % _last_result.pay, "", 18)
		paid.add_theme_font_override("font", UiStyle.BOLD_FONT)
		paid.add_theme_color_override("font_color", UiStyle.GOOD)

	UiStyle.section(_list, "Your esky", ACCENT)
	var esky := FieldJournal.esky
	if esky.is_empty():
		FieldUI.shop_row(_list, "Empty", "Room for %d legal-size fish" % FieldJournal.esky_size())
	else:
		var value := 0
		for f: Dictionary in esky:
			value += FieldJournal.fish_value(f)
		var sell := FieldUI.shop_row(_list, "%d of %d fish" % [esky.size(), FieldJournal.esky_size()], "About $%d at the scales" % value,
			"Sell the catch", true)
		sell.theme_type_variation = &"PrimaryButton"
		sell.pressed.connect(func() -> void:
			_last_result = FieldJournal.weigh_in()
			Activities.say("Weighed in: $%d." % _last_result.pay)
			refresh())
	var ice := FieldJournal.ice_left_hours()
	var buy_ice := FieldUI.shop_row(_list, "Ice: %.0f hours left" % ice if ice > 0.0 else "No ice",
		"" if ice > 0.0 else "Fish go soft without it", "Bag of ice  $%d" % FieldJournal.ICE_PRICE,
		Wallet.can_afford(FieldJournal.ICE_PRICE))
	buy_ice.pressed.connect(func() -> void:
		if FieldJournal.buy_ice():
			Activities.say("Ice in the esky: good for %.0f hours." % FieldJournal.ice_left_hours())
		refresh())

	UiStyle.section(_list, "On the wall", ACCENT)
	_gear_row("rod", FieldJournal.RODS, FieldJournal.rod,
		func(g: Dictionary) -> String: return "Stronger line, casts %d m" % roundi(FieldFishing.CAST_MAX[FieldJournal.RODS.find(g)]))
	_gear_row("esky", FieldJournal.ESKIES, FieldJournal.esky_level,
		func(g: Dictionary) -> String: return "Holds %d fish" % int(g.size))
	if FieldJournal.has_crab_net:
		FieldUI.shop_row(_list, "Crab net", "Yours. Drop it off a river jetty")
	else:
		var buy := FieldUI.shop_row(_list, "Crab net", "Blue mannas, off a river jetty", "$%d" % FieldJournal.CRAB_NET_PRICE,
			Wallet.can_afford(FieldJournal.CRAB_NET_PRICE))
		buy.pressed.connect(func() -> void:
			if FieldJournal.upgrade_fishing("crab_net"):
				Activities.say("A crab net. Summer on the river.")
			refresh())


func _gear_row(kind: String, list: Array, level: int, describe: Callable) -> void:
	if level + 1 >= list.size():
		FieldUI.shop_row(_list, list[level].name, "Best in the shop")
		return
	var next: Dictionary = list[level + 1]
	var buy := FieldUI.shop_row(_list, next.name, describe.call(next), "$%d" % int(next.price), Wallet.can_afford(int(next.price)))
	buy.pressed.connect(func() -> void:
		if FieldJournal.upgrade_fishing(kind):
			Activities.say("New %s: %s." % [kind, next.name])
		refresh())
