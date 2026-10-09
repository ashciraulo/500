class_name ActCard
extends CanvasLayer
## The act's title card (STORY.md, the five acts), shown like the label on
## the side of a cassette when a new act starts: "SIDE B / Known around
## town", in the middle of the screen for a few seconds with the deck's click.
## StoryPeople shows each act's card once.

const SIDES := ["A", "B", "C", "D", "E"]
const TITLES := ["Getting by", "Known around town", "Small business", "The regular", "Perth legend"]
const HOLD := 4.5
const FADE := 0.8

var _panel: PanelContainer
var _side: Label
var _title: Label
var _t := -1.0


func _ready() -> void:
	layer = 6
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A cassette label: cream card, a red band across the top, a ruled line.
	var style := UiStyle.box(UiStyle.PAPER, UiStyle.INK_2, 2, 6, 0.0)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 14
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", style)
	centre.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(box)
	var band := ColorRect.new()
	band.color = UiStyle.RED
	band.custom_minimum_size = Vector2(320, 6)
	box.add_child(band)
	_side = Label.new()
	_side.add_theme_font_override("font", UiStyle.LCD_FONT)
	_side.add_theme_font_size_override("font_size", 30)
	_side.add_theme_color_override("font_color", UiStyle.INK_2)
	_side.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_side)
	_title = Label.new()
	_title.add_theme_font_override("font", UiStyle.HAND_FONT)
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", UiStyle.BLUE_INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var rule := ColorRect.new()
	rule.color = UiStyle.PAPER_3
	rule.custom_minimum_size = Vector2(320, 2)
	box.add_child(rule)
	_panel.modulate.a = 0.0
	visible = false


func show_act(act: int) -> void:
	var i := clampi(act, 1, 5) - 1
	_side.text = "SIDE %s" % SIDES[i]
	_title.text = TITLES[i]
	_t = 0.0
	visible = true
	LateCity._play_2d(LateCity.SOUND_START, -10.0)


func showing() -> bool:
	return _t >= 0.0


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	if get_tree().paused:
		return
	_t += delta
	var a := clampf(_t / FADE, 0.0, 1.0) * clampf((HOLD + FADE * 2.0 - _t) / FADE, 0.0, 1.0)
	_panel.modulate.a = a
	if _t > HOLD + FADE * 2.0:
		_t = -1.0
		visible = false
