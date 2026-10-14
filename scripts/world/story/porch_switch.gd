class_name PorchSwitch
extends Node3D
## The porch light switch: the two-way plate on the front wall just inside
## the front door (STORY.md, choice 1). The rocker nearer the door is the
## porch light's; the other is the hall's. StoryPeople keeps whether it's on.
##
## The house model has this plate as set dressing (Dress_Switch_Front); this
## hides it and stands in for it with one whose porch rocker tips. It sits on
## the hinge side, so with the front door open the door covers it: shut the
## door to reach it.
##
## Placed by StoryPeople, as a child of the HomeBase, in the house's frame.

## House frame (x across, y back, z up): the middle of the plate, on the
## inside face of the front wall (build_shenton.py's Dress_Switch_Front).
const AT := Vector3(0.25, 0.0, 1.3)
## The porch rocker, across from the plate's middle (towards the door).
const ROCKER_X := 0.025

const PLATE := Color("#efece4")
const ROCKER := Color("#f7f5ef")

var people: StoryPeople
var _rocker: MeshInstance3D
var _click: AudioStreamPlayer3D


func _ready() -> void:
	name = "PorchSwitch"
	add_to_group(&"interactables")
	# Facing into the house (house +y is local -z), so no turn needed.
	position = House1979.at(AT)
	var home := get_parent()
	if home:
		for n in home.find_children("Dress_Switch_Front*", "Node3D", true, false):
			(n as Node3D).visible = false
	_box(Vector3(0.115, 0.116, 0.008), Vector3(0.0, 0.0, -0.004), PLATE)
	_box(Vector3(0.018, 0.032, 0.005), Vector3(-ROCKER_X, 0.0, -0.0105), ROCKER)
	_rocker = _box(Vector3(0.018, 0.032, 0.005), Vector3(ROCKER_X, 0.0, -0.0105), ROCKER)
	# Lit like the rest of the house's insides, as the plate it stands in for was.
	if home and home.has_method(&"_mark_indoor"):
		home.call(&"_mark_indoor", self)
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
	return to_global(Vector3(ROCKER_X, 0.0, -0.013))


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
