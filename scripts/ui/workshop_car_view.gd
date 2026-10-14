class_name WorkshopCarView
extends Node
## The workshop's look at your car: while the Parts, Tuning or Paint tab is
## up, a camera of its own frames the real car in the space beside the panel,
## so fitted parts and a fresh coat show the moment they go on. Browsing a
## part swings round to where it goes (wheels low at the side, an exhaust
## from behind, a gear knob through the window). Drag or use the right stick
## to look around; the wheel zooms.
##
## The camera keeps clear of walls (the carport is tight): it picks the side
## of the car with room and pulls in when something is in the way, and stays
## under the roof when the car is parked under one (the "rain_shelters"
## boxes, as the rain uses; the carport roof has no collision).

## [yaw from straight ahead (deg, + toward the car's right), pitch (deg),
## distance (x the whole-car distance), focus (fraction of the body box,
## -1..1 across x, y, z; -z is the front)].
const VIEWS := {
	&"car": [38.0, 12.0, 1.0, Vector3(0, 0, 0)],
	&"wheels": [72.0, 5.0, 0.75, Vector3(0.8, -0.6, -0.55)],
	&"brakes": [80.0, 4.0, 0.6, Vector3(0.8, -0.6, -0.55)],
	&"under": [66.0, 5.0, 0.8, Vector3(0.4, -0.5, 0.0)],
	&"front": [16.0, 9.0, 0.78, Vector3(0, -0.15, -0.8)],
	&"rear": [150.0, 11.0, 0.8, Vector3(0, -0.15, 0.8)],
	&"plate": [168.0, 6.0, 0.6, Vector3(0, -0.35, 0.9)],
	&"roof": [42.0, 36.0, 0.95, Vector3(0, 0.6, 0)],
	&"cabin": [78.0, 22.0, 0.5, Vector3(0.1, 0.25, -0.1)],
}
const SLOT_VIEWS := {
	&"wheels": &"wheels", &"tyres": &"wheels", &"brakes": &"brakes",
	&"suspension": &"wheels", &"anti_roll": &"under",
	&"lights": &"front", &"bumpers": &"front",
	&"exhaust": &"rear", &"towbar": &"rear", &"mudflaps": &"rear", &"rear_rack": &"rear",
	&"plate": &"plate", &"roof": &"roof",
	&"steering_wheel": &"cabin", &"gear_knob": &"cabin", &"seat_covers": &"cabin",
}
const EASE := 5.0
const MIN_PITCH := -2.0
const MAX_PITCH := 60.0
## Closest the camera comes to the car when a wall pushes it in (m).
const MIN_DISTANCE := 1.4

var _car: CarController
var _camera: Camera3D
var _lamp: OmniLight3D
var _previous: Camera3D
## Where on screen the car sits: a rect in the same space as `_screen`.
var _rect := Rect2(0, 0, 1, 1)
var _screen := Vector2(1, 1)
var _box := AABB(Vector3(-0.8, 0, -1.8), Vector3(1.6, 1.5, 3.6))
## Wanted and current view: yaw, pitch, distance scale, focus.
var _want := {"yaw": 38.0, "pitch": 12.0, "dist": 1.0, "focus": Vector3.ZERO}
var _now := {}
## 1 shows the car's right side, -1 its left; picked by where there's room.
var _side := 1.0
var _zoom := 1.0
## Highest the camera may go (world y): under the roof the car's parked under.
var _ceiling := INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_active() -> bool:
	return _camera != null


## Take over the view, framing `car` inside `rect` of a `screen`-sized canvas.
func start(car: CarController, rect: Rect2, screen: Vector2) -> void:
	if car == null or not car.is_inside_tree():
		return
	if _camera != null and _car == car:
		set_rect(rect, screen)
		return
	var viewport_camera := car.get_viewport().get_camera_3d()
	if _camera == null:
		_previous = viewport_camera
		_camera = Camera3D.new()
		_camera.name = "WorkshopCamera"
		_camera.fov = 50.0
		_camera.far = viewport_camera.far if viewport_camera else 4000.0
		# A soft work lamp so the car reads at night under the carport.
		_lamp = OmniLight3D.new()
		_lamp.light_energy = 0.5
		_lamp.omni_range = 7.0
		_lamp.light_color = Color(1.0, 0.92, 0.8)
		_lamp.shadow_enabled = false
		_camera.add_child(_lamp)
	if _camera.get_parent() != car.get_parent():
		if _camera.get_parent():
			_camera.get_parent().remove_child(_camera)
		car.get_parent().add_child(_camera)
	_car = car
	_rect = rect
	_screen = screen
	refresh_bounds()
	_ceiling = _roof_over(car.global_position)
	focus(&"car")
	_now = _want.duplicate()
	_place()
	_camera.current = true


