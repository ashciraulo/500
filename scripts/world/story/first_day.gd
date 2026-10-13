class_name FirstDay
extends Node3D
## A new game's first few minutes: something clear to do straight away, in
## the card at the top right where jobs show (ChallengeCard). Each step ticks
## off when you do it:
##
##   plate    get out and take the plate Thea left on the front step
##            (her welcome on the machine says it's there)
##   machine  go in and play the answering machine
##   job      open the phone and take a job
##   paid     the first job's paid: where the rest of the game lives (your
##            goals on the phone's Progress tab, the radio after midnight)
##
## Out driving, the home steps wait and the job step shows instead. Starts
## once Side A's card has been and gone. Only in a new game: a save from
## before this, or one already under way, starts with it done.
##
## Added by GameplayPlaces. Saved under "first_day".

enum { PLATE, MACHINE, JOB, PAID, DONE }

## Seconds after the act card before the first step.
const AFTER_CARD := 1.5
## Home steps only while you're this close to home (m).
const NEAR_HOME := 90.0
## How long the last card stays up (s).
const PAID_FOR := 16.0
## The plate: on the step, to the latch side of the front door (house frame:
## x across from the door, y out from the front wall).
const STEP_OFFSET := Vector2(0.55, -0.32)
## On the breakfast bar once it's in, beside the plant (and clear of the
## answering machine on its other side): the first of these (m from it, in
## the house's x and z) with bar top all the way under the plate.
const BAR_SPOTS := [Vector2(0.0, 0.3), Vector2(0.0, -0.3), Vector2(0.4, 0.0), Vector2(-0.6, 0.0)]
const PLATE_WHITE := Color(0.93, 0.91, 0.86)
const PLATE_BLUE := Color(0.2, 0.32, 0.6)
const BISCUIT := Color(0.93, 0.7, 0.38)
const BISCUIT_DARK := Color(0.82, 0.56, 0.27)
const NOTE := Color(0.96, 0.94, 0.88)

var step := PLATE
## Taken off the step, and the day it came in (it's gone by the day after next).
var plate_taken := false
var plate_day := 0

var _home: HomeBase
var _people: Node
var _plate: Node3D
var _note: MeshInstance3D
var _wait := -1.0
var _paid_t := 0.0
var _checked := false
var _loaded := false
var _day := 0


func _ready() -> void:
	name = "FirstDay"
	add_to_group(&"challenges")
	add_to_group(&"interactables")
	_plate = _build_plate()
	_plate.visible = false
	SaveGame.register("first_day", self)
	Jobs.job_completed.connect(_on_paid)


func _exit_tree() -> void:
	SaveGame.unregister("first_day")


func _process(delta: float) -> void:
	if get_tree().paused or SaveGame.hold:
		return
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as HomeBase
		if _home == null:
			return
		_place_plate()
	if _day != GameClock.day:
		_day = GameClock.day
		_place_plate()
	if not _checked:
		_checked = true
		# A game from before this, or one well under way.
		if not _loaded and (GameClock.day > 1 or Progression.get_stat("deliveries") > 0.0
				or Wallet.total_earned > 0 or Story.heard(&"kostas_welcome")):
			step = DONE
			_place_plate()
	if step == DONE:
		return
	if _wait < 0.0:
		# Side A's card first.
		if not _card_done():
			return
		_wait = 0.0
	_wait += delta
	if step == MACHINE and Story.heard(&"kostas_welcome"):
		step = JOB
	if step == PAID:
		_paid_t += delta
		if _paid_t >= PAID_FOR:
			step = DONE


func _card_done() -> bool:
	if _people == null or not is_instance_valid(_people):
		_people = get_tree().get_first_node_in_group(&"story_people")
		if _people == null and get_parent():
			_people = get_parent().get_node_or_null(^"StoryPeople")
		if _people == null:
			return true
	if int(_people.get("card_act")) < 1:
		return false
	for c in _people.get_children():
		if c is ActCard and (c as ActCard).showing():
			return false
	return true


func _on_paid(_job: Dictionary, _pay: int, _summary: String) -> void:
	if step < PAID:
		step = PAID
		_paid_t = 0.0


func _near_home() -> bool:
	var player := get_tree().get_first_node_in_group(&"player_on_foot") as Node3D
	var who := player
	if player == null or player.get("in_car") != false:
		who = get_tree().get_first_node_in_group(&"player_car") as Node3D
	if who == null or _home == null:
		return true
	return who.global_position.distance_to(_home.global_position) < NEAR_HOME


func _on_foot() -> bool:
	var player := get_tree().get_first_node_in_group(&"player_on_foot")
	return player != null and player.get("in_car") == false


# --- The card -------------------------------------------------------------------

func challenge_card() -> Dictionary:
	if step == DONE or _wait < AFTER_CARD:
		return {}
	var shown := step
	if shown < JOB and not _near_home():
		shown = JOB
	match shown:
		PLATE:
			return _card("Something on the step",
				("Go and see" if _on_foot() else "Get out (hold F) and see") + " what the neighbour left on your front step.")
		MACHINE:
			return _card("The answering machine",
				"It's blinking. Go inside and play the message.")
		JOB:
			if not Jobs.active.is_empty():
				return {}
			return _card("Rent's coming", "Open your phone (Tab / X) and take a job.")
		PAID:
			return _card("Paid", "There's more work on your phone any time. Your goals are under Progress.",
				"Late at night, try the radio.")
	return {}


