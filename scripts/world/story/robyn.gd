class_name Robyn
extends Node3D
## Choice 3 (STORY.md): finding Robyn, Mick's daughter, in Fremantle.
##
## From act 4, once Thea's message says Robyn sends a card from Fremantle,
## you can ask around there: a delivery to the markets (the customer points
## you to the harbour), the market stalls, and the Fishing Boat Harbour (both
## know her street). Once you know it, her door on Arundel Street can be
## knocked on. Bring the Polaroid of the lane and she takes it, and comes to
## the river on 11 July: Story.make_choice(&"robyn", &"found"). Without the
## Polaroid nobody answers. Leaving it is the other choice: nothing happens.
##
## A card at the top right (ChallengeCard) says where to ask next, but only
## for a while after Thea's message and whenever you're in Fremantle, so it
## never sits there for good.
##
## Added by GameplayPlaces. Saved under "robyn".

enum { WAITING, ASKING, KNOWN, FOUND }

const FROM_ACT := 4
## The card shows this long (s) after Thea's message, and whenever you're
## this close (m) to the markets.
const CARD_FOR := 90.0
const FREO_NEAR := 1800.0
## Where to ask (x/z), and how close you need to be on foot (m).
const MARKETS := Vector2(-9920.9, 12307.9)
const MARKETS_NEAR := 40.0
const HARBOUR := Vector2(-10203.9, 12676.2)
const HARBOUR_NEAR := 70.0
const MARKETS_SITE := "fremantle_markets"
## Her house: a brick cottage on Arundel Street, found from this point on the
## road by looking this way for its front wall.
const ROAD_AT := Vector3(-9880.6, 5.11, 12582.7)
const SIDE := Vector3(-0.653, 0.0, -0.757)
const PLACE_NEAR := 260.0
## She answers between these hours.
const ANSWERS_FROM := 8.0
const ANSWERS_TO := 22.0
const DOOR_GREEN := Color(0.16, 0.3, 0.22)
const BRASS := Color(0.78, 0.62, 0.3)
const STEP := Color(0.62, 0.6, 0.55)
const LAMP := Color(1.0, 0.72, 0.4)
const HALL := Color(0.95, 0.66, 0.36)
const POLAROID_CLUE := "mystery/polaroid"

var step := WAITING
## Where you've asked: "delivery", "markets", "harbour".
var asked: Array[String] = []

var _house: Node3D
var _door: Node3D
var _lamp: OmniLight3D
var _place_check := 0.0
var _heard_at := -1.0
var _clock := 0.0
## Lines still to say at the door: [heading, text], and when the next one goes.
var _lines: Array = []
var _next_line := 0.0
var _door_open := 0.0
var _door_target := 0.0


func _ready() -> void:
	name = "Robyn"
	add_to_group(&"challenges")
	add_to_group(&"interactables")
	SaveGame.register("robyn", self)
	Jobs.job_completed.connect(_on_job_done)


func _exit_tree() -> void:
	SaveGame.unregister("robyn")


func _process(delta: float) -> void:
	if get_tree().paused or SaveGame.hold or TitleScreen.is_showing(get_tree()):
		return
	_clock += delta
	if step == WAITING and Story.act() >= FROM_ACT and Story.heard(&"kostas_robyn") \
			and Story.choice(&"robyn") == &"":
		step = ASKING
		_heard_at = _clock
	if step == ASKING:
		_check_asking()
	if step >= KNOWN:
		_place_check -= delta
		if _house == null and _place_check <= 0.0:
			_place_check = 1.0
			_try_place()
	if _door:
		_door_open = move_toward(_door_open, _door_target, delta * 1.5)
		_door.rotation.y = -_door_open * 0.45
	if _lamp:
		_lamp.visible = GameClock.is_night() or step == FOUND
	if not _lines.is_empty():
		_next_line -= delta
		if _next_line <= 0.0:
			var line: Array = _lines.pop_front()
			Notices.post(String(line[1]), "odd", "-", String(line[0]))
			_next_line = _seconds(String(line[1])) + 0.6
	# Her door shuts again once you've gone.
	if _door_target > 0.0 and _lines.is_empty() and _house:
		var who := _who()
		if who == null or who.global_position.distance_to(_house.global_position) > 25.0:
			_door_target = 0.0


# --- Asking around -----------------------------------------------------------

