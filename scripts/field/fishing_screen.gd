class_name FishingScreen
extends CanvasLayer
## What's drawn over the view while fishing: the prompt at a spot, the swing
## meter, the fight's tension and line, the esky count, and the catch card
## (keep it, let it go, take its photo).

const ACCENT := Color(0.55, 0.8, 0.95)

var fishing: FieldFishing

var _overlay: Control
var _prompt: Label
var _card: PanelContainer
var _card_box: VBoxContainer
var _card_note: Label
var _keep: Button
var _font: Font
var _message := ""
var _message_time := 0.0
var _flash := 0.0


func _ready() -> void:
	layer = 6
	_font = ThemeDB.fallback_font
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -240.0
	_prompt.offset_right = 240.0
	_prompt.offset_top = -126.0
	_prompt.offset_bottom = -102.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 5)
	add_child(_prompt)
	_card = FieldUI.panel(ACCENT)
	_card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = -400.0
	_card.offset_right = -40.0
	_card_box = VBoxContainer.new()
	_card_box.custom_minimum_size = Vector2(340, 0)
	_card_box.add_theme_constant_override("separation", 6)
	_card.add_child(_card_box)
	_card.visible = false
	add_child(_card)


func _process(delta: float) -> void:
	_message_time = maxf(_message_time - delta, 0.0)
	_flash = maxf(_flash - delta * 3.0, 0.0)
	if fishing:
		_prompt.text = fishing.prompt()
	_overlay.queue_redraw()


func say(text: String) -> void:
	_message = text
	_message_time = 4.0


# --- the catch card ---------------------------------------------------------------------------

func open_card(c: Dictionary) -> void:
	FieldUI.clear(_card_box)
	var f := FieldJournal.fish_species(String(c.species))
	var junk: bool = c.get("junk", false)
	FieldUI.label(_card_box, String(f.get("name", c.species)), 24, ACCENT)
	if String(f.get("latin", "")) != "":
		FieldUI.label(_card_box, String(f.latin), 13, Color(0.75, 0.75, 0.7))
	if junk:
		FieldUI.label(_card_box, String(f.get("note", "")), 15)
	else:
		var size_text := "%.1f cm across the shell" % float(c.cm) if String(f.get("method", "")) == "net" else "%.1f cm" % float(c.cm)
		FieldUI.label(_card_box, "%s   %.2f kg" % [size_text, float(c.kg)], 18)
		var legal := float(f.get("legal", 0))
		if legal > 0.0:
			var ok: bool = c.get("legal", false)
			FieldUI.label(_card_box, ("Legal size (%.0f cm)" if ok else "Undersize (needs %.0f cm)") % legal, 14,
				Color(0.7, 0.95, 0.7) if ok else Color(1, 0.65, 0.5))
		if c.get("first", false):
			FieldUI.label(_card_box, "First one in the journal.", 15, Color(1, 0.9, 0.6))
		var e: Dictionary = FieldJournal.catches.get(String(c.species), {})
		if not c.get("first", false) and not e.is_empty() and float(c.cm) >= float(e.biggest_cm):
			FieldUI.label(_card_box, "Your biggest yet.", 15, Color(1, 0.9, 0.6))
		var pay := int(f.get("pay", 0))
		if pay > 0:
			FieldUI.label(_card_box, "About $%d at the weigh-in, kept on ice." % FieldJournal.fish_value(
				{"species": c.species, "kg": c.kg, "caught_at": FieldJournal.now_minutes()}), 14, Color(0.85, 0.85, 0.8))
		FieldUI.label(_card_box, String(f.get("note", "")), 13, Color(0.82, 0.82, 0.78))
	_card_note = FieldUI.label(_card_box, "", 14, Color(1, 0.9, 0.6))
	var why := fishing.keep_blocked(c)
	if why != "":
		_card_note.text = why
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_card_box.add_child(row)
	_keep = _button(row, "Keep  (F)" if not junk else "Take it home  (F)", "keep")
	_keep.disabled = why != ""
	var release := _button(row, "Let it go  (R)" if not junk else "Throw it back  (R)", "release")
	_button(row, "Photo  (C)", "photo")
	_card.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(release if _keep.disabled else _keep).grab_focus.call_deferred()


func _button(row: HBoxContainer, text: String, action: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: fishing.choose(action))
	row.add_child(b)
	return b


func close_card() -> void:
	_card.visible = false


func hide_card(hidden: bool) -> void:
	_card.visible = not hidden
	_overlay.visible = not hidden
	_prompt.visible = not hidden


