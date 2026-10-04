extends CanvasLayer
## A small amber head-unit readout that pops up top-right when the radio
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.02, 0.82)
	style.border_color = Color(0.45, 0.3, 0.08, 0.9)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -330
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.offset_bottom = 86
	_panel.modulate.a = 0.0
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_station = _label(16, Color(1.0, 0.68, 0.2))
	_track = _label(13, Color(0.95, 0.8, 0.55))
	box.add_child(_station)
	box.add_child(_track)
	var radio: Node = get_parent().radio
	radio.station_changed.connect(_on_station)
	radio.now_playing.connect(_on_track)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.clip_text = true
	l.custom_minimum_size.x = 300
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
