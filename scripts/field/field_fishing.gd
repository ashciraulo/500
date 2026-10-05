class_name FieldFishing
extends Node3D
## The fishing side of the field journal: the spots in data/field/fishing_spots.json
## (a bait bucket on the jetty, rings on the water when the fish are about),
## and the rod.
##
## Walk to a spot and press F / A to get the rod out. Hold F to swing it back
## and let go to cast where you're looking. Then wait: the float nods when
## something's having a look, and goes under when it bites. Strike (F) while
## it's under. A nibble isn't a bite; strike at a nibble and shy fish leave.
## Then the fight: hold F to reel, let go to give it line. Reel through the
## fish's runs and the line snaps; when the rod tip shivers a run is coming,
## so ease off. Give it nothing at all for too long and it throws the hook.
## Get it to your feet and it's landed: keep it (if it's legal and the esky
## has room), let it go, or take its photo. Esc / B puts the rod away.
##
## With a crab net (from the tackle shop) a crab spot gets the net dropped
## off the side too; come back in an hour or so and pull it.

signal state_changed(state: int)
## A fish came up: the catch dictionary from FieldJournal.land.
signal landed(caught: Dictionary)
## The fish got away: "snapped", "thrown", "missed", "spooked".
signal lost(why: String)

enum State { IDLE, READY, CHARGING, WAITING, BITE, FIGHT, LANDED }

## Stand this close to a spot's place to fish it.
const REACH := 4.5
## The spot goes in the journal from this close.
const FIND_RANGE := 30.0
## Props and water signs are built for spots this close.
const SHOW_RANGE := 400.0
const CAST_MIN := 6.0
## Longest cast for each rod.
const CAST_MAX := [22.0, 28.0, 36.0]
## Seconds of the swing meter's full back-and-forth.
const SWING_PERIOD := 1.4
## Line out past this and the fish has spooled you.
const MAX_LINE := 70.0
## The fight: see FIELD_JOURNAL.md for the numbers and how they were tuned.
const REEL_SPEED := 2.4
const SLACK_LIMIT := 2.5
const WARN_TIME := 0.5

var state := State.IDLE
## The spot being fished, or the one in reach.
var current_spot := {}
## 0..1 while swinging back.
var power := 0.0
var cast_distance := 0.0
## The fight, for the screen: metres of line out, tension 0..1, true while a
## run is coming or under way.
var line_out := 0.0
var tension := 0.0
var warning := false
var surging := false
## The fish on the line {species, cm, kg, legal, junk} and, once landed, the catch.
var fish_on := {}
var caught := {}
var screen: FishingScreen

var _rng := RandomNumberGenerator.new()
var _walker: Node3D
var _eyes: Camera3D
var _car: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _swing_t := 0.0
var _wait := 0.0
var _nibbles := 0
var _nibble_t := 0.0
var _bite_t := 0.0
var _species := {}
var _stamina := 0.0
var _stamina0 := 0.0
var _pull := 0.0
var _surge_in := 0.0
var _surge_t := 0.0
var _slack := 0.0
var _reeling := false
var _idle_note := 0.0
var _time := 0.0
var _cast_dir := Vector3.FORWARD
var _water_y := 0.0
var _hook := Vector3.ZERO

var _rod: Node3D
var _rod_joints: Array[Node3D] = []
var _rod_tip: Node3D
var _float: Node3D
var _line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _splash: MeshInstance3D
var _held: Node3D
var _held_light: OmniLight3D
var _props := {}
var _check_t := 0.0


func _ready() -> void:
	add_to_group(&"fishing")
	_rng.randomize()
	_line_mesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.name = "Line"
	_line.mesh = _line_mesh
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.85, 0.88, 0.8, 0.8)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line.material_override = line_mat
	_line.top_level = true
	add_child(_line)
	_float = _make_float()
	_float.top_level = true
	_float.visible = false
	add_child(_float)
	_splash = MeshInstance3D.new()
	_splash.name = "Splash"
	var foam := SphereMesh.new()
	foam.radius = 0.5
	foam.height = 0.3
	foam.radial_segments = 8
	foam.rings = 3
	_splash.mesh = foam
	var foam_mat := StandardMaterial3D.new()
	foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam_mat.albedo_color = Color(0.92, 0.95, 0.95, 0.7)
	foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash.material_override = foam_mat
	_splash.top_level = true
	_splash.visible = false
	add_child(_splash)


