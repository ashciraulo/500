extends Node
## Global time of day for the whole game (autoload: GameClock).
##
## Time runs in in-game hours (0.0 to 24.0). Days are long on purpose: the
## default is 40 real minutes per in-game day, so a lap of the city at dusk
## actually feels like dusk. The player can lock the clock to keep their
## favourite time of day.
##
## The sun follows Perth's real path for early October: it rises in the east,
## arcs through the NORTHERN sky (southern hemisphere) and sets in the west.

signal hour_changed(hour: int)
signal day_started(day: int)
signal lock_changed(locked: bool)

const PERTH_LATITUDE_DEG := -31.95
## Solar declination for early October (just after the spring equinox).
const DECLINATION_DEG := -4.6

## Real seconds per in-game day.
@export var seconds_per_day := 2400.0

var time_of_day := 8.5
var day := 1
var locked := false


func _process(delta: float) -> void:
	if not locked:
		advance(delta * 24.0 / seconds_per_day)


## Move the clock forward by `hours` (can be negative).
func advance(hours: float) -> void:
	var previous_hour := int(time_of_day)
	time_of_day += hours
	while time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
		day_started.emit(day)
	while time_of_day < 0.0:
		time_of_day += 24.0
		day = maxi(1, day - 1)
	if int(time_of_day) != previous_hour:
		hour_changed.emit(int(time_of_day))


func set_time(hours: float) -> void:
	advance(fposmod(hours, 24.0) - time_of_day)


func set_locked(value: bool) -> void:
	if value == locked:
		return
	locked = value
	lock_changed.emit(locked)


func toggle_locked() -> void:
	set_locked(not locked)


## Unit vector pointing from the ground TOWARDS the sun, in world space.
## World axes: -Z is north, +X is east, +Y is up.
func sun_direction() -> Vector3:
	var lat := deg_to_rad(PERTH_LATITUDE_DEG)
	var dec := deg_to_rad(DECLINATION_DEG)
	var hour_angle := deg_to_rad((time_of_day - 12.0) * 15.0)
	var east := -cos(dec) * sin(hour_angle)
	var north := cos(lat) * sin(dec) - sin(lat) * cos(dec) * cos(hour_angle)
	var up := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hour_angle)
	return Vector3(east, up, -north).normalized()


## Sine of the sun's elevation: 1 overhead, 0 at the horizon, negative at night.
func sun_height() -> float:
	return sun_direction().y


## 0 at full night, 1 in full daylight, smooth through dawn and dusk.
func daylight() -> float:
	return smoothstep(-0.12, 0.22, sun_height())


func is_night() -> bool:
	return daylight() < 0.35


func time_string() -> String:
	var minutes := int(time_of_day * 60.0) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
