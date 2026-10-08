extends CanvasLayer
## The driving HUD: the round dash dial (bottom right), a cream status strip
## with money, day, clock and weather (bottom left), the job and challenge
## card (top right, ChallengeCard) and the controls card (F1). Messages are
## the Notices autoload's.

@export var car_path: NodePath

## [keyboard, gamepad, what it does], in columns of sections.
const HELP := [
	[["Driving", [
		["W / S", "RT / LT", "Throttle and brake"],
		["A / D", "L stick", "Steer"],
		["Space", "B", "Handbrake"],
		["E / Q", "RB / LB", "Gear up and down"],
		["G", "Select", "Manual or automatic"],
		["C", "Y", "Chase or interior camera"],
		["Hold Z", "Hold R3", "Look behind"],
		["L", "D-pad up", "Headlights"],
		["O", "", "Roof (convertibles)"],
		["H", "", "Horn"],
		["R", "D-pad down", "Put the car back upright"],
	]], ["Radio", [
		["/", "", "On and off"],
		[". / ,", "", "Next or last station"],
		[";", "", "Next track"],
		["N", "", "Next playlist (My Music)"],
	]]],
	[["Out and about", [
		["Hold F", "Hold A", "Get out of the car"],
		["F", "A", "Use, open, get in, sleep"],
		["W A S D", "L stick", "Walk (Shift to hurry)"],
		["Space", "Y", "Hop up a ledge"],
		["Tab", "X", "Phone: jobs and leads"],
		["P", "L3", "Photo mode"],
		["B", "R3", "Binoculars (stopped or on foot)"],
		["Enter", "A", "Take the photo"],
		["J", "", "Field journal"],
		["M", "", "Map (on the phone too)"],
	]], ["The world", [
		["F5 / F6", "D-pad right", "Next weather / hold it"],
		["F7 / F8", "D-pad left", "An hour on / stop the clock"],
		["F9", "", "Lo-fi filter on and off"],
		["F11", "", "Full screen"],
		["Esc", "Start", "Pause and settings"],
		["F1", "", "Hide this card"],
	]]],
]

var _car: CarController
var _root: Control
var _dash: DashCluster
var _strip: PanelContainer
var _money: Label
var _day: Label
var _clock: Label
var _clock_lock: TextureRect
var _weather_icon: TextureRect
var _weather: Label
var _weather_lock: TextureRect
var _weather_key := ""
var _help: PanelContainer
var _help_pad := false
var _challenge: ChallengeCard
var _night := 0.0
var _minimap: Minimap
var _map_screen: MapScreen


func _ready() -> void:
	_car = get_node_or_null(car_path) as CarController
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# The dial: hidden while the player is out of the car.
	_dash = DashCluster.new()
	_dash.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dash.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dash.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dash.offset_left = -_dash.custom_minimum_size.x - 14.0
	_dash.offset_top = -_dash.custom_minimum_size.y - 10.0
	_dash.offset_right = -14.0
	_dash.offset_bottom = -10.0
	_root.add_child(_dash)

	_build_strip()
	_build_map()
	_challenge = ChallengeCard.new()
	_root.add_child(_challenge)
	_challenge.place_top_right()
	_build_help()
	_help.visible = Settings.show_help
	add_to_group(&"hud")
	if _car:
		_car.fuel_low.connect(func() -> void: toast("Fuel's low. Find a servo."))
		_car.fuel_empty.connect(func() -> void:
			toast("Out of fuel. Call roadside assist on your phone."))
		_car.service_due.connect(func(item: String) -> void:
			toast({"tyres": "Tyres are going bald",
				"brakes": "Brakes are squealing",
				"oil": "Oil change due"}.get(item, "Something's due for a service")))


## Tuck the controls card away (screenshot tools).
func hide_help() -> void:
	_help.visible = false


## Show a message for a few seconds (a Notices card). Messages queue up.
func toast(text: String) -> void:
	Notices.post(text)


## The controls card's right edge while it's up, else 0 (Notices sits clear of it).
func help_right() -> float:
	return _help.position.x + _help.size.x if _help.visible else 0.0


## Where the job and challenge card is, or an empty rect while it's hidden.
func challenge_rect() -> Rect2:
	return _challenge.get_global_rect() if _challenge.visible and visible else Rect2()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_help"):
		_help.visible = not _help.visible
		Settings.show_help = _help.visible
	if _help.visible and _help_pad != UiStyle.using_pad:
		_fill_help()
	_update_strip()
	if not _car:
		_dash.visible = false
		return
	_dash.visible = _car.player_controlled
	if not _dash.visible:
		return
	_night = move_toward(_night, 1.0 if _car.headlights_on else 0.0, delta * 2.5)
	_dash.night = _night
	_minimap.set_night(_night * 0.6)
	_dash.speed_kmh = _car.speed_kmh()
	_dash.rpm = _car.rpm
	_dash.redline_rpm = _car.redline_rpm
	_dash.limiter_rpm = _car.limiter_rpm
	match _car.gear:
		-1: _dash.gear_text = "R"
		0: _dash.gear_text = "N"
		_: _dash.gear_text = str(_car.gear)
	if _car.is_shifting:
		_dash.gear_text = "-"
	_dash.automatic = _car.transmission == CarController.Transmission.AUTOMATIC
	_dash.fuel = _car.fuel_fraction()
	_dash.fuel_low = _dash.fuel < CarController.LOW_FUEL_FRACTION


