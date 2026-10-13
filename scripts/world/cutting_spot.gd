class_name CuttingSpot
extends Node3D
## A rare plant growing somewhere in the city (data/world/cuttings.json): the
## grown, flowering plant with the findable sparkle over it (FindableMarker)
## until you've had a cutting. Walk up and press F to take a cutting home
## (discovery "cutting/<id>"); it shows up on the dining table, and HomeLife
## grows it from there.

const WALK_REACH := 2.4

@export var cutting_id := ""
@export var title := ""

var _grounded := false
var _check := 0.0
var _marker: FindableMarker


func _ready() -> void:
	add_to_group(&"interactables")
	var path := HomeLife.PLANT_MODEL % cutting_id
	if ResourceLoader.exists(path):
		var plant := (load(path) as PackedScene).instantiate() as Node3D
		PS1Model.apply(plant)
		for child in plant.get_children():
			if child is Node3D and String(child.name).begins_with("Stage_"):
				(child as Node3D).visible = child.name == "Stage_3"
		plant.scale = Vector3.ONE * 1.6  # the parent plant is bigger than yours will be
		add_child(plant)
	_marker = FindableMarker.new()
	_marker.height = 1.7
	add_child(_marker)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	_marker.visible = not taken()
	if not _grounded:
		var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
		if car and car.global_position.distance_to(global_position) < 150.0:
			_snap_to_ground(car)


func _snap_to_ground(car: Node3D) -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 8.0, global_position + Vector3.DOWN * 12.0, 1)
	if car is CollisionObject3D:
		query.exclude = [(car as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		global_position = hit.position
		_grounded = true


func taken() -> bool:
	return Discoveries.has("cutting/" + cutting_id)


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.6


func interact_hint() -> String:
	return "" if taken() else "Take a cutting of the %s" % title.to_lower()


func interact() -> void:
	if not Discoveries.discover("cutting/" + cutting_id):
		return
	Activities.say("You take a cutting of the %s. It'll want a jar of water on the dining table." % title.to_lower())
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has("home/home_leaves_brush_01"):
		audio.play_2d("home/home_leaves_brush_01", "SFX", -4.0)
