class_name TitleArt
extends Control
## The title screen's look, ready for whoever builds the title flow: a warm
## wash down the left over whatever's behind (the carport at dusk, say), the
## "500" wordmark, a pencilled tagline, a column of menu buttons and a footer
## line. Logic stays with the caller:
##
##   var art := TitleArt.new()
##   add_child(art)
##   art.add_button("Drive", _on_continue, true)   # true: the main button
##   art.add_button("New game", _on_new)
##   art.add_button("Quit", get_tree().quit)
##   art.footer = "Day 12, Saturday · $1,240"
##   art.focus_first()

## A line under the buttons (the save's day and money, say).
var footer := "":
	set(value):
		footer = value
		if _footer:
			_footer.text = value
			_footer.visible = value != ""

var _column: VBoxContainer
var _buttons: VBoxContainer
var _footer: Label
var _shown := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 88
	column.offset_right = 520
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_column = column

	var mark := Label.new()
	mark.text = "500"
	mark.add_theme_font_override("font", UiStyle.TITLE_FONT)
	mark.add_theme_font_size_override("font_size", 168)
	mark.add_theme_color_override("font_color", UiStyle.CREAM_TEXT)
	mark.add_theme_color_override("font_shadow_color", UiStyle.RED)
	mark.add_theme_constant_override("shadow_offset_x", 7)
	mark.add_theme_constant_override("shadow_offset_y", 7)
	mark.add_theme_constant_override("line_spacing", -40)
	column.add_child(mark)
	var tag := Label.new()
	tag.text = "a slow drive around Perth"
	tag.theme_type_variation = &"HandLabel"
	tag.add_theme_font_size_override("font_size", 34)
	tag.add_theme_color_override("font_color", UiStyle.SUN_LIGHT)
	column.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	column.add_child(gap)

	_buttons = add_group()

	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 18
	column.add_child(gap2)
	_footer = UiStyle.label(column, footer)
	_footer.add_theme_color_override("font_color", Color(UiStyle.CREAM_TEXT, 0.75))
	_footer.visible = footer != ""
	modulate.a = 0.0


## Another column of buttons in the same spot (a "are you sure?" step, say),
## for add_button's parent. Show one group at a time.
func add_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 10)
	group.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if _buttons:
		_column.add_child(group)
		_column.move_child(group, _buttons.get_index() + 1)
	else:
		_column.add_child(group)
	return group


## Add a menu button. The main one is red; the rest cream.
func add_button(text: String, action: Callable, main := false, parent: Container = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 19)
	if main:
		b.theme_type_variation = &"PrimaryButton"
	b.mouse_entered.connect(b.grab_focus)
	b.pressed.connect(action)
	(parent if parent else _buttons).add_child(b)
	return b


func focus_first() -> void:
	if _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Control).grab_focus()


func _process(delta: float) -> void:
	# A slow fade in, like the lights coming up.
	_shown = minf(_shown + delta / 1.2, 1.0)
	modulate.a = ease(_shown, 0.6)


func _draw() -> void:
	# A warm wash down the left so the type reads over any scene.
	var w := size.x * 0.55
	var steps := 48
	for i in steps:
		var t := float(i) / steps
		var a := 0.82 * pow(1.0 - t, 1.6)
		draw_rect(Rect2(Vector2(w * t, 0), Vector2(w / steps + 1.0, size.y)), Color(UiStyle.NIGHT, a))
	# A thin stripe in the three colours along the bottom.
	var y := size.y - 8.0
	draw_rect(Rect2(0, y, size.x / 3.0, 8), UiStyle.TEAL)
	draw_rect(Rect2(size.x / 3.0, y, size.x / 3.0, 8), UiStyle.PAPER)
	draw_rect(Rect2(size.x * 2.0 / 3.0, y, size.x / 3.0 + 1.0, 8), UiStyle.RED)
