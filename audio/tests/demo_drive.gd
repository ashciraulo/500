extends SceneTree
## A scripted ~50 second drive for hearing the audio in the real game, and
## for recording it with Godot's movie maker:
##
##   godot --path . --fixed-fps 60 --write-movie build/demo.avi --script res://audio/tests/demo_drive.gd
##
## (add --headless to just run it). Start-up, idle, pulling away through the
## gears, lifting off, a horn tap, then inside the car with the radio on as a
## storm rolls in, and finally coming to a stop.

var _main: Node
var _car: Node
var _rig: Node
var _t := 0.0
var _done := {}
const STEER := 0.1


func _process(delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_rig = _main.get_node("LoFi/SubViewport/World/CameraRig")
		root.get_node("GameClock").set_time(17.4)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_state(0, true)
		root.get_node("Weather").set_locked(true)
		_car.transmission = 0  # manual
		return false
	_t += delta
	_at(0.1, func() -> void:
		var hud := _main.get_node_or_null("HUD")
		if hud and hud.get("_help"):
			hud._help.visible = false)
	_at(4.0, func() -> void: Input.action_press("accelerate"))
	# Lean on the wheel a little so the drive circles inside the test grid.
	_at(9.0, func() -> void: Input.action_press("steer_left", STEER))
	_at(7.0, func() -> void: _car.shift_up())
	_at(11.0, func() -> void: _car.shift_up())
	_at(16.0, func() -> void: Input.action_release("accelerate"))
	_at(19.5, func() -> void: Input.action_press("horn"))
	_at(20.0, func() -> void: Input.action_release("horn"))
	_at(21.0, func() -> void:
		_rig.toggle_mode()
		Input.action_press("accelerate", 0.45))
	_at(22.0, func() -> void: root.get_node("Audio").radio.set_station("cinquecento"))
	_at(29.0, func() -> void: root.get_node("Weather").set_state(2, true))
	_at(33.0, func() -> void: root.get_node("Weather").lightning.emit(1.0, 700.0))
	_at(38.0, func() -> void: root.get_node("Audio").radio.next_station())
	_at(42.0, func() -> void:
		Input.action_release("accelerate")
		Input.action_press("brake", 0.5))
	_at(43.0, func() -> void: root.get_node("Weather").lightning.emit(1.0, 3500.0))
	_at(47.0, func() -> void: _car.shift_down())
	_at(48.0, func() -> void: _car.shift_down())
	_at(52.0, func() -> void:
		Input.action_release("brake")
		Input.action_release("steer_left")
		print("demo finished: %.0f km/h, gear %d" % [_car.speed_kmh(), _car.gear])
		quit(0))
	if int(_t * 2.0) != int((_t - delta) * 2.0):
		print("  t=%4.1f  %3.0f km/h  gear %d  %4.0f rpm  %s" % [_t, _car.speed_kmh(), _car.gear, _car.rpm, _car.global_position.snapped(Vector3.ONE)])
	return false


func _at(time: float, action: Callable) -> void:
	if _t >= time and not _done.has(time):
		_done[time] = true
		action.call()
