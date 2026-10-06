class_name ChallengeCard
extends PanelContainer
## The card at the top right for whatever you're doing right now: the job
## you've taken, or a challenge you've driven into (a parking bay, a scenic
## drive, racing a train). A red tag says what it is, then a line saying what
## to do and a live line of progress (time, bumps, markers left).
##
## Jobs come from Jobs.objective_text(). Challenges are any node in the
## "challenges" group with a challenge_card() that returns {} when idle, or:
##   {"tag": "Parking", "icon": "car", "title": "Mends St",
##    "line": "Pull into the gap and stop.", "detail": "0:07  ·  1 bump"}
## A challenge appearing slides in with a click, so it's hard to miss.

const WIDTH := 340.0
const SLIDE := 60.0

var _tag: Label
var _icon: TextureRect
var _title: Label
var _line: Label
var _detail: Label
var _key := ""
var _shown_for := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiStyle.chip(12)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	custom_minimum_size.x = WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var tag := PanelContainer.new()
	var tag_box := UiStyle.box(UiStyle.RED, Color.TRANSPARENT, 0, 5, 0)
	tag_box.content_margin_left = 7
	tag_box.content_margin_right = 7
	tag.add_theme_stylebox_override("panel", tag_box)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tag)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 4)
	tag.add_child(tag_row)
	_icon = UiStyle.icon_rect("flag", 16, UiStyle.CREAM_TEXT, UiStyle.SUN)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_row.add_child(_icon)
	_tag = UiStyle.label(tag_row, "Job", "SectionLabel")
	_tag.add_theme_color_override("font_color", UiStyle.CREAM_TEXT)
	_tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title = UiStyle.label(top, "", "", 18)
	_title.add_theme_font_override("font", UiStyle.BOLD_FONT)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_line = UiStyle.label(col, "", "", 16)
	_detail = UiStyle.label(col, "", "", 16)
	_detail.add_theme_font_override("font", UiStyle.BOLD_FONT)
	_detail.add_theme_color_override("font_color", UiStyle.TEAL)
	visible = false


## Pin to the top right corner of the parent.
func place_top_right(margin := 16.0) -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -margin - WIDTH
	offset_right = -margin
	offset_top = margin


## What the card should say now: {} for nothing.
func current() -> Dictionary:
	var objective := Jobs.objective_text()
	if objective != "":
		var job: Dictionary = Jobs.active
		return {"tag": "Trial" if job.get("type", "") == "trial" else "Job", "icon": "flag",
			"title": String(job.get("title", "")), "line": objective, "detail": "", "job": true}
	for node in get_tree().get_nodes_in_group(&"challenges"):
		if node.has_method("challenge_card"):
			var card: Dictionary = node.challenge_card()
			if not card.is_empty():
				return card
	return {}


func _process(delta: float) -> void:
	var card := current()
	visible = not card.is_empty()
	if not visible:
		_key = ""
		return
	var key := "%s/%s" % [card.get("tag", ""), card.get("title", "")]
	if key != _key:
		_key = key
		_shown_for = 0.0
		_icon.texture = UiStyle.icon(String(card.get("icon", "flag")), 16, UiStyle.CREAM_TEXT, Vector2.ZERO, UiStyle.SUN)
		_tag.text = String(card.get("tag", ""))
		if not card.get("job", false):
			_click()
	_title.text = String(card.get("title", ""))
	_line.text = String(card.get("line", ""))
	_line.visible = _line.text != ""
	_detail.text = String(card.get("detail", ""))
	_detail.visible = _detail.text != ""
	reset_size()  # shrink to the lines shown now
	# Slide in from the right and flash once, so the eye goes to it.
	_shown_for += delta
	var t := clampf(_shown_for / 0.3, 0.0, 1.0)
	position.x = get_parent_area_size().x - size.x - 16.0 + SLIDE * (1.0 - ease(t, 0.3))
	modulate.a = t
	var flash := clampf(1.0 - absf(_shown_for - 0.45) / 0.25, 0.0, 1.0)
	self_modulate = Color.WHITE.lerp(UiStyle.SUN_LIGHT, flash * 0.8)


func _click() -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has_method("ui"):
		audio.ui("ui_checkpoint", -6.0)