# --- the minimap and the full map --------------------------------------------------------

func _build_map() -> void:
	# Bottom left, standing on the status strip.
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_minimap.offset_left = 16
	_minimap.offset_bottom = -62
	_minimap.offset_top = _minimap.offset_bottom - _minimap.custom_minimum_size.y
	_root.add_child(_minimap)
	# Suggested routes, which both maps draw (and the road, if it's set to).
	var guide := RouteGuide.new()
	guide.name = "RouteGuide"
	get_parent().add_child.call_deferred(guide)
	# The full map goes last in the scene so Esc reaches it before the pause menu.
	_map_screen = MapScreen.new()
	_map_screen.name = "MapScreen"
	get_parent().add_child.call_deferred(_map_screen)


# --- the status strip ---------------------------------------------------------------------

func _build_strip() -> void:
	_strip = PanelContainer.new()
	_strip.theme_type_variation = &"ChipPanel"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_strip.offset_left = 16
	_strip.offset_top = -16
	_strip.offset_bottom = -16
	_root.add_child(_strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(row)
	row.add_child(UiStyle.icon_rect("money", 20, UiStyle.INK, UiStyle.GOOD))
	_money = _strip_label(row, true)
	_strip_gap(row)
	row.add_child(UiStyle.icon_rect("calendar", 20))
	_day = _strip_label(row)
	_strip_gap(row)
	row.add_child(UiStyle.icon_rect("clock", 20))
	_clock = _strip_label(row)
	_clock_lock = UiStyle.icon_rect("lock", 14, UiStyle.INK, UiStyle.SUN)
	row.add_child(_clock_lock)
	_strip_gap(row)
	_weather_icon = UiStyle.icon_rect("sun", 22, UiStyle.INK, UiStyle.SUN)
	row.add_child(_weather_icon)
	_weather = _strip_label(row)
	_weather_lock = UiStyle.icon_rect("lock", 14, UiStyle.INK, UiStyle.SUN)
	row.add_child(_weather_lock)


func _strip_label(row: HBoxContainer, bold := false) -> Label:
	var l := UiStyle.label(row, "")
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if bold:
		l.add_theme_font_override("font", UiStyle.BOLD_FONT)
	return l


func _strip_gap(row: HBoxContainer) -> void:
	var dot := UiStyle.label(row, "·", "NoteLabel")
	dot.autowrap_mode = TextServer.AUTOWRAP_OFF
	dot.add_theme_color_override("font_color", UiStyle.INK_3)


func _update_strip() -> void:
	_money.text = "$" + UiStyle.number(Wallet.balance)
	_day.text = "Day %d, %s" % [GameClock.day, Garage.weekday().left(3)]
	_clock.text = GameClock.time_string()
	_clock_lock.visible = GameClock.locked
	_weather.text = Weather.state_name()
	_weather_lock.visible = Weather.locked
	var key: String = ["moon" if GameClock.is_night() else "sun", "rain", "storm"][clampi(int(Weather.state), 0, 2)]
	if Weather.state == Weather.State.CLEAR and Weather.cloud_cover > 0.45:
		key = "cloud"
	if key != _weather_key:
		_weather_key = key
		_weather_icon.texture = UiStyle.icon(key, 22, UiStyle.INK, Vector2.ZERO,
			UiStyle.SUN if key in ["sun", "moon"] else UiStyle.TEAL)


# --- the controls card --------------------------------------------------------------------

func _build_help() -> void:
	_help = PanelContainer.new()
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.position = Vector2(16, 16)
	var style := UiStyle.card(14)
	style.bg_color = Color(UiStyle.PAPER, 0.95)
	_help.add_theme_stylebox_override("panel", style)
	_root.add_child(_help)
	_fill_help()


func _fill_help() -> void:
	_help_pad = UiStyle.using_pad
	for child in _help.get_children():
		_help.remove_child(child)
		child.queue_free()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_help.add_child(outer)
	var title := UiStyle.label(outer, "Controls", "TitleLabel", 24)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	outer.add_child(columns)
	for column: Array in HELP:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		columns.add_child(col)
		for section: Array in column:
			UiStyle.section(col, section[0])
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 10)
			grid.add_theme_constant_override("v_separation", 3)
			col.add_child(grid)
			for entry: Array in section[1]:
				var keys: String = entry[1] if _help_pad and entry[1] != "" else entry[0]
				var caps := HBoxContainer.new()
				caps.add_theme_constant_override("separation", 3)
				caps.custom_minimum_size.x = 92
				for k in keys.split(" / "):
					for part in ([k] if k.begins_with("Hold") or k.begins_with("D-pad") or k.begins_with("L stick") else k.split(" ")):
						caps.add_child(UiStyle.keycap(part, 12))
				grid.add_child(caps)
				var what := UiStyle.label(grid, entry[2], "", 14)
				what.autowrap_mode = TextServer.AUTOWRAP_OFF
	var hint := UiStyle.label(outer, "F1 hides this. Your gamepad's buttons show here once you use it." if not _help_pad
		else "Keyboard keys show here when you go back to the keyboard.", "NoteLabel", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
