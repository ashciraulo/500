class_name LabScreen
extends CanvasLayer
## The counter at the Lake Street photo lab: develop the roll and sell the
## prints, and buy better binoculars and cameras. From the story's act 3 the
## wrong birds' prints come back blank, and each goes to Ros for Mick's field
## guide or is kept for the buyer (FieldJournal.give_blank). Once the story
## asks for it, a roll comes back with one extra frame: you at the wheel, from
## the back seat (BackSeatPhoto). The game pauses while it's open.

const ACCENT := Color("a8456d")

var _panel: PanelContainer
var _dim: ColorRect
var _list: VBoxContainer
var _close: Button
var _last_result := {}
## Takes the back-seat photograph if it's due when you develop (FieldWorld sets it).
var back_seat_photo: BackSeatPhoto


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
	_back_seat()
	if not _last_result.is_empty():
		UiStyle.section(_list, "Your prints", ACCENT)
		for p: Dictionary in _last_result.prints:
			if p.has("extra"):
				continue
			var stars := UiStyle.stars(int(p.stars))
			if p.wrong:
				FieldUI.shop_row(_list, "%s  ·  %s" % [p.name, stars], "Came out blank. Ros holds it up to the light." if p.get("blank", false)
					else "Came out blank. \"Odd, that. The rest of the roll's fine.\"",
					"", true, SpeciesIcon.bird(FieldJournal.bird(String(p.species)), 44, true))
			else:
				FieldUI.shop_row(_list, "%s  ·  %s  ·  $%d" % [p.name, stars, p.pay], "First print: the magazine pays extra" if p.first else "",
					"", true, SpeciesIcon.bird(FieldJournal.bird(String(p.species)), 44))
		var paid := UiStyle.label(_list, "Paid $%d, after $%d developing" % [_last_result.pay, _last_result.fee] if int(_last_result.pay) >= 0
			else "Developing: $%d" % _last_result.fee, "", 18)
		paid.add_theme_font_override("font", UiStyle.BOLD_FONT)
		paid.add_theme_color_override("font_color", UiStyle.GOOD)

	_blank_prints()

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
			if FieldJournal.back_seat_due() and back_seat_photo and back_seat_photo.can_take_now():
				develop.disabled = true
				await back_seat_photo.take()
			_last_result = FieldJournal.develop()
			Activities.say("Prints sold: $%d." % _last_result.pay)
			if _last_result.prints.any(func(p: Dictionary) -> bool: return p.has("extra")):
				_tape_click()
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


## The back-seat photograph, waiting on the counter until you say where it goes.
func _back_seat() -> void:
	if not FieldJournal.back_seat_waiting():
		return
	UiStyle.section(_list, "One more frame", ACCENT)
	var tex := FieldUI.photo_texture(String(FieldJournal.back_seat.print), 300)
	if tex:
		# On the counter as a print, white border and all.
		var paper := PanelContainer.new()
		paper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var border := StyleBoxFlat.new()
		border.bg_color = Color("f7f2e6")
		border.set_content_margin_all(6)
		border.content_margin_bottom = 14
		border.shadow_color = Color(0, 0, 0, 0.25)
		border.shadow_size = 3
		border.shadow_offset = Vector2(1, 2)
		paper.add_theme_stylebox_override("panel", border)
		_list.add_child(paper)
		var pic := TextureRect.new()
		pic.texture = tex
		pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		paper.add_child(pic)
	var ros := FieldUI.shop_row(_list, "A frame you didn't take",
		"You, at the wheel, from the back seat. \"I'll keep this one, if you like,\" Ros says.", "Ros keeps it")
	var answers := VBoxContainer.new()
	answers.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ros.get_parent().add_child(answers)
	ros.reparent(answers)
	var home := Button.new()
	home.text = "Take it home"
	answers.add_child(home)
	ros.pressed.connect(_give_back_seat.bind(&"ros"))
	home.pressed.connect(_give_back_seat.bind(&"home"))


func _give_back_seat(to: StringName) -> void:
	FieldJournal.give_back_seat(to)
	Activities.say("Ros slips it into Mick's manuscript, at the back." if to == &"ros" else "You take it home. It's in the album now.")
	refresh()
	_close.grab_focus()


## The late city's tape click, as the extra frame comes out of the envelope.
func _tape_click() -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has("late/late_tape_start"):
		audio.play_2d("late/late_tape_start", "SFX", -6.0)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = LateSounds.make("late_tape_start")
		p.bus = "SFX"
		p.volume_db = -6.0
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


## The blank prints waiting on the counter, and Mick's field guide.
func _blank_prints() -> void:
	if FieldJournal.story_act() < FieldJournal.BLANKS_FROM_ACT and FieldJournal.blanks.is_empty():
		return
	UiStyle.section(_list, "Blank prints", ACCENT)
	FieldUI.shop_row(_list, "Mick's field guide", "Night pages: %d of %d. Ros keeps the manuscript under the counter." % [
		FieldJournal.guide_pages(), FieldJournal.guide_total()])
	for i in FieldJournal.blanks.size():
		var p: Dictionary = FieldJournal.blanks[i]
		var b := FieldJournal.bird(String(p.species))
		var thirteen := FieldJournal.is_thirteen_choice(p)
		var note := "\"That's the page Mick never finished. The buyer wants it too.\"" if thirteen \
			else ("\"Mick's page for this one is empty.\"" if not FieldJournal.guide.has(String(p.species))
			else "\"Mick's page for this one is done. Still, it's yours.\"")
		var ros := FieldUI.shop_row(_list, "%s  ·  %s" % [b.get("name", p.species), UiStyle.stars(int(p.stars))], note,
			"Give to Ros", true, SpeciesIcon.bird(b, 44, true))
		# The two answers stacked, so the print's name keeps its line.
		var answers := VBoxContainer.new()
		answers.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ros.get_parent().add_child(answers)
		ros.reparent(answers)
		var buyer := Button.new()
		# Until the first envelope, you don't know there's a buyer.
		buyer.text = "Keep it" if not _buyer_known() else "Keep for the buyer  $%d" % FieldJournal.buyer_offer(p)
		answers.add_child(buyer)
		ros.pressed.connect(_give.bind(i, &"ros"))
		buyer.pressed.connect(_give.bind(i, &"buyer"))


func _give(index: int, to: StringName) -> void:
	var thirteen := index < FieldJournal.blanks.size() and FieldJournal.is_thirteen_choice(FieldJournal.blanks[index])
	var known := _buyer_known()
	var pay := FieldJournal.give_blank(index, to)
	if to == &"ros":
		Activities.say("Ros finds Mick's page for it." + (" The night section's done." if thirteen else ""))
	elif known:
		Activities.say("You keep it. By morning there'll be $%d under your door." % pay)
	else:
		Activities.say("You keep it.")
	refresh()
	_close.grab_focus()


func _buyer_known() -> bool:
	return FieldJournal.money_from_buyer > 0


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