func _check_asking() -> void:
	var feet := _on_foot_at()
	if feet == Vector3.INF:
		return
	var here := Vector2(feet.x, feet.z)
	if not asked.has("markets") and here.distance_to(MARKETS) < MARKETS_NEAR \
			and GameClock.time_of_day >= 7.0 and GameClock.time_of_day < 18.0:
		ask("markets")
	elif not asked.has("harbour") and here.distance_to(HARBOUR) < HARBOUR_NEAR \
			and GameClock.time_of_day >= 6.0:
		ask("harbour")


func _on_job_done(job: Dictionary, _pay: int, _summary: String) -> void:
	if step != ASKING or asked.has("delivery") or job.get("lift", false):
		return
	if job.get("pickup", "") == MARKETS_SITE or job.get("dropoff", "") == MARKETS_SITE:
		ask.call_deferred("delivery")


## Ask about her at `where` (also called by tests).
func ask(where: String) -> void:
	if asked.has(where) or step >= KNOWN:
		return
	asked.append(where)
	match where:
		"delivery":
			Notices.post("Robyn? Doran? Doesn't ring a bell. There's a Robyn buys fish off the boats at the harbour most evenings, though. Fifties, always in a hurry.",
				"odd", "-", "The customer at the markets")
		"markets":
			Notices.post("Robyn with the shell earrings? She gave up the stall years back. Lives up Arundel Street, one of the old brick cottages.",
				"odd", "-", "A stallholder")
		"harbour":
			Notices.post("Robyn? Arundel Street. The brick place with the porch light. It's on all night, every night. Always has been.",
				"odd", "-", "A man mending nets")
	if where != "delivery":
		step = KNOWN
		Story.log_night(&"robyn_street", "Asked around Fremantle about Robyn. Arundel Street, the brick cottage with the porch light on all night.")


# --- Her door ----------------------------------------------------------------

func _try_place() -> void:
	var player := _who()
	if player == null or Vector2(player.global_position.x - ROAD_AT.x, player.global_position.z - ROAD_AT.z).length() > PLACE_NEAR:
		return
	var space := get_world_3d().direct_space_state
	var from := ROAD_AT + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(from, from + SIDE * 25.0)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var wall: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	normal.y = 0.0
	normal = normal.normalized()
	# The ground in front of the wall.
	var probe := wall + normal * 0.8
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 3.0, probe + Vector3.DOWN * 6.0))
	var ground: float = (down.position as Vector3).y if not down.is_empty() else ROAD_AT.y
	_build(Vector3(wall.x, ground, wall.z), normal)


## The front door on the cottage's wall at `at`, facing `out`: a green door
## with a brass knob, a step, the porch light, and her hall's warm light
## behind (seen when the door opens).
func _build(at: Vector3, out: Vector3) -> void:
	_house = Node3D.new()
	_house.name = "RobynDoor"
	add_child(_house)
	_house.global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), at)
	# In the house's own frame: +z out of the wall, x along it, y up.
	_box(_house, Vector3(1.1, 2.2, 0.04), Vector3(0, 1.1 + 0.15, 0.01), Color(0.22, 0.18, 0.15))
	_box(_house, Vector3(0.92, 2.04, 0.02), Vector3(0, 1.02 + 0.15, 0.035), HALL, 1.6)
	_box(_house, Vector3(1.5, 0.15, 0.5), Vector3(0, 0.075, 0.25), STEP)
	# The door hangs on its left edge, so it swings out on the hinge.
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.46, 0.15, 0.06)
	_house.add_child(hinge)
	_door = hinge
	_box(hinge, Vector3(0.92, 2.04, 0.05), Vector3(0.46, 1.02, 0.0), DOOR_GREEN)
	_box(hinge, Vector3(0.06, 0.06, 0.05), Vector3(0.8, 1.0, 0.04), BRASS, 0.4)
	for k in 2:
		_box(hinge, Vector3(0.62, 0.62, 0.012), Vector3(0.46, 0.55 + k * 0.85, 0.028), DOOR_GREEN.darkened(0.2))
	# A plate with the number, and the porch light.
	_box(_house, Vector3(0.16, 0.1, 0.01), Vector3(0.85, 1.75, 0.025), BRASS, 0.3)
	_box(_house, Vector3(0.14, 0.2, 0.1), Vector3(-0.8, 2.15, 0.08), LAMP, 2.5)
	_lamp = OmniLight3D.new()
	_lamp.light_color = LAMP
	_lamp.light_energy = 1.2
	_lamp.omni_range = 5.0
	_lamp.position = Vector3(-0.8, 2.1, 0.35)
	_house.add_child(_lamp)


