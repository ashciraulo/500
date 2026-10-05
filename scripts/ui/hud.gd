extends CanvasLayer
## The driving HUD: the round dash dial (bottom right), a cream status strip
## with money, day, clock and weather (bottom left), the job card (top right),
## messages as little cards that drop in at the top, and the controls card
## (F1).

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
		["L", "D-pad up", "Headlights"],
		["O", "", "Roof (convertibles)"],
		["H", "", "Horn"],
		["R", "D-pad down", "Put the car back upright"],
	]], ["Radio", [
		["/", "", "On and off"],
		[". / ,", "", "Next or last station"],
		["M", "", "Next track"],
		["N", "", "Next playlist (My Music)"],
	]]],
	[["Out and about", [
		["Hold F", "Hold A", "Get out of the car"],
		["F", "A", "Use, open, get in, sleep"],
		["W A S D", "L stick", "Walk (Space to hurry)"],
		["Tab", "X", "Phone: jobs and leads"],
		["P", "L3", "Photo mode"],
		["B", "R3", "Binoculars (stopped or on foot)"],
		["Enter", "A", "Take the photo"],
		["J", "", "Field journal"],
	]], ["The world", [
		["F5 / F6", "D-pad right", "Next weather / hold it"],
		["F7 / F8", "D-pad left", "An hour on / stop the clock"],
		["F9", "", "Lo-fi filter on and off"],
		["F11", "", "Full screen"],
		["Esc", "Start", "Pause and settings"],
		["F1", "", "Hide this card"],
	]]],
]

const TOAST_TOP := 18.0
const TOAST_SECONDS := 4.5

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
var _objective: PanelContainer
var _objective_text: Label
var _toast: PanelContainer
var _toast_icon: TextureRect
var _toast_label: Label
var _toast_queue: PackedStringArray = []
var _toast_time := 0.0
var _night := 0.0


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
	_build_objective()
	_build_toast()
	_build_help()
	_help.visible = Settings.show_help

	Jobs.job_started.connect(func(job: Dictionary) -> void: toast(job.title))
	Jobs.job_completed.connect(func(_job: Dictionary, _pay: int, summary: String) -> void: toast(summary))
	Jobs.place_discovered.connect(func(site: JobSite) -> void: toast("Discovered: %s" % site.label()))
	Progression.challenge_completed.connect(func(_tier: int, challenge: Dictionary) -> void:
		toast("Challenge done: %s" % challenge.title))
	Progression.tier_completed.connect(func(index: int, tier: Dictionary) -> void:
		var names := PackedStringArray()
		for car in Progression.cars_unlocked_at(index + 1):
			names.append(car.name)
		var cars := " The car yard has the %s for you." % " and ".join(names) if not names.is_empty() else ""
		toast("Tier complete: %s! Jobs pay better now.%s" % [tier.title, cars]))
	Progression.reward_unlocked.connect(func(reward: Dictionary) -> void:
		toast("%s: %s. Fit it in any workshop's Extras tab." % [reward.why, reward.title] if reward.get("kind", "") in ["trinket", "livery"] else "%s: %s" % [reward.why, reward.title]))
	add_to_group(&"hud")
	Activities.message.connect(toast)
	Activities.photo_spot_found.connect(func(_id: String, title: String) -> void:
		toast("Photo spot: %s (%d of %d)" % [title, Activities.photo_spots_found(), Activities.PHOTO_SPOTS_TOTAL]))
	Activities.scenic_finished.connect(func(_id: String, title: String) -> void:
		toast("Scenic drive done: %s. Nice one." % title))
	Classics.rumour_heard.connect(func(_car: String, _text: String) -> void:
		toast("New barn-find rumour. Check Leads on your phone (Tab / X)."))
	Classics.wreck_found.connect(func(car_id: String) -> void:
		toast("Found a %s! It's on the bench at home." % CarCatalogue.get_car(car_id).get("name", "classic")))
	Classics.restored.connect(func(car_id: String, _finish: String) -> void:
		toast("The %s is finished. Take it out from the Cars tab at home." % CarCatalogue.get_car(car_id).get("name", "classic")))
	Discoveries.discovered.connect(func(id: String) -> void:
		if id.begins_with("spot/"):
			var spot := get_tree().get_root().find_child("Photo_" + id.substr(5), true, false)
			toast("Discovered: %s. A good spot for a photo (P)." % (spot.title if spot else "a photo spot"))
		if id.begins_with("badge/"):
			toast("Found a 500 badge (%d of %d)" % [Collectible.found_count(), Collectible.TOTAL]))
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


