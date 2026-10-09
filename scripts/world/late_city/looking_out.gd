class_name LookingOut
extends Node3D
## Looking out (STORY.md, event 6): the other house the other way round.
## You're at home after midnight with the doors shut, and the deck clicks on.
## Look out of a front window and outside isn't right:
##
##   act 3   the lane is 1979: round tin bins at the gates, a sodium lamp, and
##           a small round car at the kerb outside with its parkers on.
##   act 4   nothing at all. Deep blue-black, like the empty road, and one
##           streetlamp. Only the house is there.
##
## Open any door to the outside and the lane is there again, and the deck
## clunks off. It also lets go if you sleep, or when the night's over. On
## Gentle, act 4 is thick dark fog rather than nothing.

const EVENT := &"looking_out"
const FROM_ACT := 3
const EVERY_DAYS := 3
const CHANCE := 0.5
## Doors to the outside: opening any of them lets it go.
const OUT_DOORS := [&"Door_Front", &"Door_Sliding", &"Door_French_L", &"Door_French_R", &"Door_Balcony_L", &"Door_Balcony_R"]
## Inside this long (s) with the doors shut before it may start, and only
## while you aren't looking towards the front of the house.
const SETTLE := 20.0
const FACING_FRONT := 0.3
## It lets go by itself after this long (s).
const LASTS := 360.0
## In the house's frame (x across, y back from the lane, z up): Mick's car
## across the lane, its nose towards +x; a Valiant outside number 17; the tin
## bins at the gates; the lamp.
const CAR_AT := Vector3(2.2, -7.9, 0.0)
const VALIANT_AT := Vector3(8.4, -5.4, 0.0)
const BINS_AT := [Vector3(-0.2, -3.6, 0.0), Vector3(1.9, -3.6, 0.0), Vector3(6.4, -3.6, 0.0), Vector3(-4.0, -3.6, 0.0)]
const LAMP_AT := Vector3(4.2, -9.6, 0.0)
## In 1979 the lane has sodium lamps all along it, across the way, and one
## right outside the front fence (its arm over the lane) that isn't there now.
const LAMPS_1979 := [Vector3(-7.0, -9.6, 0.0), Vector3(3.0, -9.6, 0.0), Vector3(12.0, -9.6, 0.0)]
const LAMP_OUTSIDE := Vector3(5.4, -3.7, 0.0)
## The windows when there's nothing out there: deep blue-black glass. In 1979
## the glass is clear and dark, so the sodium light outside shows through
## rather than the house's own lamps greying it.
const NIGHT_GLASS := Color(0.008, 0.012, 0.035, 0.3)
const CLEAR_GLASS := Color(0.02, 0.018, 0.016, 0.22)
## The materials of the glass to the outside (not the shower's, or a glass of water).
const GLASS_NAMES := [&"WindowGlass", &"DoorGlass"]
const CAR := "res://art/models/cars/classic_l/classic_l.glb"
const VALIANT := "res://art/models/vehicles/period/valiant.glb"
const SODIUM := Color(1.0, 0.62, 0.28)
const PARKER := Color(1.0, 0.86, 0.6)
const SKY := Color(0.012, 0.016, 0.04)
const GENTLE_FOG := 0.08
const VOID_FOG := 0.02
const FADE := 3.0

## Tests and the dev panel: ignore the act, the hour, the odds and the gap.
var force := false
var last_day := -100
## What's out there now: &"" (the lane), &"1979" or &"nothing".
var form: StringName = &""

var _home: HomeBase
var _check := 0.0
var _settled := 0.0
var _rolled_night := -1
var _tonight := false
var _t := 0.0
var _outside: Node3D
var _hidden: Array[Node3D] = []
var _lit: Array = []
var _glass: Array = []   # [MeshInstance3D, surface, previous override]
var _void := 0.0
var _void_tween: Tween
var _env: Environment
var _sky: ProceduralSkyMaterial


func _ready() -> void:
	process_priority = 100   # after the environment, so the void sky wins
	SaveGame.register("looking_out", self)


func _exit_tree() -> void:
	SaveGame.unregister("looking_out")
	if form != &"":
		_clear()


