class_name StationVoice
extends Node
## The station that answers back (STORY.md, event 4). The midnight station
## has always read out places (Mystery). From act 3 the calm voice starts to
## notice you, between the places it sends you to:
##
##   act 3   where you are right now: "...a little round car, stopped on
##           Riverside Drive. The engine's ticking over..."
##   act 4   where you're going before you've decided: the job you're on, or
##           a place nearby. Go there that night and it's in the Nights tab.
##
## It's the radio talking, not an event: no deck, no counter, just the voice
## under the static, a few times a night at most.

const MIDNIGHT := "midnight"
## First line this long (s) after you tune in, then one every REPEAT.
const FIRST := 28.0
const REPEAT := 120.0
const PER_NIGHT := 3
## Not this soon (s) after the voice has read out a clue (Mystery.REPEAT 75).
const AFTER_CLUE := 15.0
## A place it says you'll go: this far away (m), and close enough to count.
const AHEAD_MIN := 500.0
const AHEAD_MAX := 2600.0
const ARRIVED := 70.0
const NIGHT_TO := 4.5

## Tests: ignore the act and the hour.
var force := false
var said_tonight := 0
## The place it said you'd go: {at: Vector3, title: String, until: float
## (game hours since day 0: the end of that night)}, or {}.
var foretold := {}

var _radio: Object
var _on := false
var _wait := FIRST
var _night := -1
var _check := 0.0
var _spots: Array = []


func _ready() -> void:
	SaveGame.register("station_voice", self)
	_hook.call_deferred()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/places.json"))
	if parsed is Dictionary:
		_spots = parsed.get("photo_spots", [])


func _exit_tree() -> void:
	SaveGame.unregister("station_voice")


func _hook() -> void:
	var audio := get_node_or_null(^"/root/Audio")
	_radio = audio.get("radio") if audio else null
	if _radio and _radio.has_signal("station_changed"):
		_radio.station_changed.connect(_on_station_changed)
		_on = _radio.call("current_station_id") == MIDNIGHT


func _on_station_changed(id: String, _display: String) -> void:
	_on = id == MIDNIGHT
	_wait = FIRST


func _process(delta: float) -> void:
	_check_foretold(delta)
	if not _on:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REPEAT
	var night := GameClock.day if GameClock.time_of_day >= 12.0 else GameClock.day - 1
	if night != _night:
		_night = night
		said_tonight = 0
	if not force:
		var h := GameClock.time_of_day
		if Story.act() < 3 or not (h >= 0.0 and h < NIGHT_TO) or said_tonight >= PER_NIGHT:
			return
	var mystery := get_tree().root.find_child("Mystery", true, false)
	if mystery and float(mystery.get("_repeat")) > Mystery.REPEAT - AFTER_CLUE:
		_wait = AFTER_CLUE
		return
	var line := line_now()
	if line == "":
		return
	said_tonight += 1
	Activities.say("Under the static, the calm voice: \"...%s...\"" % line)


## What the voice says now, by act.
func line_now() -> String:
	return ahead_line() if Story.act() >= 4 else here_line()


## Act 3: where you are, and what you're doing.
func here_line() -> String:
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	var walker := get_tree().root.find_child("Player", true, false) as Node3D
	var on_foot: bool = walker != null and walker.get("in_car") == false
	var at: Vector3 = walker.global_position if on_foot else (car.global_position if car else Vector3.INF)
	if at == Vector3.INF:
		return ""
	var data := MapData.shared()
	var street := data.street_at(at) if data.is_loaded else ""
	var suburb := data.suburb_at(at) if data.is_loaded else ""
	var where := street if street != "" else suburb
	if where == "":
		return ""
	var line := ""
	if on_foot:
		line = "someone standing on %s, listening to a car radio through the window" % where
	elif car and absf(car.speed_kmh()) < 3.0:
		line = "a little round car, stopped on %s. The engine's ticking over" % where
	else:
		line = "a little round car on %s, going %s. Mind the lights" % [where, _compass(car)]
	if Discoveries.discover("oddity/station_knows"):
		Story.log_night(&"station_knows", "The midnight station said where I was: %s." % where)
	return line


## Act 4: where you're going. The job you're on, if there is one; otherwise
## somewhere near that you haven't thought of yet.
func ahead_line() -> String:
	if not Jobs.active.is_empty():
		var site := _job_site(String(Jobs.active.get("dropoff", "")))
		if site:
			return "%s. You'll be there before the kettle's boiled" % site.display_name
	var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
	if car == null:
		return ""
	var options: Array = []
	for spot: Dictionary in _spots:
		var p := Vector3(spot.p[0], spot.p[1], spot.p[2])
		var d := p.distance_to(car.global_position)
		if d > AHEAD_MIN and d < AHEAD_MAX:
			options.append(spot)
	if options.is_empty():
		return ""
	var spot: Dictionary = options[randi() % options.size()]
	var h := GameClock.time_of_day
	var until := (GameClock.day + (0 if h < NIGHT_TO else 1)) * 24.0 + NIGHT_TO
	foretold = {"at": Vector3(spot.p[0], spot.p[1], spot.p[2]), "title": String(spot.title), "until": until}
	return "%s. You'll go there tonight. You just don't know it yet" % spot.title


func _check_foretold(delta: float) -> void:
	if foretold.is_empty():
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if GameClock.day * 24.0 + GameClock.time_of_day > float(foretold.until):
		foretold = {}
		return
	var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
	if car and car.global_position.distance_to(foretold.at) < ARRIVED:
		var title: String = foretold.title
		foretold = {}
		Notices.post("The midnight station said you'd come here tonight.", "odd")
		Discoveries.discover("oddity/station_ahead")
		Story.log_night(StringName("station_ahead_%d" % GameClock.day),
			"The midnight station said I'd go to %s tonight. I hadn't meant to. I did." % title)


func _compass(car: CarController) -> String:
	if car == null:
		return "nowhere"
	var f := -car.global_basis.z
	# North is -Z on the map.
	if absf(f.x) > absf(f.z):
		return "east" if f.x > 0.0 else "west"
	return "north" if f.z < 0.0 else "south"


func _job_site(id: String) -> JobSite:
	for s in Jobs.sites():
		if s.site_id == id:
			return s
	return null


func save_state() -> Dictionary:
	var out := {}
	if not foretold.is_empty():
		var at: Vector3 = foretold.at
		out["foretold"] = {"at": [at.x, at.y, at.z], "title": foretold.title, "until": foretold.until}
	return out


func load_state(data: Dictionary) -> void:
	foretold = {}
	var f: Variant = data.get("foretold")
	if f is Dictionary and (f.get("at", []) as Array).size() == 3:
		foretold = {"at": Vector3(f.at[0], f.at[1], f.at[2]), "title": String(f.get("title", "")), "until": float(f.get("until", 0.0))}
