class_name HomeOddities
extends Node
## Home stays cozy almost all the time. Every so often, mostly late at night
## or in storms, something is slightly wrong; none of it jumps out at you.
##
##   footprints  small muddy prints in from the courtyard, the morning after rain
##   drawing     a child's crayon drawing under the fridge magnets
##   plant       the plant on the breakfast bar turned to face the front door
##   photo       the stair photo: someone is standing at the courtyard gate
##   intercom    it buzzes after midnight; nobody is at the gate, only static
##   tapping     something taps behind the bricked-up fireplace on storm nights
##   headlights  headlights sweep across the bedroom ceiling; the lane is empty
##
## The first four are chosen when you wake (at most one a day, none in the
## first few days); the rest happen while you're home at night. Noticing one
## the first time is a discovery ("oddity/home_<id>"). Cozy mode
## (Settings.cozy_mode) turns all of it off. The props are the townhouse
## model's Oddity_* nodes (art/models/README.md).

## No oddities in the first days at home.
const FIRST_DAY := 3
## Chance of one of the daytime oddities on waking (higher after a storm).
const DAY_CHANCE := 0.3
const STORM_CHANCE := 0.6
const NOTICE_RANGE := 2.6
## Average real seconds between night events while they're possible.
const INTERCOM_EVERY := 150.0
const HEADLIGHTS_EVERY := 90.0
const TAP_GAP := Vector2(45.0, 110.0)
const ANSWER_WINDOW := 25.0

## Townhouse places (Blender frame: x across, y back from the street, z up).
const INTERCOM := Vector3(5.36, 11.6, 1.5)
const FIREPLACE := Vector3(0.45, 2.4, 0.6)
const BEDROOM := Rect2(2.0, 0.0, 3.4, 4.6)  # x, y of bedroom 1, upstairs
const UPSTAIRS_Z := 2.6

const LINES := {
	"footprints": "Little muddy footprints, in from the courtyard. The sliding door was locked.",
	"drawing": "There's a child's drawing on the fridge. A small car, a lane, a shed.",
	"plant": "The plant on the bar has turned to face the front door.",
	"photo": "In the photo on the stairs, someone is standing at the courtyard gate.",
	"intercom": "Nobody at the gate. Only static, and under it, almost, a voice.",
	"tapping": "Something taps behind the bricked-up fireplace. Three times, then nothing.",
	"headlights": "Headlights sweep across the ceiling. Outside, the lane is empty.",
}

## Today's daytime oddity ("" for none). Not saved: a fresh day's start.
var today := ""

var _home: Node3D
var _props := {}            # name -> Node3D
var _plant_rest := 0.0
var _check := 0.0
var _night := -1            # the day number of the night being tracked
var _intercom_done := false
var _headlights_done := false
var _tap_in := 30.0
var _answer: Node3D         # the intercom's "answer" spot while it's buzzing
var _answer_left := 0.0
var _sweep: SpotLight3D


func _process(delta: float) -> void:
	_tap_in -= delta
	if _answer_left > 0.0:
		_answer_left -= delta
		if _answer_left <= 0.0 and _answer:
			_answer.queue_free()
			_answer = null
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		if _home == null:
			return
		_collect()
	if Settings.cozy_mode:
		today = ""
	_show_day()
	if Settings.cozy_mode:
		return
	_notice()
	_night_events()


## Pick today's oddity (called on waking; tests call it with `force`).
func roll(force := "") -> String:
	today = ""
	if force != "":
		today = force
	elif not Settings.cozy_mode and GameClock.day >= FIRST_DAY:
		var stormy := Weather.state == Weather.State.STORM
		if randf() < (STORM_CHANCE if stormy else DAY_CHANCE):
			var options := ["drawing", "plant", "photo"]
			if Weather.state != Weather.State.CLEAR:
				options.append("footprints")
			today = options.pick_random()
	_show_day()
	return today


func _collect() -> void:
	_props.clear()
	for prop_name in ["Oddity_Plant", "Oddity_Footprints", "Oddity_Drawing", "Oddity_Photo",
			"Oddity_Photo_Figure", "Oddity_LooseBrick", "Intercom"]:
		var node := _home.find_child(prop_name, true, false) as Node3D
		if node:
			_props[prop_name] = node
	if _props.has("Oddity_Plant"):
		_plant_rest = (_props["Oddity_Plant"] as Node3D).rotation.y
	if _home.has_signal("slept") and not _home.slept.is_connected(_on_slept):
		_home.slept.connect(_on_slept)


func _on_slept(_day: int) -> void:
	roll()


func _show_day() -> void:
	_set_visible("Oddity_Footprints", today == "footprints")
	_set_visible("Oddity_Drawing", today == "drawing")
	_set_visible("Oddity_Photo", today != "photo")
	if _props.has("Oddity_Plant"):
		(_props["Oddity_Plant"] as Node3D).rotation.y = _plant_rest + (PI if today == "plant" else 0.0)


func _set_visible(prop_name: String, on: bool) -> void:
	if _props.has(prop_name):
		(_props[prop_name] as Node3D).visible = on


