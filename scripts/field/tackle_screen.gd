class_name TackleScreen
extends CanvasLayer
## The counter at the Mends Street bait and tackle: the anglers' club weighs
## in the esky and pays by the kilo, a bag of ice keeps the catch fresh, and
## better rods, bigger eskies and a crab net are on the wall. The game pauses
## while it's open.

const ACCENT := Color(0.45, 0.78, 0.95)

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
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	_panel = FieldUI.panel(ACCENT)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 500)
	_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	FieldUI.label(header, "Mends Street Bait & Tackle", 22, ACCENT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	if not _last_result.is_empty():
		FieldUI.label(_list, "The weigh-in", 18, ACCENT)
		for f: Dictionary in _last_result.fish:
			var fresh := float(f.fresh)
			var note := "" if fresh >= 0.99 else ("   (gone soft: %d%%)" % roundi(fresh * 100.0))
			FieldUI.label(_list, "  %s  %.1f cm  %.2f kg   $%d%s%s" % [f.name, float(f.cm), float(f.kg), int(f.pay),
				"   (new to the club's board: bonus)" if f.first else "", note], 14)
		FieldUI.label(_list, "The club pays you $%d." % _last_result.pay, 16, Color(1, 0.9, 0.6))
		_list.add_child(HSeparator.new())
	FieldUI.label(_list, "Your esky", 18, ACCENT)
	var esky := FieldJournal.esky
	if esky.is_empty():
		FieldUI.label(_list, "Empty. %d fish fit in the %s. Legal-size fish only; the club checks." % [FieldJournal.esky_size(), FieldJournal.gear_esky().name.to_lower()])
	else:
		var value := 0
		for f: Dictionary in esky:
			value += FieldJournal.fish_value(f)
		FieldUI.label(_list, "%d of %d. Roughly $%d on the scales, before the new-species bonuses." % [esky.size(), FieldJournal.esky_size(), value])
		var weigh := Button.new()
		weigh.text = "Weigh in and sell the catch"
		weigh.pressed.connect(func() -> void:
			_last_result = FieldJournal.weigh_in()
			Activities.say("Weighed in: $%d." % _last_result.pay)
			refresh())
		_list.add_child(weigh)
	var ice := FieldJournal.ice_left_hours()
	var ice_row := HBoxContainer.new()
	FieldUI.label(ice_row, "Ice: %s" % ("%.0f hours left in the esky" % ice if ice > 0.0 else "none. Fish go soft without it."), 15,
		Color(0.8, 0.9, 1.0) if ice > 0.0 else Color(1, 0.7, 0.55)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buy_ice := Button.new()
	buy_ice.text = "Bag of ice $%d" % FieldJournal.ICE_PRICE
	buy_ice.disabled = not Wallet.can_afford(FieldJournal.ICE_PRICE)
	buy_ice.pressed.connect(func() -> void:
		if FieldJournal.buy_ice():
			Activities.say("Ice in the esky: good for %.0f hours." % FieldJournal.ice_left_hours())
		refresh())
	ice_row.add_child(buy_ice)
	_list.add_child(ice_row)
	_list.add_child(HSeparator.new())
	FieldUI.label(_list, "On the wall", 18, ACCENT)
	_gear_row("rod", FieldJournal.RODS, FieldJournal.rod,
		func(g: Dictionary) -> String: return "holds %d%% harder fish, casts %d m" % [roundi(float(g.strength) * 100.0 - 100.0),
			roundi(FieldFishing.CAST_MAX[FieldJournal.RODS.find(g)])])
	_gear_row("esky", FieldJournal.ESKIES, FieldJournal.esky_level,
		func(g: Dictionary) -> String: return "holds %d fish" % int(g.size))
	if FieldJournal.has_crab_net:
		FieldUI.label(_list, "Crab net: yours. Drop it off a river jetty and come back in an hour.", 15)
	else:
		var row := HBoxContainer.new()
		FieldUI.label(row, "Crab net: drop it off a river jetty, pull it an hour later. Blue mannas.", 15).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy := Button.new()
		buy.text = "Buy $%d" % FieldJournal.CRAB_NET_PRICE
		buy.disabled = not Wallet.can_afford(FieldJournal.CRAB_NET_PRICE)
		buy.pressed.connect(func() -> void:
			if FieldJournal.upgrade_fishing("crab_net"):
				Activities.say("A crab net. Summer on the river.")
			refresh())
		row.add_child(buy)
		_list.add_child(row)
	_list.add_child(HSeparator.new())
	FieldUI.label(_list, "Journal: %d of %d fish caught. %d weighed in, $%d from the club so far." % [
		FieldJournal.caught_count(), FieldJournal.fish_total(), FieldJournal.fish_weighed, FieldJournal.money_from_fish], 14, Color(0.8, 0.8, 0.78))


func _gear_row(kind: String, list: Array, level: int, describe: Callable) -> void:
	FieldUI.label(_list, "%s: %s" % [kind.capitalize(), list[level].name], 15)
	if level + 1 >= list.size():
		FieldUI.label(_list, "  Best in the shop.", 13, Color(0.7, 0.7, 0.68))
		return
	var next: Dictionary = list[level + 1]
	var row := HBoxContainer.new()
	FieldUI.label(row, "  Next: %s, %s." % [next.name, describe.call(next)], 13, Color(0.8, 0.8, 0.78)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buy := Button.new()
	buy.text = "Buy $%d" % int(next.price)
	buy.disabled = not Wallet.can_afford(int(next.price))
	buy.pressed.connect(func() -> void:
		if FieldJournal.upgrade_fishing(kind):
			Activities.say("New %s: %s." % [kind, next.name])
		refresh())
	row.add_child(buy)
	_list.add_child(row)
