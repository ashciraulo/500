class_name CarCameraRig
extends Node3D
## Follows a car with a lazy chase camera or sits in the driver's seat.
##
## Chase: swings round behind the car with a little lag, pulls back, rises and
## widens the FOV with speed, and won't clip through walls or into the ground.
## Free-look orbits the car and keeps it in the middle of the view. Interior:
## sits at the car's `DriverSeat` marker, leans gently with g-forces and lets
## the player look around with the mouse (when captured) or the right stick.
## Holding `look_behind` looks back down the road in either view.

enum Mode { CHASE, INTERIOR }

@export var car_path: NodePath
@export var mode := Mode.CHASE

@export_group("Chase")
# Low and nearly level, aimed well up the road past the car, so you see
# where you're going rather than the roof.
@export var chase_distance := 4.6
@export var chase_height := 1.3
@export var look_height := 1.0
@export var look_ahead := 5.0
## How fast the camera swings round behind the car.
@export var yaw_follow := 6.0
@export var position_follow := 9.0
@export var fov_slow := 68.0
@export var fov_fast := 80.0
## At full speed (~120 km/h) the camera sits this much higher and aims this
## much further up the road, so the car doesn't hide what's coming.
@export var speed_rise := 0.45
@export var speed_look_ahead := 7.0

@export_group("Interior")
## Narrower than a chase lens, so the windscreen fills more of the view.
@export var interior_fov := 58.0
## From the DriverSeat marker to the driver's eyes: up near the headlining
## and forward toward the glass, tipped down a touch, so the road shows over
## the dash. Lower roofs (the classics) bring it down to fit; see `_headroom_above`.
@export var eye_offset := Vector3(0.0, 0.15, -0.15)
@export var eye_pitch_deg := -3.5
## Space kept between the eye and the roof lining above it.
const HEAD_CLEARANCE := 0.06
@export var stick_look_speed := 2.2
## Looking back from inside: the eye moves back along the middle of the car,
## as if turned round between the seats, so the back window fills the view
## instead of the driver's own headrest.
@export var rear_glass_inset := 1.0

var _car: CarController
var _camera: Camera3D
var _yaw := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _look_idle := 0.0
var _lean := Vector3.ZERO
var _last_car_velocity := Vector3.ZERO
var _ray_query := PhysicsRayQueryParameters3D.new()
var _headroom_body: Node = null
var _headroom := INF
## Where the chase camera sits relative to the car. Smoothed in the car's
## frame rather than the world's, so it doesn't trail metres behind at speed.
var _offset := Vector3.ZERO
var _has_offset := false
var _behind := false


func _ready() -> void:
	_ray_query.collision_mask = ~MapTileLoader.LAYER_WATER  # the water surface isn't a wall
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
	_has_offset = false


## True while the player holds look-behind.
func is_looking_behind() -> bool:
	return _behind


