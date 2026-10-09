extends Node
## The story's state (autoload: Story): which act you're in, the choices you've
## made, story flags and the Nights log. The design is in the project's story
## notes (STORY.md); the API other code builds on is STORY_API.md.
##
## Acts follow the career tiers: 1 Getting by ... 5 Perth legend. The weird
## events themselves are run by the LateCity autoload; this only remembers.
##
##   Story.act()                                  # 1..5
##   Story.make_choice(&"porch_light", &"on")
##   Story.log_night(&"other_house_1979", "Opened the door and it was 1979.")
##   Story.leave_message(&"ros_first_roll", "Ros", "Got your roll back...")
##
## Saved under "story".

signal act_changed(act: int)
signal choice_made(id: StringName, value: StringName)
signal flag_set(id: StringName)
signal night_logged(entry: Dictionary)
signal message_left(message: Dictionary)
signal ending_reached(ending: StringName)

const ACTS := 5
## Choice ids and the values each may take (STORY_API.md).
const CHOICES := {
	&"porch_light": [&"on", &"off"],
	&"thirteen": [&"ros", &"buyer"],
	&"robyn": [&"found"],
	&"eleventh_july": [&"lights_on", &"tape_13", &"switch_off", &"went_in"],
}
## The five endings (STORY.md section 9).
const ENDINGS := [&"city_of_light", &"half_light", &"night_drive_13", &"lights_out", &"late_city"]

## Oldest first. Each: {id: StringName, text: String, day: int, time: float}.
var nights: Array[Dictionary] = []
## The answering machine at home, oldest first. Each: {id: StringName,
## from: String, text: String, late: bool, day: int, time: float, heard: bool}.
var messages: Array[Dictionary] = []
var prints_to_ros := 0
var prints_to_buyer := 0
## Dev and test override: when > 0, act() returns this instead of the tier.
var act_override := 0

var _choices := {}   # StringName -> StringName
var _flags := {}     # StringName -> day set
var _last_act := 0
var _act_began := {}  # int act -> day it began
var _ending := &""
var _ending_day := -1


func _ready() -> void:
	SaveGame.register("story", self)
	Progression.tier_completed.connect(func(_i: int, _t: Dictionary) -> void: _check_act())
	_check_act.call_deferred()


## 1 Getting by, 2 Known around town, 3 Small business, 4 The regular,
## 5 Perth legend (and still 5 once the last tier is done).
func act() -> int:
	if act_override > 0:
		return clampi(act_override, 1, ACTS)
	return clampi(Progression.tier_index + 1, 1, ACTS)


## 0..5: the act, plus how far through its tier you are, plus a little if the
## thirteen went to the buyer. For "a little more, the further along" tuning.
func strangeness() -> float:
	var a := act()
	var through := 0.0
	var tier := Progression.current_tier()
	if act_override <= 0 and not tier.is_empty() and not tier.challenges.is_empty():
		var done := 0
		for challenge: Dictionary in tier.challenges:
			if Progression.is_done(challenge):
				done += 1
		through = float(done) / float(tier.challenges.size())
	var extra := 0.5 if choice(&"thirteen") == &"buyer" else 0.0
	return clampf(float(a - 1) + through + extra, 0.0, 5.0)


func gentle() -> bool:
	return Settings.strange_things == "gentle"


func choice(id: StringName) -> StringName:
	return _choices.get(id, &"")


func make_choice(id: StringName, value: StringName) -> void:
	if not CHOICES.has(id) or not value in CHOICES[id]:
		push_warning("Story: unknown choice %s = %s" % [id, value])
		return
	if _choices.get(id, &"") == value:
		return
	_choices[id] = value
	choice_made.emit(id, value)


func flag(id: StringName) -> bool:
	return _flags.has(id)


func set_flag(id: StringName) -> void:
	if _flags.has(id):
		return
	_flags[id] = GameClock.day
	flag_set.emit(id)


## A wrong-bird print went to Ros (the field guide) or the buyer.
func note_print(_species_id: String, to: StringName) -> void:
	match to:
		&"ros":
			prints_to_ros += 1
		&"buyer":
			prints_to_buyer += 1


## Adds a line to the Nights tab, once per id. Returns true if it was new.
func log_night(id: StringName, text: String) -> bool:
	for entry in nights:
		if entry.id == id:
			return false
	var entry := {"id": id, "text": text, "day": GameClock.day, "time": GameClock.time_of_day}
	nights.append(entry)
	night_logged.emit(entry)
	return true