func card_note(text: String) -> void:
	if is_instance_valid(_card_note):
		_card_note.text = text


func card_open() -> bool:
	return _card.visible


func _input(event: InputEvent) -> void:
	if not _card.visible or fishing == null or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F:
				fishing.choose("keep" if not _keep.disabled else "release")
			KEY_R:
				fishing.choose("release")
			KEY_C:
				fishing.choose("photo")
			_:
				return
		get_viewport().set_input_as_handled()


# --- the overlay --------------------------------------------------------------------------------

func _draw_overlay() -> void:
	if fishing == null:
		return
	var size := _overlay.size
	var centre := size * 0.5
	var ink := Color(0.95, 0.97, 1.0, 0.85)
	if _message_time > 0.0:
		_text(_message, Vector2(centre.x, size.y * 0.14), 19, Color(1, 0.96, 0.86, minf(_message_time, 1.0)))
	if fishing.state == FieldFishing.State.IDLE:
		return
	var hint := ""
	match fishing.state:
		FieldFishing.State.READY:
			hint = "Hold F / A to swing back, let go to cast where you're looking.    Esc / B  put the rod away"
		FieldFishing.State.CHARGING:
			_meter(Vector2(centre.x, size.y * 0.78), 260.0, fishing.power, Color(0.95, 0.85, 0.5), "Cast")
			hint = "Let go to cast"
		FieldFishing.State.WAITING:
			hint = "Watch the float. When it goes under: F / A to strike.    Esc / B  wind in"
		FieldFishing.State.BITE:
			_text("!", Vector2(centre.x, centre.y - 40.0), 64, Color(1, 0.85, 0.4))
			hint = "Strike!  F / A"
		FieldFishing.State.FIGHT:
			_draw_fight(size)
			hint = "Hold F / A to reel, let go to give it line. Ease off when the rod tip shivers."
	_text(hint, Vector2(centre.x, size.y - 16.0), 14, Color(0.88, 0.9, 0.9, 0.85))
	# The esky, in the corner.
	var esky := "ESKY %d / %d" % [FieldJournal.esky.size(), FieldJournal.esky_size()]
	var ice := FieldJournal.ice_left_hours()
	if not FieldJournal.esky.is_empty():
		esky += "   ice %s" % ("%.0f h" % ice if ice > 0.0 else "gone")
	_text(esky, Vector2(size.x - 120.0, size.y - 44.0), 15, ink if ice > 0.0 or FieldJournal.esky.is_empty() else Color(1, 0.6, 0.45))


func _draw_fight(size: Vector2) -> void:
	var at := Vector2(size.x * 0.5, size.y * 0.8)
	var t := fishing.tension
	var col := Color(0.5, 0.85, 0.55).lerp(Color(1.0, 0.35, 0.25), clampf((t - 0.5) * 2.0, 0.0, 1.0))
	_meter(at, 320.0, t, col, "Line tension")
	# The danger zone at the top end.
	draw_rect_on(Rect2(at + Vector2(160.0 - 320.0 * 0.12, -9.0), Vector2(320.0 * 0.12, 18.0)), Color(1, 0.3, 0.2, 0.25))
	_text("%d m" % roundi(fishing.line_out), at + Vector2(0, 40.0), 16, Color(0.9, 0.95, 1.0))
	if fishing.warning:
		_text("The rod tip's shivering...", at + Vector2(0, -44.0), 17, Color(1, 0.85, 0.45))
	elif fishing.surging:
		_text("It's running!", at + Vector2(0, -44.0), 18, Color(1, 0.55, 0.4))


func _meter(at: Vector2, width: float, value: float, color: Color, label: String) -> void:
	var r := Rect2(at - Vector2(width * 0.5, 9.0), Vector2(width, 18.0))
	_overlay.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.55))
	_overlay.draw_rect(Rect2(r.position, Vector2(width * clampf(value, 0.0, 1.0), 18.0)), color)
	_overlay.draw_rect(r, Color(1, 1, 1, 0.5), false, 1.5)
	_text(label, at + Vector2(0, -16.0), 13, Color(0.9, 0.92, 0.9, 0.8))


func draw_rect_on(r: Rect2, color: Color) -> void:
	_overlay.draw_rect(r, color)


func _text(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var pos := at - Vector2(w * 0.5, 0)
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
		_overlay.draw_string(_font, pos + o * 1.5, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8 * color.a))
	_overlay.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
