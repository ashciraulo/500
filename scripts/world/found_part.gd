class_name FoundPart
extends Node3D
## A part you can't buy, sitting where data/world/found_parts.json says:
## a set of old wheels by a roller door, a surf rack behind the surf club.
## Stop next to it in the car, or walk up to it, and it's yours (discovery
## "part/<id>"); fit it in any workshop that does parts. An `on_foot` part
## (the tailpipe on a shed bench) is only taken by walking up to it.

const DATA_PATH := "res://data/world/found_parts.json"
const FIND_RADIUS := 7.0
const FIND_SPEED_KMH := 4.0
const WALK_RADIUS := 2.2

@export var part_id := ""
## Only taken on foot, not by stopping the car near it.
@export var on_foot := false

var _visual: Node3D
var _car: Node3D
var _player: Node
var _check := 0.0
var _grounded := false


## The found-only parts and where they are, from DATA_PATH.
static func entries() -> Array:
	if not FileAccess.file_exists(DATA_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed.get("parts", []) if parsed is Dictionary else []


func _ready() -> void:
	add_to_group(&"found_parts")
	_visual = Node3D.new()
	add_child(_visual)
	var part := PartsCatalogue.get_part(StringName(part_id))
	var model_path := ""
	if part and part.visual != "":
		model_path = CarController.PART_MODEL_PATH % (part.visual + ("_l" if part.slot == &"wheels" else ""))
	if model_path != "" and ResourceLoader.exists(model_path):
		var model := (load(model_path) as PackedScene).instantiate() as Node3D
		_visual.add_child(model)
		PS1Model.apply(model)
		if part.slot == &"wheels":
			# Leaning against something, as wheels do.
			model.position = Vector3(0.0, 0.28, 0.0)
			model.rotation.z = 0.25
			var second := (load(model_path) as PackedScene).instantiate() as Node3D
			second.position = Vector3(0.18, 0.28, 0.1)
			second.rotation.z = 0.3
			_visual.add_child(second)
			PS1Model.apply(second)
		else:
			model.position.y = 0.15 if part.slot != &"roof" else 0.25
	var glint := OmniLight3D.new()
	glint.light_color = Color(1.0, 0.92, 0.75)
	glint.light_energy = 0.6
	glint.omni_range = 3.0
	glint.position.y = 0.8
	_visual.add_child(glint)
	_refresh()


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.4
	_refresh()
	if not _visual.visible:
		return
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as Node3D
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().root.find_child("Player", true, false)
	if not _grounded and _car and _car.global_position.distance_to(global_position) < 150.0:
		_snap_to_ground()
	var walking: bool = _player != null and _player is Node3D and not _player.get("in_car")
	if walking:
		if (_player as Node3D).global_position.distance_to(global_position) < WALK_RADIUS \
				and _can_reach(_player as Node3D):
			take()
	elif not on_foot and _car and _car.global_position.distance_to(global_position) < FIND_RADIUS \
			and _car.linear_velocity.length() * 3.6 < FIND_SPEED_KMH:
		take()


## Nothing solid between your hands and it: no taking the tailpipe off the
## bench through the shed wall from outside.
func _can_reach(player: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.9, global_position + Vector3.UP * 0.2, 1)
	var skip: Array[RID] = []
	if player is CollisionObject3D:
		skip.append((player as CollisionObject3D).get_rid())
	if _car is CollisionObject3D:
		skip.append((_car as CollisionObject3D).get_rid())
	query.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Sit on whatever's under it, once the map has loaded around it (from
## under a shed roof: the tailpipe sits on the Kensington shed's bench).
func _snap_to_ground() -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 2.0, global_position + Vector3.DOWN * 12.0, 1)
	if _car is CollisionObject3D:
		query.exclude = [(_car as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		global_position = hit.position
		_grounded = true


func take() -> void:
	if not Discoveries.discover("part/" + part_id):
		return
	var part := PartsCatalogue.get_part(StringName(part_id))
	var title := part.display_name if part else part_id
	Notices.post("%s. It's yours to fit in the workshop." % title, "find")
	Progression.add_stat("parts_found")
	_refresh()


func _refresh() -> void:
	_visual.visible = not Discoveries.has("part/" + part_id)