func _card(title: String, line: String, detail := "") -> Dictionary:
	return {"tag": "First day", "icon": "star", "title": title, "line": line, "detail": detail}


# --- The plate ------------------------------------------------------------------

func interact_point() -> Vector3:
	return _plate.global_position + Vector3.UP * 0.04


func interact_hint() -> String:
	return "Take the plate" if _plate.visible and not plate_taken else ""


func interact() -> void:
	if plate_taken:
		return
	plate_taken = true
	plate_day = GameClock.day
	_place_plate()
	Notices.post("Koulourakia, still warm. The note says: \"Welcome to the lane! Thea, no. 11\"",
		"info", "ui/ui_phone_notify", "On the step")
	if step == PLATE:
		step = MACHINE


## On the step until it's taken, then on the breakfast bar until the day
## after next. Not at all in a game that started before it existed.
func _place_plate() -> void:
	if _home == null:
		return
	var on_step := not plate_taken and step <= PLATE
	var on_bar := plate_taken and GameClock.day <= plate_day + 1
	_plate.visible = on_step or on_bar
	if _note:
		_note.visible = on_step
	if on_step:
		var door := _home.to_local(_home.spawn_transform(&"Spawn_Front").origin).x
		_put(_home.to_global(Vector3(door + STEP_OFFSET.x, 0.0, -STEP_OFFSET.y)), _home.global_basis)
	elif on_bar:
		var plant := _home.find_child("Oddity_Plant", true, false) as Node3D
		if plant == null:
			_plate.visible = false
			return
		var level := _ground(plant.global_position, 0.3, 0.3)
		for o: Vector2 in BAR_SPOTS:
			var at := plant.global_position + _home.global_basis.x * o.x + _home.global_basis.z * o.y
			if _flat(at, level):
				at.y = level
				_plate.global_transform = Transform3D(_home.global_basis.orthonormalized().rotated(Vector3.UP, 0.3), at)
				return
		_plate.visible = false


## Bar top at `level` under the middle and the rim of a plate at `at`.
func _flat(at: Vector3, level: float) -> bool:
	for d: Vector3 in [Vector3.ZERO, Vector3(0.12, 0, 0), Vector3(-0.12, 0, 0), Vector3(0, 0, 0.12), Vector3(0, 0, -0.12)]:
		if absf(_ground(at + d, 0.3, 0.3) - level) > 0.02:
			return false
	return true


## Sat on whatever's under `at` (the step, the bar).
func _put(at: Vector3, basis: Basis) -> void:
	at.y = _ground(at, 1.2, 2.0)
	_plate.global_transform = Transform3D(basis.orthonormalized().rotated(Vector3.UP, 0.3), at)


## The height of whatever's under `at`, looking from `up` above to `down`
## below (`at`'s own height if nothing).
func _ground(at: Vector3, up: float, down: float) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * up, at + Vector3.DOWN * down, 1 | 2)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else at.y - down


func _build_plate() -> Node3D:
	var plate := Node3D.new()
	plate.name = "Plate"
	add_child(plate)
	# A white plate with a blue band round the rim.
	_cylinder(plate, 0.125, 0.012, Vector3(0, 0.006, 0), PLATE_BLUE)
	_cylinder(plate, 0.112, 0.014, Vector3(0, 0.008, 0), PLATE_WHITE)
	# Koulourakia: plaited twists round the plate, a couple of rings on top.
	for i in 7:
		var a := TAU * i / 7.0
		var twist := Node3D.new()
		twist.position = Vector3(cos(a), 0.0, sin(a)) * 0.068 + Vector3.UP * 0.026
		twist.rotation.y = -a + PI / 2.0  # lying round the rim
		plate.add_child(twist)
		for side in [-1.0, 1.0]:
			var strand := _capsule(twist, 0.0095, 0.085, BISCUIT if side > 0 else BISCUIT_DARK)
			strand.position.y = 0.003 * side
			strand.rotation = Vector3(0.0, side * 0.18, PI / 2.0)
	for p: Vector3 in [Vector3(0.012, 0.03, -0.012), Vector3(-0.016, 0.042, 0.014)]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.012
		torus.outer_radius = 0.026
		torus.rings = 12
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = PS1Material.make(BISCUIT)
		ring.position = p
		ring.rotation.x = 0.15
		plate.add_child(ring)
	# The note, folded, leaning on the biscuits.
	_note = MeshInstance3D.new()
	var card := BoxMesh.new()
	card.size = Vector3(0.075, 0.05, 0.002)
	_note.mesh = card
	_note.material_override = PS1Material.make(NOTE)
	_note.position = Vector3(0.0, 0.05, 0.085)
	_note.rotation.x = -0.5
	plate.add_child(_note)
	return plate


func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius * 0.8
	c.height = height
	c.radial_segments = 16
	c.rings = 1
	mi.mesh = c
	mi.material_override = PS1Material.make(colour)
	mi.position = at
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, radius: float, length: float, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = length
	c.radial_segments = 6
	c.rings = 2
	mi.mesh = c
	mi.material_override = PS1Material.make(colour)
	parent.add_child(mi)
	return mi


# --- Saving ---------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"step": step, "plate_taken": plate_taken, "plate_day": plate_day}


func load_state(data: Dictionary) -> void:
	_loaded = true
	step = int(data.get("step", DONE))
	plate_taken = bool(data.get("plate_taken", false))
	plate_day = int(data.get("plate_day", 0))
	_place_plate()
