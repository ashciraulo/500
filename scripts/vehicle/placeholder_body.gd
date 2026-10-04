extends Node3D
## Stand-in Fiat 500 body made of boxes, until the Blender model lands.
##
## Built in code so it is easy to throw away: the model thread replaces this
## `Body` node in scenes/vehicles/fiat_500_pop.tscn with the imported model.
## The cabin is hollow (pillars, roof, dash, seats, wheel) so the interior
## camera has something to look out of. Right-hand drive, like in Australia.

@export var paint := Color(0.62, 0.78, 0.84)
@export var trim := Color(0.12, 0.12, 0.13)

var _steering_wheel: Node3D


func _ready() -> void:
	var body_paint := PS1Material.make(paint, 0.6)
	var dark := PS1Material.make(trim, 0.8)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.35, 0.45, 0.5, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var chrome := PS1Material.make(Color(0.8, 0.8, 0.82), 0.3)
	var lamp := PS1Material.glowing(Color(1.0, 0.95, 0.8), 1.5)
	var tail := PS1Material.glowing(Color(0.8, 0.05, 0.05), 0.8)

	# Car local space: origin ~0.44 m above the ground, nose towards -Z.
	_box(Vector3(1.62, 0.62, 3.0), Vector3(0, 0.02, -0.05), body_paint)       # lower body
	_box(Vector3(1.5, 0.22, 0.55), Vector3(0, 0.12, -1.6), body_paint)        # rounded nose
	_box(Vector3(1.66, 0.16, 0.12), Vector3(0, -0.2, -1.84), dark)            # front bumper
	_box(Vector3(1.66, 0.18, 0.12), Vector3(0, -0.18, 1.5), dark)             # rear bumper
	_box(Vector3(1.6, 0.12, 0.25), Vector3(0, -0.25, 1.35), body_paint)       # rear valance
	_box(Vector3(1.36, 0.05, 1.7), Vector3(0, 1.03, 0.25), body_paint)        # roof
	for x in [-0.68, 0.68]:
		_box(Vector3(0.07, 0.68, 0.08), Vector3(x, 0.68, -0.62), body_paint, Vector3(-28, 0, 0))  # A pillars
		_box(Vector3(0.07, 0.62, 0.12), Vector3(x, 0.7, 0.45), body_paint)    # B pillars
		_box(Vector3(0.07, 0.62, 0.3), Vector3(x, 0.7, 1.05), body_paint, Vector3(15, 0, 0))  # C pillars
	_box(Vector3(1.3, 0.62, 0.03), Vector3(0, 0.69, -0.64), glass, Vector3(-55, 0, 0))  # windscreen
	_box(Vector3(1.25, 0.5, 0.03), Vector3(0, 0.72, 1.12), glass, Vector3(25, 0, 0))    # rear window
	_box(Vector3(1.5, 0.18, 0.4), Vector3(0, 0.42, -0.62), dark)              # dashboard
	_box(Vector3(0.45, 0.08, 0.5), Vector3(0.36, 0.25, 0.4), dark)            # driver seat base
	_box(Vector3(0.45, 0.6, 0.1), Vector3(0.36, 0.55, 0.68), dark)            # driver seat back
	_box(Vector3(0.45, 0.08, 0.5), Vector3(-0.36, 0.25, 0.4), dark)           # passenger seat
	_box(Vector3(0.45, 0.6, 0.1), Vector3(-0.36, 0.55, 0.68), dark)
	for x in [-0.58, 0.58]:
		_cylinder(0.09, 0.05, Vector3(x, 0.2, -1.88), lamp, Vector3(90, 0, 0))  # round headlights
		_box(Vector3(0.2, 0.12, 0.04), Vector3(x, 0.22, 1.47), tail)           # tail lights
	_box(Vector3(0.4, 0.05, 0.05), Vector3(0, 0.08, -1.88), chrome)          # badge bar

	# Tilted column, with the wheel spinning about the column's own axis.
	var column := Node3D.new()
	column.position = Vector3(0.36, 0.47, -0.36)
	column.rotation_degrees = Vector3(62, 0, 0)
	add_child(column)
	_steering_wheel = Node3D.new()
	column.add_child(_steering_wheel)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.18
	torus.rings = 12
	torus.ring_segments = 6
	rim.mesh = torus
	rim.material_override = dark
	_steering_wheel.add_child(rim)
	var spoke := MeshInstance3D.new()
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(0.3, 0.02, 0.04)
	spoke.mesh = spoke_mesh
	spoke.material_override = dark
	_steering_wheel.add_child(spoke)


func _process(_delta: float) -> void:
	var car := get_parent() as CarController
	if car and _steering_wheel:
		# Road-wheel angle times a 14:1-ish ratio, scaled down to look right.
		_steering_wheel.rotation.y = car.steer_angle * 6.0


func _box(size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation_degrees = rot_deg
	add_child(instance)


func _cylinder(radius: float, height: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation_degrees = rot_deg
	add_child(instance)