func _process(delta: float) -> void:
	if not _car:
		return
	if Input.is_action_just_pressed("camera_toggle"):
		toggle_mode()
	var behind := Input.is_action_pressed("look_behind") and not get_tree().paused
	if behind != _behind:
		_behind = behind
		_has_offset = false  # cut straight round, then straight back

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
	# Positive pitch looks up, as on foot: the camera swings down behind the car.
	_look_pitch = clampf(_look_pitch, -0.6, 0.3)

	var car_pos := _car.global_position
	var car_yaw := _car.global_rotation.y
	_yaw = lerp_angle(_yaw, car_yaw, 1.0 - exp(-yaw_follow * delta))

	var speed := _car.linear_velocity.length()
	var speed_t := clampf(speed / 33.0, 0.0, 1.0)
	# Smaller cars (the classics) get the camera lower and closer.
	var fit := clampf(_car.body_size.y / CarController.POP_SIZE.y, 0.75, 1.2)
	var distance := chase_distance * sqrt(fit) + speed_t * 1.0
	var yaw := _yaw + _look_yaw
	var pitch := _look_pitch
	if _behind:
		# From in front of the car, looking back over it down the road.
		yaw = car_yaw + PI
		pitch = 0.0
	var turn := Basis(Vector3.UP, yaw)
	var orbit := turn * Basis(Vector3.RIGHT, pitch)
	# Under a low roof (carport, car park), drop the camera and pull it in so
	# it stays below the ceiling instead of filming the roof.
	var height := chase_height * fit + speed_t * speed_rise
	_ray_query.from = car_pos + Vector3.UP * 0.9
	_ray_query.to = car_pos + Vector3.UP * (height + 0.8)
	var ceiling := get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if not ceiling.is_empty():
		height = clampf(ceiling.position.y - car_pos.y - 0.45, look_height, height)
	var desired := car_pos + orbit * Vector3(0.0, height, distance)
	# Aim up the road the camera is looking along, through the car, so turning
	# the view orbits the car instead of swinging it off the side of the screen.
	var ahead := look_ahead + speed_t * speed_look_ahead
	var target := car_pos + Vector3.UP * look_height + turn * Vector3(0.0, 0.0, -ahead)

	# On a steep slope the road behind can be higher than the car: lift the
	# camera clear of it rather than letting the wall check pull it in low.
	# (Starts under the low-roof margin above, so it never lands on a roof.)
	_ray_query.from = desired + Vector3.UP * 0.3
	_ray_query.to = desired - Vector3.UP * 1.0
	var ground := get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if not ground.is_empty():
		desired.y = maxf(desired.y, ground.position.y + 0.9)

	# Keep the camera out of walls: check from above the car's roof, so the
	# road itself never counts as a wall.
	var pivot := car_pos + Vector3.UP * minf(height, look_height + 0.5)
	_ray_query.from = pivot
	_ray_query.to = desired
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if not hit.is_empty():
		desired = hit.position + (pivot - desired).normalized() * 0.3

	# Smooth in the car's frame: speed doesn't leave the camera behind.
	var offset := desired - car_pos
	if not _has_offset or _offset.distance_to(offset) > 25.0:
		_offset = offset  # Teleports, resets and looking back: don't swoop.
		_has_offset = true
	else:
		_offset = _offset.lerp(offset, 1.0 - exp(-position_follow * delta))
	global_position = car_pos + _offset
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
	var eye := eye_offset
	eye.y = minf(eye.y, _headroom_above(seat) - HEAD_CLEARANCE)
	global_position = seat.global_position + seat_basis * (eye + _lean)
	var look := Basis(Vector3.UP, _look_yaw) * Basis(Vector3.RIGHT, _look_pitch + deg_to_rad(eye_pitch_deg))
	var at := global_position
	if _behind:
		# Straight back through the rear glass, turned round between the seats.
		look = Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-4.0))
		var local := _car.to_local(global_position)
		at = _car.to_global(Vector3(0.0, local.y - 0.06, _car.body_size.z * 0.5 - rear_glass_inset))
	_camera.global_transform = Transform3D(seat_basis * look, at)
	_camera.fov = interior_fov


## How far above the seat marker the car's lowest roof surface is, over the
## eye: the classics are a good 10 cm lower inside than the Pop. Measured
## once from the body's meshes whenever the body changes.
func _headroom_above(seat: Node3D) -> float:
	var body := _car.get_node_or_null(^"Body")
	if body == _headroom_body:
		return _headroom
	_headroom_body = body
	_headroom = INF
	if body == null:
		return _headroom
	var to_seat := seat.global_transform.affine_inverse()
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		# Hidden ones too: a folded soft top still comes back over your head.
		if mi.mesh == null:
			continue
		var xf := to_seat * mi.global_transform
		for si in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var p := xf * v
				# Straight over the head, from the eye back to the headrest.
				if absf(p.x) < 0.15 and p.z > eye_offset.z - 0.1 and p.z < 0.15 and p.y > 0.05:
					_headroom = minf(_headroom, p.y)
	return _headroom
