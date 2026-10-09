class_name HomeField
extends Node3D
## The field journal at home: the binoculars you start with hang on the hook
## by the back door until you take them (an M scratched into the prism
## cover), and once the journal has 30 species a bird feeder goes up in the
## courtyard and garden birds you've seen come to it by day. From the story's
## act 3, the buyer's envelope turns up inside the front door the morning
## after you keep a blank print (FieldJournal.take_envelope).

const BINOCULARS := "res://art/models/props/field/binoculars.glb"
const FEEDER := "res://art/models/props/field/bird_feeder.glb"
## Discovered once the binoculars are off the hook.
const TAKEN := "field/binoculars"
const FEEDER_SPECIES := 30
## Garden birds that really come to a seed tray in a Perth courtyard.
const FEEDER_BIRDS := ["laughing_dove", "spotted_dove", "new_holland_honeyeater", "singing_honeyeater",
	"red_wattlebird", "rainbow_lorikeet", "willie_wagtail", "splendid_fairywren"]
const REACH := 1.5
## Birds at the feeder keep this far from you.
const SHY := 4.0
## The envelope lies on the hall floor this far in from the front door.
const ENVELOPE_IN := 0.5

var _home: Node3D
var _hook: Node3D
var _hanging: Node3D
var _feeder: Node3D
var _visitors: Array[Node3D] = []
var _envelope: Node3D
var _visit_day := -1
var _prompt: PromptChip
var _prompt_layer: CanvasLayer
var _check := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 5
	_prompt = PromptChip.new()
	_prompt.place_bottom(112.0)
	_prompt_layer.add_child(_prompt)
	add_child(_prompt_layer)


## True once the starter binoculars are off the hook (old saves with any
## journal entries count as having them).
static func has_binoculars() -> bool:
	if Discoveries.has(TAKEN):
		return true
	if not FieldJournal.entries.is_empty():
		Discoveries.discover(TAKEN)
		return true
	return false


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_find_home()
		_update_hook()
		_update_feeder()
		_update_envelope()
	_prompt.text = "F  Take the binoculars" if _can_take() else ("F  Pick up the envelope" if _near_envelope() else "")
	_animate_visitors(delta)


func _input(event: InputEvent) -> void:
	if get_tree().paused or not event.is_action_pressed("interact") or event.is_echo():
		return
	if _can_take():
		take_binoculars()
		get_viewport().set_input_as_handled()
	elif _near_envelope():
		take_envelope()
		get_viewport().set_input_as_handled()


func _find_home() -> void:
	if is_instance_valid(_home):
		return
	_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
	if _home:
		_hook = _home.find_child("Binoculars_Hook", true, false) as Node3D


func _walker() -> Node3D:
	var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
	var walker := car.get_parent().get_node_or_null(^"Player") as Node3D if car else null
	return walker if walker and not walker.get("in_car") and walker.is_physics_processing() else null


func _can_take() -> bool:
	if not is_instance_valid(_hanging) or get_tree().paused:
		return false
	var walker := _walker()
	if walker == null:
		return false
	var to := _hanging.global_position - walker.global_position
	return Vector2(to.x, to.z).length() < REACH


# --- the hook by the back door -----------------------------------------------------------------

func _update_hook() -> void:
	if has_binoculars():
		if is_instance_valid(_hanging):
			_hanging.queue_free()
		return
	if is_instance_valid(_hanging) or not is_instance_valid(_hook) or not ResourceLoader.exists(BINOCULARS):
		return
	_hanging = (load(BINOCULARS) as PackedScene).instantiate() as Node3D
	_hanging.name = "HangingBinoculars"
	_hook.add_child(_hanging)
	# Hanging by the strap: eyepieces up, the big barrels down, the M on the
	# prism cover facing into the room.
	_hanging.rotation = Vector3(PI * 0.5, 0, 0)
	_hanging.position = Vector3(0, -0.14, 0.04)


func take_binoculars() -> void:
	if is_instance_valid(_hanging):
		_hanging.queue_free()
	_hanging = null
	Discoveries.discover(TAKEN)
	Activities.say("Binoculars, off the hook. Someone's scratched an M into the prism cover. B to use them.")
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has("field/binoculars_up"):
		audio.play_2d("field/binoculars_up", "UI", -6.0)


# --- the feeder ---------------------------------------------------------------------------------

