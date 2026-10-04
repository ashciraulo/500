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
## Window opacity. The exported glass is quite dark; keep it light so the
## interior view can see out, day or night.
@export var glass_alpha := 0.14
@export var glass_tint := Color(0.62, 0.72, 0.76)

var _materials := {}
var _steering_wheel: Node3D
var _steering_rest: Basis
var _brake_lights: Node3D
var _stock_paint: Color
var _stock_wear: Texture2D
const LIVERY_MODES := {"stripes": 1, "chequered_roof": 2, "scorpion": 3, "side_stripe": 4, "two_tone": 5}
var _livery_mode := 0
var _trinkets: Node3D
var _swings: Array[Node3D] = []
var _last_velocity := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_speed := Vector2.ZERO


func _ready() -> void:
	_materials = PS1Model.apply(self)
	_clear_glass()
	var paint := _materials.get("Paint") as ShaderMaterial
	if paint:
		_stock_paint = paint.get_shader_parameter("albedo_color")
		_stock_wear = paint.get_shader_parameter("albedo_texture")
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
	if _livery_mode > 0:
		_set_paint_param("livery_space", Projection(global_transform.affine_inverse()))
	if not _swings.is_empty():
		_swing_trinkets(car, _delta)
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
	paint.set_shader_parameter("albedo_texture", _stock_wear if keep_wear else null)


## Back to the paint the model came with (wear and all).
func reset_paint() -> void:
	var paint := _materials.get("Paint") as ShaderMaterial
	if paint == null:
		return
	paint.set_shader_parameter("albedo_color", _stock_paint)
	paint.set_shader_parameter("albedo_texture", _stock_wear)


## Show earned extras: `livery` is a cosmetic ({} for none), `trinkets` a
## list of them (see data/progression/cosmetics.json and Trinkets).
func apply_cosmetics(livery: Dictionary, trinkets: Array) -> void:
	_livery_mode = LIVERY_MODES.get(livery.get("mode", ""), 0)
	_set_paint_param("livery_mode", _livery_mode)
	if _livery_mode > 0:
		_set_paint_param("livery_color", Color.html(livery.get("color", "#ffffff")))
		var bounds := _body_bounds()
		_set_paint_param("livery_min", bounds.position)
		_set_paint_param("livery_max", bounds.end)
		_set_paint_param("livery_space", Projection(global_transform.affine_inverse()) if is_inside_tree() else Projection.IDENTITY)
	if _trinkets:
		_trinkets.free()
	_swings.clear()
	_trinkets = Node3D.new()
	_trinkets.name = "Trinkets"
	add_child(_trinkets)
	for item: Dictionary in trinkets:
		var node := Trinkets.build(item)
		node.position = Trinkets.slot_position(self, item.get("slot", "dash"))
		_trinkets.add_child(node)
		for swing in node.find_children("Swing", "Node3D", true, false) + node.find_children("Bob", "Node3D", true, false):
			_swings.append(swing)


func _set_paint_param(param: String, value: Variant) -> void:
	var paint := _materials.get("Paint") as ShaderMaterial
	if paint:
		paint.set_shader_parameter(param, value)


## The main shell's bounds in this model's space (liveries are laid out on it).
func _body_bounds() -> AABB:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body:
		return body.transform * body.get_aabb()
	return AABB(Vector3(-0.8, 0.2, -1.8), Vector3(1.6, 1.5, 3.6))


## Hanging and bobbing trinkets lean against the car's acceleration and
## spring back.
func _swing_trinkets(car: CarController, delta: float) -> void:
	if delta <= 0.0:
		return
	var accel := (car.linear_velocity - _last_velocity) / delta
	_last_velocity = car.linear_velocity
	var local := global_basis.inverse() * accel
	# Settles at roughly the angle a pendulum would: atan(a / g).
	var push := Vector2(local.z, -local.x) * (60.0 / 9.8)
	_sway_speed += (push - _sway * 60.0) * delta - _sway_speed * 2.5 * delta
	_sway += _sway_speed * delta
	_sway = _sway.clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
	for swing in _swings:
		# Standing ones lean the opposite way to hanging ones, and less.
		var lean := _sway * (-0.5 if swing.name == "Bob" else 1.0)
		swing.rotation = Vector3(lean.x, 0.0, lean.y)


func _clear_glass() -> void:
	var glass := _materials.get("Glass") as BaseMaterial3D
	if glass == null:
		return
	glass.albedo_color = Color(glass_tint, glass_alpha)
	glass.roughness = 0.1
	glass.metallic_specular = 0.3
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED


func _glow(material_name: String, color: Color, energy: float) -> void:
	var material := _materials.get(material_name) as ShaderMaterial
	if material:
		material.set_shader_parameter("emission_color", color)
		material.set_shader_parameter("emission_energy", energy)