func is_busy() -> bool:
	return state != State.IDLE


# --- the spots ----------------------------------------------------------------------------

## The player on foot, or null while they're in the car.
func _on_foot() -> Node3D:
	var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
	if car == null:
		return null
	_car = car
	var walker := car.get_parent().get_node_or_null(^"Player") as Node3D
	if walker and not walker.get("in_car"):
		return walker
	return null


## The fishing spot the player's standing at, or {}.
func spot_in_reach() -> Dictionary:
	var walker := _on_foot()
	if walker == null:
		return {}
	var p := walker.global_position
	for sp: Dictionary in FieldJournal.spots:
		var s := FieldJournal.spot_stand(sp)
		if Vector2(s.x - p.x, s.z - p.z).length() < REACH and absf(s.y - p.y) < 2.0:
			return sp
	return {}


## The prompt for the screen ("" for none).
func prompt() -> String:
	if state != State.IDLE or get_tree().paused:
		return ""
	var sp := spot_in_reach()
	if sp.is_empty():
		return ""
	if _crab_net_ready(sp):
		return "F / A  Pull the crab net"
	return "F / A  Fish here (%s)" % sp.name


func _process(delta: float) -> void:
	_time += delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		_update_spots()
	_animate_props(delta)
	if get_tree().paused or state == State.IDLE:
		return
	if not is_instance_valid(_walker) or _walker.get("in_car"):
		_put_away()
		return
	_look(delta)
	match state:
		State.CHARGING:
			_swing_t += delta
			power = 1.0 - absf(fmod(_swing_t / SWING_PERIOD, 2.0) - 1.0)
			_bend(-power * 0.35)
		State.WAITING:
			_waiting(delta)
		State.BITE:
			_bite_t -= delta
			_float_at(_hook + Vector3(0, -0.18, 0))
			if _bite_t <= 0.0:
				_lose("missed", "It took the bait. Wind in and try again.")
		State.FIGHT:
			_fight(delta)
		State.LANDED:
			if _held:
				_held.rotation.z = sin(_time * 3.1) * 0.12
				_held.rotation.x = sin(_time * 2.3) * 0.08
	_draw_line()


func _update_spots() -> void:
	var focus := _focus()
	for sp: Dictionary in FieldJournal.spots:
		var s := FieldJournal.spot_stand(sp)
		var d := Vector2(s.x - focus.x, s.z - focus.z).length()
		var id := String(sp.id)
		if d < FIND_RANGE and Discoveries.discover("fishing/" + id):
			Activities.say("Fishing spot: %s. It's in the journal." % sp.name)
		if d < SHOW_RANGE and not _props.has(id):
			_props[id] = _make_spot_props(sp)
			add_child(_props[id])
		elif d > SHOW_RANGE + 50.0 and _props.has(id):
			_props[id].queue_free()
			_props.erase(id)
	# Rings on the water while something worth catching is about.
	var hour := GameClock.time_of_day
	for id: String in _props:
		var sp := FieldJournal.spot(id)
		var lively := false
		for f: Dictionary in FieldJournal.fish_candidates(sp, hour):
			if int(f.get("rarity", 1)) >= 2:
				lively = true
				break
		(_props[id] as Node3D).get_node(^"Rings").visible = lively


func _focus() -> Vector3:
	var walker := _on_foot()
	if walker:
		return walker.global_position
	return _car.global_position if is_instance_valid(_car) else Vector3.INF


