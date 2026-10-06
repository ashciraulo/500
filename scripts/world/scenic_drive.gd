class_name ScenicDrive
extends Node3D
## A signposted scenic drive: Kings Park at sunset, Riverside Drive, the
## South Perth foreshore. Drive past the sign at the start and soft markers
## lead you along the route. No timer, no score, just a note at the end.
## Not offered while you're on a job.

const POINT_RADIUS := 18.0

@export var drive_id := ""
@export var title := ""
## World positions along the route, start first.
@export var points: PackedVector3Array = []

var _car: CarController
var _next := -1
var _beacon: Beacon
var _sign: Label3D
var _cooldown := 0.0


func _ready() -> void:
	add_to_group(&"scenic_drives")
	add_to_group(&"challenges")
	if points.is_empty():
		return
	global_position = points[0]
	_sign = Label3D.new()
	_sign.text = "SCENIC DRIVE\n" + title
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.pixel_size = 0.01
	_sign.font_size = 36
	_sign.outline_size = 8
	_sign.modulate = Color(0.55, 0.85, 0.6)
	_sign.position = Vector3(0, 3.2, 0)
	add_child(_sign)


func is_running() -> bool:
	return _next >= 0


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if points.size() < 2:
		return
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
		return
	if _next < 0:
		if _cooldown <= 0.0 and Jobs.active.is_empty() and _near(points[0]):
			start()
		return
	if not Jobs.active.is_empty():
		stop()
		return
	if _near(points[_next]):
		_next += 1
		if _next >= points.size():
			stop()
			_cooldown = 120.0
			Activities.finish_scenic(drive_id, title)
		else:
			_move_beacon()


func start() -> void:
	_next = 1
	_move_beacon()


## For the challenge card (top right) while the drive runs.
func challenge_card() -> Dictionary:
	if _next < 0:
		return {}
	return {"tag": "Scenic drive", "icon": "flag", "title": title,
		"line": "Follow the green markers. No rush.",
		"detail": "Marker %d of %d" % [_next, points.size() - 1]}


func stop() -> void:
	_next = -1
	if _beacon:
		_beacon.queue_free()
		_beacon = null


func _move_beacon() -> void:
	if _beacon == null:
		_beacon = Beacon.new()
		_beacon.color = Color(0.5, 0.95, 0.6)
		_beacon.radius = POINT_RADIUS * 0.5
		get_parent().add_child(_beacon)
	_beacon.global_position = points[_next]


func _near(point: Vector3) -> bool:
	return _car.global_position.distance_to(point) < POINT_RADIUS
