class_name OnFoot
extends CharacterBody3D
## The player out of the car: first person, walking pace.
##
## Starts in the car. Press interact (F / A) with the car stopped to get out
## on the driver's side; walk around the townhouse, open doors, try the shed,
## go to bed; walk back to the car and press interact to get in again.
##
## Moves with the driving actions (accelerate/brake = forward/back,
## steer = strafe, handbrake = hurry), looks with the mouse or the right
## stick. Climbs stairs by stepping up small ledges.

signal got_out
signal got_in

@export var car_path: NodePath
@export var camera_rig_path: NodePath

@export var walk_speed := 1.7
@export var hurry_speed := 3.3
@export var eye_height := 1.62
@export var step_height := 0.32
@export var reach := 1.9
@export var stick_look_speed := 2.4
## Metres per head-bob cycle (matches FootstepAudio.stride_walk).
@export var stride := 0.7

const RADIUS := 0.24
const HEIGHT := 1.7
const GRAVITY := 9.8
## Layers the player bumps into: world (1) and buildings, doors (2).
const MASK := 1 | 2
## How far from the driver's door you can be to get in.
const CAR_REACH := 2.2
## Seconds F has to be held in the car to get out.
const HOLD_TO_GET_OUT := 0.45
## Getting in: the door opens, you sit, it shuts, belt on, key in and turned,
## then the car is yours (seconds from pressing F).
const IN_SIT := 0.5
const IN_DOOR_SHUT := 1.0
const IN_BELT := 1.4
const IN_KEY := 1.75
const IN_DRIVE := 2.1
## Getting out: belt off and the engine off at once, then the key out, the
## door, you step out, and the door shuts behind you.
const OUT_KEY := 0.3
const OUT_DOOR := 0.55
const OUT_STEP := 1.0
const OUT_DOOR_SHUT := 1.5

var in_car := true
## Tells the audio hooks this plays the car's doors, belt and key itself.
var plays_car_sounds := true

var _car: CarController
var _rig: Node3D
var _camera: Camera3D
var _shape: CollisionShape3D
var _yaw := 0.0
var _pitch := 0.0
var _bob := 0.0
var _prompt: Label
var _ui: CanvasLayer
var _fade: ColorRect
var _note_timer := 0.0
var _hold := 0.0
var _hold_armed := true  # F was let go since getting in
var _busy := false
var _footsteps: FootstepAudio


func _ready() -> void:
	_car = get_node_or_null(car_path) as CarController
	_rig = get_node_or_null(camera_rig_path) as Node3D
	collision_layer = 8
	collision_mask = MASK
	floor_snap_length = step_height + 0.05
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.02

	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	_shape.shape = capsule
	_shape.position.y = HEIGHT / 2.0
	add_child(_shape)

	_camera = Camera3D.new()
	_camera.name = "Eyes"
	_camera.fov = 72.0
	_camera.near = 0.05
	_camera.far = 4000.0
	_camera.position.y = eye_height
	add_child(_camera)

	# Drawn in the window at its resolution, not inside the low-res lo-fi
	# viewport (where the prompt came out scaled up, blurry and over the HUD).
	var ui := CanvasLayer.new()
	ui.layer = 5
	_ui = ui
	get_tree().root.add_child.call_deferred(ui)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -160.0
	_prompt.offset_right = 160.0
	_prompt.offset_top = -96.0
	_prompt.offset_bottom = -72.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(_prompt)

	_footsteps = FootstepAudio.new()
	_footsteps.name = &"FootstepAudio"
	add_child(_footsteps)
	_set_body_active(false)
	_camera.current = false


func _input(event: InputEvent) -> void:
	if in_car or _busy:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var settings := get_node_or_null(^"/root/Settings")
		var sens: float = settings.mouse_sensitivity if settings else 0.003
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, -1.35, 1.35)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _busy or get_tree().paused:
		return
	if not in_car:
		interact()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(_ui):
		_ui.queue_free()


