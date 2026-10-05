class_name PromptChip
extends PanelContainer
## An on-screen prompt as a cream chip: "F  Get in" becomes a keycap and a
## label. Keeps the plain-text interface the prompts already use: set text,
## and an empty text hides it.
##
## Understands "Hold F  Get out", "F / A: use the workshop" (keyboard /
## gamepad, shown to match whichever the player last touched), "Enter / A  Take
## the photo", a title line above ("Carport\nF / A: use the workshop"), and
## plain notes with no key at all.

const _KEY := "^(Hold )?((?:[A-Z0-9]{1,2}|F[0-9]{1,2}|Enter|Space|Esc|Tab|Shift|L[1-3]|R[1-3]|LB|RB|LT|RT)(?: / (?:[A-Z0-9]{1,2}|Enter|Space|Esc|Tab|L[1-3]|R[1-3]|LB|RB|LT|RT))?)(?::\\s*|\\s{1,})(.+)$"

var text := "":
	set(value):
		if value == text and _built_pad == UiStyle.using_pad:
			return
		text = value
		_rebuild()

static var _re: RegEx
var _rows: VBoxContainer
var _built_pad := false


func _init() -> void:
	theme_type_variation = &"ChipPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)
	visible = false
	# Runs while paused so it can step aside for menus and photo mode.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Sit centred along the bottom of the screen, `up` pixels above it.
func place_bottom(up: float) -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = -up
	offset_bottom = -up
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func _process(_delta: float) -> void:
	# A touch dimmer at night so it doesn't glare.
	var night := GameClock.is_night() if is_instance_valid(GameClock) else false
	self_modulate = Color(0.86, 0.83, 0.78) if night else Color.WHITE
	modulate.a = 0.0 if get_tree().paused else 1.0
	if visible and text.strip_edges() == "":
		visible = false  # shown from outside with nothing to say
	elif visible and _built_pad != UiStyle.using_pad:
		_rebuild()


func _rebuild() -> void:
	_built_pad = UiStyle.using_pad
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	visible = text.strip_edges() != ""
	if not visible:
		return
	if _re == null:
		_re = RegEx.create_from_string(_KEY)
	var lines := text.split("\n", false)
	for i in lines.size():
		var line := lines[i].strip_edges()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(row)
		var m := _re.search(line)
		if m == null:
			var plain := UiStyle.label(row, line, "SectionLabel" if lines.size() > 1 and i == 0 else "")
			plain.autowrap_mode = TextServer.AUTOWRAP_OFF
			plain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			continue
		if m.get_string(1) != "":
			UiStyle.label(row, "Hold", "NoteLabel").autowrap_mode = TextServer.AUTOWRAP_OFF
		var keys := m.get_string(2).split(" / ")
		var key := keys[1] if keys.size() > 1 and UiStyle.using_pad else keys[0]
		row.add_child(UiStyle.keycap(key))
		var action := m.get_string(3)
		var l := UiStyle.label(row, action.left(1).to_upper() + action.substr(1))
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