## Hand the view back to the camera that had it.
func stop() -> void:
	if _camera == null:
		return
	if is_instance_valid(_previous) and _previous.is_inside_tree():
		_previous.current = true
	_camera.queue_free()
	_camera = null
	_lamp = null
	_car = null


## Move the car to a new spot on screen (the panel moved).
func set_rect(rect: Rect2, screen: Vector2) -> void:
	_rect = rect
	_screen = screen


## Re-measure the car (a roof rack makes it taller).
func refresh_bounds() -> void:
	if _car == null:
		return
	var box := _car.body_bounds()
	if box.size.length() > 0.5:
		_box = box


## Swing round to the part of the car `slot` changes (a parts slot, or
## &"car" for the whole car).
func focus(slot: StringName) -> void:
	var view: Array = VIEWS[SLOT_VIEWS.get(slot, &"car") if not VIEWS.has(slot) else slot]
	_zoom = 1.0
	_want = _roomiest(view)


## `view` as a wanted view, on whichever side of the car (and, if a wall
## is in the way, from however high up) leaves the camera the most room.
## Stays on the side it's on unless the other is clearly better.
func _roomiest(view: Array) -> Dictionary:
	var best := {}
	var best_room := -1.0
	var keep := _side
	for side: float in [keep, -keep]:
		for lift: float in [0.0, 15.0, 30.0]:
			_side = side
			var pitch := minf(float(view[1]) + lift, MAX_PITCH)
			var want := _fit_distance(_half_tans()) * float(view[2])
			# Share of the wanted distance the camera gets; a little bonus for
			# staying put and for not climbing.
			var room := _room(view[3], view[0], pitch, want) / want
			room += (0.08 if side == keep else 0.0) - lift * 0.002
			if room > best_room + 0.001:
				best_room = room
				best = {"yaw": view[0], "pitch": pitch, "dist": view[2], "focus": view[3], "side": side}
		if best_room >= 1.0:
			break  # all the room it wants without changing sides
	if best.side != keep and _camera != null and not _now.is_empty():
		# Mirror the current view too, so the swing goes round the near way.
		_now.yaw = -float(_now.yaw)
		_now.focus = (_now.focus as Vector3) * Vector3(-1, 1, 1)
	_side = best.side
	best.erase("side")
	return best


## How far the camera could get from the focus for a view before a wall.
func _room(f: Vector3, yaw: float, pitch: float, want: float) -> float:
	var focus_point := _focus_world(f)
	var dir := _direction(yaw, pitch)
	return _clear_distance(focus_point, dir, _shift(dir, _half_tans()), want)


## The sideways offset (per metre out) that puts the focus in the middle of
## the free rect rather than the middle of the screen.
func _shift(dir: Vector3, tans: Vector2) -> Vector3:
	var centre := _rect.get_center() / _screen
	var ndc := Vector2(centre.x * 2.0 - 1.0, 1.0 - centre.y * 2.0)
	var basis := Basis.looking_at(-dir, Vector3.UP)
	return basis.x * ndc.x * tans.x + basis.y * ndc.y * tans.y


## Look around by hand (degrees).
func orbit(yaw: float, pitch: float) -> void:
	_want.yaw = wrapf(_want.yaw + yaw * _side, -180.0, 180.0)
	_want.pitch = clampf(_want.pitch + pitch, MIN_PITCH, MAX_PITCH)


func zoom(factor: float) -> void:
	_zoom = clampf(_zoom * factor, 0.45, 1.6)