func _process(delta: float) -> void:
	if _home == null or not is_instance_valid(_home):
		_check -= delta
		if _check > 0.0:
			return
		_check = 1.0
		_home = get_tree().get_first_node_in_group(&"home_base") as HomeBase
		if _home:
			_home.door_toggled.connect(_on_door)
			_home.slept.connect(func(_d: int) -> void: let_go())
		return
	if form != &"":
		_t += delta
		_apply_sky()
		if _t > LASTS or (not force and GameClock.time_of_day >= LateCity.NIGHT_TO and GameClock.time_of_day < 12.0):
			let_go()
		return
	_settled = _settled + delta if _inside_and_shut() else 0.0
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if _settled > SETTLE and can_start() and not _facing_front():
		begin()


func can_start() -> bool:
	if form != &"" or _home == null or Settings.cozy_mode:
		return false
	if force:
		return not LateCity.active()
	if Story.act() < FROM_ACT or GameClock.day < last_day + EVERY_DAYS:
		return false
	if not LateCity.allowed_now(true):
		return false
	var night := GameClock.day if GameClock.time_of_day >= 12.0 else GameClock.day - 1
	if night != _rolled_night:
		_rolled_night = night
		_tonight = randf() < CHANCE
	return _tonight


## Start it (also called by tests): the 1979 lane in act 3, nothing from act 4.
func begin(which: StringName = &"") -> bool:
	if form != &"" or _home == null or not LateCity.begin(EVENT):
		return false
	form = which if which != &"" else (&"1979" if Story.act() <= 3 else &"nothing")
	last_day = GameClock.day
	_t = 0.0
	LateCity.set_hiss(true)
	LateCity.fade_look(0.5, 2.0)
	if form == &"1979":
		_lane_1979()
		Discoveries.discover("oddity/looking_out_1979")
		Story.log_night(&"looking_out_1979",
			"Looked out of the front window after midnight and the lane was 1979: tin bins at the gates, a sodium lamp, and a little round car outside with its parkers on.")
	else:
		_nothing()
		Discoveries.discover("oddity/looking_out_nothing")
		Story.log_night(&"looking_out_nothing",
			"Looked out of the window and there was nothing out there. Blue-black, and one streetlamp. I opened the door and the lane was there.")
	return true


## The lane comes back and the deck clunks off.
func let_go() -> void:
	if form == &"":
		return
	_clear()
	LateCity.end(EVENT)


func _on_door(door: StringName, open: bool) -> void:
	if open and door in OUT_DOORS:
		let_go()


func _clear() -> void:
	form = &""
	if _outside:
		_outside.queue_free()
		_outside = null
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for g: Array in _glass:
		if is_instance_valid(g[0]):
			(g[0] as MeshInstance3D).set_surface_override_material(g[1], g[2])
	_glass.clear()
	# Backwards, so anything kept twice ends up as it was.
	_lit.reverse()
	LateCity.release_lit(_lit)
	_lit.clear()
	if _void_tween:
		_void_tween.kill()
	_set_void(0.0)


# --- Act 3: the lane in 1979 -------------------------------------------------------

func _lane_1979() -> void:
	_outside = Node3D.new()
	_outside.name = "Lane1979"
	_home.add_child(_outside)
	# Your car (and the night's wheelie bins) aren't there in 1979.
	var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
	if car and _near_front(car.global_position, 18.0):
		_hide(car)
	var night := get_tree().root.find_child("Night", true, false)
	if night and night.get("bins") is Array:
		for bin: Dictionary in night.bins:
			var node: Node3D = bin.get("node")
			if node and node.visible and _near_front(node.global_position, 24.0):
				_hide(node)
	_mick_car(_outside)
	_valiant(_outside)
	for b: Vector3 in BINS_AT:
		_tin_bin(_outside, b)
	for at: Vector3 in LAMPS_1979:
		_lamp(_outside, false, at)
	_lamp(_outside, false, LAMP_OUTSIDE, true)
	_tint_glass(CLEAR_GLASS)
	LateCity.add_shimmer(_outside, 0.5)


