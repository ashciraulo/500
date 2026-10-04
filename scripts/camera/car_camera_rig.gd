class_name CarCameraRig
extends Node3D
## Follows a car with a lazy chase camera or sits in the driver's seat.
##
## Chase: swings round behind the car with a little lag, pulls back and widens
## the FOV with speed, and won't clip through walls. Interior: sits at the
## car's `DriverSeat` marker, leans gently with g-forces and lets the player
## look around with the mouse (when captured) or the right stick.

enum Mode { CHASE, INTERIOR }

@export var car_path: NodePath
@export var mode := Mode.CHASE

@export_group("Chase")
@export var chase_distance := 4.3
@export var chase_height := 1.55
@export var look_height := 0.75
@export var look_ahead := 1.5
## How fast the camera swings round behind the car.
@export var yaw_follow := 6.0
@export var position_follow := 9.0
@export var fov_slow := 68.0
@export var fov_fast := 80.0

@export_group("Interior")
@export var interior_fov := 72.0
@export var stick_look_speed := 2.2

var _car: CarController
var _camera: Camera3D
var _yaw := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _look_idle := 0.0
var _lean := Vector3.ZERO
var _last_car_velocity := Vector3.ZERO
var _ray_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	top_level = true
	_car = get_node_or_null(car_path) as CarController
	_camera = get_node("Camera3D")
	_camera.current = true
	if _car:
		_yaw = _car.global_rotation.y
		_ray_query.exclude = [_car.get_rid()]
		_car.is_player_inside = mode == Mode.INTERIOR
		global_position = _car.global_position


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw -= event.relative.x * Settings.mouse_sensitivity
		_look_pitch -= event.relative.y * Settings.mouse_sensitivity
		_look_idle = 0.0


func toggle_mode() -> void:
	mode = Mode.INTERIOR if mode == Mode.CHASE else Mode.CHASE
	if _car:
		_car.is_player_inside = mode == Mode.INTERIOR
	_look_yaw = 0.0
	_look_pitch = 0.0


func _process(delta: float) -> void:
	if not _car:
		return
	if Input.is_action_just_pressed("camera_toggle"):
		toggle_mode()

	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.1:
		_look_yaw -= stick.x * stick_look_speed * delta
		_look_pitch -= stick.y * stick_look_speed * delta
		_look_idle = 0.0
	else:
		_look_idle += delta

	if mode == Mode.CHASE:
		_update_chase(delta)
	else:
		_update_interior(delta)


func _update_chase(delta: float) -> void:
	# Free-look in chase drifts back to centre once the player lets go.
	if _look_idle > 1.5:
		_look_yaw = lerp_angle(_look_yaw, 0.0, 1.0 - exp(-3.0 * delta))
		_look_pitch = lerpf(_look_pitch, 0.0, 1.0 - exp(-3.0 * delta))
	_look_pitch = clampf(_look_pitch, -0.5, 0.6)

	var car_pos := _car.global_position
	var car_yaw := _car.global_rotation.y
	_yaw = lerp_angle(_yaw, car_yaw, 1.0 - exp(-yaw_follow * delta))

	var speed := _car.linear_velocity.length()
	var speed_t := clampf(speed / 33.0, 0.0, 1.0)
	var distance := chase_distance + speed_t * 1.0
	var orbit := Basis(Vector3.UP, _yaw + _look_yaw) * Basis(Vector3.RIGHT, -_look_pitch)
	# Under a low roof (carport, car park), drop the camera and pull it in so
	# it stays below the ceiling instead of filming the roof.
	var height := chase_height
	_ray_query.from = car_pos + Vector3.UP * 0.9
	_ray_query.to = car_pos + Vector3.UP * (chase_height + 0.8)
	var ceiling := get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if not ceiling.is_empty():
		height = clampf(ceiling.position.y - car_pos.y - 0.45, look_height, chase_height)
		distance *= lerpf(0.75, 1.0, (height - look_height) / maxf(chase_height - look_height, 0.01))
	var desired := car_pos + orbit * Vector3(0.0, height, distance)
	var target := car_pos + Vector3.UP * look_height + (-_car.global_basis.z) * look_ahead

	# Keep the camera out of walls.
	_ray_query.from = target
	_ray_query.to = desired
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if not hit.is_empty():
		desired = hit.position + (target - desired).normalized() * 0.3

	global_position = global_position.lerp(desired, 1.0 - exp(-position_follow * delta))
	if global_position.distance_to(desired) > 25.0:
		global_position = desired  # Teleports/resets: don't swoop.
	_camera.global_position = global_position
	if not global_position.is_equal_approx(target):
		_camera.look_at(target, Vector3.UP)
	_camera.fov = lerpf(_camera.fov, lerpf(fov_slow, fov_fast, speed_t), 1.0 - exp(-2.0 * delta))


func _update_interior(delta: float) -> void:
	var seat := _car.get_node_or_null("DriverSeat") as Node3D
	if not seat:
		return
	if _look_idle > 2.5 and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_look_yaw = lerp_angle(_look_yaw, 0.0, 1.0 - exp(-2.0 * delta))
		_look_pitch = lerpf(_look_pitch, 0.0, 1.0 - exp(-2.0 * delta))
	_look_yaw = clampf(_look_yaw, -2.2, 2.2)
	_look_pitch = clampf(_look_pitch, -0.9, 0.7)

	# Head leans against acceleration: back when pulling away, sideways in corners.
	var accel := (_car.linear_velocity - _last_car_velocity) / maxf(delta, 0.0001)
	_last_car_velocity = _car.linear_velocity
	var local_accel := seat.global_basis.inverse() * accel
	var lean_target := Vector3(-local_accel.x, 0.0, -local_accel.z) * 0.006
	lean_target = lean_target.limit_length(0.08)
	_lean = _lean.lerp(lean_target, 1.0 - exp(-6.0 * delta))

	var seat_basis := seat.global_basis.orthonormalized()
	global_position = seat.global_position + seat_basis * _lean
	_camera.global_transform = Transform3D(
		seat_basis * Basis(Vector3.UP, _look_yaw) * Basis(Vector3.RIGHT, _look_pitch),
		global_position)
	_camera.fov = interior_fov