func _process(delta: float) -> void:
	if _camera == null:
		return
	if not is_instance_valid(_car) or not _car.is_inside_tree():
		stop()
		return
	var look := Input.get_vector("look_left", "look_right", "look_down", "look_up")
	if look.length() > 0.1:
		orbit(-look.x * 90.0 * delta, -look.y * 60.0 * delta)
	var t := 1.0 - exp(-EASE * delta)
	_now.yaw = lerp_angle(deg_to_rad(_now.yaw), deg_to_rad(_want.yaw), t) * 180.0 / PI
	_now.pitch = lerpf(_now.pitch, _want.pitch, t)
	_now.dist = lerpf(_now.dist, _want.dist * _zoom, t)
	_now.focus = (_now.focus as Vector3).lerp(_want.focus, t)
	_place()


## Put the camera where the current view says, kept out of walls.
func _place() -> void:
	var focus_point := _focus_world(_now.focus)
	var dir := _direction(_now.yaw, _now.pitch)
	var tans := _half_tans()
	var dist := _fit_distance(tans) * float(_now.dist)
	var shift := _shift(dir, tans)
	dist = minf(dist, _clear_distance(focus_point, dir, shift, dist))
	_camera.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), focus_point + dir * dist - shift * dist)


## How far the camera has to be for the whole car to fill the rect.
func _fit_distance(tans: Vector2) -> float:
	# Most of the bounding sphere: a car seen from any angle is never as
	# big as the sphere round its corners.
	var radius := _box.size.length() * 0.5 * 0.85
	var fit := minf(tans.x * _rect.size.x / _screen.x, tans.y * _rect.size.y / _screen.y)
	return radius / maxf(fit, 0.05) * 1.02


## tan of half the field of view across and up the whole screen.
func _half_tans() -> Vector2:
	var v := tan(deg_to_rad(_camera.fov) * 0.5)
	return Vector2(v * _screen.x / maxf(_screen.y, 1.0), v)


## The world point a view focuses on (fractions of the body box, mirrored to
## the side being shown).
func _focus_world(f: Vector3) -> Vector3:
	var half := _box.size * 0.5
	var local := _box.get_center() + Vector3(f.x * _side * half.x, f.y * half.y, f.z * half.z)
	return _car.global_transform * local


## Unit vector from the focus out to the camera, level with the world.
func _direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	var forward := -_car.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var flat := forward.rotated(Vector3.UP, -deg_to_rad(yaw_deg) * _side)
	var side := flat.cross(Vector3.UP).normalized()
	return flat.rotated(side, deg_to_rad(pitch_deg)).normalized()


## World height a little under the lowest roof over `point`, or INF.
func _roof_over(point: Vector3) -> float:
	var top := INF
	for node in _car.get_tree().get_nodes_in_group(&"rain_shelters"):
		if not node.has_method("rain_shelters"):
			continue
		for box: Transform3D in node.rain_shelters():
			var local := box.affine_inverse() * point
			if absf(local.x) <= 1.0 and absf(local.z) <= 1.0 and absf(local.y) <= 1.0:
				top = minf(top, (box * Vector3(0, 1, 0)).y - 0.35)
	return top


## The furthest the camera can sit along `dir` before a wall (three rays:
## straight out and a little to either side, so a doorway can't fool it).
func _clear_distance(focus_point: Vector3, dir: Vector3, shift: Vector3, dist: float) -> float:
	var space := _car.get_world_3d().direct_space_state
	if space == null:
		return dist
	var best := dist
	var rise := (dir - shift).y
	if rise > 0.01 and _ceiling < INF:
		best = minf(best, (_ceiling - focus_point.y) / rise)
	var across := dir.cross(Vector3.UP).normalized() * 0.45
	for offset: Vector3 in [Vector3.ZERO, across, -across]:
		var to := focus_point + (dir - shift) * (dist + 0.3) + offset
		var query := PhysicsRayQueryParameters3D.create(focus_point, to)
		query.exclude = [_car.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var along: float = (hit.position - focus_point).length() / (dir - shift).length()
			best = minf(best, along - 0.3)
	return maxf(best, MIN_DISTANCE)