func _update_feeder() -> void:
	if is_instance_valid(_feeder) or not is_instance_valid(_home) or FieldJournal.seen_count() < FEEDER_SPECIES:
		return
	var spot := _home.find_child("Feeder_Spot", true, false) as Node3D
	if spot == null or not ResourceLoader.exists(FEEDER):
		return
	_feeder = (load(FEEDER) as PackedScene).instantiate() as Node3D
	_feeder.name = "BirdFeeder"
	spot.add_child(_feeder)
	if Discoveries.discover("field/feeder"):
		Activities.say("Thirty species in the journal. There's a bird feeder up in the courtyard now.")


## Garden birds you've seen come to the feeder by day, a couple at a time,
## and flit off when you get close.
func _animate_visitors(delta: float) -> void:
	if not is_instance_valid(_feeder):
		return
	var day := GameClock.day if GameClock.daylight() > 0.3 else -1
	if day != _visit_day:
		_visit_day = day
		_clear_visitors()
		if day >= 0:
			_seat_visitors()
	var walker := _walker()
	var t := Time.get_ticks_msec() / 1000.0
	for i in _visitors.size():
		var bird := _visitors[i]
		if not is_instance_valid(bird):
			continue
		var near := walker != null and walker.global_position.distance_to(bird.global_position) < SHY
		if near and bird.visible:
			bird.visible = false  # off to the gutter until you've gone
		elif not near and not bird.visible and _rng.randf() < delta * 0.2:
			bird.visible = true
		if bird.visible:
			bird.rotation.y = sin(t * 0.7 + i * 2.0) * 0.6
			BirdModels.flap(bird, t * 3.0 + i, 0.0)


func _seat_visitors() -> void:
	var garden: Array[Dictionary] = []
	for id: String in FEEDER_BIRDS:
		if FieldJournal.entries.has(id):
			garden.append(FieldJournal.bird(id))
	if garden.is_empty():
		return
	var perches: Array[Node3D] = []
	for i in range(1, 5):
		var p := _feeder.find_child("Perch_%d" % i, true, false) as Node3D
		if p:
			perches.append(p)
	perches.shuffle()
	for i in mini(_rng.randi_range(1, 3), perches.size()):
		var sp: Dictionary = garden[_rng.randi() % garden.size()]
		var bird := BirdModels.build(sp)
		bird.name = "FeederVisitor"
		perches[i].add_child(bird)
		_visitors.append(bird)


func _clear_visitors() -> void:
	for bird in _visitors:
		if is_instance_valid(bird):
			bird.queue_free()
	_visitors.clear()


# --- the buyer's envelope -----------------------------------------------------------------------

func _update_envelope() -> void:
	if not FieldJournal.envelope_ready() or not is_instance_valid(_home):
		if is_instance_valid(_envelope):
			_envelope.queue_free()
		_envelope = null
		return
	if is_instance_valid(_envelope):
		return
	var door := _home.find_child("Door_Front", true, false) as Node3D
	if door == null:
		return
	var box := _bounds(door)
	var centre := box.get_center()
	# In from the door: away from the front gate.
	var gate: Transform3D = _home.call("spawn_transform", &"Spawn_Front") if _home.has_method("spawn_transform") else _home.global_transform
	var inward := centre - gate.origin
	inward.y = 0.0
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.FORWARD
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.23, 0.004, 0.12)
	mesh.material = PS1Material.make(Color("c4a26a"), 1.0)  # a brown paper envelope
	var env := MeshInstance3D.new()
	env.name = "BuyerEnvelope"
	env.mesh = mesh
	add_child(env)
	env.global_position = Vector3(centre.x, box.position.y + 0.004, centre.z) + inward * ENVELOPE_IN
	env.rotation.y = atan2(inward.x, inward.z) + _rng.randf_range(-0.5, 0.5)
	_envelope = env


func _bounds(node: Node3D) -> AABB:
	var box := AABB(node.global_position, Vector3.ZERO)
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		box = box.merge(m.global_transform * m.get_aabb())
	if node is MeshInstance3D:
		box = box.merge(node.global_transform * (node as MeshInstance3D).get_aabb())
	return box


func _near_envelope() -> bool:
	if not is_instance_valid(_envelope) or get_tree().paused:
		return false
	var walker := _walker()
	if walker == null:
		return false
	var to := _envelope.global_position - walker.global_position
	return Vector2(to.x, to.z).length() < REACH


## Pick up the buyer's envelope: the cash, and a note in the tapes' handwriting.
func take_envelope() -> void:
	var got := FieldJournal.take_envelope()
	if is_instance_valid(_envelope):
		_envelope.queue_free()
	_envelope = null
	if got.is_empty():
		return
	Activities.say("An envelope under the door. $%d, and a note: \"%s\"" % [int(got.pay), String(got.note)])
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has("field/envelope"):
		audio.play_2d("field/envelope", "UI", -6.0)