## Show a message for a few seconds. Messages queue up.
func toast(text: String) -> void:
	_toast_queue.append(text)


func _process(delta: float) -> void:
	var objective := Jobs.objective_text()
	_objective.visible = objective != ""
	_objective_text.text = objective

	_toast_time -= delta
	if _toast_time <= 0.0 and not _toast_queue.is_empty():
		_show_toast(_toast_queue[0])
		_toast_queue.remove_at(0)
		_toast_time = TOAST_SECONDS
	var shown := TOAST_SECONDS - _toast_time
	var fade_in := clampf(shown / 0.25, 0.0, 1.0)
	_toast.modulate.a = minf(fade_in, clampf(_toast_time / 0.6, 0.0, 1.0))
	_toast.visible = _toast.modulate.a > 0.0
	# Drop in from just above; sit beside the controls card while it's up.
	_toast.offset_top = TOAST_TOP - 14.0 * (1.0 - ease(fade_in, 0.4))
	_toast.offset_bottom = _toast.offset_top
	if _help.visible:
		_toast.anchor_left = 0.0
		_toast.anchor_right = 0.0
		_toast.grow_horizontal = Control.GROW_DIRECTION_END
		_toast.offset_left = _help.position.x + _help.size.x + 16.0
	else:
		_toast.anchor_left = 0.5
		_toast.anchor_right = 0.5
		_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast.offset_left = 0.0
	_toast.offset_right = _toast.offset_left

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


# --- the job card ---------------------------------------------------------------------------

func _build_objective() -> void:
	_objective = PanelContainer.new()
	_objective.theme_type_variation = &"ChipPanel"
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_objective.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_objective.offset_left = -16
	_objective.offset_right = -16
	_objective.offset_top = 16
	_root.add_child(_objective)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.add_child(row)
	var tag := PanelContainer.new()
	var tag_box := UiStyle.box(UiStyle.RED, Color.TRANSPARENT, 0, 5, 0)
	tag_box.content_margin_left = 7
	tag_box.content_margin_right = 7
	tag.add_theme_stylebox_override("panel", tag_box)
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tag_label := UiStyle.label(tag, "JOB", "SectionLabel")
	tag_label.add_theme_color_override("font_color", UiStyle.CREAM_TEXT)
	tag_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(tag)
	_objective_text = UiStyle.label(row, "")
	_objective_text.custom_minimum_size.x = 300
	_objective_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# --- messages -----------------------------------------------------------------------------

## Which icon and colour a message gets, from what it says.
const TOAST_KINDS := [
	["Discovered", "pin", UiStyle.TEAL],
	["Challenge done", "star", UiStyle.SUN],
	["Tier complete", "flag", UiStyle.RED],
	["Photo spot", "camera", UiStyle.TEAL],
	["Scenic drive", "flag", UiStyle.TEAL],
	["Fuel", "fuel", UiStyle.RED],
	["Out of fuel", "fuel", UiStyle.RED],
	["Found a 500 badge", "badge", UiStyle.RED],
	["Found a ", "car", UiStyle.SUN],
	["New barn-find", "car", UiStyle.SUN],
	["Tyres", "wrench", UiStyle.RED],
	["Brakes", "wrench", UiStyle.RED],
	["Oil", "wrench", UiStyle.RED],
	["Something's due", "wrench", UiStyle.RED],
	["Your binoculars", "binoculars", UiStyle.TEAL],
]


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.theme_type_variation = &"ChipPanel"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = TOAST_TOP
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(row)
	_toast_icon = UiStyle.icon_rect("note", 26)
	row.add_child(_toast_icon)
	_toast_label = UiStyle.label(row, "")
	_toast_label.add_theme_font_size_override("font_size", 17)


func _show_toast(text: String) -> void:
	var icon_name := "note"
	var accent := UiStyle.SUN
	for kind: Array in TOAST_KINDS:
		if text.begins_with(kind[0]):
			icon_name = kind[1]
			accent = kind[2]
			break
	_toast_icon.texture = UiStyle.icon(icon_name, 26, UiStyle.INK, Vector2.ZERO, accent)
	_toast_label.text = text
	# Short ones on one line; long ones wrap at a comfortable width.
	var font := UiStyle.BODY_FONT
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF if width < 520 else TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size.x = 0.0 if width < 520 else 520.0


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
