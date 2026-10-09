class_name Minimap
extends Control
## The round minimap in the bottom-left corner: a street-directory map that
## turns with the player so the way they face is always up, a red N on the
## rim for north, nearby places, and the street and suburb they're in on a
## chip just below it. The job you're on and your nearest marker stay on the
## rim when they're off the map, and the suggested route there is drawn on
## it (RouteGuide). M (or Map on the phone) opens the full map.

const DIAMETER := 184.0
const RIM := 7.0
## Metres per pixel: closer in on foot and in town, further out at speed.
const ZOOM_FOOT := 1.0
const ZOOM_SLOW := 1.7
const ZOOM_FAST := 3.4
## How much of the route (m) is worth drawing on a map this small.
const ROUTE_REACH := 900.0

var _disc: Control
var _view: MapView
var _rim: Control
var _chip: PanelContainer
var _street: Label
var _suburb: Label
var _pins_timer := 0.0
var _where_timer := 0.0
var _zoom := ZOOM_SLOW
var _yaw := 0.0
var _have_yaw := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(DIAMETER, DIAMETER + 48)
	# The map, cut to a circle by the disc it sits in.
	_disc = Control.new()
	_disc.name = "Disc"
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.position = Vector2.ZERO
	_disc.size = Vector2(DIAMETER, DIAMETER)
	_disc.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_disc.draw.connect(func() -> void:
		_disc.draw_circle(Vector2.ONE * DIAMETER * 0.5, DIAMETER * 0.5 - RIM + 1.0, Color.WHITE))
	add_child(_disc)
	_view = MapView.new()
	_view.name = "View"
	_view.is_round = true
	_view.rim_inset = RIM + 9.0
	_view.position = Vector2.ZERO
	_view.size = _disc.size
	_disc.add_child(_view)
	# The bezel, the north mark and the rim pins go over the cut.
	_rim = Control.new()
	_rim.name = "Rim"
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim.size = _disc.size
	_rim.draw.connect(_draw_rim)
	add_child(_rim)

	_chip = PanelContainer.new()
	_chip.theme_type_variation = &"ChipPanel"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.position = Vector2(0, DIAMETER + 4)
	_chip.custom_minimum_size = Vector2(DIAMETER, 0)
	_chip.size = Vector2(DIAMETER, 0)
	add_child(_chip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(box)
	_street = UiStyle.label(box, "", "", 15)
	_street.add_theme_font_override("font", UiStyle.BOLD_FONT)
	_suburb = UiStyle.label(box, "", "", 12, UiStyle.INK_2)
	for l: Label in [_street, _suburb]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var p := MapPins.player_position(get_tree())
	if p == Vector3.INF:
		return
	var yaw := MapPins.player_yaw(get_tree())
	# Smooth the turn a little so the map doesn't shiver with the steering.
	if not _have_yaw:
		_yaw = yaw
		_have_yaw = true
	_yaw = lerp_angle(_yaw, yaw, clampf(delta * 8.0, 0.0, 1.0))
	var target := ZOOM_FOOT
	var car := MapPins.player_car(get_tree())
	if MapPins.in_car(get_tree()) and car:
		target = lerpf(ZOOM_SLOW, ZOOM_FAST, smoothstep(20.0, 90.0, absf(car.speed_kmh())))
	_zoom = lerpf(_zoom, target, clampf(delta * 1.5, 0.0, 1.0))
	_view.centre = Vector2(p.x, p.z)
	_view.metres_per_px = _zoom
	_view.turn = _yaw
	_view.player = Vector2(p.x, p.z)
	_view.player_yaw = yaw
	_view.ghost = MinimapPassenger.shown
	_view.ghost_yaw = MinimapPassenger.shown_yaw
	_view.ghost_alpha = MinimapPassenger.alpha
	_pins_timer -= delta
	if _pins_timer <= 0.0:
		_pins_timer = 1.0
		MapPins.note_spots(p)
		_view.pins = MapPins.gather(get_tree(), true)
	var guide := RouteGuide.of(get_tree())
	if guide and guide.has_route():
		_view.route = guide.ahead(ROUTE_REACH)
		_view.route_ends = guide.loose_ends()
	elif not _view.route.is_empty() or not _view.route_ends.is_empty():
		_view.route = PackedVector2Array()
		_view.route_ends = PackedVector2Array()
	_where_timer -= delta
	if _where_timer <= 0.0:
		_where_timer = 0.4
		_update_where(p)
	_rim.queue_redraw()


func set_night(amount: float) -> void:
	_view.night = amount


func _update_where(p: Vector3) -> void:
	var data := MapData.shared()
	var street := data.street_at(p)
	var suburb := data.suburb_at(p)
	if street == "":
		street = suburb
		suburb = ""
	_street.text = street if street != "" else "Perth"
	_suburb.text = suburb
	_suburb.visible = suburb != ""


func _draw_rim() -> void:
	var c := Vector2.ONE * DIAMETER * 0.5
	var r := DIAMETER * 0.5
	# A cream bezel with an ink edge either side, like the dial's.
	_rim.draw_arc(c + Vector2(2, 3), r - 1.5, 0, TAU, 96, UiStyle.SHADOW, 3.0, true)
	_rim.draw_arc(c, r - RIM * 0.5, 0, TAU, 96, UiStyle.PAPER, RIM, true)
	_rim.draw_arc(c, r - 1.0, 0, TAU, 96, UiStyle.INK, 2.0, true)
	_rim.draw_arc(c, r - RIM, 0, TAU, 96, UiStyle.INK, 1.5, true)
	# North: a red tab on the rim, turned with the map.
	var north := c + Vector2(0, -(r - RIM * 0.5)).rotated(_view.turn)
	_rim.draw_circle(north + Vector2(1, 2), 10.0, UiStyle.SHADOW)
	_rim.draw_circle(north, 10.0, UiStyle.INK)
	_rim.draw_circle(north, 8.5, UiStyle.RED)
	var font := UiStyle.BOLD_FONT
	var w := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_rim.draw_string(font, north + Vector2(-w * 0.5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.CREAM_TEXT)
