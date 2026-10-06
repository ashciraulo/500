class_name UiStyle
extends RefCounted
## The game's look for every HUD and menu: one palette, five fonts, the
## styleboxes and a small icon set (inline SVG, drawn at whatever size is
## asked for). The UiTheme autoload merges theme() into Godot's default theme
## at startup, so every Control in the game picks it up without asking.
##
## The idea: a 2013 500's cream dial and amber dot-matrix screen for driving,
## printed cream card with ink, tomato red and Indian Ocean teal for menus,
## and a pencilled field notebook for the journal.

# --- palette ------------------------------------------------------------------------------

const PAPER := Color("f3ead7")
const PAPER_2 := Color("e7d9bd")      # buttons, wells, the darker cream
const PAPER_3 := Color("d3c09c")      # rules and quiet borders
const INK := Color("2a231e")
const INK_2 := Color("5d5146")        # secondary text
const INK_3 := Color("93857a")        # hints, disabled
const RED := Color("c4432f")          # tomato red: primary actions, selection
const RED_DARK := Color("9a3122")
const TEAL := Color("2f7c78")         # the ocean: headings on cream, progress
const TEAL_LIGHT := Color("9fd0c5")
const SUN := Color("e8aa3c")          # mustard: highlights, money
const SUN_LIGHT := Color("f6d48a")
const GOOD := Color("4f8a3f")
const NIGHT := Color("1d2130")        # dark cards (night, the phone's bezel)
const NIGHT_2 := Color("2b3144")
const LCD_BG := Color("1b140b")
const LCD := Color("ffb54a")          # amber dot-matrix
const LCD_DIM := Color("7a5222")
const CREAM_TEXT := Color("fff4dd")   # text straight over the world
const BLUE_INK := Color("27366b")     # M.'s fountain pen
const SHADOW := Color(0.1, 0.07, 0.05, 0.35)
const DIM := Color(0.08, 0.06, 0.05, 0.55)

# --- fonts --------------------------------------------------------------------------------

const BODY_FONT := preload("res://ui/fonts/Jost-Regular.ttf")
const BOLD_FONT := preload("res://ui/fonts/Jost-SemiBold.ttf")
const TITLE_FONT := preload("res://ui/fonts/DMSerifDisplay-Regular.ttf")
const LCD_FONT := preload("res://ui/fonts/VT323-Regular.ttf")
const HAND_FONT := preload("res://ui/fonts/Caveat-Medium.ttf")

const BODY_SIZE := 16

static var _theme: Theme
static var _icons := {}
static var _spaced: FontVariation

## True after the last input came from a gamepad: prompts show pad buttons.
static var using_pad := false


static func body_font() -> Font:
	return BODY_FONT


## Jost SemiBold, opened up a little: section headings and keycaps.
static func spaced_font() -> Font:
	if _spaced == null:
		_spaced = FontVariation.new()
		_spaced.base_font = BOLD_FONT
		_spaced.spacing_glyph = 1
	return _spaced


# --- styleboxes ---------------------------------------------------------------------------

