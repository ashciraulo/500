class_name LateDrive
extends Node
## What the late city's events out on the road have in common (StoppedClock,
## RepeatStreet, MinimapPassenger, LookoutSignal): whose car it is, whether
## tonight is a night for it, how often it may come back, and the driver
## flashing the headlights (K, or the headlights off and on again quickly,
## for pads), which is how you answer most of them.
##
## A subclass sets `event`, `from_act` and `every_days` in _init(), says when
## it wants to start in _ready_to_start(), and does its thing in _run(). It
## calls begin() and finish() round it; finish() ends the late-city event,
## writes down the day and lets it rest.

## Headlights off and on (or on and off) inside this long (s) counts as a flash.
const DOUBLE_TOGGLE := 1.5

var event: StringName = &""
var from_act := 3
## At most once every this many game days.
var every_days := 3
## The odds, once a night, that tonight is a night for it.
var chance := 0.5
## Tests and the dev panel: ignore the act, the hour, the odds and the gap.
var force := false
var running := false
var last_day := -100

var _car: CarController
var _check := 0.0
var _rolled_night := -1
var _tonight := false
var _toggled_at := -10.0
var _clock := 0.0


func _ready() -> void:
	if event != &"":
		SaveGame.register("late_" + String(event), self)


func _exit_tree() -> void:
	if event != &"":
		SaveGame.unregister("late_" + String(event))
	if running:
		_stop()


func _process(delta: float) -> void:
	_clock += delta
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
		if _car:
			_car.lights_flashed.connect(_flashed)
			_car.headlights_changed.connect(_toggled)
	if running:
		_run(delta)
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if _car and _may_start() and _ready_to_start():
		begin()


## The section-5 rules, the act, the gap since last time and tonight's odds.
func _may_start() -> bool:
	if not driving():
		return false
	if force:
		return not LateCity.active()
	if Story.act() < from_act or GameClock.day < last_day + every_days:
		return false
	if not Jobs.active.is_empty():
		return false
	if not LateCity.allowed_now(true):
		return false
	# One roll a night: the night is the game day it began on (before midnight).
	var night := GameClock.day if GameClock.time_of_day >= 12.0 else GameClock.day - 1
	if night != _rolled_night:
		_rolled_night = night
		_tonight = randf() < chance
	return _tonight


func driving() -> bool:
	return _car != null and is_instance_valid(_car) and _car.player_controlled


func speed_kmh() -> float:
	return absf(_car.speed_kmh()) if _car else 0.0


## Start it now (also called by tests): false if another event is running.
func begin() -> bool:
	if running or not LateCity.begin(event):
		return false
	running = true
	last_day = GameClock.day
	_start()
	return true


## It's over: the deck clunks off.
func finish() -> void:
	if not running:
		return
	running = false
	_stop()
	LateCity.end(event)


func _flashed() -> void:
	if running:
		_on_flash()


func _toggled(_on: bool) -> void:
	if _clock - _toggled_at < DOUBLE_TOGGLE:
		_toggled_at = -10.0
		_flashed()
	else:
		_toggled_at = _clock


# --- For the events themselves ----------------------------------------------------

func _ready_to_start() -> bool:
	return true


func _start() -> void:
	pass


func _run(_delta: float) -> void:
	pass


func _stop() -> void:
	pass


func _on_flash() -> void:
	pass


func save_state() -> Dictionary:
	return {"last_day": last_day}


func load_state(data: Dictionary) -> void:
	last_day = int(data.get("last_day", -100))
