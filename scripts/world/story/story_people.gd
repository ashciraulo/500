class_name StoryPeople
extends Node
## The people of the story (STORY.md: Mrs Kostas, Ros, Dee, Len, the buyer)
## and the story's beats that aren't late-city events:
##
##   - The answering machine at home (AnsweringMachine): messages from
##     data/story/messages.json turn up one a day at most, by act and by what
##     you've done, and a card says so when one's waiting.
##   - The act title cards ("SIDE B / Known around town"), once per act.
##   - Choice 1, the porch light: the switch by the front door. After the
##     "leave the porch light on for me" message, at twenty to three the next
##     night, the game looks to see if it's on.
##   - Choice 2's Nights lines (the bird thread's lab asks the question,
##     calls Story.make_choice(&"thirteen", ...) and pays the buyer's money).
##
## Added by GameplayPlaces. Saved under "story_people".

const MESSAGES_PATH := "res://data/story/messages.json"
## Twenty to three, and how long after it the porch check still counts (h).
const CHECK_AT := 2.0 + 40.0 / 60.0
const CHECK_WINDOW := 0.75
## The porch check waits at least this long (h) after the message.
const CHECK_AFTER := 20.0
## Seconds into a new game before Side A's card.
const FIRST_CARD := 6.0

var messages: Array = []
var porch_light_on := true
## The act whose title card was shown last.
var card_act := 0

var _home: HomeBase
var _machine: AnsweringMachine
var _switch: PorchSwitch
var _card: ActCard
var _check := 0.0
var _since_start := 0.0
var _last_left_day := -1
var _porch_lamp: OmniLight3D
var _porch_energy := 0.9
## The porch lamps' glowing shades: [mesh, surface, unlit material], so they
## go dark with the light. And whether they're lit now.
var _porch_glows: Array = []
var _glows_lit := true
var _blinks := 0.0


func _ready() -> void:
	name = "StoryPeople"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MESSAGES_PATH))
	if parsed is Dictionary:
		messages = parsed.get("messages", [])
	_card = ActCard.new()
	add_child(_card)
	SaveGame.register("story_people", self)
	Story.choice_made.connect(_on_choice)


func _exit_tree() -> void:
	SaveGame.unregister("story_people")


func _process(delta: float) -> void:
	_since_start += delta
	if _home == null or not is_instance_valid(_home):
		_find_home()
	_update_porch(delta)
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	_maybe_card()
	_maybe_message()
	_maybe_porch_check()


func _find_home() -> void:
	_home = get_tree().get_first_node_in_group(&"home_base") as HomeBase
	if _home == null:
		return
	_machine = AnsweringMachine.new()
	_home.add_child(_machine)
	_switch = PorchSwitch.new()
	_switch.people = self
	_home.add_child(_switch)
	var markers: Variant = _home.get("_markers")
	if markers is Dictionary and (markers as Dictionary).has(&"Light_Porch"):
		for c in (markers[&"Light_Porch"] as Node).get_children():
			if c is OmniLight3D:
				_porch_lamp = c
				_porch_energy = _porch_lamp.light_energy
	for mi: MeshInstance3D in _home.find_children("porch_light*", "MeshInstance3D", true, false):
		for i in mi.get_surface_override_material_count():
			var m := mi.get_active_material(i) as ShaderMaterial
			var glow: Variant = m.get_shader_parameter("emission_energy") if m else null
			if glow != null and float(glow) > 0.0:
				var unlit := m.duplicate() as ShaderMaterial
				unlit.set_shader_parameter("emission_energy", 0.0)
				_porch_glows.append([mi, i, unlit])


# --- Act cards ------------------------------------------------------------------

func _maybe_card() -> void:
	var act := Story.act()
	if act <= card_act or _card.showing() or get_tree().paused:
		return
	# A new game's first card waits until you've had a moment to look round.
	if act == 1 and _since_start < FIRST_CARD:
		return
	card_act = act
	_card.show_act(act)


# --- Messages -----------------------------------------------------------------

