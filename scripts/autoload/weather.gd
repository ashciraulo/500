extends Node
## Global weather (autoload: Weather).
##
## Three states: clear, light rain and storm. Left alone, the weather drifts
## between them on its own (Perth leans clear), with slow transitions. The
## player can pick a state and lock it.
##
## Other systems should read the smoothed values (`rain`, `cloud_cover`,
## `wetness`, `wind`) rather than `state`, so changes blend instead of popping.
## Audio hooks: `intensity()` for rain loudness and the `lightning` signal for
## thunder (delay the thunder by distance / 343 m/s).

enum State { CLEAR, LIGHT_RAIN, STORM }

signal state_changed(state: State)
signal lock_changed(locked: bool)
## A lightning strike. `distance_m` is how far away it struck.
signal lightning(strength: float, distance_m: float)

const STATE_NAMES := ["Clear", "Light rain", "Storm"]
const TARGET_RAIN := [0.0, 0.35, 1.0]
const TARGET_CLOUD := [0.15, 0.7, 1.0]
const TARGET_WIND := [0.15, 0.35, 0.9]
## Markov weights for the next state, indexed [current][next].
const NEXT_WEIGHTS := [
	[0.72, 0.23, 0.05],
	[0.45, 0.35, 0.20],
	[0.25, 0.60, 0.15],
]

## Real seconds for a full blend between two states.
@export var transition_seconds := 90.0
## How long (in-game hours) a weather spell lasts before it may change.
@export var min_spell_hours := 1.5
@export var max_spell_hours := 5.0

var state: State = State.CLEAR
var locked := false

## Smoothed 0..1 values.
var rain := 0.0
var cloud_cover := TARGET_CLOUD[State.CLEAR]
var wind := TARGET_WIND[State.CLEAR]
## How wet the roads are. Lags behind rain and dries slowly afterwards.
var wetness := 0.0

var _hours_until_change := 3.0
var _seconds_until_lightning := 10.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_hours_until_change = _rng.randf_range(min_spell_hours, max_spell_hours)


func _process(delta: float) -> void:
	if not locked:
		_hours_until_change -= delta * 24.0 / GameClock.seconds_per_day
		if _hours_until_change <= 0.0:
			_hours_until_change = _rng.randf_range(min_spell_hours, max_spell_hours)
			set_state(_pick_next_state())

	var step := delta / transition_seconds
	rain = move_toward(rain, TARGET_RAIN[state], step)
	cloud_cover = move_toward(cloud_cover, TARGET_CLOUD[state], step)
	wind = move_toward(wind, TARGET_WIND[state], step)

	if rain > 0.02:
		wetness = minf(1.0, wetness + delta * rain * 0.03)
	else:
		# Roads dry faster in sunshine than at night.
		wetness = maxf(0.0, wetness - delta * lerpf(0.002, 0.006, GameClock.daylight()))
	RenderingServer.global_shader_parameter_set("ps1_wetness", wetness)

	if rain > 0.7:
		_seconds_until_lightning -= delta
		if _seconds_until_lightning <= 0.0:
			_seconds_until_lightning = _rng.randf_range(6.0, 28.0)
			lightning.emit(_rng.randf_range(0.4, 1.0), _rng.randf_range(400.0, 6000.0))


## Rain intensity 0..1, for audio and particles.
func intensity() -> float:
	return rain


func set_state(new_state: State, instant := false) -> void:
	if instant:
		rain = TARGET_RAIN[new_state]
		cloud_cover = TARGET_CLOUD[new_state]
		wind = TARGET_WIND[new_state]
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


## Player-facing: step to the next state. Picking a state also locks it, so it
## stays put until the player unlocks.
func cycle_state() -> void:
	set_state(((state + 1) % State.size()) as State)
	set_locked(true)


func set_locked(value: bool) -> void:
	if value == locked:
		return
	locked = value
	lock_changed.emit(locked)


func toggle_locked() -> void:
	set_locked(not locked)


func state_name() -> String:
	return STATE_NAMES[state]


func _pick_next_state() -> State:
	var weights: Array = NEXT_WEIGHTS[state]
	var roll := _rng.randf()
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i as State
	return State.CLEAR
