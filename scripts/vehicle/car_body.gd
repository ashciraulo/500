extends Node3D
## Visual side of a car built in Blender (art/models/cars/...): PS1 materials,
## steering wheel, lamps and paint. Attach to the instanced model that sits
## in the car scene's `Body` slot; the parent must be a CarController.
##
## Model contract (see art/models/README.md): nodes `SteeringWheel` (turns
## about its local Z), `Door_L` / `Door_R` (hinge on local Y), materials
## `Paint`, `LampHead`, `LampTail`.

## Steering wheel turns per radian of road-wheel angle (roughly a 14:1 rack,
## scaled down so it reads at low resolution).
@export var steering_ratio := 6.0
@export var head_glow := 2.5
@export var tail_glow := 0.6
@export var brake_glow := 2.0

var _materials := {}
var _steering_wheel: Node3D
var _steering_rest: Basis
var _brake_lights: Node3D


func _ready() -> void:
	_materials = PS1Model.apply(self)
	var wheels := get_parent().get_node_or_null("Wheels")
	if wheels:
		PS1Model.apply(wheels)
	_steering_wheel = find_child("SteeringWheel", true, false) as Node3D
	if _steering_wheel:
		_steering_rest = _steering_wheel.basis
	_brake_lights = get_parent().get_node_or_null("BrakeLights")


func _process(_delta: float) -> void:
	var car := get_parent() as CarController
	if car == null:
		return
	if _steering_wheel:
		_steering_wheel.basis = _steering_rest * Basis(Vector3.BACK, -car.steer_angle * steering_ratio)
	var braking := _brake_lights != null and _brake_lights.visible
	_glow("LampHead", Color(1.0, 0.95, 0.82), head_glow if car.headlights_on else 0.0)
	var tail := (brake_glow if braking else 0.0) + (tail_glow if car.headlights_on else 0.0)
	_glow("LampTail", Color(1.0, 0.1, 0.06), tail)


## Respray. A fresh coat drops the sun-faded wear texture.
func set_paint(color: Color, keep_wear := false) -> void:
	var paint := _materials.get("Paint") as ShaderMaterial
	if paint == null:
		return
	paint.set_shader_parameter("albedo_color", color)
	if not keep_wear:
		paint.set_shader_parameter("albedo_texture", null)


func _glow(material_name: String, color: Color, energy: float) -> void:
	var material := _materials.get(material_name) as ShaderMaterial
	if material:
		material.set_shader_parameter("emission_color", color)
		material.set_shader_parameter("emission_energy", energy)
