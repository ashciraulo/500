class_name MapScreen
extends CanvasLayer
## The full map: M (or Map on the phone) opens it, north up, with the whole
## city to look round. Drag or use the left stick to move, the wheel or the
## triggers to zoom. Right-click (or F / A at the crosshair) puts down a
## marker; your markers are listed on the side, where you can rename or
## remove them, and the nearest one stays on the minimap's rim. "Go here"
## asks for a suggested route to one (the job you're on comes first).
## The game pauses while it's open.

const ZOOM_MIN := 0.6
const ZOOM_MAX := 40.0
const ZOOM_OPEN := 5.0
## Pan speed with keys or the stick, in screen pixels a second.
const PAN_SPEED := 520.0

const KEY := [
	["home", "Home"], ["flag", "The job you're on"], ["note", "Job places"], ["wrench", "Workshop"],
	["fish", "Tackle, fishing spots"], ["camera", "Photo lab"], ["fuel", "Servo"],
	["bird", "Birds"], ["park", "Parking challenge"], ["quiet", "Quiet places"],
	["route", "Suggested route"],
]

var _root: Control
var _dim: ColorRect
var _panel: PanelContainer
var _view: MapView
var _where: Label
var _markers_box: VBoxContainer
var _marker_group := ButtonGroup.new()
var _name_edit: LineEdit
var _remove: Button
var _go: Button
var _close: Button
var _hint_row: HBoxContainer
var _hint_pad := false
var _count: Label
var _selected := -1
var _dragging := false
var _drag_moved := 0.0
var _zoom := ZOOM_OPEN
var _cross: Control
var _route_wait := 0.0


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"map_screen")
	_build()
	_panel.visible = false
	_dim.visible = false
	SaveGame.register("map", self)


func _exit_tree() -> void:
	SaveGame.unregister("map")


func save_state() -> Dictionary:
	return MapPins.save_state()


func load_state(data: Dictionary) -> void:
	MapPins.load_state(data)
	if is_open():
		_fill_markers()


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if not is_open() and (get_tree().paused or get_tree().get_first_node_in_group(&"title_screen")):
		return  # Another menu has the game paused, or we're on the title screen.
	_set_open(not is_open())


## Opens it whatever else is up (the phone's Map button closes the phone first).
func open() -> void:
	if not is_open():
		_set_open(true)


func _set_open(open: bool) -> void:
	var was_open := _panel.visible
	_panel.visible = open
	_dim.visible = open
	if open:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var p := MapPins.player_position(get_tree())
		if p != Vector3.INF:
			_view.centre = Vector2(p.x, p.z)
			_view.player = Vector2(p.x, p.z)
			_view.player_yaw = MapPins.player_yaw(get_tree())
			var street := MapData.shared().street_at(p)
			var suburb := MapData.shared().suburb_at(p)
			_where.text = ", ".join(PackedStringArray([street, suburb]).slice(0 if street != "" else 1))
		_zoom = ZOOM_OPEN
		_view.metres_per_px = _zoom
		_view.pins = MapPins.gather(get_tree())
		_show_route()
		_selected = -1
		_fill_markers()
		_fill_hints()
		# Nothing focused, so A and F reach the map rather than a button.
		if _root.get_viewport().gui_get_focus_owner():
			_root.get_viewport().gui_get_focus_owner().release_focus()
	elif was_open:
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		if not is_open() and get_tree().paused:
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _name_edit.has_focus():
			_name_edit.release_focus()
		else:
			_set_open(false)
		get_viewport().set_input_as_handled()
	elif _name_edit.has_focus():
		return
	elif event.is_action_pressed("interact"):
		_place_or_pick(_view.size * 0.5)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_X:
		_remove_selected()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y:
		_toggle_route()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_DELETE:
		_remove_selected()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	if _hint_pad != UiStyle.using_pad:
		_fill_hints()
		_cross.queue_redraw()
	if _route_wait > 0.0:
		_route_wait -= delta
		_show_route()
	# Keys and the left stick pan; triggers or Q/E zoom.
	var move := Vector2.ZERO
	if not _name_edit.has_focus():
		move = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if move.length() < 0.2:
			move = Vector2.ZERO
		move.x += float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) \
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		move.y += float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) \
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		move = move.limit_length(1.0)
		var zoom_in := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) + (1.0 if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_EQUAL) else 0.0)
		var zoom_out := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) + (1.0 if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_MINUS) else 0.0)
		var z := zoom_out - zoom_in
		if absf(z) > 0.15:
			_zoom_at(_view.size * 0.5, exp(z * delta * 2.0))
	if move.length() > 0.0:
		_view.centre += move * PAN_SPEED * delta * _view.metres_per_px
		_clamp_centre()
	# The pin under the crosshair (pad, keys) or the cursor.
	var at := _view.get_local_mouse_position() if not UiStyle.using_pad else _view.size * 0.5
	_view.hot_pin = _view.pin_at(at) if Rect2(Vector2.ZERO, _view.size).has_point(at) else -1


