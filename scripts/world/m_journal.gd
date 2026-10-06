class_name MJournal
extends Node3D
## M.'s 1979 field journal, closed, in green cloth. It turns up on the boxes in
## the cupboard under the stairs with the first thing the midnight station
## leaves you, and you can open it there. Its pages have been torn out: those
## are M.'s pages the field journal finds out in the world.
##
## The model is art/models/home/mystery/m_journal.glb; its `Cover` is hinged on
## the spine and opens by turning rotation.z to +178 degrees.

const MODEL := "res://art/models/home/mystery/m_journal.glb"
const OPEN_ANGLE := 178.0

var is_open := false
var _cover: Node3D
var _tween: Tween


func _ready() -> void:
	name = "MJournal"
	if ResourceLoader.exists(MODEL):
		var model := (load(MODEL) as PackedScene).instantiate() as Node3D
		PS1Model.apply(model)
		add_child(model)
		_cover = model.find_child("Cover", true, false) as Node3D
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.155, 0.022, 0.215)
		mesh.mesh = box
		mesh.position.y = 0.011
		mesh.material_override = PS1Material.make(Color(0.2, 0.32, 0.24))
		add_child(mesh)
	add_to_group(&"interactables")


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.05


func interact_hint() -> String:
	return "Close M.'s journal" if is_open else "Open M.'s journal"


func interact() -> void:
	set_open(not is_open)
	if is_open and Discoveries.discover("mystery/m_journal"):
		Activities.say("A field journal, 1979. Inside the cover, in pencil: M.")
		Activities.say("Most of the pages have been torn out.")


func set_open(open: bool, animate := true) -> void:
	is_open = open
	if _cover == null:
		return
	var angle := deg_to_rad(OPEN_ANGLE) if open else 0.0
	if _tween:
		_tween.kill()
	if not animate or not is_inside_tree():
		_cover.rotation.z = angle
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_cover, "rotation:z", angle, 0.8)