func _make_spot_props(sp: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Spot_" + String(sp.id)
	root.position = FieldJournal.spot_stand(sp)
	root.rotation.y = float(sp.get("yaw", 0.0))
	# A bait bucket someone's left by the rail.
	var bucket := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.11
	cyl.height = 0.26
	cyl.radial_segments = 8
	cyl.rings = 1
	bucket.mesh = cyl
	bucket.material_override = PS1Material.make(Color(0.86, 0.84, 0.78))
	bucket.position = Vector3(0.9, 0.13, 0.4)
	root.add_child(bucket)
	var lid := MeshInstance3D.new()
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.15
	lid_mesh.bottom_radius = 0.15
	lid_mesh.height = 0.03
	lid_mesh.radial_segments = 8
	lid.mesh = lid_mesh
	lid.material_override = PS1Material.make(Color(0.85, 0.4, 0.15))
	lid.position = Vector3(0.9, 0.27, 0.4)
	root.add_child(lid)
	# Rings spreading on the water out in front.
	var rings := Node3D.new()
	rings.name = "Rings"
	rings.top_level = true
	var ahead := root.position + Vector3(-sin(root.rotation.y), 0, -cos(root.rotation.y)) * 12.0
	rings.position = Vector3(ahead.x, 0.03, ahead.z)
	root.add_child(rings)
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.92
		torus.outer_radius = 1.0
		torus.rings = 16
		torus.ring_segments = 3
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.9, 0.95, 1.0, 0.0)
		ring.material_override = mat
		ring.scale = Vector3(1, 0.2, 1)
		ring.position = Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
		ring.set_meta("phase", i / 3.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rings.add_child(ring)
	return root


func _animate_props(_delta: float) -> void:
	for id: String in _props:
		var rings := (_props[id] as Node3D).get_node(^"Rings") as Node3D
		if not rings.visible:
			continue
		for ring: MeshInstance3D in rings.get_children():
			var t := fmod(_time / 3.2 + float(ring.get_meta("phase")), 1.0)
			var s := lerpf(0.3, 2.6, t)
			ring.scale = Vector3(s, 0.2, s)
			(ring.material_override as StandardMaterial3D).albedo_color.a = (1.0 - t) * 0.45
			if t < 0.02:
				ring.position = Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))


# --- input ---------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if state == State.IDLE:
		if event.is_action_pressed("interact") and not event.is_echo():
			var sp := spot_in_reach()
			if not sp.is_empty() and _walker_free():
				start(sp)
				get_viewport().set_input_as_handled()
		return
	if state == State.LANDED:
		return  # the catch card has it
	if event.is_action_pressed("pause") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		if state != State.FIGHT:
			_put_away()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Settings.mouse_sensitivity
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, -1.2, 0.9)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		_press()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("interact"):
		_release()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("binoculars"):
		Activities.say("Put the rod down first (Esc / B).")
		get_viewport().set_input_as_handled()


## Not when the walker's got the car door or a house door in front of them.
func _walker_free() -> bool:
	var walker := _on_foot()
	if walker == null or (walker as CharacterBody3D).velocity.length() > 2.5:
		return false
	return not walker.has_method("_hint") or String(walker.call("_hint")) == ""


func _press() -> void:
	match state:
		State.READY:
			state = State.CHARGING
			_swing_t = 0.0
			power = 0.0
			state_changed.emit(state)
		State.WAITING:
			_strike_early()
		State.BITE:
			_hooked()
		State.FIGHT:
			_reeling = true


func _release() -> void:
	match state:
		State.CHARGING:
			_cast()
		State.FIGHT:
			_reeling = false


# --- getting the rod out and away -----------------------------------------------------

## Get the rod out at `sp` (pulling or dropping the crab net first).
func start(sp: Dictionary) -> void:
	_walker = _on_foot()
	if _walker == null:
		return
	current_spot = sp
	_eyes = _walker.get_node_or_null(^"Eyes") as Camera3D
	_yaw = _walker.rotation.y
	_pitch = _eyes.rotation.x if _eyes else 0.0
	_walker.set_physics_process(false)
	_walker.set_process_unhandled_input(false)
	_walker.set_process_input(false)
	(_walker as CharacterBody3D).velocity = Vector3.ZERO
	_water_y = 0.0
	_make_rod()
	_crab_net(sp)
	state = State.READY
	state_changed.emit(state)
	_sound("field/rod_out")


func _put_away() -> void:
	if state == State.IDLE:
		return
	var was := state
	state = State.IDLE
	_reeling = false
	_float.visible = false
	_splash.visible = false
	_line_mesh.clear_surfaces()
	_drop_held()
	if is_instance_valid(_rod):
		_rod.queue_free()
	_rod = null
	_rod_joints.clear()
	if is_instance_valid(_walker):
		# Hand the look back to the walker where it is now.
		_walker.set("_yaw", _yaw)
		_walker.set("_pitch", _pitch)
		_walker.set_physics_process(not _walker.get("in_car"))
		_walker.set_process_unhandled_input(true)
		_walker.set_process_input(true)
	if screen:
		screen.close_card()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if was != State.READY:
		_sound("field/reel_in")
	state_changed.emit(state)


