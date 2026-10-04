class_name PhotoSpot
extends Node3D
## One of the 30 marked photo spots: a little camera sign by the road. Take a
## photo (photo mode, P) within RADIUS of it to add it to your album's set.

const RADIUS := 40.0
## Driving this close counts the spot as a discovered place.
const DISCOVER_RADIUS := 25.0

@export var spot_id := ""
@export var title := ""

var _sign: Label3D
var _car: Node3D
var _check := 0.0


func _ready() -> void:
	add_to_group(&"photo_spots")
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 2.2, 0.1)
	post.mesh = box
	post.position.y = 1.1
	post.material_override = PS1Material.make(Color(0.75, 0.75, 0.72))
	add_child(post)
	var plate := MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = Vector3(1.1, 0.75, 0.05)
	plate.mesh = face
	plate.position.y = 2.45
	plate.material_override = PS1Material.make(Color(0.15, 0.5, 0.85))
	add_child(plate)
	_sign = Label3D.new()
	_sign.text = "PHOTO"
	_sign.font_size = 48
	_sign.pixel_size = 0.006
	_sign.outline_size = 8
	_sign.modulate = Color(1.0, 0.95, 0.6)
	_sign.position = Vector3(0, 2.45, 0.04)
	_sign.double_sided = true
	add_child(_sign)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if Discoveries.has("spot/" + spot_id):
		set_process(false)
		return
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as Node3D
		return
	if _car.global_position.distance_to(global_position) < DISCOVER_RADIUS:
		Discoveries.discover("spot/" + spot_id)


func is_taken() -> bool:
	return Discoveries.has("photo/" + spot_id)


## The nearest photo spot within RADIUS of `point`, or null.
static func nearest(tree: SceneTree, point: Vector3) -> PhotoSpot:
	var best: PhotoSpot = null
	var best_d := RADIUS
	for node in tree.get_nodes_in_group(&"photo_spots"):
		var d := (node as Node3D).global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = node
	return best
