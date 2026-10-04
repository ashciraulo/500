class_name Collectible
extends Node3D
## One of the hidden "500" badges. Drive through it to collect it; it's
## counted in Discoveries as "badge/<badge_id>" and won't appear again.
## The map places these (some on rooftops reached by car park ramps); the
## test grid has a handful.

const PICKUP_RADIUS := 3.0
## How many badges the finished map hides.
const TOTAL := 60

@export var badge_id := ""

var _visual: Node3D
var _time := 0.0
var _car: Node3D


func _ready() -> void:
	add_to_group(&"collectibles")
	if Discoveries.has(key()):
		queue_free()
		return
	_visual = Node3D.new()
	_visual.position.y = 1.4
	add_child(_visual)
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.55
	cylinder.bottom_radius = 0.55
	cylinder.height = 0.08
	cylinder.radial_segments = 12
	disc.mesh = cylinder
	disc.rotation.x = PI / 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.12, 0.12)
	material.emission_enabled = true
	material.emission = Color(0.9, 0.2, 0.15)
	material.emission_energy_multiplier = 0.8
	material.metallic = 0.6
	disc.material_override = material
	_visual.add_child(disc)
	var text := Label3D.new()
	text.text = "500"
	text.font_size = 48
	text.pixel_size = 0.008
	text.outline_size = 6
	text.modulate = Color(1.0, 0.95, 0.8)
	text.position.z = 0.05
	text.double_sided = true
	_visual.add_child(text)


func key() -> String:
	return "badge/" + badge_id


func _process(delta: float) -> void:
	if _visual == null:
		return
	_time += delta
	_visual.rotation.y = _time * 2.0
	_visual.position.y = 1.4 + sin(_time * 2.5) * 0.12
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as Node3D
		return
	if _car.global_position.distance_to(global_position + Vector3.UP) <= PICKUP_RADIUS:
		collect()


func collect() -> void:
	if Discoveries.discover(key()):
		queue_free()


## How many badges have been found.
static func found_count() -> int:
	var count := 0
	for id in Discoveries.all():
		if String(id).begins_with("badge/"):
			count += 1
	return count
