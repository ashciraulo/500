class_name BarnFind
extends Node3D
## A classic 500 rotting where a rumour said it would be. It only shows up
## once you've heard the rumour (see the Classics autoload), and some only at
## certain hours. Pull up next to it and stop to claim it: it goes to your
## garage as a restoration project.
##
## Until the classic models exist this uses the Pop's model in rust, sat low
## on flat tyres with a tarp over the back.

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
	var model := MODEL.instantiate() as Node3D
	model.position.y = 0.32
	model.rotation = Vector3(0.03, 0.0, -0.04)
	_visual.add_child(model)
	var materials := PS1Model.apply(model)
	var paint := materials.get("Paint") as ShaderMaterial
	if paint:
		paint.set_shader_parameter("albedo_color", Classics.paint_for(car_id))
	var tarp := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.75, 0.9, 2.0)
	tarp.mesh = box
	tarp.position = Vector3(0.0, 0.95, 0.9)
	tarp.rotation.x = -0.12
	tarp.material_override = PS1Material.make(Color(0.32, 0.36, 0.3))
	_visual.add_child(tarp)
	_refresh()


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
