class_name Binoculars
extends CanvasLayer
## The binoculars (B / D-pad right): stop the car or stand still and look.
## Keep a bird in the middle a moment and it's identified for the journal.
## Then Enter / A starts the shot: a focus dial goes round the view with
## "sharp" arcs on it and a needle sweeping round. Press when the needle is
## in an arc; a few clean presses and the shutter goes. Miss too often, or
## let the bird wander out of the frame for too long, and it's gone.
##
## Look with the mouse, right stick or W/A/S/D; zoom with the wheel or E/Q
## (bumpers); B / Esc lowers them. The game keeps running: birds move,
## the clock ticks.

signal raised
signal lowered
## The shot finished: `stars` 0 when the bird got away.
signal shot(species: String, stars: int)

## The reticle's radius as a share of the half field of view.
const RETICLE := 0.36
const WIDE_FOV := 32.0
const LOOK_SPEED := 1.6
## Smallest share of the view height a bird must fill for the lab to want it.
const MIN_FRAME := 0.018

enum State { CLOSED, LOOKING, FOCUS }

var state := State.CLOSED
## What's in the reticle: {node, species, dist, frame, angle} or {}.
var target := {}
var identified := ""

var _camera: Camera3D
var _previous_camera: Camera3D
var _car: CarController
var _walker: Node3D
var _held_car := false
var _yaw := 0.0
var _pitch := 0.0
var _dwell := 0.0
var _dwell_node: Node3D
var _overlay: BinocularsOverlay
var _post_saved := {}
var _message := ""
var _message_time := 0.0
var _rng := RandomNumberGenerator.new()
# The focus dial.
var dial := {}


func _ready() -> void:
	layer = 6
	_rng.randomize()
	_overlay = BinocularsOverlay.new()
	_overlay.owner_binoculars = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	visible = false


func is_open() -> bool:
	return state != State.CLOSED


# --- raising and lowering -----------------------------------------------------------

## Why the binoculars can't come up right now ("" if they can).
func blocked_reason() -> String:
	var tree := get_tree()
	if tree.paused:
		return "paused"
	var photo := tree.root.find_child("PhotoMode", true, false)
	if photo and photo.has_method("is_open") and photo.is_open():
		return "photo mode"
	var fishing := tree.get_first_node_in_group(&"fishing")
	if fishing and fishing.has_method("is_busy") and fishing.is_busy():
		return "fishing"
	_car = tree.get_first_node_in_group(&"player_car") as CarController
	if _car == null:
		return "no car"
	_walker = _car.get_parent().get_node_or_null(^"Player") as Node3D
	if _walker and not _walker.get("in_car"):
		return "" if (_walker as CharacterBody3D).velocity.length() < 2.5 else "Stand still to use the binoculars."
	_walker = null
	if not _car.player_controlled:
		return "busy"
	var parked: bool = _car.is_parked_for_viewing() if _car.has_method("is_parked_for_viewing") else _car.linear_velocity.length() <= 1.4
	if not parked:
		return "Pull over first: the binoculars need a stopped car."
	return ""


func open() -> bool:
	if state != State.CLOSED:
		return false
	var why := blocked_reason()
	if why != "":
		if why.length() > 12:
			Activities.say(why)
		return false
	var view := get_viewport()
	var world_camera: Camera3D = null
	var sub := get_tree().root.find_child("SubViewport", true, false) as SubViewport
	if sub:
		world_camera = sub.get_camera_3d()
	if world_camera == null:
		world_camera = view.get_camera_3d()
	_previous_camera = world_camera
	_camera = Camera3D.new()
	_camera.name = "BinocularsCamera"
	# Binoculars don't focus up close, and a long near plane keeps the car's
	# own dash, pillars and bonnet out of the picture.
	_camera.near = 1.5 if _walker else 2.6
	_camera.far = 4000.0
	_camera.fov = WIDE_FOV
	_car.get_parent().add_child(_camera)
	var eye: Transform3D
	if _walker:
		var eyes := _walker.get_node_or_null(^"Eyes") as Camera3D
		eye = eyes.global_transform if eyes else _walker.global_transform.translated(Vector3.UP * 1.6)
		_walker.set_physics_process(false)
		_walker.set_process_input(false)
		_walker.set_process_unhandled_input(false)
	else:
		var at := _seat_eye()
		# Look where the player was already looking, from the driver's seat.
		var look_basis := world_camera.global_basis if world_camera else _car.global_basis
		eye = Transform3D(look_basis, at)
		_held_car = true
		_car.player_controlled = false
		_car.throttle_input = 0.0
		_car.brake_input = 0.0
		_car.steer_input = 0.0
		_car.handbrake_input = 1.0
	var euler := eye.basis.get_euler()
	_yaw = euler.y
	_pitch = clampf(euler.x, -1.2, 1.2)
	_camera.global_position = eye.origin
	_camera.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))
	_camera.current = true
	state = State.LOOKING
	visible = true
	target = {}
	identified = ""
	_dwell = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_hud(false)
	_apply_post(true)
	_sound_2d("field/binoculars_up")
	raised.emit()
	return true


