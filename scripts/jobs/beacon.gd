class_name Beacon
extends Node3D
## A glowing column marking where to go, visible from a long way off and
## through fog, PS1 style. Jobs creates and moves these.

@export var color := Color(1.0, 0.8, 0.3)
@export var radius := 6.0

var _column: MeshInstance3D
var _ring: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.35)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true

	_column = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.6
	cylinder.bottom_radius = 0.9
	cylinder.height = 60.0
	cylinder.radial_segments = 8
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	_column.mesh = cylinder
	_column.material_override = material
	_column.position.y = 30.0
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.25
	torus.outer_radius = radius
	torus.rings = 24
	torus.ring_segments = 4
	_ring.mesh = torus
	var ring_material := material.duplicate() as StandardMaterial3D
	ring_material.albedo_color = Color(color, 0.8)
	_ring.material_override = ring_material
	_ring.position.y = 0.15
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _process(delta: float) -> void:
	_time += delta
	_ring.scale = Vector3.ONE * (1.0 + sin(_time * 3.0) * 0.04)


## True when `point` is inside the ring (ignoring height).
func contains(point: Vector3) -> bool:
	var flat := point - global_position
	flat.y = 0.0
	return flat.length() <= radius