func _box(parent: Node3D, size: Vector3, p: Vector3, colour: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = PS1Material.glowing(colour, glow) if glow > 0.0 else PS1Material.make(colour)
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func interact_point() -> Vector3:
	if _house == null or step < KNOWN or not _lines.is_empty():
		return Vector3(0, -10000, 0)
	return _house.global_transform * Vector3(0, 1.3, 0.3)


func interact_hint() -> String:
	if interact_point().y < -1000.0:
		return ""
	return "Knock" if step == KNOWN else ""


func interact() -> void:
	if step != KNOWN or not _lines.is_empty():
		return
	knock()


## Knock at her door (also called by tests).
func knock() -> void:
	var h := GameClock.time_of_day
	if h < ANSWERS_FROM or h >= ANSWERS_TO:
		Notices.post("The porch light's on, but the house is dark behind it. It's late to be knocking.", "odd")
		return
	if not Discoveries.has(POLAROID_CLUE):
		Notices.post("Footsteps, then nothing. A curtain moves and falls back. You've nothing of his to show her.", "odd")
		Story.log_night(&"robyn_no_answer", "Knocked on Robyn's door in Arundel Street. Nobody came. I've nothing of her dad's to show her.")
		return
	step = FOUND
	_door_target = 1.0
	Story.make_choice(&"robyn", &"found")
	Story.set_flag(&"gave_polaroid")
	Story.log_night(&"robyn_found",
		"Found Robyn in Fremantle and gave her the Polaroid of the lane. She'll be at the river on the eleventh of July.")
	_lines = [
		["", "The door opens on the chain. A woman in her fifties, reading glasses up in her hair."],
		["Robyn", "\"Yes?\""],
		["", "You hold up the Polaroid: the lane, your car, the porch light."],
		["Robyn", "\"That's our lane. That's our light.\" A long look. \"Where did you get this?\""],
		["", "She takes the chain off."],
		["Robyn", "\"He used to say the lights on the river were waiting for something. Mum said that was just Dad.\""],
		["Robyn", "\"The eleventh of July. If it's still happening, whatever it is. I'd like to be there. Will you tell me?\""],
	]
	_next_line = 0.4


# --- The card ----------------------------------------------------------------

func challenge_card() -> Dictionary:
	if step == WAITING or step == FOUND or LateCity.active():
		return {}
	var near_freo := false
	var who := _who()
	if who:
		near_freo = Vector2(who.global_position.x, who.global_position.z).distance_to(MARKETS) < FREO_NEAR
	if not near_freo and _clock - _heard_at > CARD_FOR:
		return {}
	if step == ASKING:
		var places := PackedStringArray()
		if not asked.has("delivery"):
			places.append("a delivery to the markets")
		places.append("the market stalls by day")
		places.append("the Fishing Boat Harbour")
		var line := "Thea says she's in Fremantle. Ask around: %s." % ", ".join(places)
		if asked.has("delivery"):
			line = "Someone like her buys fish at the Fishing Boat Harbour. Or ask at the market stalls by day."
		return {"tag": "Robyn", "icon": "pin", "title": "Robyn, in Fremantle", "line": line, "detail": ""}
	var bring := "" if Discoveries.has(POLAROID_CLUE) else "You've nothing of her dad's to show her. The Polaroid of the lane, maybe."
	return {"tag": "Robyn", "icon": "pin", "title": "Arundel Street, Fremantle",
		"line": "The brick cottage with the porch light on. Knock, if you like.", "detail": bring}


# --- Helpers ----------------------------------------------------------------

## The player on foot, or the car.
func _who() -> Node3D:
	var player := get_tree().get_first_node_in_group(&"player_on_foot") as Node3D
	if player and player.get("in_car") == false:
		return player
	return get_tree().get_first_node_in_group(&"player_car") as Node3D


func _on_foot_at() -> Vector3:
	var player := get_tree().get_first_node_in_group(&"player_on_foot") as Node3D
	return player.global_position if player and player.get("in_car") == false else Vector3.INF


static func _seconds(text: String) -> float:
	return clampf(2.0 + text.length() / 16.0, 3.5, 8.0)


func save_state() -> Dictionary:
	return {"step": step, "asked": asked}


func load_state(data: Dictionary) -> void:
	step = int(data.get("step", WAITING))
	asked.clear()
	for a in data.get("asked", []):
		asked.append(String(a))
	if step == ASKING:
		_heard_at = _clock - CARD_FOR  # the card's moment has passed