static func box(bg: Color, border := Color.TRANSPARENT, width := 0, radius := 8, margin := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


## The menu card: cream, an ink rule and a hard printed shadow.
static func card(margin := 20.0) -> StyleBoxFlat:
	var s := box(PAPER, INK, 2, 12, margin)
	s.shadow_color = SHADOW
	s.shadow_offset = Vector2(5, 6)
	s.shadow_size = 1
	return s


## A night card: dark blue-black with a cream rule.
static func dark_card(margin := 16.0) -> StyleBoxFlat:
	var s := box(Color(NIGHT, 0.94), Color(PAPER, 0.85), 2, 12, margin)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_offset = Vector2(4, 5)
	s.shadow_size = 1
	return s


## A recessed well on a card (lists, stat blocks).
static func well(margin := 10.0) -> StyleBoxFlat:
	var s := box(PAPER_2, PAPER_3, 1, 8, margin)
	return s


## A cream chip straight over the world (toasts, prompts, the status strip).
static func chip(margin := 10.0) -> StyleBoxFlat:
	var s := box(Color(PAPER, 0.96), INK, 2, 10, margin)
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_offset = Vector2(3, 4)
	s.shadow_size = 1
	return s


static func lcd_box(margin := 8.0) -> StyleBoxFlat:
	var s := box(Color(LCD_BG, 0.92), Color(LCD_DIM, 0.9), 2, 6, margin)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_offset = Vector2(2, 3)
	s.shadow_size = 1
	return s


# --- the theme ----------------------------------------------------------------------------

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = BODY_SIZE

	# Text.
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color(INK, 0.0))
	t.set_constant("line_spacing", "Label", 1)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", BODY_FONT)
	t.set_font("bold_font", "RichTextLabel", BOLD_FONT)

	_variation(t, "TitleLabel", "Label")
	t.set_font("font", "TitleLabel", TITLE_FONT)
	t.set_font_size("font_size", "TitleLabel", 32)
	_variation(t, "SectionLabel", "Label")
	t.set_font("font", "SectionLabel", spaced_font())
	t.set_font_size("font_size", "SectionLabel", 13)
	t.set_color("font_color", "SectionLabel", RED)
	_variation(t, "NoteLabel", "Label")
	t.set_font_size("font_size", "NoteLabel", 14)
	t.set_color("font_color", "NoteLabel", INK_2)
	_variation(t, "HandLabel", "Label")
	t.set_font("font", "HandLabel", HAND_FONT)
	t.set_font_size("font_size", "HandLabel", 23)
	t.set_color("font_color", "HandLabel", INK_2)
	_variation(t, "LcdLabel", "Label")
	t.set_font("font", "LcdLabel", LCD_FONT)
	t.set_font_size("font_size", "LcdLabel", 22)
	t.set_color("font_color", "LcdLabel", LCD)
	_variation(t, "WorldLabel", "Label")
	t.set_color("font_color", "WorldLabel", CREAM_TEXT)
	t.set_color("font_outline_color", "WorldLabel", Color(INK, 0.9))
	t.set_constant("outline_size", "WorldLabel", 5)

	# Panels.
	t.set_stylebox("panel", "PanelContainer", card())
	t.set_stylebox("panel", "Panel", card())
	_variation(t, "DarkPanel", "PanelContainer")
	t.set_stylebox("panel", "DarkPanel", dark_card())
	_variation(t, "WellPanel", "PanelContainer")
	t.set_stylebox("panel", "WellPanel", well())
	_variation(t, "ChipPanel", "PanelContainer")
	t.set_stylebox("panel", "ChipPanel", chip())
	_variation(t, "LcdPanel", "PanelContainer")
	t.set_stylebox("panel", "LcdPanel", lcd_box())
	_variation(t, "BarePanel", "PanelContainer")
	t.set_stylebox("panel", "BarePanel", StyleBoxEmpty.new())

	# Buttons, and everything built on one.
	for type in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		_button_styles(t, type)
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(4)
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var flat := box(Color(PAPER_2, 0.0) if state in ["normal", "pressed", "disabled"] else Color(PAPER_2, 0.9), Color.TRANSPARENT, 0, 6, 4)
			flat.content_margin_left = 6
			flat.content_margin_right = 8
			t.set_stylebox(state, type, flat)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_constant("h_separation", type, 10)
	t.set_icon("unchecked", "CheckBox", icon("check_off", 22))
	t.set_icon("checked", "CheckBox", icon("check_on", 22))
	t.set_icon("unchecked_disabled", "CheckBox", icon("check_off", 22, INK_3))
	t.set_icon("checked_disabled", "CheckBox", icon("check_on", 22, INK_3))
	t.set_icon("radio_unchecked", "CheckBox", icon("radio_off", 22))
	t.set_icon("radio_checked", "CheckBox", icon("radio_on", 22))
	t.set_icon("unchecked", "CheckButton", icon("toggle_off", 0, INK, Vector2(40, 22)))
	t.set_icon("checked", "CheckButton", icon("toggle_on", 0, INK, Vector2(40, 22)))
	t.set_icon("unchecked_disabled", "CheckButton", icon("toggle_off", 0, INK_3, Vector2(40, 22)))
	t.set_icon("checked_disabled", "CheckButton", icon("toggle_on", 0, INK_3, Vector2(40, 22)))
	t.set_icon("arrow", "OptionButton", icon("chevron_down", 16))
	t.set_constant("arrow_margin", "OptionButton", 10)

	_variation(t, "PrimaryButton", "Button")
	var primary := box(RED, INK, 2, 8, 0)
	_pad(primary, 18, 8)
	t.set_stylebox("normal", "PrimaryButton", primary)
	var primary_hover := primary.duplicate() as StyleBoxFlat
	primary_hover.bg_color = RED.lightened(0.12)
	t.set_stylebox("hover", "PrimaryButton", primary_hover)
	var primary_down := primary.duplicate() as StyleBoxFlat
	primary_down.bg_color = RED_DARK
	t.set_stylebox("pressed", "PrimaryButton", primary_down)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "PrimaryButton", CREAM_TEXT)

	# A row in a list (the journal's index, the job board): flat until chosen.
	_variation(t, "ListButton", "Button")
	var row := box(Color(PAPER_2, 0.0), Color.TRANSPARENT, 0, 6, 0)
	_pad(row, 12, 5)
	t.set_stylebox("normal", "ListButton", row)
	var row_hover := row.duplicate() as StyleBoxFlat
	row_hover.bg_color = PAPER_2
	t.set_stylebox("hover", "ListButton", row_hover)
	var row_on := row.duplicate() as StyleBoxFlat
	row_on.bg_color = Color(SUN_LIGHT, 0.85)
	row_on.border_width_left = 4
	row_on.border_color = RED
	t.set_stylebox("pressed", "ListButton", row_on)
	t.set_stylebox("hover_pressed", "ListButton", row_on)
	t.set_stylebox("focus", "ListButton", _focus_ring(6))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "ListButton", INK)
	# Rows carry pictures (the journal's plates): show them in their own colours.
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color", "icon_disabled_color"]:
		t.set_color(c, "ListButton", Color.WHITE)
	t.set_font("font", "ListButton", BODY_FONT)

	# Popups (the option buttons' lists) and tooltips.
	var popup := box(PAPER, INK, 2, 8, 6)
	popup.shadow_color = SHADOW
	popup.shadow_offset = Vector2(3, 4)
	popup.shadow_size = 1
	t.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := box(RED, Color.TRANSPARENT, 0, 5, 4)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", CREAM_TEXT)
	t.set_color("font_disabled_color", "PopupMenu", INK_3)
	t.set_font("font", "PopupMenu", BODY_FONT)
	t.set_font_size("font_size", "PopupMenu", BODY_SIZE)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("h_separation", "PopupMenu", 8)
	t.set_icon("radio_checked", "PopupMenu", icon("dot", 12, RED))
	t.set_icon("radio_unchecked", "PopupMenu", icon("blank", 12))
	t.set_icon("checked", "PopupMenu", icon("dot", 12, RED))
	t.set_icon("unchecked", "PopupMenu", icon("blank", 12))
	t.set_stylebox("panel", "TooltipPanel", box(INK, Color.TRANSPARENT, 0, 6, 8))
	t.set_color("font_color", "TooltipLabel", CREAM_TEXT)

	# Tabs: folder tabs on the card.
	var tab_off := box(PAPER_2, PAPER_3, 2, 0, 0)
	_pad(tab_off, 14, 6)
	tab_off.corner_radius_top_left = 8
	tab_off.corner_radius_top_right = 8
	tab_off.border_width_bottom = 0
	var tab_on := tab_off.duplicate() as StyleBoxFlat
	tab_on.bg_color = RED
	tab_on.border_color = INK
	var tab_hover := tab_off.duplicate() as StyleBoxFlat
	tab_hover.bg_color = SUN_LIGHT
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_unselected", type, tab_off)
		t.set_stylebox("tab_selected", type, tab_on)
		t.set_stylebox("tab_hovered", type, tab_hover)
		t.set_stylebox("tab_disabled", type, tab_off)
		t.set_stylebox("tab_focus", type, _focus_ring(8))
		t.set_color("font_unselected_color", type, INK_2)
		t.set_color("font_selected_color", type, CREAM_TEXT)
		t.set_color("font_hovered_color", type, INK)
		t.set_color("font_disabled_color", type, INK_3)
		t.set_font("font", type, BOLD_FONT)
		t.set_font_size("font_size", type, 15)
		t.set_constant("side_margin", type, 0)
		t.set_constant("h_separation", type, 4)
	var tab_panel := box(PAPER, INK, 2, 0, 12)
	tab_panel.corner_radius_top_right = 8
	tab_panel.corner_radius_bottom_left = 8
	tab_panel.corner_radius_bottom_right = 8
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# Sliders: an ink groove, filled red, and a cream knob.
	var groove := box(PAPER_3, INK, 1, 4, 0)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	var fill := box(RED, INK, 1, 4, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", icon("knob", 20))
	t.set_icon("grabber_highlight", "HSlider", icon("knob_hot", 20))
	t.set_icon("grabber_disabled", "HSlider", icon("knob", 20, INK_3))
	t.set_stylebox("focus", "HSlider", _focus_ring(6))

	# Progress: a teal fill in a cream groove.
	var bar_back := box(PAPER_2, INK, 1, 4, 0)
	var bar_fill := box(TEAL, Color.TRANSPARENT, 0, 4, 0)
	t.set_stylebox("background", "ProgressBar", bar_back)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", INK)

	# Scrolling: a thin ink grabber.
	for type in ["VScrollBar", "HScrollBar"]:
		var track := box(Color(PAPER_3, 0.45), Color.TRANSPARENT, 0, 4, 0)
		track.set_content_margin_all(3)
		var grab := box(Color(INK, 0.55), Color.TRANSPARENT, 0, 4, 0)
		grab.set_content_margin_all(3)
		var grab_hot := grab.duplicate() as StyleBoxFlat
		grab_hot.bg_color = RED
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hot)
		t.set_stylebox("grabber_pressed", type, grab_hot)
		for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(ic, type, icon("blank", 1))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Rules.
	var rule := StyleBoxLine.new()
	rule.color = Color(INK, 0.25)
	rule.thickness = 2
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_constant("separation", "HSeparator", 14)
	var vrule := rule.duplicate() as StyleBoxLine
	vrule.vertical = true
	t.set_stylebox("separator", "VSeparator", vrule)

	# Text entry (the spin box's line edit).
	var field := box(Color("fbf6ea"), INK, 2, 6, 6)
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = RED
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", well(6))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", RED)
	t.set_color("selection_color", "LineEdit", Color(SUN, 0.5))
	t.set_icon("updown", "SpinBox", icon("updown", 16))

	_theme = t
	return t