func _mick_car(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "MickCar"
	parent.add_child(holder)
	holder.global_position = _ground(_h(CAR_AT))
	# Nose along the lane (+x in the house's frame).
	holder.global_basis = _home.global_basis * Basis(Vector3.UP, -PI * 0.5)
	if ResourceLoader.exists(CAR):
		var model := (load(CAR) as PackedScene).instantiate() as Node3D
		LateHouse.add_wheels(model)
		PS1Model.apply(model)
		holder.add_child(model)
	# Its parkers: two small warm lamps low at the front corners.
	for side: float in [-0.48, 0.48]:
		var lamp := _box(holder, Vector3(0.09, 0.06, 0.04), Vector3(side, 0.55, -1.5), PS1Material.glowing(PARKER, 2.5))
		lamp.name = "Parker"
	var glow := OmniLight3D.new()
	glow.light_color = PARKER
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	glow.position = Vector3(0, 0.6, -1.9)
	holder.add_child(glow)


## Next door's Valiant (models thread), at the kerb, nose along the lane.
func _valiant(parent: Node3D) -> void:
	if not ResourceLoader.exists(VALIANT):
		return
	var model := (load(VALIANT) as PackedScene).instantiate() as Node3D
	model.name = "Valiant"
	PS1Model.apply(model)
	parent.add_child(model)
	model.global_position = _ground(_h(VALIANT_AT))
	# Front is -Z and the kerb side -X: nose towards -x in the house's frame,
	# so its kerb side faces the houses.
	model.global_basis = _home.global_basis * Basis(Vector3.UP, PI * 0.5)


## A round galvanised bin with its lid on.
func _tin_bin(parent: Node3D, at: Vector3) -> void:
	var bin := Node3D.new()
	parent.add_child(bin)
	bin.global_position = _ground(_h(at))
	var tin := PS1Material.make(Color(0.6, 0.62, 0.6))
	var body := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.27
	c.bottom_radius = 0.25
	c.height = 0.72
	c.radial_segments = 10
	body.mesh = c
	body.material_override = tin
	body.position = Vector3(0, 0.36, 0)
	bin.add_child(body)
	var lid := MeshInstance3D.new()
	var l := CylinderMesh.new()
	l.top_radius = 0.22
	l.bottom_radius = 0.3
	l.height = 0.07
	l.radial_segments = 10
	lid.mesh = l
	lid.material_override = tin
	lid.position = Vector3(0, 0.76, 0)
	bin.add_child(lid)
	_box(bin, Vector3(0.12, 0.04, 0.03), Vector3(0, 0.82, 0), tin)


## A streetlamp across the lane: sodium in 1979, and the only thing there is
## when there's nothing (late_keep, so the void leaves it lit).
func _lamp(parent: Node3D, keep: bool, at := LAMP_AT, towards_lane := false) -> void:
	var lamp := Node3D.new()
	lamp.name = "Lamp"
	parent.add_child(lamp)
	lamp.global_position = _ground(_h(at))
	lamp.global_basis = _home.global_basis * (Basis(Vector3.UP, PI) if towards_lane else Basis())
	var pole := PS1Material.make(Color(0.3, 0.3, 0.29))
	var head := PS1Material.glowing(SODIUM, 2.4)
	if keep:
		for m in [pole, head]:
			m.set_shader_parameter("late_keep", true)
	_box(lamp, Vector3(0.14, 5.6, 0.14), Vector3(0, 2.8, 0), pole)
	# The arm over the lane, towards the house (+y in the house's frame is -z).
	_box(lamp, Vector3(0.1, 0.1, 1.6), Vector3(0, 5.55, -0.8), pole)
	_box(lamp, Vector3(0.26, 0.12, 0.5), Vector3(0, 5.45, -1.5), head)
	var light := OmniLight3D.new()
	light.light_color = SODIUM
	light.light_energy = 5.0
	light.omni_range = 20.0
	light.omni_attenuation = 1.2
	light.position = Vector3(0, 5.1, -1.5)
	lamp.add_child(light)
	# A soft glow round the head, so it reads from inside through the glass.
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	halo.mesh = quad
	halo.material_override = _halo_material(keep)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0, 5.3, -1.5)
	lamp.add_child(halo)