func _process(delta: float) -> void:
	# In the car, hold F to get out (a tap is left for workshops and servos).
	if not Input.is_action_pressed("interact"):
		_hold_armed = true
	if in_car and _hold_armed and not _busy and not get_tree().paused and Input.is_action_pressed("interact") \
			and _car and _car.player_controlled and _car.linear_velocity.length() < 1.2:
		_hold += delta
		if _hold >= HOLD_TO_GET_OUT:
			_hold = 0.0
			get_out()
	else:
		_hold = 0.0
	_note_timer = maxf(_note_timer - delta, 0.0)
	if _note_timer <= 0.0:
		_prompt.text = _hint()


func _physics_process(delta: float) -> void:
	if in_car or _busy:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.1:
		_yaw -= stick.x * stick_look_speed * delta
		_pitch = clampf(_pitch - stick.y * stick_look_speed * delta, -1.35, 1.35)
	rotation.y = _yaw
	_camera.rotation.x = _pitch

	var move := Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var speed := hurry_speed if Input.is_action_pressed("handbrake") else walk_speed
	var wish := global_basis * Vector3(move.x, 0.0, move.y) * speed
	velocity.x = move_toward(velocity.x, wish.x, delta * 14.0)
	velocity.z = move_toward(velocity.z, wish.z, delta * 14.0)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	var before := global_position
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	if is_on_floor() and horizontal.length() > 0.0005 and test_move(global_transform, horizontal):
		_step_up(horizontal)
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()

	# A gentle head bob, one dip per stride (FootstepAudio plays the steps).
	if is_on_floor() and moved > 0.0005:
		_bob += moved * TAU / stride
	else:
		_bob = lerpf(_bob, roundf(_bob / PI) * PI, 1.0 - exp(-8.0 * delta))
	_camera.position.y = eye_height + sin(_bob) * 0.022


## Lift over a stair tread or kerb: if there's floor a little ahead at most
## step_height up, raise the body onto it and let the slide carry on.
func _step_up(horizontal: Vector3) -> void:
	var up := Vector3.UP * step_height
	if test_move(global_transform, up):
		return
	var probe := horizontal.normalized() * maxf(horizontal.length(), RADIUS * 0.8)
	var t := global_transform.translated(up)
	if test_move(t, probe):
		return
	t = t.translated(probe)
	var hit := KinematicCollision3D.new()
	if not test_move(t, -up, hit) or hit.get_normal().y < 0.7:
		return
	var rise := step_height - hit.get_travel().length()
	if rise > 0.01:
		global_position.y += rise + 0.01


## Rough floor type under the player from the house plan: timber downstairs, carpet up,
## the stairs, or brick outside.
func surface() -> String:
	var home := _home()
	if home == null:
		return "brick"
	# glTF: Blender (x, y, z) -> Godot (x, z, -y); the house is x 0..5.4, y 0..12.
	var p := home.to_local(global_position)
	var bx := p.x
	var by := -p.z
	var bz := p.y
	if bx < 0.0 or bx > 5.4 or by < 0.0 or by > 12.0:
		return "brick"
	if bx < 1.0 and by > 5.0 and by < 8.8 and bz > 0.3 and bz < 3.0:
		return "stairs"
	return "carpet" if bz > 2.9 else "timber"


## Put the player's feet at `feet`, looking at `target` (tools and cutscenes).
func teleport(feet: Vector3, target: Vector3) -> void:
	global_position = feet
	velocity = Vector3.ZERO
	var d := target - (feet + Vector3.UP * eye_height)
	_yaw = atan2(-d.x, -d.z)
	_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	rotation.y = _yaw
	_camera.rotation.x = _pitch


# ---------------------------------------------------------------------------
# Getting in and out
# ---------------------------------------------------------------------------