static func _button_styles(t: Theme, type: String) -> void:
	var normal := box(PAPER_2, INK, 2, 8, 0)
	_pad(normal, 14, 6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = SUN_LIGHT
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = RED
	var hover_pressed := pressed.duplicate() as StyleBoxFlat
	hover_pressed.bg_color = RED.lightened(0.1)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(PAPER_2, 0.5)
	disabled.border_color = Color(INK_3, 0.6)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, hover_pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, _focus_ring(10))
	t.set_font("font", type, BOLD_FONT)
	t.set_font_size("font_size", type, 15)
	t.set_color("font_color", type, INK)
	t.set_color("font_hover_color", type, INK)
	t.set_color("font_focus_color", type, INK)
	t.set_color("font_pressed_color", type, CREAM_TEXT)
	t.set_color("font_hover_pressed_color", type, CREAM_TEXT)
	t.set_color("font_disabled_color", type, INK_3)
	t.set_color("icon_normal_color", type, INK)
	t.set_color("icon_pressed_color", type, CREAM_TEXT)
	t.set_constant("h_separation", type, 8)


static func _focus_ring(radius: int) -> StyleBoxFlat:
	var s := box(Color.TRANSPARENT, RED, 2, radius, 0)
	s.draw_center = false
	s.set_expand_margin_all(3)
	return s


