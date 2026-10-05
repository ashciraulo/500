extends CanvasLayer
## A small amber head-unit readout that pops up over the dash dial when the radio
## changes station or track, then fades. Stands in for the dash display until
## the car interior has a real one (which can listen to the same signals:
## Audio.radio.station_changed and now_playing).

const SHOW_S := 4.0

var _panel: PanelContainer
var _station: Label
var _track: Label
var _tween: Tween


func _ready() -> void:
	layer = 50
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"LcdPanel"
	# Sits just above the dash dial, like the head unit over the instruments.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -18
	_panel.offset_right = -18
	_panel.offset_top = -258
	_panel.offset_bottom = -258
	_panel.modulate.a = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	var note := TextureRect.new()
	note.texture = UiStyle.icon("music", 24, UiStyle.LCD, Vector2.ZERO, UiStyle.LCD_DIM)
	note.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(note)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	row.add_child(box)
	_station = _label(24, UiStyle.LCD)
	_track = _label(18, UiStyle.LCD.darkened(0.15))
	box.add_child(_station)
	box.add_child(_track)
	var radio: Node = get_parent().radio
	radio.station_changed.connect(_on_station)
	radio.now_playing.connect(_on_track)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"LcdLabel"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.clip_text = true
	l.custom_minimum_size.x = 270
	return l


func _on_station(_id: String, display_name: String) -> void:
	_station.text = display_name.to_upper()
	_track.text = "· · ·"
	_flash()


func _on_track(id: String, title: String, artist: String) -> void:
	if id == "midnight":
		_track.text = ""
	elif artist != "" and title != "":
		_track.text = "%s - %s" % [artist, title]
	else:
		_track.text = title
	_flash()


func _flash() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.15)
	_tween.tween_interval(SHOW_S)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.8)
