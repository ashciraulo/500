class_name ShedTable
extends Node3D
## M.'s table in the shed, to use on the night of 11 July (Finale, choice 4):
## look at the microphone, the deck or the transmitter and press interact.
## The rest of the time each has a line of its own.
##
## A child of the shed's ShedReveal, in its frame (x along the table, y up,
## the wall toward +z).

## Where each thing is on the table (art/models/scripts/lib/shed_reveal.py).
const THINGS := {
	&"mic": Vector3(-0.01, 0.86, -0.1),
	&"deck": Vector3(-0.24, 0.84, 0.02),
	&"tx": Vector3(0.27, 0.9, 0.06),
}

var finale: Finale


func _ready() -> void:
	name = "ShedTable"
	add_to_group(&"interactables")


func interact_point() -> Vector3:
	return to_global(Vector3(0.0, 0.86, -0.12))


## The thing on the table you're looking most nearly at.
func looked_at() -> StringName:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return &"tx"
	var look := -cam.global_basis.z
	var best := &"tx"
	var best_dot := -2.0
	for id: StringName in THINGS:
		var dot := look.dot((to_global(THINGS[id]) - cam.global_position).normalized())
		if dot > best_dot:
			best_dot = dot
			best = id
	return best


func interact_hint() -> String:
	return finale.table_hint(looked_at()) if finale else ""


func interact() -> void:
	if finale:
		finale.use_table(looked_at())