static func _pad(s: StyleBox, h: float, v: float) -> void:
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v


static func _variation(t: Theme, name: String, base: String) -> void:
	t.set_type_variation(name, base)


# --- icons --------------------------------------------------------------------------------

## Small line icons on a 24-unit grid. {c} is the ink colour, {a} the accent.
const ICONS := {
	"blank": "",
	"dot": "<circle cx='12' cy='12' r='6' fill='{c}'/>",
	"check_off": "<rect x='3' y='3' width='18' height='18' rx='4' fill='#fbf6ea' stroke='{c}' stroke-width='2'/>",
	"check_on": "<rect x='3' y='3' width='18' height='18' rx='4' fill='{a}' stroke='{c}' stroke-width='2'/><path d='M7 12.5l3.2 3.2L17.5 8' fill='none' stroke='#fff4dd' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/>",
	"radio_off": "<circle cx='12' cy='12' r='8.5' fill='#fbf6ea' stroke='{c}' stroke-width='2'/>",
	"radio_on": "<circle cx='12' cy='12' r='8.5' fill='#fbf6ea' stroke='{c}' stroke-width='2'/><circle cx='12' cy='12' r='4.5' fill='{a}'/>",
	"toggle_off": "<rect x='2' y='3' width='40' height='18' rx='9' fill='#e7d9bd' stroke='{c}' stroke-width='2'/><circle cx='12' cy='12' r='5.5' fill='{c}'/>",
	"toggle_on": "<rect x='2' y='3' width='40' height='18' rx='9' fill='{a}' stroke='{c}' stroke-width='2'/><circle cx='32' cy='12' r='5.5' fill='#fff4dd' stroke='{c}' stroke-width='1.5'/>",
	"chevron_down": "<path d='M6 9l6 6 6-6' fill='none' stroke='{c}' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/>",
	"chevron_right": "<path d='M9 6l6 6-6 6' fill='none' stroke='{c}' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/>",
	"updown": "<path d='M7 10l5-5 5 5M7 14l5 5 5-5' fill='none' stroke='{c}' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/>",
	"knob": "<circle cx='12' cy='12' r='8' fill='#fff4dd' stroke='{c}' stroke-width='2.2'/><circle cx='12' cy='12' r='2.2' fill='{a}'/>",
	"knob_hot": "<circle cx='12' cy='12' r='9' fill='{a}' stroke='{c}' stroke-width='2.2'/><circle cx='12' cy='12' r='2.4' fill='#fff4dd'/>",
	"money": "<rect x='2.5' y='6' width='19' height='12' rx='2' fill='none' stroke='{c}' stroke-width='2'/><circle cx='12' cy='12' r='2.8' fill='none' stroke='{c}' stroke-width='2'/><path d='M5.5 9v6M18.5 9v6' stroke='{a}' stroke-width='2' stroke-linecap='round'/>",
	"calendar": "<rect x='3.5' y='5' width='17' height='15' rx='2.5' fill='none' stroke='{c}' stroke-width='2'/><path d='M3.5 10h17' stroke='{c}' stroke-width='2'/><path d='M8 3v4M16 3v4' stroke='{c}' stroke-width='2' stroke-linecap='round'/><rect x='7' y='13' width='4' height='4' rx='1' fill='{a}'/>",
	"clock": "<circle cx='12' cy='12' r='8.5' fill='none' stroke='{c}' stroke-width='2'/><path d='M12 7.5V12l3 2' fill='none' stroke='{a}' stroke-width='2.2' stroke-linecap='round'/>",
	"sun": "<circle cx='12' cy='12' r='4.5' fill='{a}' stroke='{c}' stroke-width='1.6'/><path d='M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8' stroke='{c}' stroke-width='2' stroke-linecap='round'/>",
	"moon": "<path d='M15.5 3.5a8.5 8.5 0 1 0 5 13.6A7 7 0 0 1 15.5 3.5z' fill='{a}' stroke='{c}' stroke-width='1.8' stroke-linejoin='round'/>",
	"cloud": "<path d='M7 18h10.5a4 4 0 0 0 .4-8 5.5 5.5 0 0 0-10.6 1.2A3.4 3.4 0 0 0 7 18z' fill='#fff4dd' stroke='{c}' stroke-width='2' stroke-linejoin='round'/>",
	"rain": "<path d='M7 14h10.5a3.6 3.6 0 0 0 .4-7.2 5 5 0 0 0-9.6 1.1A3 3 0 0 0 7 14z' fill='#fff4dd' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><path d='M8 17l-1 3M12 17l-1 3M16 17l-1 3' stroke='{a}' stroke-width='2' stroke-linecap='round'/>",
	"storm": "<path d='M7 13h10.5a3.6 3.6 0 0 0 .4-7.2 5 5 0 0 0-9.6 1.1A3 3 0 0 0 7 13z' fill='#fff4dd' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><path d='M12.5 14l-3 4.5h3.5l-2 4' fill='none' stroke='{a}' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>",
	"fuel": "<rect x='4' y='4' width='10' height='16' rx='1.5' fill='none' stroke='{c}' stroke-width='2'/><rect x='6.5' y='6.5' width='5' height='4' fill='{a}'/><path d='M14 9h2.5a1.5 1.5 0 0 1 1.5 1.5V16a1.5 1.5 0 0 0 3 0V8l-2.5-3' fill='none' stroke='{c}' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>",
	"lock": "<rect x='5' y='10.5' width='14' height='10' rx='2' fill='{a}' stroke='{c}' stroke-width='2'/><path d='M8 10.5V8a4 4 0 0 1 8 0v2.5' fill='none' stroke='{c}' stroke-width='2'/>",
	"pin": "<path d='M12 21s-6.5-6.2-6.5-11a6.5 6.5 0 0 1 13 0c0 4.8-6.5 11-6.5 11z' fill='{a}' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><circle cx='12' cy='10' r='2.3' fill='#fff4dd'/>",
	"star": "<path d='M12 3l2.6 5.6 6.1.7-4.5 4.2 1.2 6L12 16.6 6.6 19.5l1.2-6-4.5-4.2 6.1-.7z' fill='{a}' stroke='{c}' stroke-width='1.8' stroke-linejoin='round'/>",
	"flag": "<path d='M5 21V4' stroke='{c}' stroke-width='2.2' stroke-linecap='round'/><path d='M5 4.5h12l-2.5 4 2.5 4H5' fill='{a}' stroke='{c}' stroke-width='2' stroke-linejoin='round'/>",
	"wrench": "<path d='M14.5 4.2a4.8 4.8 0 0 0-5.8 6.3l-5 5a2 2 0 0 0 2.8 2.8l5-5a4.8 4.8 0 0 0 6.3-5.8l-2.9 2.9-2.4-.5-.5-2.4z' fill='{a}' stroke='{c}' stroke-width='1.8' stroke-linejoin='round'/>",
	"camera": "<path d='M4 8h3.5l1.8-2.5h5.4L16.5 8H20a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z' fill='none' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><circle cx='12' cy='13.2' r='3.4' fill='{a}' stroke='{c}' stroke-width='1.8'/>",
	"car": "<path d='M4 15.5v-3l2-4.5a2 2 0 0 1 1.8-1.2h8.4a2 2 0 0 1 1.8 1.2l2 4.5v3' fill='{a}' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><path d='M3 15.5h18v2H3z' fill='{c}'/><circle cx='7.5' cy='17.5' r='2' fill='#fff4dd' stroke='{c}' stroke-width='1.6'/><circle cx='16.5' cy='17.5' r='2' fill='#fff4dd' stroke='{c}' stroke-width='1.6'/>",
	"binoculars": "<circle cx='7' cy='15' r='4' fill='{a}' stroke='{c}' stroke-width='2'/><circle cx='17' cy='15' r='4' fill='{a}' stroke='{c}' stroke-width='2'/><path d='M5 11l2-6h3v7M19 11l-2-6h-3v7M10 12h4' fill='none' stroke='{c}' stroke-width='2' stroke-linejoin='round'/>",
	"fish": "<path d='M3 12c3-4.5 9-6 14-2l4-3v10l-4-3c-5 4-11 2.5-14-2z' fill='{a}' stroke='{c}' stroke-width='1.8' stroke-linejoin='round'/><circle cx='8' cy='11' r='1.2' fill='{c}'/>",
	"bird": "<path d='M3 13c3.5 0 5-2 6.5-5 1-2 3-3 5-2.5L17 4l.5 3c1.5 1 2 2.8 1.5 4.5l2.5 1-3 .5c-1.5 4-6 6-10.5 5L3 13z' fill='{a}' stroke='{c}' stroke-width='1.6' stroke-linejoin='round'/><circle cx='15.2' cy='7.2' r='1' fill='{c}'/>",
	"note": "<path d='M5 3.5h10l4 4V20.5H5z' fill='#fff4dd' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><path d='M8 11h8M8 14.5h8M8 18h5' stroke='{a}' stroke-width='1.8' stroke-linecap='round'/>",
	"signal": "<path d='M4 19v-3M9 19v-6M14 19v-9M19 19V5' stroke='{c}' stroke-width='3' stroke-linecap='round'/>",
	"battery": "<rect x='2.5' y='7' width='17' height='10' rx='2' fill='none' stroke='{c}' stroke-width='2'/><rect x='5' y='9.5' width='10' height='5' fill='{a}'/><path d='M21.5 10.5v3' stroke='{c}' stroke-width='2' stroke-linecap='round'/>",
	"phone": "<rect x='6.5' y='2.5' width='11' height='19' rx='2.5' fill='{a}' stroke='{c}' stroke-width='2'/><path d='M10.5 18.5h3' stroke='#fff4dd' stroke-width='2' stroke-linecap='round'/>",
	"key": "<circle cx='8' cy='12' r='4.2' fill='{a}' stroke='{c}' stroke-width='2'/><path d='M12 12h9M18 12v3.5M21 12v2.5' fill='none' stroke='{c}' stroke-width='2.2' stroke-linecap='round'/>",
	"badge": "<circle cx='12' cy='12' r='8.5' fill='{a}' stroke='{c}' stroke-width='2'/><text x='12' y='15.6' font-family='sans-serif' font-size='9.5' font-weight='bold' text-anchor='middle' fill='#fff4dd'>500</text>",
	"music": "<path d='M9 17.5V5.5l11-2v12' fill='none' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><circle cx='6.5' cy='17.5' r='2.8' fill='{a}' stroke='{c}' stroke-width='1.8'/><circle cx='17.5' cy='15.5' r='2.8' fill='{a}' stroke='{c}' stroke-width='1.8'/>",
	"eye": "<path d='M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z' fill='#fff4dd' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><circle cx='12' cy='12' r='3.2' fill='{a}' stroke='{c}' stroke-width='1.6'/>",
	"hand": "<path d='M8 13V5.5a1.5 1.5 0 0 1 3 0V11V4a1.5 1.5 0 0 1 3 0v7V5.5a1.5 1.5 0 0 1 3 0V13l.6-1.6a1.5 1.5 0 0 1 2.8 1L18 18a5 5 0 0 1-4.8 3.5H12A5 5 0 0 1 7 16.5V10a1.5 1.5 0 0 1 3 0' fill='{a}' stroke='{c}' stroke-width='1.6' stroke-linejoin='round'/>",
}

