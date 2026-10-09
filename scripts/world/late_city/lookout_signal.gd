class_name LookoutSignal
extends LateDrive
## Signalling from the lookouts (STORY.md, act 3). Mick's tapes say he
## flashed his headlights from the lookouts over the river, three times, and
## something answered. From act 3, after midnight, park at a lookout in Kings
## Park and flash the headlights three times (K): the deck clicks on, and out
## on the river a pair of round headlights flashes three times back, holds a
## moment, and goes. Each lookout that answers goes in the Nights tab; the
## first one leaves a card under the wiper (a clue).
##
## The lights hang over the water where the lookout looks, as two soft glows
## that are drawn at a size that reads from up on the hill.

## Each lookout: the end of the road at the top of the scarp, and where the
## lights show, out on the water where the view from the edge is clear (the
## Fraser Avenue ones far across Perth Water, above the towers on the shore).
const LOOKOUTS := [
	{"id": "fraser", "name": "Fraser Avenue", "at": Vector3(-943.4, 65.5, 1431.5), "lights": Vector3(77.0, 4.0, 2067.0)},
	{"id": "forrest", "name": "Forrest Drive", "at": Vector3(-2001.1, 53.1, 2553.4), "lights": Vector3(-1650.0, 4.0, 2700.0)},
]
## At a lookout: the car within this much (m) of it, stopped (the road, or
## out on the grass at the edge).
const REACH := 130.0
const STOPPED_KMH := 3.0
## Three flashes, each within this long (s) of the last, then a pause this long.
const FLASHES := 3
const GAP := 1.6
const PAUSE := 1.6
## The answer: a beat, three blinks, a hold, and gone (s).
const BEAT := 1.6
const BLINK := 0.45
const HOLD := 3.0
const LIGHT := Color(1.0, 0.86, 0.6)
const CLUE := "mystery/lookout_card"

## Which lookouts have answered: id -> day.
var answered := {}

var _count := 0
var _last_flash := -10.0
var _here: Dictionary = {}
var _lights: Node3D
var _t := 0.0
var _answered_night := {}   # id -> night it answered (once a night each)


func _init() -> void:
	event = &"lookout_signal"
	from_act = 3
	every_days = 0
	chance = 1.0


func _process(delta: float) -> void:
	super._process(delta)
	if not running and _count > 0 and _clock - _last_flash > PAUSE:
		var n := _count
		_count = 0
		if n == FLASHES:
			_try_answer()


## Never starts by itself: three flashes from a lookout start it.
func _may_start() -> bool:
	return false


func _flashed() -> void:
	if running:
		return
	if _clock - _last_flash > GAP:
		_count = 0
	_count += 1
	_last_flash = _clock


func _try_answer() -> void:
	var at := lookout_here()
	if at.is_empty():
		return
	if not force:
		if Story.act() < from_act or not LateCity.allowed_now(true):
			return
		if _answered_night.get(at.id, -1) == _night():
			return
	_here = at
	begin()


## The lookout the car is stopped at, or {}.
func lookout_here() -> Dictionary:
	if not driving() or speed_kmh() > STOPPED_KMH:
		return {}
	for l: Dictionary in LOOKOUTS:
		var p: Vector3 = l.at
		if Vector2(p.x - _car.global_position.x, p.z - _car.global_position.z).length() < REACH:
			return l
	return {}


func _night() -> int:
	return GameClock.day if GameClock.time_of_day >= 12.0 else GameClock.day - 1


func _start() -> void:
	_t = 0.0
	_answered_night[_here.id] = _night()
	LateCity.fade_look(0.7, 2.0)
	LateCity.set_hiss(true)
	_lights = _make_lights(_here.lights, _car.global_position)
	_lights.visible = false
	_world().add_child(_lights)
	_lights.global_position = _here.lights


func _run(delta: float) -> void:
	_t += delta
	if not driving():
		finish()
		return
	var blinks_end := BEAT + FLASHES * BLINK * 2.0
	if _t < BEAT:
		_lights.visible = false
	elif _t < blinks_end:
		_lights.visible = fmod(_t - BEAT, BLINK * 2.0) < BLINK
	elif _t < blinks_end + HOLD:
		_lights.visible = true
	else:
		_answer_done()


func _answer_done() -> void:
	var l := _here
	finish()
	var first := answered.is_empty()
	answered[l.id] = GameClock.day
	Discoveries.discover("oddity/lookout_" + String(l.id))
	Story.log_night(StringName("lookout_" + String(l.id)),
		"Flashed my lights three times from %s. Out on the river, a pair of round headlights flashed three times back." % l.name)
	if first:
		# The bird thread's lab: the next roll back has one frame too many,
		# you at the wheel, seen from the back seat (STORY.md, act 3).
		Story.set_flag(&"photo_back_seat")
	if first and Discoveries.discover(CLUE):
		Notices.post("There's a card under the wiper. In neat capitals: FRASER AVE. FORREST DR. THREE EACH. THEY ANSWER.", "odd")
	else:
		Notices.post("Out on the river, the lights flash three times back.", "odd")


func _stop() -> void:
	if _lights:
		LateCity.play_flicker(_lights.global_position)
		_lights.queue_free()
		_lights = null


## Two soft round glows, drawn big enough to read from `from`.
static func _make_lights(at: Vector3, from: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "LookoutLights"
	var d := at.distance_to(from)
	# Bigger than real lamps would be: at a kilometre they still read as two.
	var size := maxf(2.0, d * 0.05)
	var apart := maxf(1.4, d * 0.036)
	var side := Vector3(at.z - from.z, 0.0, from.x - at.x).normalized()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	m.albedo_color = LIGHT
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.9))
	glow.gradient = g
	m.albedo_texture = glow
	for s in [-0.5, 0.5]:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = side * apart * s
		root.add_child(mi)
	return root


func _world() -> Node:
	var map := get_tree().get_first_node_in_group(&"perth_map")
	return map.get_parent() if map and map.get_parent() else get_tree().current_scene


func save_state() -> Dictionary:
	return {"last_day": last_day, "answered": answered}


func load_state(data: Dictionary) -> void:
	last_day = int(data.get("last_day", -100))
	answered = data.get("answered", {})
