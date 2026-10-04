class_name BarnFind
extends Node3D
## A classic 500 rotting where a rumour said it would be. It only shows up
## once you've heard the rumour (see the Classics autoload), and some only at
## certain hours. Pull up next to it and stop to claim it: it goes to your
## garage as a restoration project.
##
## Shows the classic's own model (cars.json "model") in faded paint, sat low
## on flat tyres. Cars without a model use the Pop's, under a tarp.

const FIND_RADIUS := 7.0
const FIND_SPEED_KMH := 4.0
const MODEL := preload("res://art/models/cars/pop/pop.glb")

@export var car_id := ""
## Only there between these hours (e.g. [0, 4]); empty means always.
@export var hours: Array = []

var _visual: Node3D
var _car: Node3D
var _check := 0.0


func _ready() -> void:
	add_to_group(&"barn_finds")
	_visual = Node3D.new()
	add_child(_visual)
	var model_id := String(CarCatalogue.get_car(car_id).get("model", "pop"))
	var path := "res://art/models/cars/%s/%s.glb" % [model_id, model_id]
	var model := ((load(path) if ResourceLoader.exists(path) else MODEL) as PackedScene).instantiate() as Node3D
	# Classic bodies sit on the ground at their origin; the Pop's is lifted.
	var has_hubs := model.find_child("Hub_FL", true, false) != null
	model.position.y = -0.06 if has_hubs else 0.32
	model.rotation = Vector3(0.03, 0.0, -0.04)
	_visual.add_child(model)
	var materials := PS1Model.apply(model)
	var paint := materials.get("Paint") as ShaderMaterial
	if paint:
		paint.set_shader_parameter("albedo_color", Classics.paint_for(car_id))
	if has_hubs:
		_add_flat_wheels(model)
	if not has_hubs:
		_add_tarp(model)
	_refresh()


## The old stand-in (the Pop's body) gets a tarp over the back to hide it a bit.
func _add_tarp(model: Node3D) -> void:
	var tarp := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.75, 0.9, 2.0)
	tarp.mesh = box
	tarp.position = Vector3(0.0, 0.95, 0.9)
	tarp.rotation.x = -0.12
	tarp.material_override = PS1Material.make(Color(0.32, 0.36, 0.3))
	_visual.add_child(tarp)


## The model's own wheel style at each Hub_ empty, a little sunk (flat tyres).
func _add_flat_wheels(model: Node3D) -> void:
	var style := "classic12"
	for node in model.get_children():
		if String(node.name).begins_with("WheelStyle_"):
			style = String(node.name).trim_prefix("WheelStyle_")
	for hub_name in ["Hub_FL", "Hub_FR", "Hub_RL", "Hub_RR"]:
		var hub := model.find_child(hub_name, true, false) as Node3D
		var side := "l" if hub_name.ends_with("L") else "r"
		var path := CarController.PART_MODEL_PATH % ("wheel_%s_%s" % [style, side])
		if hub == null or not ResourceLoader.exists(path):
			continue
		var wheel := (load(path) as PackedScene).instantiate() as Node3D
		wheel.position = hub.position + Vector3(0.0, -0.05, 0.0)
		wheel.scale = Vector3(1.0, 0.9, 1.0)
		model.add_child(wheel)
		PS1Model.apply(wheel)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.4
	_refresh()
	if not _visual.visible:
		return
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as Node3D
		return
	var car := _car as CarController
	if car and car.global_position.distance_to(global_position) < FIND_RADIUS and car.speed_kmh() < FIND_SPEED_KMH:
		Classics.find_wreck(car_id)
		_refresh()


func is_present() -> bool:
	if not Classics.has_rumour(car_id) or Classics.is_found(car_id):
		return false
	if hours.size() == 2:
		var h := GameClock.time_of_day
		var from := float(hours[0])
		var to := float(hours[1])
		return h >= from and h < to if from <= to else (h >= from or h < to)
	return true


func _refresh() -> void:
	_visual.visible = is_present()