func has_night(id: StringName) -> bool:
	for entry in nights:
		if entry.id == id:
			return true
	return false


## Leaves a message on the machine at home, once per id. Late ones are from
## the late city (hiss and the deck's click instead of a beep). Returns true
## if it was new.
func leave_message(id: StringName, from: String, text: String, late := false) -> bool:
	if has_message(id):
		return false
	var m := {"id": id, "from": from, "text": text, "late": late,
		"day": GameClock.day, "time": GameClock.time_of_day, "heard": false}
	messages.append(m)
	message_left.emit(m)
	return true


func has_message(id: StringName) -> bool:
	return not message(id).is_empty()


## The message with this id, or {} if it hasn't been left.
func message(id: StringName) -> Dictionary:
	for m in messages:
		if m.id == id:
			return m
	return {}


func heard(id: StringName) -> bool:
	return bool(message(id).get("heard", false))


func unheard_messages() -> int:
	var n := 0
	for m in messages:
		if not m.heard:
			n += 1
	return n


## The unheard messages, oldest first, now marked heard.
func take_unheard() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for m in messages:
		if not m.heard:
			m.heard = true
			list.append(m)
	return list


## Which ending the game reached (ENDINGS), or &"" before the finale.
func ending() -> StringName:
	return _ending


## The game day the ending was reached, or -1.
func ending_day() -> int:
	return _ending_day


func set_ending(id: StringName) -> void:
	if not id in ENDINGS:
		push_warning("Story: unknown ending %s" % id)
		return
	if _ending == id:
		return
	_ending = id
	_ending_day = GameClock.day
	ending_reached.emit(id)


## The game day an act began (0 for act 1, or an act not reached yet).
func act_began(a: int) -> int:
	return int(_act_began.get(a, 0))


func _check_act() -> void:
	var a := act()
	if not _act_began.has(a):
		_act_began[a] = GameClock.day
	if a != _last_act:
		_last_act = a
		act_changed.emit(a)


func save_state() -> Dictionary:
	var choices := {}
	for id in _choices:
		choices[String(id)] = String(_choices[id])
	var flags := {}
	for id in _flags:
		flags[String(id)] = _flags[id]
	var entries := []
	for entry in nights:
		entries.append({"id": String(entry.id), "text": entry.text, "day": entry.day, "time": entry.time})
	var left := []
	for m in messages:
		left.append({"id": String(m.id), "from": m.from, "text": m.text, "late": m.late,
			"day": m.day, "time": m.time, "heard": m.heard})
	var began := {}
	for a in _act_began:
		began[str(a)] = _act_began[a]
	return {"choices": choices, "flags": flags, "nights": entries, "messages": left,
		"act_began": began, "ending": String(_ending), "ending_day": _ending_day, "prints_to_ros": prints_to_ros, "prints_to_buyer": prints_to_buyer}


func load_state(data: Dictionary) -> void:
	_choices.clear()
	for id in data.get("choices", {}):
		_choices[StringName(id)] = StringName(data.choices[id])
	_flags.clear()
	for id in data.get("flags", {}):
		_flags[StringName(id)] = int(data.flags[id])
	nights.clear()
	for e: Dictionary in data.get("nights", []):
		nights.append({"id": StringName(e.get("id", "")), "text": String(e.get("text", "")),
			"day": int(e.get("day", 0)), "time": float(e.get("time", 0.0))})
	messages.clear()
	for m: Dictionary in data.get("messages", []):
		messages.append({"id": StringName(m.get("id", "")), "from": String(m.get("from", "")),
			"text": String(m.get("text", "")), "late": bool(m.get("late", false)),
			"day": int(m.get("day", 0)), "time": float(m.get("time", 0.0)), "heard": bool(m.get("heard", false))})
	_act_began.clear()
	for a in data.get("act_began", {}):
		_act_began[int(a)] = int(data.act_began[a])
	_ending = StringName(data.get("ending", ""))
	_ending_day = int(data.get("ending_day", -1))
	prints_to_ros = int(data.get("prints_to_ros", 0))
	prints_to_buyer = int(data.get("prints_to_buyer", 0))
	_check_act.call_deferred()