## Where the driver's eyes are: the car's own driver_eye() when it has one.
func _seat_eye() -> Vector3:
	if _car.has_method("driver_eye"):
		return (_car.driver_eye() as Transform3D).origin
	var seat := _car.get_node_or_null(^"DriverSeat") as Node3D
	return seat.global_position if seat else _car.global_position + _car.global_basis.y * 1.1


func close() -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	dial = {}
	visible = false
	_apply_post(false)
	if is_instance_valid(_previous_camera):
		_previous_camera.current = true
	if _camera:
		_camera.queue_free()
		_camera = null
	if _walker and is_instance_valid(_walker):
		_walker.set_physics_process(true)
		_walker.set_process_input(true)
		_walker.set_process_unhandled_input(true)
	if _held_car and is_instance_valid(_car):
		_car.player_controlled = true
		_car.handbrake_input = 0.0
	_held_car = false
	_set_hud(true)
	_sound_2d("field/binoculars_down")
	lowered.emit()


func _set_hud(on: bool) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud") as CanvasLayer
	if hud:
		hud.visible = on


## Night glass: lift the picture a little after dark, more with better binoculars.
func _apply_post(on: bool) -> void:
	var lofi := get_tree().root.find_child("LoFi", true, false) as CanvasItem
	var post: ShaderMaterial = lofi.material as ShaderMaterial if lofi else null
	if post == null:
		return
	if on:
		_post_saved = {"tint": post.get_shader_parameter("tint"), "vignette": post.get_shader_parameter("vignette"),
			"contrast": post.get_shader_parameter("contrast")}
		var dark := 1.0 - GameClock.daylight()
		var lift := 1.0 + dark * (0.35 + float(FieldJournal.gear_binoculars().night) * 1.6)
		post.set_shader_parameter("tint", Color(lift, lift, lift * 1.02))
		post.set_shader_parameter("vignette", 0.0)
	elif not _post_saved.is_empty():
		for key: String in _post_saved:
			if _post_saved[key] != null:
				post.set_shader_parameter(key, _post_saved[key])
		_post_saved = {}