## The first time you're close to today's oddity and looking at it.
func _notice() -> void:
	if today == "":
		return
	var eyes := _player_eyes()
	if eyes == null:
		return
	var prop_name: String = {"footprints": "Oddity_Footprints", "drawing": "Oddity_Drawing",
		"plant": "Oddity_Plant", "photo": "Oddity_Photo_Figure"}[today]
	var prop: Node3D = _props.get(prop_name)
	if prop == null:
		return
	var to := prop.global_position - eyes.global_position
	if to.length() < NOTICE_RANGE and (-eyes.global_basis.z).dot(to.normalized()) > 0.6:
		_discover(today)


func _night_events() -> void:
	var hour: float = GameClock.time_of_day
	var night_of: int = GameClock.day if hour >= 12.0 else GameClock.day - 1
	if night_of != _night:
		_night = night_of
		_intercom_done = false
		_headlights_done = false
	var where := _player_in_house()
	if where == "":
		return
	if not _intercom_done and hour < 3.0 and randf() < 1.0 / INTERCOM_EVERY:
		_intercom_done = true
		buzz_intercom()
	if not _headlights_done and (hour >= 22.0 or hour < 4.0) and where == "bedroom" \
			and randf() < 1.0 / HEADLIGHTS_EVERY:
		_headlights_done = true
		sweep_headlights()
	if Weather.state == Weather.State.STORM and (hour >= 21.0 or hour < 5.0) and _tap_in <= 0.0:
		_tap_in = randf_range(TAP_GAP.x, TAP_GAP.y)
		tap()


func buzz_intercom() -> void:
	_play("home/home_intercom_buzz", _point(INTERCOM), -2.0)
	if _answer == null:
		_answer = _AnswerSpot.new(self)
		_home.add_child(_answer)
		_answer.position = _local(INTERCOM)
	_answer_left = ANSWER_WINDOW


func answer_intercom() -> void:
	_play("home/home_intercom_handset", _point(INTERCOM), -4.0)
	_play("home/home_intercom_static", _point(INTERCOM), -8.0)
	_answer = null  # the spot frees itself
	_answer_left = 0.0
	_discover("intercom")


func tap() -> void:
	_play("home/home_odd_wall_tapping", _point(FIREPLACE), -6.0)
	var eyes := _player_eyes()
	if eyes and eyes.global_position.distance_to(_point(FIREPLACE)) < 4.5:
		_discover("tapping")


## A car's lights crossing the bedroom ceiling through the front window.
func sweep_headlights() -> void:
	if _sweep == null:
		_sweep = SpotLight3D.new()
		_sweep.name = "Oddity_Headlights"
		_sweep.light_color = Color(1.0, 0.95, 0.82)
		_sweep.light_energy = 6.0
		_sweep.spot_range = 16.0
		_sweep.spot_angle = 14.0
		_sweep.shadow_enabled = false
		_home.add_child(_sweep)
	_sweep.visible = true
	var from := _local(Vector3(7.5, -5.0, 1.2))
	var to := _local(Vector3(-2.5, -5.0, 1.2))
	_sweep.position = from
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		_sweep.position = from.lerp(to, t)
		_sweep.look_at(_point(Vector3(lerpf(4.8, 2.2, t), 2.4, 5.8)), Vector3.UP), 0.0, 1.0, 3.2) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: _sweep.visible = false)
	if _player_in_house() == "bedroom":
		_discover("headlights")


func _discover(id: String) -> void:
	if Discoveries.discover("oddity/home_" + id):
		Notices.post(LINES.get(id, ""), "odd")


## "", "house", or "bedroom" (bedroom 1, upstairs) for where the player is on foot.
func _player_in_house() -> String:
	var eyes := _player_eyes()
	if eyes == null:
		return ""
	var p := _home.global_transform.affine_inverse() * eyes.global_position
	var b := Vector3(p.x, -p.z, p.y)  # back to the model's frame
	if b.x < 0.0 or b.x > 5.4 or b.y < 0.0 or b.y > 12.0:
		return ""
	if b.z - 1.6 > UPSTAIRS_Z and BEDROOM.has_point(Vector2(b.x, b.y)):
		return "bedroom"
	return "house"


func _player_eyes() -> Node3D:
	var player := get_tree().root.find_child("Player", true, false)
	if player == null or player.get("in_car") != false:
		return null
	return player.get_node_or_null(^"Eyes") as Node3D


func _local(b: Vector3) -> Vector3:
	return Vector3(b.x, b.z, -b.y)


func _point(b: Vector3) -> Vector3:
	return _home.global_transform * _local(b)


func _play(sound: String, at: Vector3, volume_db: float) -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has(sound):
		audio.play_at(sound, at, volume_db)


## The intercom while it's buzzing: walk up and answer it.
class _AnswerSpot extends Node3D:
	var odd: HomeOddities

	func _init(owner_odd: HomeOddities) -> void:
		odd = owner_odd
		name = "Use_intercom"

	func _ready() -> void:
		add_to_group(&"interactables")

	func interact_point() -> Vector3:
		return global_position

	func interact_hint() -> String:
		return "Answer the intercom"

	func interact() -> void:
		odd.answer_intercom()
		queue_free()
