extends CanvasLayer
## Minimal driving HUD: speed, gear, rev bar, gearbox mode, clock and weather.
## F1 shows the controls.

@export var car_path: NodePath

const HELP := """W/S or triggers: throttle / brake    A/D or stick: steer    Space / B: handbrake
E/Q or bumpers: gear up / down    G / Select: manual <-> auto    C / Y: camera
L: headlights    R / D-pad down: reset car    Mouse click: look around (interior)
F5: next weather (locks it)    F6: weather lock    F7: +1 hour    F8: clock lock
F9: lo-fi on/off    F1: hide this    Esc / Start: pause and settings    Tab / X: phone (jobs)
F / A: use a workshop, servo or spray shop when parked in its bay    P / L3: photo mode
Radio: . / , station    / on-off    M next track    N next playlist (My Music)    H: horn"""

var _car: CarController
var _speed: Label
var _gear: Label
var _status: Label
var _help: Label
var _rev_bar: ColorRect
var _rev_back: ColorRect
var _objective: Label
var _fuel_bar: ColorRect
var _fuel_label: Label
var _toast: Label
var _toast_queue: PackedStringArray = []
var _toast_time := 0.0


func _ready() -> void:
	_car = get_node_or_null(car_path) as CarController
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_speed = _label(root, 40, Vector2(-220, -110))
	var unit := _label(root, 14, Vector2(-140, -92))
	unit.text = "km/h"
	_gear = _label(root, 40, Vector2(-80, -110))
	_rev_back = ColorRect.new()
	_rev_back.color = Color(0, 0, 0, 0.45)
	_rev_back.size = Vector2(200, 10)
	_rev_back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_rev_back.position = Vector2(-220, -50)
	root.add_child(_rev_back)
	_rev_bar = ColorRect.new()
	_rev_bar.size = Vector2(0, 10)
	_rev_back.add_child(_rev_bar)
	_fuel_label = _label(root, 13, Vector2(-220, -136))
	_fuel_label.text = "FUEL"
	var fuel_back := ColorRect.new()
	fuel_back.color = Color(0, 0, 0, 0.45)
	fuel_back.size = Vector2(150, 6)
	fuel_back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fuel_back.position = Vector2(-170, -128)
	root.add_child(fuel_back)
	_fuel_bar = ColorRect.new()
	_fuel_bar.size = Vector2(150, 6)
	fuel_back.add_child(_fuel_bar)
	_status = _label(root, 16, Vector2.ZERO)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.offset_left = -520
	_status.offset_right = -16
	_status.offset_top = -36
	_status.offset_bottom = -12

	_help = Label.new()
	_help.text = HELP
	_help.position = Vector2(16, 12)
	_help.add_theme_font_size_override("font_size", 14)
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 4)
	_help.visible = Settings.show_help
	root.add_child(_help)

	_objective = Label.new()
	_objective.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_objective.offset_left = -620
	_objective.offset_right = -16
	_objective.offset_top = 12
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.add_theme_font_size_override("font_size", 16)
	_objective.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_objective.add_theme_color_override("font_outline_color", Color.BLACK)
	_objective.add_theme_constant_override("outline_size", 5)
	root.add_child(_objective)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -360
	_toast.offset_right = 360
	_toast.offset_top = 150
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	root.add_child(_toast)

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
		toast("Found it: a %s, rotten but complete. It's waiting on the restoration bench at home." % CarCatalogue.get_car(car_id).get("name", "classic")))
	Classics.restored.connect(func(car_id: String, _finish: String) -> void:
		toast("The %s is finished. Take it out from the Cars tab at home." % CarCatalogue.get_car(car_id).get("name", "classic")))
	Discoveries.discovered.connect(func(id: String) -> void:
		if id.begins_with("spot/"):
			var spot := get_tree().get_root().find_child("Photo_" + id.substr(5), true, false)
			toast("Discovered: %s. A good spot for a photo (P)." % (spot.title if spot else "a photo spot"))
		if id.begins_with("badge/"):
			toast("Found a 500 badge (%d of %d)" % [Collectible.found_count(), Collectible.TOTAL]))
	if _car:
		_car.fuel_low.connect(func() -> void: toast("Fuel's getting low. Time to find a servo."))
		_car.fuel_empty.connect(func() -> void:
			toast("Out of fuel. Call roadside assist from your phone (Tab / X)."))


## Show a message for a few seconds. Messages queue up.
func toast(text: String) -> void:
	_toast_queue.append(text)


func _process(delta: float) -> void:
	_objective.text = Jobs.objective_text()
	_toast_time -= delta
	if _toast_time <= 0.0 and not _toast_queue.is_empty():
		_toast.text = _toast_queue[0]
		_toast_queue.remove_at(0)
		_toast_time = 4.5
	_toast.modulate.a = clampf(_toast_time / 0.6, 0.0, 1.0) if _toast_time < 0.6 else 1.0
	if Input.is_action_just_pressed("toggle_help"):
		_help.visible = not _help.visible
		Settings.show_help = _help.visible
	if not _car:
		return
	_speed.text = "%3d" % roundi(_car.speed_kmh())
	match _car.gear:
		-1: _gear.text = "R"
		0: _gear.text = "N"
		_: _gear.text = str(_car.gear)
	if _car.is_shifting:
		_gear.text = "-"
	var rev := clampf((_car.rpm - 0.0) / _car.limiter_rpm, 0.0, 1.0)
	_rev_bar.size.x = 200.0 * rev
	_rev_bar.color = Color(0.95, 0.3, 0.2) if _car.rpm > _car.redline_rpm else Color(0.95, 0.85, 0.5)
	var fuel := _car.fuel_fraction()
	_fuel_bar.size.x = 150.0 * fuel
	var low := fuel < CarController.LOW_FUEL_FRACTION
	_fuel_bar.color = Color(0.95, 0.3, 0.2) if low else Color(0.85, 0.85, 0.8)
	_fuel_label.modulate.a = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() / 300.0)) if low else 1.0
	var lock := " [locked]"
	_status.text = "$%d  |  Day %d  |  %s  |  %s%s  |  %s%s" % [
		Wallet.balance, GameClock.day,
		"AUTO" if _car.transmission == CarController.Transmission.AUTOMATIC else "MANUAL",
		GameClock.time_string(), lock if GameClock.locked else "",
		Weather.state_name(), lock if Weather.locked else "",
	]


func _label(parent: Control, font_size: int, offset: Vector2) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.position = offset
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label
