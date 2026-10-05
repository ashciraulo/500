class_name FieldUI
extends RefCounted
## Small helpers shared by the field journal's screens, in the game's UiStyle.


## A cream card with the shop's colour as a band across the top.
static func panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := UiStyle.card(18)
	style.border_color = UiStyle.INK
	style.border_width_top = 10
	style.border_blend = false
	style.content_margin_top = 22
	p.add_theme_stylebox_override("panel", style)
	# The band in the accent colour, over the ink rule.
	var band_box := UiStyle.box(accent, Color.TRANSPARENT, 0, 0, 0)
	band_box.corner_radius_top_left = 10
	band_box.corner_radius_top_right = 10
	p.draw.connect(func() -> void:
		var r := Rect2(Vector2(2, 2), Vector2(p.size.x - 4, 9))
		p.draw_style_box(band_box, r))
	return p


## A line of text. Size 18 is a section heading in the given colour, 22 and up
## a serif title; anything else is body text.
static func label(parent: Control, text: String, size := 15, color := UiStyle.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size == 18:
		l.theme_type_variation = &"SectionLabel"
		l.uppercase = true
		l.add_theme_color_override("font_color", color)
	elif size >= 22:
		l.theme_type_variation = &"TitleLabel"
		l.add_theme_font_size_override("font_size", size + 4)
		l.add_theme_color_override("font_color", UiStyle.INK if color.get_luminance() > 0.5 else color)
	else:
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## An album photo as a texture, or null.
static func photo_texture(file: String, max_width := 360) -> Texture2D:
	if file == "" or not FileAccess.file_exists(file):
		return null
	var image := Image.load_from_file(file)
	if image == null or image.is_empty():
		return null
	if image.get_width() > max_width:
		image.resize(max_width, roundi(image.get_height() * float(max_width) / image.get_width()), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(image)


## One line on a cream well: a name, a short note under it, and a button or a
## price on the right. Returns the button (null if there isn't one).
static func shop_row(parent: Control, title: String, note := "", action := "", enabled := true) -> Button:
	var well := PanelContainer.new()
	well.theme_type_variation = &"WellPanel"
	parent.add_child(well)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	well.add_child(row)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var t := UiStyle.label(text, title)
	t.add_theme_font_override("font", UiStyle.BOLD_FONT)
	if note != "":
		UiStyle.label(text, note, "NoteLabel")
	if action == "":
		return null
	var b := Button.new()
	b.text = action
	b.disabled = not enabled
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	return b