func get_out() -> void:
	if not _car or not in_car or _busy:
		return
	var spot := _exit_spot()
	if spot == Vector3.INF:
		_note("No room to open the door.")
		return
	_busy = true
	_car.player_controlled = false
	_car.throttle_input = 0.0
	_car.brake_input = 0.0
	_car.steer_input = 0.0
	_car.handbrake_input = 1.0
	_set_car_sounds_controlled(false)  # The engine winds down.
	_set_audio_inside(true)  # Still in the seat for the belt and key.
	var side := _driver_side()
	_car_sound("seatbelt", [false])
	_car_sound("key", ["off"])
	var t := create_tween()
	t.tween_interval(OUT_KEY)
	t.tween_callback(_car_sound.bind("key", ["out"]))
	t.tween_interval(OUT_DOOR - OUT_KEY)
	t.tween_callback(func() -> void:
		_swing_door(side, true)
		_car_sound("door", [true, false, 1]))
	t.tween_interval(OUT_STEP - OUT_DOOR)
	t.tween_callback(func() -> void:
		var feet := _exit_spot()  # Again: something may have moved in the way.
		_step_out(spot if feet == Vector3.INF else feet))
	t.tween_interval(OUT_DOOR_SHUT - OUT_STEP)
	t.tween_callback(func() -> void:
		_swing_door(side, false)
		_car_sound("door", [false, false, 0]))


func _step_out(spot: Vector3) -> void:
	in_car = false
	_busy = false
	_car.is_player_inside = false
	_set_audio_inside(false)
	if _rig:
		_rig.set_process(false)
	global_position = spot
	velocity = Vector3.ZERO
	_yaw = _car.global_rotation.y
	_pitch = 0.0
	rotation.y = _yaw
	_set_body_active(true)
	_camera.current = true
	got_out.emit()


func get_in() -> void:
	if not _car or in_car or _busy:
		return
	_busy = true
	var side := _driver_side()
	_swing_door(side, true)
	_car_sound("door", [true, false, 0])
	var t := create_tween()
	t.tween_interval(IN_SIT)
	t.tween_callback(_sit)
	t.tween_interval(IN_DOOR_SHUT - IN_SIT)
	t.tween_callback(func() -> void:
		_swing_door(side, false)
		_car_sound("door", [false, false, 1]))
	t.tween_interval(IN_BELT - IN_DOOR_SHUT)
	t.tween_callback(_car_sound.bind("seatbelt", [true]))
	t.tween_interval(IN_KEY - IN_BELT)
	t.tween_callback(_car_sound.bind("key", ["in"]))
	t.tween_interval(0.25)
	t.tween_callback(_car_sound.bind("key", ["turn"]))
	t.tween_interval(IN_DRIVE - IN_KEY - 0.25)
	t.tween_callback(_drive)


## Into the seat: the driving camera is back, the car not yet started.
func _sit() -> void:
	in_car = true
	_hold_armed = false
	_set_body_active(false)
	# In the seat with the door shut: the belt and key are heard from inside,
	# not faintly from the street (the car's own sounds take over at _drive).
	_set_audio_inside(true)
	if _rig:
		_rig.set_process(true)
		var cam := _rig.get_node_or_null(^"Camera3D") as Camera3D
		if cam:
			cam.current = true
		if "mode" in _rig:
			_car.is_player_inside = _rig.mode == 1


func _drive() -> void:
	_busy = false
	_car.player_controlled = true
	_car.handbrake_input = 0.0
	_set_car_sounds_controlled(true)  # The engine starts.
	got_in.emit()


## "R" or "L": the driver's side, from the DriverSeat marker (+X is right).
func _driver_side() -> String:
	var seat := _car.get_node_or_null(^"DriverSeat") as Node3D
	return "R" if seat == null or seat.position.x >= 0.0 else "L"


func _swing_door(side: String, open: bool) -> void:
	var body := _car.get_node_or_null(^"Body")
	if body and body.has_method("set_door_open"):
		body.set_door_open(side, open)


func _set_audio_inside(inside: bool) -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has_method("set_player_inside"):
		audio.set_player_inside(inside)


func _car_sound(method: String, args: Array) -> void:
	var sounds := _car.find_child("CarSounds", true, false)
	if sounds and sounds.has_method(method):
		sounds.callv(method, args)