func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / 1.25)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.25)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = 0.0
				else:
					_dragging = false
					if _drag_moved < 6.0:
						_pick(mb.position)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_place_or_pick(mb.position)
		_view.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		_view.centre -= mm.relative * _view.metres_per_px
		_clamp_centre()
		_view.accept_event()


func _zoom_at(local: Vector2, factor: float) -> void:
	var before := _view.to_world(local)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_view.metres_per_px = _zoom
	# Keep the spot under the cursor still.
	_view.centre += before - _view.to_world(local)
	_clamp_centre()


func _clamp_centre() -> void:
	var b := MapData.shared().bounds
	if b.size != Vector2.ZERO:
		_view.centre = _view.centre.clamp(b.position, b.end)


## A click: select a marker under it.
func _pick(local: Vector2) -> void:
	var i := _view.pin_at(local)
	if i >= 0 and _view.pins[i].has("marker"):
		_select(int(_view.pins[i].marker))


## Right-click, F / A: select the marker there, or put a new one down.
func _place_or_pick(local: Vector2) -> void:
	var i := _view.pin_at(local)
	if i >= 0 and _view.pins[i].has("marker"):
		_select(int(_view.pins[i].marker))
		return
	var n := MapPins.add_marker(_view.to_world(local))
	if n < 0:
		_count.text = "That's all the markers you can have. Remove one first."
		return
	_refresh_pins()
	_fill_markers()
	_select(n)


func _refresh_pins() -> void:
	_view.pins = MapPins.gather(get_tree())


func _select(i: int) -> void:
	_selected = i
	var rows := _markers_box.get_children()
	if i >= 0 and i < rows.size():
		(rows[i] as Button).button_pressed = true
	var has := i >= 0 and i < MapPins.markers.size()
	_name_edit.editable = has
	_remove.disabled = not has
	_go.disabled = not has or Settings.route_guide == 0
	_go.text = "Stop route" if has and MapPins.route_marker == i else "Go here"
	_name_edit.text = String(MapPins.markers[i].name) if has else ""
	_name_edit.placeholder_text = "Name the marker" if has else "Pick a marker"


func _fill_markers() -> void:
	for c in _markers_box.get_children():
		c.queue_free()
		_markers_box.remove_child(c)
	for i in MapPins.markers.size():
		var m: Dictionary = MapPins.markers[i]
		var b := Button.new()
		b.theme_type_variation = &"ListButton"
		b.toggle_mode = true
		b.button_group = _marker_group
		b.text = String(m.name)
		b.icon = UiStyle.icon("pin", 18, UiStyle.INK, Vector2.ZERO, UiStyle.TEAL)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.pressed.connect(func() -> void:
			_select(i)
			_view.centre = m.at)
		_markers_box.add_child(b)
	_count.text = "Right-click the map to add one." if MapPins.markers.is_empty() else "%d of %d" % [MapPins.markers.size(), MapPins.MAX_MARKERS]
	if UiStyle.using_pad and MapPins.markers.is_empty():
		_count.text = "Press A to add one at the crosshair."
	_select(_selected if _selected < MapPins.markers.size() else -1)


func _rename(text: String) -> void:
	if _selected < 0:
		return
	MapPins.rename_marker(_selected, text)
	var rows := _markers_box.get_children()
	if _selected < rows.size():
		(rows[_selected] as Button).text = String(MapPins.markers[_selected].name)
	_refresh_pins()


func _remove_selected() -> void:
	if _selected < 0:
		return
	MapPins.remove_marker(_selected)
	_selected = -1
	_refresh_pins()
	_fill_markers()


## Go here / Stop route on the selected marker.
func _toggle_route() -> void:
	if _selected < 0 or _selected >= MapPins.markers.size() or Settings.route_guide == 0:
		return
	MapPins.route_marker = -1 if MapPins.route_marker == _selected else _selected
	_select(_selected)
	# The route is found while the map's open (the guide keeps going while
	# the game's paused), and drawn when it comes in.
	_route_wait = 3.0


## The suggested route from where you are, if there is one.
func _show_route() -> void:
	var guide := RouteGuide.of(get_tree())
	if guide and guide.has_route():
		_view.route = guide.ahead()
		_view.route_ends = guide.loose_ends()
	else:
		_view.route = PackedVector2Array()
		_view.route_ends = PackedVector2Array()


