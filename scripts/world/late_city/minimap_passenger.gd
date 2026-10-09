class_name MinimapPassenger
extends LateDrive
## The minimap passenger (STORY.md, event 12). From act 4, now and then on a
## late drive, the deck clicks on and a second arrow turns up on the minimap,
## a little way behind yours, following every turn you made. There's nothing
## in the mirror. Slow down and it closes up. Flash the headlights and it
## fades off the map; leave it, and after a while it goes on its own.
##
## The minimap reads `shown`, `shown_yaw` and `alpha` (Minimap, MapView).

## Where the second arrow is (x/z; INF when it isn't), which way it faces,
## and how solid it is (0..1).
static var shown := Vector2.INF
static var shown_yaw := 0.0
static var alpha := 0.0

const MIN_KMH := 25.0
## How far behind (m) along the way you came, and how close it creeps when
## you stop.
const FOLLOW := 40.0
const CLOSEST := 12.0
const CREEP := 1.5
## It turns up from this far back, over this long (s).
const ARRIVE_FROM := 140.0
const ARRIVE := 6.0
const SOLID := 0.85
## It goes by itself after this long (s).
const LASTS := 150.0
const FADE := 1.2
## The trail: a point every this many metres, as far back as this many.
const STEP := 2.0
const TRAIL := 160

var _trail := PackedVector3Array()
var _gap := ARRIVE_FROM
var _t := 0.0
var _leaving := false
var _how := ""


func _init() -> void:
	event = &"minimap_passenger"
	from_act = 4
	every_days = 3
	chance = 0.5


func _process(delta: float) -> void:
	super._process(delta)
	if _car and is_instance_valid(_car) and driving():
		var p := _car.global_position
		if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(p) >= STEP:
			_trail.append(p)
			if _trail.size() > TRAIL:
				_trail.remove_at(0)
		elif _trail[_trail.size() - 1].distance_to(p) > 60.0:
			_trail.clear()  # moved by other means (a teleport)


func _ready_to_start() -> bool:
	return speed_kmh() > MIN_KMH and _trail.size() * STEP > ARRIVE_FROM


func _start() -> void:
	_gap = ARRIVE_FROM
	_t = 0.0
	_leaving = false
	_how = ""
	alpha = 0.0
	LateCity.fade_look(0.25, 3.0)
	_place()


func _run(delta: float) -> void:
	_t += delta
	if not driving():
		_how = "out"
		_leave()
	if _t > LASTS and not _leaving:
		_how = "went"
		_leave()
	var want := FOLLOW if speed_kmh() > 5.0 else CLOSEST
	if _t < ARRIVE:
		_gap = lerpf(ARRIVE_FROM, FOLLOW, smoothstep(0.0, ARRIVE, _t))
	else:
		_gap = move_toward(_gap, want, delta * (CREEP if want < _gap else 6.0))
	if _leaving:
		alpha = move_toward(alpha, 0.0, delta / FADE)
		if alpha <= 0.0:
			_done()
			return
	else:
		alpha = SOLID * smoothstep(0.0, ARRIVE * 0.6, _t)
	_place()


func _on_flash() -> void:
	if not _leaving:
		_how = "flashed"
		_leave()


func _leave() -> void:
	_leaving = true


func _done() -> void:
	finish()
	Discoveries.discover("oddity/minimap_passenger")
	var out: String = {"flashed": " I flashed the lights and it was gone."}.get(_how, " After a while it wasn't there.")
	Story.log_night(StringName("minimap_passenger_%d" % GameClock.day),
		"A second little arrow followed mine on the map, a block behind, every turn I made. Nothing in the mirror.%s" % out)


func _stop() -> void:
	shown = Vector2.INF
	alpha = 0.0


## `_gap` metres back along the trail.
func _place() -> void:
	if _trail.size() < 2:
		shown = Vector2.INF
		return
	var left := _gap
	var i := _trail.size() - 1
	var at := _car.global_position if _car else _trail[i]
	var from := at
	while i >= 0:
		var d := from.distance_to(_trail[i])
		if d >= left:
			at = from.lerp(_trail[i], left / maxf(d, 0.001))
			break
		left -= d
		from = _trail[i]
		at = from
		i -= 1
	var ahead := _trail[mini(maxi(i + 1, 1), _trail.size() - 1)]
	var dir := Vector2(ahead.x - at.x, ahead.z - at.z)
	shown = Vector2(at.x, at.z)
	if dir.length() > 0.01:
		# The same yaw as the player's (0 facing -Z).
		shown_yaw = atan2(-dir.x, -dir.y)
