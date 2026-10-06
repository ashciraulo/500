class_name JournalScreen
extends CanvasLayer
## The field journal (J): a page per species, birds in one half (with the
## quiet places you've found) and fish in the other (with the fishing spots). Until you find one it's a
## blank with a pencilled hint; then the name, the note, where and when you
## first saw or caught it and your best photo. The game pauses while it's open.

const ACCENT := UiStyle.RED
const PAPER := Color("f4ecda")
const INK := UiStyle.INK
## The cloth cover, a deep bottle green.
const COVER := Color("2d4a42")
const RULE := Color(0.35, 0.5, 0.7, 0.16)
const MARGIN := Color(0.78, 0.3, 0.25, 0.35)

var _list: VBoxContainer
var _page: VBoxContainer
var _summary: Label
var _close: Button
var _selected := ""
## "birds" or "fish".
var _tab := "birds"
var _tab_buttons := {}
var _group: ButtonGroup
## Room tone while one of M.'s pages is open.
var _room: AudioStreamPlayer


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(UiStyle.backdrop())
	# The notebook: a cloth cover with two ruled pages open on it.
	var cover := PanelContainer.new()
	cover.set_anchors_preset(Control.PRESET_CENTER)
	cover.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cover.grow_vertical = Control.GROW_DIRECTION_BOTH
	UiStyle.animate(cover)
	var cloth := UiStyle.box(COVER, UiStyle.INK, 2, 16, 12)
	cloth.shadow_color = UiStyle.SHADOW
	cloth.shadow_offset = Vector2(6, 8)
	cloth.shadow_size = 1
	cover.add_theme_stylebox_override("panel", cloth)
	root.add_child(cover)
	var spread := HBoxContainer.new()
	spread.custom_minimum_size = Vector2(980, 590)
	spread.add_theme_constant_override("separation", 0)
	cover.add_child(spread)

	# Left page: the title, the Birds / Fish bookmarks and the index.
	var left := _paper(true)
	left.custom_minimum_size.x = 360
	spread.add_child(left)
	var index := VBoxContainer.new()
	index.add_theme_constant_override("separation", 6)
	left.add_child(index)
	var header := HBoxContainer.new()
	index.add_child(header)
	var title := FieldUI.label(header, "Field journal", 26, INK)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close = Button.new()
	_close.text = "Close"
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(close)
	header.add_child(_close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	index.add_child(tabs)
	for tab: String in ["birds", "fish"]:
		var b := Button.new()
		b.text = tab.capitalize()
		b.icon = UiStyle.icon("bird" if tab == "birds" else "fish", 20, UiStyle.INK, Vector2.ZERO, UiStyle.TEAL)
		b.toggle_mode = true
		b.pressed.connect(func() -> void:
			if _tab != tab:
				_tab = tab
				_selected = ""
			refresh())
		tabs.add_child(b)
		_tab_buttons[tab] = b
	_summary = FieldUI.label(index, "", 15, INK.lightened(0.25))
	_summary.theme_type_variation = &"HandLabel"
	_summary.add_theme_font_size_override("font_size", 20)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	index.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	scroll.add_child(_list)

	# Right page: the entry.
	var page_panel := _paper(false)
	page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spread.add_child(page_panel)
	var page_scroll := ScrollContainer.new()
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_panel.add_child(page_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 8)
	page_scroll.add_child(_page)
	visible = false


func is_open() -> bool:
	return visible


## A page of the notebook: cream paper with faint blue rules, a red margin on
## the right-hand page, and the shadow of the spine along the inside edge.
func _paper(left_page: bool) -> PanelContainer:
	var page := PanelContainer.new()
	var paper := UiStyle.box(PAPER, Color.TRANSPARENT, 0, 0, 18)
	if left_page:
		paper.corner_radius_top_left = 8
		paper.corner_radius_bottom_left = 8
		paper.content_margin_right = 26
	else:
		paper.corner_radius_top_right = 8
		paper.corner_radius_bottom_right = 8
		paper.content_margin_left = 40
	page.add_theme_stylebox_override("panel", paper)
	page.draw.connect(func() -> void:
		var w := page.size.x
		var h := page.size.y
		var y := 64.0
		while y < h - 8.0:
			page.draw_line(Vector2(10, y), Vector2(w - 10, y), RULE, 1.0)
			y += 28.0
		if not left_page:
			page.draw_line(Vector2(28, 0), Vector2(28, h), MARGIN, 1.5)
		# The spine: a soft shadow into the fold.
		for i in 12:
			var x := w - 1.0 - i if left_page else float(i)
			page.draw_line(Vector2(x, 0), Vector2(x, h), Color(0.25, 0.18, 0.1, 0.16 * (1.0 - i / 12.0)), 1.0))
	return page


func _input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("journal") and not get_tree().paused:
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("journal") or event.is_action_pressed("pause") or event.is_action_pressed("phone"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	var binoculars := get_tree().root.find_child("Binoculars", true, false)
	if binoculars and binoculars.has_method("close"):
		binoculars.close()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	_music(true)


func close() -> void:
	if not visible:
		return
	_room_tone(false)
	visible = false
	get_tree().paused = false
	_music(false)


func refresh() -> void:
	for tab: String in _tab_buttons:
		(_tab_buttons[tab] as Button).set_pressed_no_signal(tab == _tab)
	if _tab == "fish":
		_refresh_fish()
		return
	_summary.text = "%d of %d seen, %d photographed. Film: %d of %d left." % [
		FieldJournal.seen_count(), FieldJournal.species_total(), FieldJournal.photographed_count(),
		FieldJournal.film_left(), FieldJournal.roll_size()]
	var quiet := FieldJournal.places_found()
	if quiet > 0:
		_summary.text += " %d quiet place%s." % [quiet, "" if quiet == 1 else "s"]
	FieldUI.clear(_list)
	_group = ButtonGroup.new()
	var first: Button = null
	var pages_header := false
	for id: String in FieldJournal.bird_order:
		var b := FieldJournal.bird(id)
		if b.get("wrong", false) and not FieldJournal.is_seen(id):
			continue
		if b.get("wrong", false) and not pages_header:
			# The wrong birds come last, on pages that were already written.
			pages_header = true
			FieldUI.label(_list, "Loose pages, in another hand", 14, ACCENT)
		var button := Button.new()
		button.theme_type_variation = &"ListButton"
		button.toggle_mode = true
		button.button_group = _group
		button.button_pressed = id == _selected
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var e := FieldJournal.entry(id)
		if e.is_empty():
			button.text = "? ? ?   (%s)" % FieldJournal.RARITY_NAMES[clampi(int(b.rarity), 1, 4)].to_lower()
			button.modulate = Color(1, 1, 1, 0.55)
		else:
			button.text = "%s  %s" % [b.name, UiStyle.stars(int(e.get("best", 0))) if int(e.get("best", 0)) > 0 else ""]
		# A pencil outline until you've seen it; M.'s loose pages give nothing away.
		button.icon = _blank_icon() if b.get("wrong", false) and e.is_empty() else SpeciesIcon.bird(b, 30, e.is_empty())
		button.pressed.connect(func() -> void:
			_selected = id
			_show(id))
		_list.add_child(button)
		if first == null or id == _selected:
			first = button
	# Quiet places you've stumbled on, at the back of the book.
	var places := FieldJournal.quiet_places().filter(func(h: Dictionary) -> bool: return FieldJournal.is_place_found(h))
	if not places.is_empty():
		FieldUI.label(_list, "Quiet places", 14, ACCENT)
		for h: Dictionary in places:
			var key := "place:" + String(h.id)
			var button := Button.new()
			button.theme_type_variation = &"ListButton"
			button.toggle_mode = true
			button.button_group = _group
			button.button_pressed = key == _selected
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.text = String(h.name)
			button.pressed.connect(func() -> void:
				_selected = key
				_show(key))
			_list.add_child(button)
			if key == _selected:
				first = button
	if _selected.begins_with("place:"):
		_show(_selected)
		if first:
			first.grab_focus()
		return
	if _selected == "" or FieldJournal.bird(_selected).is_empty():
		_selected = FieldJournal.bird_order[0] if not FieldJournal.bird_order.is_empty() else ""
	_show(_selected)
	if first:
		first.set_pressed_no_signal(true)
		first.grab_focus()


func _show(id: String) -> void:
	FieldUI.clear(_page)
	_room_tone(false)
	if id.begins_with("place:"):
		_show_place(FieldJournal.habitat(id.trim_prefix("place:")))
		return
	var b := FieldJournal.bird(id)
	if b.is_empty():
		return
	var e := FieldJournal.entry(id)
	if e.is_empty():
		if not b.get("wrong", false):
			_plate(SpeciesIcon.bird(b, 96, true))
		FieldUI.label(_page, "Not yet seen", 22, INK)
		FieldUI.label(_page, FieldJournal.RARITY_NAMES[clampi(int(b.rarity), 1, 4)], 15, INK.lightened(0.3))
		_pencil("Pencilled in the margin:", String(b.get("hint", "")))
		FieldUI.label(_page, _when(b), 14, INK.lightened(0.3))
		return
	FieldUI.label(_page, b.name, 24, INK)
	if b.get("wrong", false):
		_show_wrong(b, e)
		return
	FieldUI.label(_page, "%s   %s" % [b.get("latin", ""), FieldJournal.RARITY_NAMES[clampi(int(b.rarity), 1, 4)]], 14, INK.lightened(0.3))
	var tex := FieldUI.photo_texture(String(e.get("best_file", "")))
	if tex:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(0, 230)
		_page.add_child(pic)
		FieldUI.label(_page, "Best photo: %s   (%d taken, %d sold)" % [UiStyle.stars(int(e.best)), int(e.photos), int(e.get("sold", 0))], 14, INK)
	else:
		_plate(SpeciesIcon.bird(b, 96))
		FieldUI.label(_page, "No photo yet. Binoculars (B), then Enter / A.", 14, INK.lightened(0.2))
	FieldUI.label(_page, b.get("note", ""), 16, INK)
	FieldUI.label(_page, "First seen: day %d, %s, %s." % [int(e.seen), e.get("time", ""), e.get("where", "somewhere")], 14, INK.lightened(0.2))
	FieldUI.label(_page, "Where to look: %s" % b.get("hint", ""), 14, INK.lightened(0.2))
	FieldUI.label(_page, _when(b), 14, INK.lightened(0.3))
	FieldUI.label(_page, "Prints sell for about $%d (two stars)." % int(b.get("value", 0)), 14, INK.lightened(0.3))


# --- fish ---------------------------------------------------------------------------------

func _refresh_fish() -> void:
	_summary.text = "%d of %d caught. Esky: %d of %d. %d of %d spots found." % [
		FieldJournal.caught_count(), FieldJournal.fish_total(), FieldJournal.esky.size(), FieldJournal.esky_size(),
		_spots_found(), _spots_known()]
	FieldUI.clear(_list)
	_group = ButtonGroup.new()
	var first: Button = null
	for id: String in FieldJournal.fish_order:
		var f := FieldJournal.fish_species(id)
		if (f.get("junk", false) or f.get("wrong", false)) and not FieldJournal.is_caught(id):
			continue
		var e: Dictionary = FieldJournal.catches.get(id, {})
		var label := "? ? ?   (%s)" % FieldJournal.RARITY_NAMES[clampi(int(f.get("rarity", 1)), 1, 4)].to_lower() if e.is_empty() \
			else "%s  %.0f cm" % [f.name, float(e.biggest_cm)]
		first = _list_button(label, id, e.is_empty(), first, SpeciesIcon.fish(f, 30, e.is_empty()))
	FieldUI.label(_list, "Fishing spots", 14, ACCENT)
	for sp: Dictionary in FieldJournal.spots:
		var found := Discoveries.has("fishing/" + String(sp.id))
		if sp.get("hidden", false) and not found:
			continue  # a quiet spot: not even a blank until you find it
		first = _list_button(String(sp.name) if found else "  ? ? ?   (a spot)", "spot:" + String(sp.id), not found, first)
	if _selected == "" or (not _selected.begins_with("spot:") and FieldJournal.fish_species(_selected).is_empty()):
		_selected = FieldJournal.fish_order[0] if not FieldJournal.fish_order.is_empty() else ""
	_show_fish(_selected)
	if first:
		first.set_pressed_no_signal(true)
		first.grab_focus()


func _list_button(text: String, id: String, dim: bool, first: Button, icon: Texture2D = null) -> Button:
	var button := Button.new()
	button.icon = icon
	button.theme_type_variation = &"ListButton"
	button.toggle_mode = true
	button.button_group = _group
	button.button_pressed = id == _selected
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = text
	if dim:
		button.modulate = Color(1, 1, 1, 0.55)
	button.pressed.connect(func() -> void:
		_selected = id
		_show_fish(id))
	_list.add_child(button)
	return button if first == null or id == _selected else first


## Spots the journal knows of: every ordinary one, and the quiet ones you've found.
func _spots_known() -> int:
	return FieldJournal.spots.filter(func(sp: Dictionary) -> bool:
		return not sp.get("hidden", false) or Discoveries.has("fishing/" + String(sp.id))).size()


func _spots_found() -> int:
	var n := 0
	for sp: Dictionary in FieldJournal.spots:
		if Discoveries.has("fishing/" + String(sp.id)):
			n += 1
	return n


func _show_fish(id: String) -> void:
	FieldUI.clear(_page)
	_room_tone(false)
	if id.begins_with("spot:"):
		_show_spot(FieldJournal.spot(id.trim_prefix("spot:")))
		return
	var f := FieldJournal.fish_species(id)
	if f.is_empty():
		return
	var e: Dictionary = FieldJournal.catches.get(id, {})
	if e.is_empty():
		_plate(SpeciesIcon.fish(f, 120, true))
		FieldUI.label(_page, "Not yet caught", 22, INK)
		FieldUI.label(_page, FieldJournal.RARITY_NAMES[clampi(int(f.get("rarity", 1)), 1, 4)], 15, INK.lightened(0.3))
		_pencil("Pencilled in the margin:", String(f.get("hint", "")))
		FieldUI.label(_page, _when(f), 14, INK.lightened(0.3))
		return
	FieldUI.label(_page, f.name, 24, INK)
	if f.get("wrong", false):
		_show_wrong_fish(f, e)
		return
	if String(f.get("latin", "")) != "":
		FieldUI.label(_page, "%s   %s" % [f.latin, FieldJournal.RARITY_NAMES[clampi(int(f.get("rarity", 1)), 1, 4)]], 14, INK.lightened(0.3))
	var tex := FieldUI.photo_texture(String(e.get("best_file", "")))
	if tex:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(0, 230)
		_page.add_child(pic)
	else:
		_plate(SpeciesIcon.fish(f, 120))
	FieldUI.label(_page, f.get("note", ""), 16, INK)
	if not f.get("junk", false):
		FieldUI.label(_page, "Biggest: %.1f cm, %.2f kg.   Caught %d, kept %d, let go %d." % [float(e.biggest_cm), float(e.biggest_kg),
			int(e.caught), int(e.kept), int(e.released)], 15, INK)
		var legal := float(f.get("legal", 0))
		if legal > 0.0:
			FieldUI.label(_page, "Legal size: %.1f cm." % legal, 14, INK.lightened(0.2))
	FieldUI.label(_page, "First caught: day %d, %s, %s." % [int(e.first_day), e.get("time", ""), e.get("where", "somewhere")], 14, INK.lightened(0.2))
	FieldUI.label(_page, "Where to try: %s" % f.get("hint", ""), 14, INK.lightened(0.2))
	FieldUI.label(_page, _when(f), 14, INK.lightened(0.3))


## One of the wrong fish: M.'s 1979 page, like the night birds'.
func _show_wrong_fish(f: Dictionary, e: Dictionary) -> void:
	_show_wrong(f, {"best_file": e.get("best_file", ""), "seen": e.get("first_day", 0), "time": e.get("time", ""),
		"where": e.get("where", "")}, "caught")
	FieldUI.label(_page, String(f.get("note", "")), 15, INK)


## A quiet place: where it is and what you've seen there (the birds that
## only live in places like it are pencilled in until you see them).
func _show_place(h: Dictionary) -> void:
	if h.is_empty():
		return
	FieldUI.label(_page, String(h.name), 24, INK)
	FieldUI.label(_page, "A quiet place you found yourself.", 14, INK.lightened(0.3))
	var seen := PackedStringArray()
	var unseen := 0
	for id: String in FieldJournal.bird_order:
		var b := FieldJournal.bird(id)
		if b.get("wrong", false) or not Array(b.get("places", [])).has(String(h.id)):
			continue
		if FieldJournal.is_seen(id):
			seen.append(String(b.name))
		else:
			unseen += 1
	if not seen.is_empty():
		FieldUI.label(_page, "Only here: %s." % ", ".join(seen), 16, INK)
	if unseen > 0:
		_pencil("Still to see", "something else lives here. Try early or late.")
	var first := 0
	for e: Dictionary in FieldJournal.entries.values():
		if String(e.get("where", "")) == String(h.name):
			first += 1
	if first > 0:
		FieldUI.label(_page, "%d first seen here." % first, 14, INK.lightened(0.2))


func _show_spot(sp: Dictionary) -> void:
	if sp.is_empty():
		return
	if not Discoveries.has("fishing/" + String(sp.id)):
		FieldUI.label(_page, "A spot you haven't found", 22, INK)
		FieldUI.label(_page, "Someone at the tackle shop mentioned it: \"%s\"" % sp.get("hint", ""), 16, INK)
		return
	FieldUI.label(_page, sp.name, 24, INK)
	var water: String = {"river": "The Swan River", "estuary": "The river mouth", "ocean": "The ocean"}.get(String(sp.get("water", "")), "")
	FieldUI.label(_page, "%s, off a %s." % [water, "jetty" if sp.get("kind", "") == "deck" else "shore"], 14, INK.lightened(0.3))
	FieldUI.label(_page, String(sp.get("hint", "")), 16, INK)
	var caught := PackedStringArray()
	for id: String in FieldJournal.catches:
		if String(FieldJournal.catches[id].get("where", "")) == String(sp.name):
			caught.append(String(FieldJournal.fish_species(id).get("name", id)))
	FieldUI.label(_page, "First caught here: %s." % (", ".join(caught) if not caught.is_empty() else "nothing yet"), 14, INK.lightened(0.2))
	if Array(sp.get("tags", [])).has("crabs"):
		FieldUI.label(_page, "A good place to drop a crab net.", 14, INK.lightened(0.2))


## A wrong bird: the page that was already there when you found it.
func _show_wrong(b: Dictionary, e: Dictionary, verb := "saw") -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has("field/m_page_open"):
		audio.play_2d("field/m_page_open", "UI", -6.0)
	_room_tone(true)
	var yours: bool = b.get("page_by", "") == "you"
	FieldUI.label(_page, "The page is already filled in. It's your handwriting." if yours else "A loose page, dated 1979, signed M.", 14, INK.lightened(0.3))
	var hand := FieldUI.label(_page, String(b.get("page", "")), 17, UiStyle.BLUE_INK if not yours else UiStyle.INK_2)
	hand.theme_type_variation = &"HandLabel"
	hand.add_theme_font_size_override("font_size", 25)
	hand.add_theme_constant_override("line_spacing", -2)
	var tex := FieldUI.photo_texture(String(e.get("best_file", "")))
	if tex:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(0, 200)
		_page.add_child(pic)
		FieldUI.label(_page, "Your photo. The lab won't print it.", 14, INK.lightened(0.2))
	FieldUI.label(_page, "You %s it: day %d, %s, %s." % [verb, int(e.seen), e.get("time", ""), e.get("where", "somewhere")], 14, INK.lightened(0.2))


## The journal's own music while it's open, if nothing else is playing (the
## radio has its own player, and mission music is left alone).
func _music(on: bool) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio == null or not audio.has_method("play_music") or not audio.has("music/mus_field_journal"):
		return
	var playing := String(audio.get("_music_name"))
	if on and playing == "":
		audio.play_music("mus_field_journal")
	elif not on and playing == "mus_field_journal":
		audio.stop_music()


func _room_tone(on: bool) -> void:
	if not on:
		if _room:
			_room.queue_free()
			_room = null
		return
	var audio := get_node_or_null("/root/Audio")
	if _room or audio == null or not audio.has_method("stream") or not audio.has("field/m_page_room"):
		return
	_room = AudioStreamPlayer.new()
	_room.stream = audio.stream("field/m_page_room", true)
	_room.bus = "Ambience"
	_room.volume_db = -10.0
	add_child(_room)
	_room.play()


## A pencilled note: a small printed lead-in, then the note in handwriting.
## A field-guide plate on the page, left-aligned.
func _plate(tex: Texture2D) -> void:
	var pic := TextureRect.new()
	pic.texture = tex
	pic.stretch_mode = TextureRect.STRETCH_KEEP
	pic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_page.add_child(pic)


## Same size as a plate in the list, nothing on it.
static func _blank_icon() -> Texture2D:
	return SpeciesIcon.blank(30)


func _pencil(lead: String, note: String) -> void:
	FieldUI.label(_page, lead, 14, INK.lightened(0.3))
	var hand := FieldUI.label(_page, "\"%s\"" % note, 15, Color("6a6058"))
	hand.theme_type_variation = &"HandLabel"
	hand.add_theme_font_size_override("font_size", 24)


static func _when(b: Dictionary) -> String:
	var spans := PackedStringArray()
	for span: Array in b.get("hours", []):
		spans.append("%s to %s" % [_clock(float(span[0])), _clock(float(span[1]))])
	var weather: String = {"dry": ", not in the rain", "wet": ", in the rain"}.get(String(b.get("weather", "any")), "")
	return "About: %s%s." % [", ".join(spans), weather]


static func _clock(h: float) -> String:
	var hour := int(floor(h)) % 24
	var minute := roundi((h - floor(h)) * 60.0)
	var suffix := "am" if hour < 12 else "pm"
	var h12 := hour % 12
	if h12 == 0:
		h12 = 12
	return ("%d %s" % [h12, suffix]) if minute == 0 else ("%d:%02d %s" % [h12, minute, suffix])