## An icon as a texture. Accent defaults to red; ink to INK.
static func icon(name: String, px := 24, ink := INK, size := Vector2.ZERO, accent := RED) -> Texture2D:
	var w := int(size.x) if size != Vector2.ZERO else px
	var h := int(size.y) if size != Vector2.ZERO else px
	var key := "%s/%d/%d/%s/%s" % [name, w, h, ink.to_html(), accent.to_html()]
	if _icons.has(key):
		return _icons[key]
	var body := String(ICONS.get(name, "")).replace("{c}", "#" + ink.to_html(false)).replace("{a}", "#" + accent.to_html(false))
	var vb := "0 0 24 24" if size == Vector2.ZERO else "0 0 %d %d" % [roundi(24.0 * w / h), 24]
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='%s'>%s</svg>" % [w, h, vb, body]
	var image := Image.new()
	var scale := 4.0  # drawn big, then shrunk: smooth edges at small sizes
	var tex: Texture2D
	if image.load_svg_from_string(svg.replace("width='%d' height='%d'" % [w, h], "width='%d' height='%d'" % [w * 4, h * 4]), 1.0) == OK:
		image.resize(w, h, Image.INTERPOLATE_LANCZOS)
		tex = ImageTexture.create_from_image(image)
	else:
		var blank := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
		tex = ImageTexture.create_from_image(blank)
	_icons[key] = tex
	return tex