static func _halo_material(keep: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(SODIUM, 0.55 if keep else 0.7)
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = g
	m.albedo_texture = glow
	return m


# --- Act 4: nothing -----------------------------------------------------------------

func _nothing() -> void:
	_outside = Node3D.new()
	_outside.name = "Nothing"
	_home.add_child(_outside)
	# The house stays: everything in it is kept lit while the rest goes.
	_lit = LateCity.keep_lit(_home.get_node(^"House"))
	var interior := _home.get_node_or_null(^"Interior")
	if interior:
		_lit.append_array(LateCity.keep_lit(interior))
	var world := _home.get_parent()
	while world and world.name != &"World":
		world = world.get_parent()
	for g in _geometry(world if world else _home.get_parent()):
		if g.is_inside_tree() and _in_house(g.global_transform * g.get_aabb().get_center()) \
				and not _home.is_ancestor_of(g):
			_lit.append_array(LateCity.keep_lit(g))
	var player := get_tree().root.find_child("Player", true, false)
	if player:
		_lit.append_array(LateCity.keep_lit(player))
	_lamp(_outside, true)
	_tint_glass(NIGHT_GLASS)
	if _void_tween:
		_void_tween.kill()
	_void_tween = create_tween()
	_void_tween.tween_method(_set_void, 0.0, 1.0, FADE)


## Unshaded glass in the windows and glazed doors to the outside, so the
## house's own lamps don't grey it and what's out there shows through.
func _tint_glass(colour: Color) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colour
	for g in _geometry(_home):
		var mi := g as MeshInstance3D
		if mi == null or mi.mesh == null or (_outside and _outside.is_ancestor_of(mi)):
			continue
		for i in mi.mesh.get_surface_count():
			var was := mi.get_active_material(i)
			if mi.name == &"House_Glass" or (was and StringName(was.resource_name) in GLASS_NAMES):
				_glass.append([mi, i, mi.get_surface_override_material(i)])
				mi.set_surface_override_material(i, m)


func _set_void(v: float) -> void:
	_void = v
	RenderingServer.global_shader_parameter_set(&"late_void", 0.0 if Story.gentle() else v)


func _apply_sky() -> void:
	if _void <= 0.0:
		return
	if _env == null:
		var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if we == null:
			return
		_env = we.environment
		_sky = _env.sky.sky_material as ProceduralSkyMaterial if _env.sky else null
	var v := _void
	var fog := GENTLE_FOG if Story.gentle() else VOID_FOG
	var fog_colour := Color(0.06, 0.06, 0.07) if Story.gentle() else SKY
	_env.fog_density = lerpf(_env.fog_density, fog, v)
	_env.fog_light_color = _env.fog_light_color.lerp(fog_colour, v)
	if _sky:
		_sky.sky_top_color = _sky.sky_top_color.lerp(SKY, v)
		_sky.sky_horizon_color = _sky.sky_horizon_color.lerp(fog_colour, v)
		_sky.ground_horizon_color = _sky.ground_horizon_color.lerp(fog_colour, v)
		_sky.ground_bottom_color = _sky.ground_bottom_color.lerp(fog_colour, v)


# --- Where you are -------------------------------------------------------------------

func _inside_and_shut() -> bool:
	var player := get_tree().root.find_child("Player", true, false) as Node3D
	if player == null or player.get("in_car") != false or not _in_house(player.global_position):
		return false
	for d: StringName in OUT_DOORS:
		if _home.is_door_open(d):
			return false
	return true


func _facing_front() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var front := -(_home.global_basis * Vector3(0, 0, -1)).normalized()   # towards the lane (-y)
	return (-cam.global_basis.z).dot(front) > FACING_FRONT


func _in_house(p: Vector3) -> bool:
	var l := _home.to_local(p)
	var b := Vector3(l.x, -l.z, l.y)
	return b.x >= OtherHouse.BOX_MIN.x and b.x <= OtherHouse.BOX_MAX.x and b.y >= OtherHouse.BOX_MIN.y \
		and b.y <= OtherHouse.BOX_MAX.y and b.z >= OtherHouse.BOX_MIN.z and b.z <= OtherHouse.BOX_MAX.z


func _near_front(p: Vector3, reach: float) -> bool:
	return p.distance_to(_h(Vector3(1.0, -5.0, 0.0))) < reach


func _hide(n: Node3D) -> void:
	n.visible = false
	_hidden.append(n)


func _h(p: Vector3) -> Vector3:
	return _home.to_global(House1979.at(p))


func _ground(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0)
	var hit := _home.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else at


static func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _geometry(node: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if node is GeometryInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_geometry(c))
	return out


func save_state() -> Dictionary:
	return {"last_day": last_day}


func load_state(data: Dictionary) -> void:
	last_day = int(data.get("last_day", -100))