func _look(delta: float) -> void:
	if state == State.LANDED:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.1:
		_yaw -= stick.x * 1.6 * delta
		_pitch = clampf(_pitch - stick.y * 1.6 * delta, -1.2, 0.9)
	_walker.rotation.y = _yaw
	if _eyes:
		_eyes.rotation.x = _pitch


# --- casting and waiting ------------------------------------------------------------------

func _cast() -> void:
	var reach: float = CAST_MAX[clampi(FieldJournal.rod, 0, CAST_MAX.size() - 1)]
	cast_distance = lerpf(CAST_MIN, reach, power)
	_bend(0.0)
	var forward := -_walker.global_basis.z
	_cast_dir = Vector3(forward.x, 0, forward.z).normalized()
	var at := _walker.global_position + _cast_dir * cast_distance
	_sound("field/cast")
	if not _is_water(at):
		state = State.READY
		state_changed.emit(state)
		_say("Snagged on the bank. You wind it back in. Cast out over the water.")
		return
	_hook = Vector3(at.x, _water_y, at.z)
	_sound("field/lure_plop")
	_float.visible = true
	_float_at(_hook)
	state = State.WAITING
	state_changed.emit(state)
	_next_fish()


## Water here: nothing solid above the waterline.
func _is_water(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.z), Vector3(p.x, -12.0, p.z), 1 | 2)
	if is_instance_valid(_car):
		q.exclude = [(_car as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.position.y < _water_y + 0.25


## Pick what's going to come along, and when.
func _next_fish() -> void:
	var list := FieldJournal.fish_candidates(current_spot, GameClock.time_of_day)
	_species = FieldJournal.pick_fish(list, _rng)
	_wait = _rng.randf_range(4.0, 14.0)
	var shy := float(_species.get("shy", 0.0))
	_nibbles = _rng.randi_range(0, 1 + roundi(shy * 3.0))
	_nibble_t = 0.0
	_idle_note = 30.0


func _waiting(delta: float) -> void:
	var bob := sin(_time * 2.2) * 0.02
	_nibble_t = maxf(_nibble_t - delta, 0.0)
	var dip := -0.06 * sin(_nibble_t / 0.35 * PI) if _nibble_t > 0.0 else 0.0
	_float_at(_hook + Vector3(0, bob + dip, 0))
	if _species.is_empty():
		_idle_note -= delta
		if _idle_note <= 0.0:
			_idle_note = 40.0
			_say("Nothing's biting here at this hour. Another spot, or another time.")
		return
	_wait -= delta
	if _wait > 0.0:
		return
	if _nibbles > 0:
		_nibbles -= 1
		_nibble_t = 0.35
		_wait = _rng.randf_range(1.2, 3.5)
		_sound("field/bite_nibble")
		return
	state = State.BITE
	_bite_t = lerpf(1.0, 0.5, float(_species.get("shy", 0.0)))
	_sound("field/splash_small")
	state_changed.emit(state)


func _strike_early() -> void:
	_bend(-0.2)
	if _nibble_t > 0.0 and _rng.randf() < float(_species.get("shy", 0.0)):
		_say("Too early. Whatever it was has gone.")
		_next_fish()
		_wait += 4.0
	else:
		_say("Too early.")


func _hooked() -> void:
	fish_on = FieldJournal.fish_size(_species, _rng)
	fish_on["name"] = _species.get("name", _species.id)
	var kg := float(fish_on.kg)
	var fight := float(_species.get("fight", 0.3))
	_pull = fight * (0.5 + minf(kg / 4.0, 0.8))
	_stamina0 = 2.0 + fight * 6.0 + kg * 1.2
	_stamina = _stamina0
	line_out = _walker.global_position.distance_to(_hook)
	tension = 0.2
	_slack = 0.0
	_surge_in = _rng.randf_range(1.5, 3.5)
	_surge_t = 0.0
	_reeling = Input.is_action_pressed("interact")
	state = State.FIGHT
	_sound("field/strike")
	state_changed.emit(state)


# --- the fight -------------------------------------------------------------------------------

func _fight(delta: float) -> void:
	var rod_gear := FieldJournal.gear_rod()
	var strength := float(rod_gear.strength)
	var reel := float(rod_gear.reel)
	_surge_in -= delta
	warning = _surge_in > 0.0 and _surge_in <= WARN_TIME and _stamina > 0.0
	if _surge_in <= 0.0:
		_surge_t = _rng.randf_range(0.6, 1.2)
		_surge_in = _rng.randf_range(2.0, 4.5) + _surge_t
		_sound("field/drag")
	surging = _surge_t > 0.0
	_surge_t = maxf(_surge_t - delta, 0.0)
	var tired := clampf(_stamina / _stamina0, 0.25, 1.0)
	var pull := _pull * tired * (2.5 if surging else 1.0)
	if _reeling:
		line_out -= reel * REEL_SPEED * maxf(1.0 - 0.7 * minf(pull, 1.2), 0.12) * delta
		var rise := (0.2 + pull * 0.85) / strength
		if tension > 0.75:
			# The drag slips a little.
			rise *= 0.7
			line_out += pull * 0.5 * delta
		tension += rise * delta
	else:
		tension -= 0.8 * delta
		line_out += pull * 1.6 * delta
	tension = maxf(tension, 0.0)
	_stamina = maxf(_stamina - delta * (0.35 + tension), 0.0)
	_slack = _slack + delta if tension < 0.06 else 0.0
	_bend(-0.1 - tension * 0.9 - (0.15 if warning else 0.0) * sin(_time * 40.0))
	# Where the fish is: off along the cast, swinging about, closer as it comes in.
	var side := _cast_dir.cross(Vector3.UP)
	var swing := sin(_time * 0.8) * minf(line_out * 0.25, 6.0) + (sin(_time * 5.0) * 1.5 if surging else 0.0)
	var foot := _walker.global_position
	var hook := foot + _cast_dir * line_out + side * swing
	_hook = Vector3(hook.x, _water_y, hook.z)
	_float_at(_hook + Vector3(0, -0.1 if surging else 0.0, 0))
	_splash.visible = surging or line_out < 4.0
	if _splash.visible:
		var s := 0.4 + 0.3 * absf(sin(_time * 9.0))
		_splash.global_position = _hook
		_splash.scale = Vector3(s, s * 0.6, s)
	if tension >= 1.0:
		_sound("field/line_snap")
		_lose("snapped", "Snap! The line's gone. Ease off when the rod tip shivers.")
	elif line_out > MAX_LINE:
		_sound("field/line_snap")
		_lose("snapped", "It stripped the reel and the line parted.")
	elif _slack > SLACK_LIMIT and float(_species.get("fight", 0.0)) > 0.3:
		_lose("thrown", "The line went slack and it threw the hook. Keep a little pressure on.")
	elif line_out <= 1.5:
		_land()


func _lose(why: String, text: String) -> void:
	_say(text)
	fish_on = {}
	_reeling = false
	warning = false
	surging = false
	_splash.visible = false
	_float.visible = false
	_bend(0.0)
	state = State.READY
	state_changed.emit(state)
	lost.emit(why)


func _land() -> void:
	_splash.visible = false
	_float.visible = false
	_reeling = false
	warning = false
	surging = false
	_bend(0.0)
	caught = FieldJournal.land(fish_on.duplicate(), String(current_spot.get("name", "")))
	caught["name"] = fish_on.get("name", "")
	fish_on = {}
	_show_held(caught)
	state = State.LANDED
	_sound("field/landed_flop")
	state_changed.emit(state)
	landed.emit(caught)
	if screen:
		screen.open_card(caught)


## What the catch card does: "keep", "release" or "photo".
func choose(action: String) -> void:
	if state != State.LANDED:
		return
	var sp := FieldJournal.fish_species(String(caught.species))
	match action:
		"keep":
			if caught.get("junk", false):
				Discoveries.discover("fishing/" + String(caught.species))
				_say("It's coming home. It'll look good on the shed wall.")
			elif not FieldJournal.keep(caught):
				return
			else:
				_say("Into the esky (%d of %d)." % [FieldJournal.esky.size(), FieldJournal.esky_size()])
				_sound("field/esky_lid")
		"release":
			FieldJournal.release(caught)
			_say("Back it goes." if not caught.get("junk", false) else "Back in the river with it.")
			_sound("field/splash_small")
		"photo":
			_photo(sp)
			return
	_drop_held()
	caught = {}
	if screen:
		screen.close_card()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	state = State.READY
	state_changed.emit(state)


## Why a catch can't go in the esky ("" when it can).
func keep_blocked(c: Dictionary) -> String:
	if c.get("junk", false):
		return ""
	if int(FieldJournal.fish_species(String(c.species)).get("pay", 0)) <= 0:
		return "Nobody keeps one of these."
	if not c.get("legal", false):
		return "Undersize: it has to go back."
	if FieldJournal.esky_room() <= 0:
		return "The esky's full."
	return ""


func _photo(_sp: Dictionary) -> void:
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		if screen:
			screen.hide_card(true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		image = get_viewport().get_texture().get_image()
		if screen:
			screen.hide_card(false)
	var photo := Activities.add_photo(image, null)
	var file := String(photo.get("file", ""))
	var e: Dictionary = FieldJournal.catches.get(String(caught.get("species", "")), {})
	if not e.is_empty() and file != "" and (String(e.best_file) == "" or float(caught.cm) >= float(e.biggest_cm)):
		e.best_file = file
	_sound("field/shutter")
	if screen:
		screen.card_note("Photo in the album.")


# --- the crab net ------------------------------------------------------------------------

func _crab_net_ready(sp: Dictionary) -> bool:
	var id := String(sp.get("id", ""))
	return FieldJournal.crab_nets.has(id) and \
		FieldJournal.now_minutes() - float(FieldJournal.crab_nets[id]) >= FieldJournal.CRAB_SOAK_HOURS * 60.0


func _crab_net(sp: Dictionary) -> void:
	var id := String(sp.id)
	if _crab_net_ready(sp):
		pull_crab_net(sp)
		return
	if FieldJournal.crab_nets.has(id):
		_say("The crab net's still soaking. Give it a while yet.")
		return
	if not FieldJournal.has_crab_net or not Array(sp.get("tags", [])).has("crabs"):
		return
	if not FieldJournal.crab_nets.is_empty():
		var other := FieldJournal.spot(String(FieldJournal.crab_nets.keys()[0]))
		_say("Your crab net's still down at %s." % other.get("name", "another spot"))
		return
	FieldJournal.crab_nets[id] = FieldJournal.now_minutes()
	_say("You drop the crab net over the side. Come back for it in an hour or so.")
	_sound("field/splash_big")


## Haul up the net: a few blue mannas, the legal ones into the esky. Returns the catches.
func pull_crab_net(sp: Dictionary) -> Array:
	var id := String(sp.id)
	var soaked := (FieldJournal.now_minutes() - float(FieldJournal.crab_nets.get(id, 0.0))) / 60.0
	FieldJournal.crab_nets.erase(id)
	var out := []
	var hour := GameClock.time_of_day
	var list := FieldJournal.fish_candidates(sp, hour, "net")
	var n := 0 if list.is_empty() else _rng.randi_range(0, 2) + (1 if soaked > 2.0 else 0) + (1 if hour < 6.0 or hour > 19.0 else 0)
	var kept := 0
	for i in n:
		var c := FieldJournal.fish_size(FieldJournal.pick_fish(list, _rng), _rng)
		c = FieldJournal.land(c, String(sp.name))
		if FieldJournal.keep(c):
			kept += 1
		else:
			FieldJournal.release(c)
		out.append(c)
	_sound("field/bucket_drop")
	if n == 0:
		_say("The net comes up empty, bar a bit of weed.")
	else:
		_say("Pulled the crab net: %d blue manna%s, %d kept, %d went back." % [n, "" if n == 1 else "s", kept, n - kept])
	return out


# --- the rod, the float and the line ---------------------------------------------------------

func _make_rod() -> void:
	if is_instance_valid(_rod):
		_rod.queue_free()
	_rod_joints.clear()
	_rod = Node3D.new()
	_rod.name = "Rod"
	_rod.position = Vector3(0.3, -0.38, -0.45)
	_rod.rotation = Vector3(0.5, -0.06, 0.0)
	if _eyes:
		_eyes.add_child(_rod)
	else:
		_walker.add_child(_rod)
	var cork := PS1Material.make(Color(0.62, 0.48, 0.32))
	var blank := PS1Material.make(Color(0.12, 0.13, 0.14) if FieldJournal.rod > 0 else Color(0.5, 0.36, 0.22))
	var handle := _rod_part(0.022, 0.018, 0.4, cork)
	handle.position = Vector3(0, 0, 0.15)
	_rod.add_child(handle)
	var reel := MeshInstance3D.new()
	var reel_mesh := CylinderMesh.new()
	reel_mesh.top_radius = 0.045
	reel_mesh.bottom_radius = 0.045
	reel_mesh.height = 0.04
	reel_mesh.radial_segments = 10
	reel.mesh = reel_mesh
	reel.material_override = PS1Material.make(Color(0.55, 0.56, 0.58) if FieldJournal.rod < 2 else Color(0.75, 0.62, 0.3))
	reel.position = Vector3(0, -0.06, 0.12)
	reel.rotation.z = PI * 0.5
	_rod.add_child(reel)
	# The blank in four pieces that bend at the joins.
	var parent: Node3D = _rod
	var at := Vector3(0, 0, -0.05)
	var r := 0.014
	for i in 4:
		var joint := Node3D.new()
		joint.position = at
		parent.add_child(joint)
		var piece := _rod_part(r, r * 0.7, 0.42, blank)
		piece.position = Vector3(0, 0, -0.21)
		joint.add_child(piece)
		_rod_joints.append(joint)
		parent = joint
		at = Vector3(0, 0, -0.42)
		r *= 0.7
	_rod_tip = Node3D.new()
	_rod_tip.position = Vector3(0, 0, -0.42)
	parent.add_child(_rod_tip)


func _rod_part(r0: float, r1: float, length: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = r0
	c.top_radius = r1
	c.height = length
	c.radial_segments = 6
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	m.rotation.x = -PI * 0.5
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Bend the rod: negative pulls the tip down and forward.
func _bend(amount: float) -> void:
	for i in _rod_joints.size():
		_rod_joints[i].rotation.x = amount * (0.12 + 0.1 * i)


func _make_float() -> Node3D:
	var root := Node3D.new()
	root.name = "Float"
	# Bigger than life, so it reads at twenty metres in the lo-fi picture.
	root.scale = Vector3.ONE * 1.8
	var body := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.06
	ball.height = 0.14
	ball.radial_segments = 8
	ball.rings = 4
	body.mesh = ball
	body.material_override = PS1Material.make(Color(0.92, 0.3, 0.12))
	root.add_child(body)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.008
	stem_mesh.bottom_radius = 0.012
	stem_mesh.height = 0.16
	stem_mesh.radial_segments = 4
	stem.mesh = stem_mesh
	# A little glow stick on top, for after dark.
	stem.material_override = PS1Material.glowing(Color(0.55, 1.0, 0.45), 1.6)
	stem.position = Vector3(0, 0.12, 0)
	root.add_child(stem)
	return root


func _float_at(p: Vector3) -> void:
	_float.global_position = p


func _draw_line() -> void:
	_line_mesh.clear_surfaces()
	if not is_instance_valid(_rod_tip) or not _float.visible and state != State.LANDED:
		return
	var a := _rod_tip.global_position
	var b := _float.global_position + Vector3.UP * 0.06
	if state == State.LANDED and is_instance_valid(_held):
		b = _held.global_position
	# A little sag, less as the line comes tight.
	var sag := (1.0 - tension) * minf(a.distance_to(b) * 0.06, 1.2)
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 13:
		var t := i / 12.0
		_line_mesh.surface_add_vertex(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	_line_mesh.surface_end()


## The catch held up in front of you.
func _show_held(c: Dictionary) -> void:
	_drop_held()
	var f := FieldJournal.fish_species(String(c.species))
	var cm := float(c.get("cm", 20.0))
	if String(f.get("model", "")) == "hubcap":
		cm = 30.0
	_held = FishModels.sized(f, cm)
	_held.name = "Catch"
	var reach := maxf(0.55, cm / 100.0 * 1.1)
	_held.position = Vector3(0.0, -0.1 - cm / 100.0 * 0.12, -reach)
	_held.rotation.y = PI * 0.5
	var host: Node3D = _eyes if _eyes else _walker
	host.add_child(_held)
	_held_light = OmniLight3D.new()
	_held_light.light_energy = 0.4 + (1.0 - GameClock.daylight()) * 1.2
	_held_light.omni_range = reach * 2.5
	_held_light.position = Vector3(0, 0.3, -reach * 0.4)
	host.add_child(_held_light)


func _drop_held() -> void:
	if is_instance_valid(_held):
		_held.queue_free()
	if is_instance_valid(_held_light):
		_held_light.queue_free()
	_held = null
	_held_light = null


func _say(text: String) -> void:
	if screen:
		screen.say(text)
	else:
		Activities.say(text)


func _sound(sound_name: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play_2d") and (not audio.has_method("has") or audio.has(sound_name)):
		audio.play_2d(sound_name, "UI", -6.0)