# --- building blocks ----------------------------------------------------------------------

static func label(parent: Node, text: String, variation := "", size := 0, color := Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = variation
	if variation == "SectionLabel":
		l.uppercase = true
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	if parent:
		parent.add_child(l)
	return l


## A heading row: a small red caps label with a rule running off to the right.
static func section(parent: Node, text: String, color := RED) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := label(row, text, "SectionLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if color != RED:
		l.add_theme_color_override("font_color", color)
	var rule := HSeparator.new()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rule)
	parent.add_child(row)
	return row


## A full-screen dim behind a menu, warm rather than flat black.
static func backdrop() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	return dim


## A centred card holding a VBox; returns [panel, box].
static func centred_card(parent: Node, min_size: Vector2, variation := "") -> Array:
	var panel := PanelContainer.new()
	if variation != "":
		panel.theme_type_variation = variation
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(panel)
	var b := VBoxContainer.new()
	b.custom_minimum_size = min_size
	b.add_theme_constant_override("separation", 10)
	panel.add_child(b)
	animate(panel)
	return [panel, b]


## Menus pop in (a quick fade and a small grow from the centre) and make a
## soft sound as they open and close. centred_card() does this for you.
static func animate(panel: Control) -> void:
	panel.visibility_changed.connect(func() -> void:
		var shown := panel.is_inside_tree() and panel.is_visible_in_tree()
		if shown == bool(panel.get_meta(&"ui_shown", false)):
			return  # not a real open or close (being built, or a parent toggling twice)
		panel.set_meta(&"ui_shown", shown)
		if shown:
			panel.pivot_offset = panel.size * 0.5
			panel.modulate.a = 0.0
			panel.scale = Vector2(0.97, 0.97)
			var tween := panel.create_tween().set_parallel().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tween.tween_property(panel, "modulate:a", 1.0, 0.12)
			tween.tween_property(panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			# The size settles a frame later; keep growing from the middle.
			tween.tween_callback(func() -> void: panel.pivot_offset = panel.size * 0.5).set_delay(0.01)
			sound("ui_menu_select")
		else:
			panel.modulate.a = 1.0
			panel.scale = Vector2.ONE
			sound("ui_menu_back"))


## A quiet UI sound from the audio thread's set (audio/ui), if audio is up.
static func sound(sound_name: String, volume_db := -8.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio := tree.root.get_node_or_null(^"Audio") if tree else null
	if audio and audio.has_method("ui"):
		audio.ui(sound_name, volume_db)


## A title bar for a card: icon, serif title, a subtitle under it, and a
## close button on the right. Returns [title Label, subtitle Label, close Button, row].
static func header(parent: Node, title: String, icon_name := "", subtitle := "", close_text := "Close") -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	if icon_name != "":
		var ic := TextureRect.new()
		ic.texture = icon(icon_name, 34)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	var t := label(titles, title, "TitleLabel")
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	var sub := label(titles, subtitle, "NoteLabel")
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.clip_text = true
	sub.visible = subtitle != ""
	var close: Button = null
	if close_text != "":
		close = Button.new()
		close.text = close_text
		close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(close)
	var rule := HSeparator.new()
	parent.add_child(rule)
	return [t, sub, close, row]


## A small icon as a TextureRect.
static func icon_rect(name: String, px := 20, ink := INK, accent := RED) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(name, px, ink, Vector2.ZERO, accent)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Stars for a 0 to 3 rating, as text in the body font.
static func stars(n: int, of := 3) -> String:
	return "★".repeat(clampi(n, 0, of)) + "☆".repeat(maxi(of - n, 0))


static func number(value: float) -> String:
	var text := str(roundi(absf(value)))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + out


## Gamepad face buttons get their own colours on a keycap.
const PAD_COLOURS := {"A": Color("4f8a3f"), "B": Color("c4432f"), "X": Color("2f6fa8"), "Y": Color("d9a12e")}


## A keyboard key or gamepad button drawn as a little keycap.
static func keycap(key: String, px := 14) -> PanelContainer:
	var cap := PanelContainer.new()
	var pad: bool = PAD_COLOURS.has(key) and using_pad
	var s := box(PAD_COLOURS[key] if pad else Color("fbf6ea"), INK, 2, 999 if pad else 5, 0)
	s.border_width_bottom = 2 if pad else 4
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 1
	s.content_margin_bottom = 2 if pad else 3
	cap.add_theme_stylebox_override("panel", s)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", BOLD_FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", CREAM_TEXT if pad else INK)
	l.custom_minimum_size.x = px * 0.7
	cap.add_child(l)
	return cap
