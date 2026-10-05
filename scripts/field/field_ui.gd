class_name FieldUI
extends RefCounted
## Small helpers shared by the field journal's screens, in the phone's style.


static func panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.085, 0.08, 0.97)
	style.border_color = accent
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", style)
	return p


static func label(parent: Control, text: String, size := 15, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