# --- building ----------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = UiStyle.backdrop()
	_root.add_child(_dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 28
	_panel.offset_top = 22
	_panel.offset_right = -28
	_panel.offset_bottom = -22
	_root.add_child(_panel)
	UiStyle.animate(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var head: Array = UiStyle.header(box, "Map", "pin", "", "Close")
	_where = head[1]
	_where.visible = true
	_close = head[2]
	_close.pressed.connect(func() -> void: _set_open(false))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	# The map, in a well with an ink edge.
	var well := PanelContainer.new()
	well.theme_type_variation = &"WellPanel"
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PAPER_2, UiStyle.INK, 2, 10, 3))
	body.add_child(well)
	_view = MapView.new()
	_view.show_suburbs = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_view_input)
	_view.metres_per_px = ZOOM_OPEN
	well.add_child(_view)
	var cross := Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(func() -> void:
		if not UiStyle.using_pad:
			return
		var c := cross.size * 0.5
		for d: Vector2 in [Vector2(1, 0), Vector2(0, 1)]:
			cross.draw_line(c - d * 14, c - d * 5, UiStyle.INK, 2.0)
			cross.draw_line(c + d * 5, c + d * 14, UiStyle.INK, 2.0))
	_view.add_child(cross)
	_cross = cross

	# The side: your markers, then the key.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(250, 0)
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	UiStyle.section(side, "Your markers")
	_count = UiStyle.label(side, "", "NoteLabel", 13)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_markers_box = VBoxContainer.new()
	_markers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_markers_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_markers_box)
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 6)
	side.add_child(edit_row)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 28
	_name_edit.text_submitted.connect(func(t: String) -> void:
		_rename(t)
		_name_edit.release_focus())
	_name_edit.focus_exited.connect(func() -> void: _rename(_name_edit.text))
	edit_row.add_child(_name_edit)
	_remove = Button.new()
	_remove.text = "Remove"
	_remove.pressed.connect(_remove_selected)
	edit_row.add_child(_remove)
	_go = Button.new()
	_go.text = "Go here"
	_go.tooltip_text = "Show the way there on the maps"
	_go.pressed.connect(_toggle_route)
	side.add_child(_go)

	UiStyle.section(side, "Key")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	side.add_child(grid)
	for k: Array in KEY:
		var chip := TextureRect.new()
		chip.texture = _key_icon(String(k[0]))
		chip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(chip)
		UiStyle.label(grid, String(k[1]), "", 13, UiStyle.INK_2).autowrap_mode = TextServer.AUTOWRAP_OFF

	_hint_row = HBoxContainer.new()
	_hint_row.add_theme_constant_override("separation", 6)
	box.add_child(_hint_row)


## The key's icons, drawn like the map's pins (a cream disc with an ink edge).
func _key_icon(name: String) -> Texture2D:
	var px := 22
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) * 0.5
	if name == "route":
		# A short stretch of the route line: red with an ink edge.
		for y in px:
			for x in px:
				var d := absf(y + 0.5 - c.y - (x + 0.5 - c.x) * 0.35)
				if x >= 2 and x < px - 2 and d <= 3.2:
					image.set_pixel(x, y, UiStyle.RED if d <= 1.8 else UiStyle.INK)
		return ImageTexture.create_from_image(image)
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= 10.5:
				image.set_pixel(x, y, UiStyle.INK if d > 9.0 else (UiStyle.RED if name == "flag" else UiStyle.PAPER))
	var glyph := (MapView.glyph(name, 14) if MapView.GLYPHS.has(name) else UiStyle.icon(name, 14, UiStyle.CREAM_TEXT if name == "flag" else UiStyle.INK, Vector2.ZERO, _accent(name))).get_image()
	glyph.convert(Image.FORMAT_RGBA8)
	image.blend_rect(glyph, Rect2i(Vector2i.ZERO, glyph.get_size()), Vector2i(4, 4))
	return ImageTexture.create_from_image(image)


static func _accent(name: String) -> Color:
	return {"flag": UiStyle.RED, "note": UiStyle.SUN, "wrench": UiStyle.TEAL, "fish": UiStyle.SUN, "camera": UiStyle.SUN,
		"fuel": UiStyle.SUN, "bird": UiStyle.GOOD}.get(name, UiStyle.RED)


func _fill_hints() -> void:
	_hint_pad = UiStyle.using_pad
	for c in _hint_row.get_children():
		c.queue_free()
	var hints := [["L stick", "Move"], ["RT / LT", "Zoom"], ["A", "Add a marker"], ["X", "Remove it"], ["Y", "Go there"], ["B", "Close"]] if _hint_pad \
		else [["Drag", "Move"], ["Wheel", "Zoom"], ["Right-click", "Add a marker"], ["Del", "Remove it"], ["M", "Close"]]
	for h: Array in hints:
		_hint_row.add_child(UiStyle.keycap(String(h[0]), 12))
		var l := UiStyle.label(_hint_row, String(h[1]), "NoteLabel", 13)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(10, 0)
		_hint_row.add_child(gap)
