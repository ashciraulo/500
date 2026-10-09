class_name PorchSwitch
extends Node3D
## The porch light switch, on the wall just inside the front door (STORY.md,
## choice 1). An old cream rocker plate. StoryPeople keeps whether it's on.
##
## Placed by StoryPeople, as a child of the HomeBase, in the house's frame.

## House frame (x across, y back, z up): on the front wall by the door, next
## to the hall light's switch.
const AT := Vector3(0.115, 0.007, 1.3)

var people: StoryPeople
var _rocker: MeshInstance3D
var _click: AudioStreamPlayer3D


func _ready() -> void:
	name = "PorchSwitch"
	add_to_group(&"interactables")
	position = House1979.at(AT)
	_box(Vector3(0.075, 0.115, 0.012), Vector3.ZERO, Color(0.88, 0.85, 0.76))
	_rocker = _box(Vector3(0.022, 0.04, 0.012), Vector3(0.0, 0.0, -0.008), Color(0.8, 0.77, 0.68))
	_click = AudioStreamPlayer3D.new()
	_click.stream = LateSounds.make("light_switch")
	_click.bus = "SFX"
	_click.unit_size = 1.5
	_click.max_distance = 10.0
	add_child(_click)


func _process(_delta: float) -> void:
	# The rocker tips up for on and down for off.
	if people:
		_rocker.rotation.x = -0.35 if people.porch_light_on else 0.35


func interact_point() -> Vector3:
	return global_position


func interact_hint() -> String:
	if people == null:
		return ""
	return "Porch light: turn off" if people.porch_light_on else "Porch light: turn on"


func interact() -> void:
	if people:
		people.set_porch_light(not people.porch_light_on)
		_click.play()


func _box(size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	# Baked to an ArrayMesh: the other house goes through its surfaces.
	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	mi.mesh = baked
	mi.material_override = PS1Material.make(colour)
	mi.position = at
	add_child(mi)
	return mi