# --- input ---------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if state == State.CLOSED:
		if event.is_action_pressed("binoculars") and not event.is_echo():
			if open():
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("binoculars") or event.is_action_pressed("pause") \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		if state == State.FOCUS:
			_end_shot(0, "You lowered the camera.")
		close()
	elif event.is_action_pressed("photo_take") and not event.is_echo():
		if state == State.FOCUS:
			_press()
		else:
			_start_shot()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := _camera.fov / WIDE_FOV if _camera else 1.0
		_yaw -= event.relative.x * Settings.mouse_sensitivity * k
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity * k, -1.3, 1.3)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(2.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("shift_up"):
		zoom(-4.0)
	elif event.is_action_pressed("shift_down"):
		zoom(4.0)
	elif event.is_action_pressed("phone") or event.is_action_pressed("photo_mode") or event.is_action_pressed("journal"):
		return  # let them through (they pause the game)
	else:
		return
	get_viewport().set_input_as_handled()


func zoom(step: float) -> void:
	if _camera:
		_camera.fov = clampf(_camera.fov + step, float(FieldJournal.gear_binoculars().fov), WIDE_FOV)


func _process(delta: float) -> void:
	_message_time = maxf(_message_time - delta, 0.0)
	if state == State.CLOSED or _camera == null:
		return
	if get_tree().paused:
		return
	var k := _camera.fov / WIDE_FOV
	var look := Input.get_vector("look_left", "look_right", "look_down", "look_up")
	var keys := Input.get_vector("steer_left", "steer_right", "brake", "accelerate")
	look += keys
	_yaw -= look.x * LOOK_SPEED * k * delta
	_pitch = clampf(_pitch + look.y * LOOK_SPEED * k * delta, -1.3, 1.3)
	# A little hand shake, less with better glass and less zoomed out.
	var shake := (1.0 - float(FieldJournal.binoculars) * 0.35) * 0.0012 * (WIDE_FOV / _camera.fov) * 0.25
	var t := Time.get_ticks_msec() / 1000.0
	_camera.global_basis = Basis.from_euler(Vector3(_pitch + sin(t * 3.1) * shake, _yaw + sin(t * 2.3 + 1.0) * shake, 0))
	if _walker and is_instance_valid(_walker):
		var eyes := _walker.get_node_or_null(^"Eyes") as Node3D
		if eyes:
			_camera.global_position = eyes.global_position
	elif is_instance_valid(_car):
		_camera.global_position = _seat_eye()
	_update_target(delta)
	if state == State.FOCUS:
		_update_dial(delta)
	_overlay.queue_redraw()


# --- what's in view ------------------------------------------------------------------------

## Every bird the binoculars could pick out: [{node, species}], the field
## journal's own and traffic's magpies and ibis.
func candidates() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group(&"field_birds"):
		var n := node as Node3D
		if n.visible and n.is_inside_tree():
			out.append({"node": n, "species": String(n.get_meta("species", ""))})
	var traffic := get_tree().get_first_node_in_group(&"traffic")
	var wildlife: Object = traffic.get("wildlife") if traffic else null
	if wildlife and "animals" in wildlife:
		for a: Dictionary in wildlife.animals:
			var kind := int(a.get("kind", -1))
			var n := a.get("node") as Node3D
			if n == null or not n.visible or kind > 1 or a.get("state", &"") == &"gone":
				continue
			out.append({"node": n, "species": "australian_magpie" if kind == 0 else "australian_white_ibis"})
	return out


func _update_target(delta: float) -> void:
	var gear := FieldJournal.gear_binoculars()
	var from := _camera.global_position
	var forward := -_camera.global_basis.z
	var half := deg_to_rad(_camera.fov) * 0.5
	var best := {}
	var best_angle := half * RETICLE
	for c: Dictionary in candidates():
		var b := FieldJournal.bird(c.species)
		if b.is_empty():
			continue
		var size := float(b.get("size", 0.3))
		var at: Vector3 = (c.node as Node3D).global_position + Vector3.UP * size * 0.3
		var to := at - from
		var dist := to.length()
		if dist < 0.5 or dist > float(gear.range) * 1.6:
			continue
		var angle := forward.angle_to(to)
		if angle > best_angle:
			continue
		if not _clear_line(from, at):
			continue
		best_angle = angle
		best = {"node": c.node, "species": c.species, "dist": dist, "angle": angle,
			"frame": (size / dist) / deg_to_rad(_camera.fov), "in_range": dist <= float(gear.range)}
	target = best
	if state == State.FOCUS:
		return
	if target.is_empty() or not target.in_range:
		_dwell = maxf(_dwell - delta * 2.0, 0.0)
		return
	if target.node != _dwell_node:
		_dwell_node = target.node
		_dwell = 0.0
	var need: float = float(gear.identify) * (1.0 + target.dist / float(gear.range))
	_dwell += delta
	if _dwell >= need and identified != target.species:
		identified = target.species
		var where := FieldJournal.place_name(target.node.global_position)
		if FieldJournal.see(target.species, where):
			var b := FieldJournal.bird(target.species)
			if b.get("wrong", false):
				Activities.say("There's already a page about this in the journal. It isn't in your handwriting." if b.get("page_by", "") != "you" else "There's already a page about this in the journal. It is in your handwriting.")
				_sound_2d("field/m_page_found" if b.get("page_by", "") != "you" else "field/m_page_found_yours")
			else:
				Activities.say("New for the journal: %s." % b.get("name", target.species))
				_sound_2d("music/mus_field_new_species", "Music")
			_sound_2d("field/focus_hit")
	elif _dwell < need and identified != "" and identified != target.species:
		identified = ""


## True when nothing solid is between the eye and p (birds in tree crowns are
## fine: the map's trees have no collision).
func _clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	var ex: Array[RID] = []
	if is_instance_valid(_car):
		ex.append(_car.get_rid())
	q.exclude = ex
	return get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty() if get_viewport().world_3d else true


func is_identified() -> bool:
	return not target.is_empty() and identified == target.species and _dwell_node == target.node


# --- the shot ----------------------------------------------------------------------------------

func _start_shot() -> void:
	if target.is_empty():
		_say("Nothing in the middle of the view.")
		return
	if not is_identified():
		_say("Hold it in the middle a moment first.")
		return
	if FieldJournal.film_left() <= 0:
		_say("Out of film. The lab on Lake Street will develop it.")
		_sound_2d("field/film_full")
		return
	if target.frame < MIN_FRAME:
		_say("Too small to make out in a photo. Get closer or zoom in.")
		return
	var b := FieldJournal.bird(target.species)
	var ease := float(FieldJournal.gear_camera().ease)
	var shy := clampf(float(b.get("shy", 0.3)) - ease * 0.4, 0.0, 1.0)
	dial = {
		"node": target.node, "species": target.species, "shy": shy,
		"needle": _rng.randf() * TAU, "dir": 1.0 if _rng.randf() < 0.5 else -1.0,
		"speed": TAU * (0.42 + shy * 0.55),
		"half": deg_to_rad(30.0 - shy * 15.0) * (1.0 + ease * 0.4),
		"need": 2 + roundi(shy * 2.0), "hits": 0, "sharp": 0,
		"patience": 3 - roundi(shy * 1.5), "time": 9.0 + (1.0 - shy) * 6.0,
		"out_of_frame": 0.0, "arcs": [], "flash": 0.0, "flash_good": true,
	}
	for i in 2:
		_add_arc()
	state = State.FOCUS


func _add_arc() -> void:
	for attempt in 12:
		var at := _rng.randf() * TAU
		var ok := absf(angle_difference(at, dial.needle)) > 1.0
		for other: float in dial.arcs:
			ok = ok and absf(angle_difference(at, other)) > dial.half * 2.4
		if ok:
			dial.arcs.append(at)
			return


func _update_dial(delta: float) -> void:
	if not is_instance_valid(dial.get("node")) or not (dial.node as Node3D).visible:
		_end_shot(0, "It's gone.")
		return
	dial.needle = wrapf(dial.needle + dial.dir * dial.speed * delta, 0.0, TAU)
	dial.flash = maxf(dial.flash - delta * 3.0, 0.0)
	dial.time -= delta
	# Keep the bird in the frame, or the lens loses it.
	if not in_frame():
		dial.out_of_frame += delta
		if dial.out_of_frame > 2.5:
			_end_shot(0, "Lost it.")
			return
	else:
		dial.out_of_frame = maxf(dial.out_of_frame - delta, 0.0)
	if dial.time <= 0.0:
		_flush_target()
		_end_shot(0, "It got bored of you and left.")


## Whether the bird being photographed is still in the reticle.
func in_frame() -> bool:
	return not target.is_empty() and target.node == dial.get("node")


func _press() -> void:
	if not in_frame():
		_sound_2d("field/focus_miss")
		return
	for i in dial.arcs.size():
		var off := absf(angle_difference(dial.needle, dial.arcs[i]))
		if off <= dial.half:
			dial.arcs.remove_at(i)
			dial.hits += 1
			if off <= dial.half * 0.35:
				dial.sharp += 1
			dial.dir = -dial.dir
			dial.flash = 1.0
			dial.flash_good = true
			_sound_2d("field/focus_hit")
			if dial.hits >= dial.need:
				_take()
			else:
				_add_arc()
			return
	dial.patience -= 1
	dial.flash = 1.0
	dial.flash_good = false
	_sound_2d("field/focus_miss")
	if dial.patience <= 0:
		_flush_target()
		_end_shot(0, "Too much fiddling: it's off.")


func _flush_target() -> void:
	var birds := get_tree().get_first_node_in_group(&"field_bird_spawner")
	if birds and dial.get("node") and is_instance_valid(dial.node) and birds.has_method("flush"):
		birds.flush(dial.node, _camera.global_position if _camera else dial.node.global_position)


## Stars from how sharp the presses were and how well the bird fills the frame.
func stars_for(hits: int, sharp: int, frame: float) -> int:
	var stars := 1
	if sharp * 2 >= hits:
		stars = 2
	if sharp >= hits:
		stars = 3
	if frame < 0.04:
		stars -= 1
	elif frame > 0.12 and sharp * 2 >= hits:
		stars += 1
	return clampi(stars, 1, 3)


func _take() -> void:
	var species: String = dial.species
	var node: Node3D = dial.node
	var stars := stars_for(dial.hits, dial.sharp, target.frame if not target.is_empty() else 0.0)
	var where := FieldJournal.place_name(node.global_position)
	state = State.LOOKING
	dial = {}
	_sound_2d("field/shutter")
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		_overlay.visible = false
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return  # the game closed under the shutter
		image = get_viewport().get_texture().get_image()
		_overlay.visible = true
	_overlay.flash = 1.0
	var photo := Activities.add_photo(image, null)
	FieldJournal.log_photo(species, stars, String(photo.get("file", "")), where)
	var birds := get_tree().get_first_node_in_group(&"field_bird_spawner")
	if birds and is_instance_valid(node) and birds.has_method("photographed"):
		birds.photographed(node)
	var b := FieldJournal.bird(species)
	_say("%s  %s   (%d frames left)" % [b.get("name", species), "*".repeat(stars), FieldJournal.film_left()])
	shot.emit(species, stars)


func _end_shot(stars: int, why: String) -> void:
	var species: String = dial.get("species", "")
	dial = {}
	state = State.LOOKING
	_say(why)
	shot.emit(species, stars)


func _say(text: String) -> void:
	_message = text
	_message_time = 3.5


func message() -> String:
	return _message if _message_time > 0.0 else ""


func _sound_2d(sound_name: String, bus := "UI") -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play_2d") and (not audio.has_method("has") or audio.has(sound_name)):
		audio.play_2d(sound_name, bus, -4.0)