func _maybe_message() -> void:
	if GameClock.day == _last_left_day:
		return
	for m: Dictionary in messages:
		if Story.has_message(StringName(m.id)) or not ready_to_leave(m):
			continue
		if Story.leave_message(StringName(m.id), String(m.from), String(m.text), bool(m.get("late", false))):
			_last_left_day = GameClock.day
			if not m.get("late", false):
				Notices.post("A new message on the answering machine at home.", "info", "ui/ui_phone_notify", "Answering machine")
		return


## Whether a message's time has come (act, days, needs, and the hour for late ones).
func ready_to_leave(m: Dictionary) -> bool:
	var act := int(m.get("act", 1))
	if Story.act() < act:
		return false
	if GameClock.day - Story.act_began(act) < int(m.get("days", 0)):
		return false
	if m.get("late", false):
		var h := GameClock.time_of_day
		if not (h >= 0.0 and h < LateCity.NIGHT_TO):
			return false
	for need: String in m.get("needs", []):
		if not _met(need):
			return false
	return true


func _met(need: String) -> bool:
	var kind := need.get_slice(":", 0)
	var arg := need.substr(kind.length() + 1)
	match kind:
		"deliveries":
			return Progression.get_stat("deliveries") >= float(arg)
		"photos":
			return Progression.get_stat("species_photographed") >= float(arg)
		"found":
			return Discoveries.has(arg)
		"flag":
			return Story.flag(StringName(arg))
		"choice":
			return Story.choice(StringName(arg.get_slice("=", 0))) == StringName(arg.get_slice("=", 1))
		"heard":
			return Story.heard(StringName(arg))
	push_warning("StoryPeople: unknown need " + need)
	return false


# --- Choice 1: the porch light ------------------------------------------------

func set_porch_light(on: bool) -> void:
	porch_light_on = on


func _update_porch(delta: float) -> void:
	if _porch_lamp == null or not is_instance_valid(_porch_lamp):
		return
	var energy := _porch_energy if porch_light_on else 0.0
	# Three blinks, like three knocks on the door.
	if _blinks > 0.0:
		_blinks -= delta
		var phase := fmod(_blinks, 0.7)
		if phase < 0.25:
			energy = 0.0
	_porch_lamp.light_energy = energy
	var lit := energy > 0.0
	if lit != _glows_lit:
		_glows_lit = lit
		for g: Array in _porch_glows:
			if is_instance_valid(g[0]):
				(g[0] as MeshInstance3D).set_surface_override_material(g[1], null if lit else g[2])


func _maybe_porch_check() -> void:
	if Story.choice(&"porch_light") != &"":
		return
	var left := Story.message(&"porch_light")
	if left.is_empty():
		return
	var h := GameClock.time_of_day
	if h < CHECK_AT or h > CHECK_AT + CHECK_WINDOW:
		return
	var since := (GameClock.day - int(left.day)) * 24.0 + h - float(left.time)
	if since < CHECK_AFTER:
		return
	if porch_light_on:
		Story.make_choice(&"porch_light", &"on")
		Story.log_night(&"porch_light_on", "Left the porch light on. At twenty to three it blinked, three times, like someone knocking.")
		if _home and _player_near_home():
			_blinks = 0.7 * 3.0
			Notices.post("At twenty to three the porch light blinks. Three times, like someone knocking.", "odd")
	else:
		Story.make_choice(&"porch_light", &"off")
		Story.log_night(&"porch_light_off", "Left the porch light off. Nothing knocked.")


func _player_near_home() -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_to(_home.global_position) < 150.0


# --- Choice 2: the thirteen ---------------------------------------------------

func _on_choice(id: StringName, value: StringName) -> void:
	if id != &"thirteen":
		return
	match value:
		&"buyer":
			Story.log_night(&"thirteen_buyer", "Sold the thirteen to the buyer.")
		&"ros":
			Story.log_night(&"thirteen_ros", "Gave the thirteen to Ros. The night section is finished.")


func save_state() -> Dictionary:
	return {"porch_light_on": porch_light_on, "card_act": card_act, "last_left_day": _last_left_day}


func load_state(data: Dictionary) -> void:
	porch_light_on = bool(data.get("porch_light_on", true))
	card_act = int(data.get("card_act", 0))
	_last_left_day = int(data.get("last_left_day", -1))