func _exit_spot() -> Vector3:
	# The model's own spot beside the open driver's door, when it has one.
	var body := _car.get_node_or_null(^"Body")
	var marker: Node3D = body.find_child("Exit_" + _driver_side(), true, false) as Node3D if body else null
	if marker:
		var ground := _ground_at(marker.global_position)
		if ground != Vector3.INF and _fits(ground):
			return ground
	var side := 1.0 if _driver_side() == "R" else -1.0
	var b := _car.global_basis
	var base := _car.global_position
	for offset in [Vector3(side * 1.25, 0, 0.1), Vector3(-side * 1.25, 0, 0.1), Vector3(0, 0, 2.7),
			Vector3(0, 0, -2.8), Vector3(side * 1.9, 0, 0.1)]:
		var p: Vector3 = base + b * offset
		var ground := _ground_at(p)
		if ground == Vector3.INF:
			continue
		if _fits(ground):
			return ground
	return Vector3.INF


func _ground_at(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.2, p + Vector3.DOWN * 2.0, MASK)
	q.exclude = [_car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


func _fits(feet: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape.shape
	q.transform = Transform3D(Basis(), feet + Vector3.UP * (HEIGHT / 2.0 + 0.05))
	q.collision_mask = MASK
	q.exclude = [_car.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _set_body_active(on: bool) -> void:
	visible = on
	_shape.disabled = not on
	set_physics_process(on)


func _set_car_sounds_controlled(on: bool) -> void:
	for n in _car.find_children("*", "", true, false):
		if n != _car and "player_controlled" in n:
			n.set("player_controlled", on)


# ---------------------------------------------------------------------------
# Interacting
# ---------------------------------------------------------------------------

func interact() -> void:
	match _target():
		["car", _]:
			get_in()
		["door", var door_name]:
			var home := _home()
			if not home.toggle_door(door_name):
				_note("Locked. The key must be somewhere." if door_name == &"Shed_Door" else "It won't budge.")
		["bed", _]:
			_sleep()


func _hint() -> String:
	if _busy:
		return ""
	if in_car:
		if _car and _car.linear_velocity.length() < 1.2 and _car.player_controlled:
			return "Hold F  Get out"
		return ""
	if not is_physics_processing():
		return ""  # held still by the binoculars or the fishing rod, which have their own prompts
	match _target():
		["car", _]:
			return "F  Get in"
		["door", var door_name]:
			var home := _home()
			if door_name == &"Shed_Door" and not home.shed_is_unlocked:
				return "F  Try the shed"
			return "F  %s" % ("Close" if home.is_door_open(door_name) else "Open")
		["bed", _]:
			return "F  Sleep"
	return ""


## What the player can act on right now: ["car" | "door" | "bed" | "", detail].
func _target() -> Array:
	var home := _home()
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - _camera.global_basis.z * reach, MASK)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and home:
		var n: Node = hit.collider
		while n and n != home:
			var nm := StringName(n.name)
			if home.is_door(nm):
				return ["door", nm]
			n = n.get_parent()
	if _car and _driver_door().distance_to(global_position) < CAR_REACH:
		return ["car", null]
	if home == null:
		return ["", null]
	if home.has_marker(&"Bed"):
		var bed := home.spawn_transform(&"Bed").origin
		if absf(bed.y - global_position.y) < 0.8 and Vector2(bed.x - global_position.x, bed.z - global_position.z).length() < 1.4:
			return ["bed", null]
	return ["", null]


func _driver_door() -> Vector3:
	var seat := _car.get_node_or_null(^"DriverSeat") as Node3D
	var side := 1.0 if seat == null or seat.position.x >= 0.0 else -1.0
	return _car.global_position + _car.global_basis * Vector3(side * 1.0, -0.4, 0.1)


func _home() -> HomeBase:
	for n in get_tree().get_nodes_in_group(&"home_base"):
		return n as HomeBase
	return null


func _sleep() -> void:
	var home := _home()
	_busy = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 1.2)
	tween.tween_callback(home.sleep)
	tween.tween_interval(1.6)
	tween.tween_property(_fade, "color:a", 0.0, 1.6)
	tween.tween_callback(func() -> void: _busy = false)


func _note(text: String) -> void:
	_prompt.text = text
	_note_timer = 2.5
