class_name StoppedClock
extends LateDrive
## The 2:40 clock (STORY.md, event 7). On a late drive from act 3, as the
## clock comes round to twenty to three, the deck clicks on and the dash
## clock and the phone stop at 02:40, while the world carries on: the sky
## gets lighter, the traffic thins. Get out of the car and they jump to the
## real time, and the deck clunks off.
##
## It's the time on the clock in the Dorans' lounge (House1979), and the time
## the porch light gets checked (StoryPeople).

const SHOWN := "02:40"
## It starts as the clock passes 2:40, within this long (hours) of it.
const AT := 2.0 + 40.0 / 60.0
const WINDOW := 0.25
## How much of the late city's look it brings: a touch, the counter turning.
const LOOK := 0.3

var _started_at := 0.0


func _init() -> void:
	event = &"stopped_clock"
	from_act = 3
	every_days = 4
	chance = 0.6


func _ready_to_start() -> bool:
	var h := GameClock.time_of_day
	return (force or (h >= AT and h < AT + WINDOW)) and speed_kmh() > 10.0


func _start() -> void:
	_started_at = GameClock.time_of_day
	GameClock.shown_override = SHOWN
	LateCity.fade_look(LOOK, 3.0)


func _run(_delta: float) -> void:
	# Out of the car, a job taken, or the night over: it lets go.
	if not driving() or not Jobs.active.is_empty() or GameClock.time_of_day >= LateCity.NIGHT_TO + 1.0:
		_let_go()


func _let_go() -> void:
	var now := GameClock.time_string()
	finish()
	Notices.post("The clock says %s. It said 02:40 the whole way." % now, "odd")
	Discoveries.discover("oddity/stopped_clock")
	Story.log_night(&"stopped_clock",
		"The dash clock and the phone stopped at 02:40 for a whole drive. When I got out it was %s." % now)


func _stop() -> void:
	GameClock.shown_override = ""
