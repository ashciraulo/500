class_name OtherHouse
extends Node3D
## The other house (STORY.md, event 1). From outside, late at night, your
## townhouse looks exactly as you left it. Open the front door or the sliding
## door and it's 1979 inside: the Dorans' house (House1979), the walls papered,
## brown carpet, the fire going, Mick's radio on the midnight station. Step
## back out and shut the door, and it's yours again.
##
## Only the door shows it. From outside, the windows always show your own
## house, even with the door wide open; it's 1979 only through the doorway,
## and all round you once you step in.
##
## The look is the late city's: the deck clicks on and the tape hisses as the
## door opens, and the light goes sodium once you're in. Act 2 on, once the
## first tape has turned up, at most once every few nights, never in cozy mode.
##
## From act 3 it's the second form: the same house abandoned since 1979
## (HouseAbandoned), dust sheets and leaves and a stain down the stairwell,
## the porch switch taped on, and a cassette on the stairs.

const EVENT := &"other_house"
const FROM_ACT := 2
const EVERY_DAYS := 3
## The doors in from outside.
const DOORS := [&"Door_Front", &"Door_Sliding"]
## The house box in its own frame (x across, y back, z up), and how far past
## it (m) counts as outside again.
const BOX_MIN := Vector3(-0.1, -0.05, 0.0)
const BOX_MAX := Vector3(5.5, 12.1, 6.0)
const OUT_MARGIN := 0.6
## Walk this far (m) from the house with a door left open and it lets go.
const LET_GO := 15.0
## The 1979 house's render layer, so today's lamps can leave it alone.
const LAYER_1979 := 1 << 16
## A door's opening is its leaf plus this much each side (m), and counts as
## shut once it's had this long (s) to swing to.
const OPENING_MARGIN := 0.05
const DOOR_SWING := 0.7
## Standing within this much (m) of an open doorway counts as inside.
const DOORWAY := 0.4
## The shell's materials and what they become in 1979.
const RETINT := {
	&"WallPaint": "wallpaper", &"Carpet": "carpet", &"Jarrah": "carpet",
	&"StairCarpet": "carpet", &"FloorTiles": "lino", &"Ceiling": "ceiling",
	&"WallTiles": "tiles", &"Firebox": "firebox",
}

## Tests and the dev panel: ignore the act, the clock and the gap between nights.
var force := false
var last_day := -100
## Which house is behind the door: &"1979" (act 2) or &"abandoned" (act 3 on).
## Tests can set `force_form`.
var form: StringName = &"1979"
var force_form: StringName = &""

var _home: HomeBase
var _active := false
var _dressing: House1979   # or HouseAbandoned
## 0 off, 1 looking in from outside, 2 inside (what the shader is told).
var portal_mode := 0
var _overrides: Array = []   # [MeshInstance3D, surface, previous override]
var _dimmed: Array = []      # [Light3D, previous cull mask]: lamps kept off the other side
var _flat_today: Array[GeometryInstance3D] = []  # no PS1 material: hidden while you're inside
var _flat_1979: Array[GeometryInstance3D] = []   # (labels): shown only while you're inside
var _copies: Array[MeshInstance3D] = []          # the shell's papered copies
var _shelved: Array[Node] = []   # today's interactables in the house (the cat's bowl...): out of reach in 1979
var _openings := {}          # door -> {centre, right, half_w, up, half_h} (world)
var _shut_at := {}           # door -> when it was shut (s), while it swings to
var _was_inside := false
var _clock := 0.0            # game seconds, for the doors' swing
var _late_cache := {}
var _papered_cache := {}
var _plain_cache := {}       # plain material -> its PS1 stand-in
static var _late_shader: Shader
var _materials := {}         # "wallpaper" -> ShaderMaterial
var _radio: AudioStreamPlayer3D
var _out_time := 0.0
var _check := 0.0
var _took_drawing := false
var _took_tape := false


func _ready() -> void:
	add_to_group(&"interactables")
	SaveGame.register("other_house", self)


func _exit_tree() -> void:
	SaveGame.unregister("other_house")
	if _radio:
		_radio.stop()


func _process(delta: float) -> void:
	_clock += delta
	if _home == null or not is_instance_valid(_home):
		_check -= delta
		if _check > 0.0:
			return
		_check = 1.0
		_home = get_tree().get_first_node_in_group(&"home_base") as HomeBase
		if _home:
			_home.door_toggled.connect(_on_door)
			_home.slept.connect(func(_d: int) -> void: swap_out())
		return
	if not _active:
		return
	_update_view(delta)
	# Back outside with the doors shut, or well clear of the house: it's yours again.
	var eyes := _eyes()
	var inside := eyes != null and _in_box(eyes.global_position, -OUT_MARGIN)
	if eyes == null or not inside:
		_out_time += delta
		var shut := true
		for d in DOORS:
			shut = shut and not _door_showing(d)
		var far := eyes == null or not _in_box(eyes.global_position, LET_GO)
		if _out_time > 0.4 and (shut or far):
			swap_out()
	else:
		_out_time = 0.0


func is_active() -> bool:
	return _active


func can_start() -> bool:
	if _active or _home == null or Settings.cozy_mode:
		return false
	if force:
		return not LateCity.active()
	if Story.act() < FROM_ACT or not Discoveries.has("mystery/tape_1"):
		return false
	if GameClock.day < last_day + EVERY_DAYS:
		return false
	return LateCity.allowed_now(true)


func _on_door(door: StringName, open: bool) -> void:
	if not open or not door in DOORS or not can_start():
		return
	var eyes := _eyes()
	if eyes == null or _in_box(eyes.global_position, -OUT_MARGIN):
		return  # opened from inside: nothing changes
	swap_in()


## Make the inside 1979 (also called by tests). From outside, only what you
## see through the open door is 1979; the windows still show your house.
func swap_in() -> void:
	if _active or _home == null or not LateCity.begin(EVENT):
		return
	_active = true
	_out_time = 0.0
	_was_inside = false
	last_day = GameClock.day
	_measure_doors()
	_today_aside()
	_shelve_today()
	form = force_form if force_form != &"" else (&"abandoned" if Story.act() >= 3 else &"1979")
	_retint(true)
	if form == &"abandoned":
		var empty := HouseAbandoned.new()
		empty.tidy = Story.gentle()
		empty.took_tape = _took_tape
		_dressing = empty
	else:
		_dressing = House1979.new()
	_home.add_child(_dressing)
	_dress_1979(_dressing)
	_update_view(0.0)
	LateCity.set_hiss(true)
	if form == &"abandoned":
		Discoveries.discover("oddity/other_house_abandoned")
		Story.log_night(&"other_house_abandoned",
			"Opened the door and the house was empty, like nobody had lived there since 1979: dust sheets, leaves in the hall, the porch light switch taped on.")
		return
	_play_radio()
	Discoveries.discover("oddity/other_house_1979")
	Story.log_night(&"other_house_1979",
		"Opened the door and it was 1979 inside: orange lamps, brown carpet, the fire going, a child's drawings on the fridge.")


## Back to your own house.
func swap_out() -> void:
	if not _active:
		return
	_active = false
	for o: Array in _overrides:
		if is_instance_valid(o[0]):
			(o[0] as MeshInstance3D).set_surface_override_material(o[1], o[2])
	_overrides.clear()
	for d: Array in _dimmed:
		if is_instance_valid(d[0]):
			(d[0] as Light3D).light_cull_mask = d[1]
	_dimmed.clear()
	for n in _flat_today:
		if is_instance_valid(n):
			n.visible = true
	_flat_today.clear()
	_flat_1979.clear()
	for n in _shelved:
		if is_instance_valid(n):
			n.add_to_group(&"interactables")
	_shelved.clear()
	for n in _copies:
		if is_instance_valid(n):
			n.queue_free()
	_copies.clear()
	if _dressing:
		_dressing.queue_free()
		_dressing = null
	if _radio:
		_radio.stop()
		_radio.queue_free()
		_radio = null
	portal_mode = 0
	RenderingServer.global_shader_parameter_set(&"late_portal", 0.0)
	LateCity.end(EVENT)


## Today's things you can use (the cat's bowl, the answering machine...)
## can't be used in 1979: out of the interactables group until it's over.
func _shelve_today() -> void:
	for n in get_tree().get_nodes_in_group(&"interactables"):
		if n == self or not n.has_method("interact_point"):
			continue
		if _in_box(n.interact_point(), 0.0):
			n.remove_from_group(&"interactables")
			_shelved.append(n)


# --- Taking the drawing (interactables) ------------------------------------------

func interact_point() -> Vector3:
	if not _active or _home == null:
		return Vector3(0, -10000, 0)
	if form == &"abandoned":
		return Vector3(0, -10000, 0) if _took_tape else _home.to_global(House1979.at(HouseAbandoned.TAPE_AT))
	return Vector3(0, -10000, 0) if _took_drawing else _home.to_global(House1979.at(House1979.DRAWING_AT))


func interact_hint() -> String:
	if not _active:
		return ""
	if form == &"abandoned":
		return "" if _took_tape else "Pick up the cassette"
	return "" if _took_drawing else "Take the drawing"


func interact() -> void:
	if not _active:
		return
	if form == &"abandoned":
		_take_tape()
		return
	if _took_drawing:
		return
	_took_drawing = true
	if _dressing and _dressing.drawing:
		_dressing.drawing.visible = false
	Story.set_flag(&"drawing_1979")
	Notices.post("A child's drawing in crayon: a small round car, a lane, a shed. Signed ROBYN, 8.", "odd")
	Story.log_night(&"drawing_1979", "Took a drawing off the 1979 fridge. A little round car, the lane, the shed. ROBYN, 8.")


## The cassette on the stairs: Mick on the lookouts (LookoutSignal).
func _take_tape() -> void:
	if _took_tape:
		return
	_took_tape = true
	var empty := _dressing as HouseAbandoned
	if empty and empty.tape:
		empty.tape.visible = false
	Discoveries.discover(HouseAbandoned.CLUE)
	Notices.post("A cassette on the stairs: NIGHT DRIVE 6. Mick, quietly: \"From the lookouts. Fraser Avenue, Forrest Drive. Three flashes of the headlights, and wait.\" (Hold K to flash.)", "odd")
	Story.log_night(&"stairs_tape", "Found NIGHT DRIVE 6 on the stairs of the empty house. Mick says to flash the headlights three times from the lookouts, and wait.")


# --- Inside ---------------------------------------------------------------------
#
# Nothing is hidden or swapped wholesale: today's things inside the house and
# the 1979 house are both there, each with a copy of the PS1 shader that has
# LATE_SIDES on (late_side 1 and 2). The shader works out, per pixel, whether
# you're looking at it through an open door from outside (or are inside) and
# shows the 1979 side there, today's side everywhere else. So through the
# windows it's always your house, even with the door wide open. Lamps only
# light their own side.

## Where each door's opening is (world), measured with the door shut.
func _measure_doors() -> void:
	_openings.clear()
	var doors: Variant = _home.get("_doors")
	for d: StringName in DOORS:
		if not (doors is Dictionary) or not (doors as Dictionary).has(d):
			continue
		var leaf: Node3D = doors[d].node
		var rest: Transform3D = doors[d].rest
		var parent := leaf.get_parent() as Node3D
		# The leaf's meshes, in the house's own space, as if it were shut.
		var to_home := _home.global_transform.affine_inverse() * parent.global_transform * rest
		var box := AABB()
		var first := true
		for mi in _meshes(leaf):
			var local := leaf.global_transform.affine_inverse() * mi.global_transform
			var b: AABB = to_home * (local * mi.get_aabb())
			box = b if first else box.merge(b)
			first = false
		if first:
			continue
		var size := box.size
		var thin := 0 if size.x < size.z else 2
		var across := Vector3.RIGHT if thin == 2 else Vector3.BACK
		var half_w := (size.z if thin == 0 else size.x) * 0.5 + OPENING_MARGIN
		var half_h := size.y * 0.5 + OPENING_MARGIN
		var basis := _home.global_basis
		_openings[d] = {
			"centre": _home.to_global(box.get_center()),
			"right": (basis * across).normalized(), "half_w": half_w,
			"up": (basis * Vector3.UP).normalized(), "half_h": half_h,
		}


## True while a door is open, and for as long as it takes to swing shut.
func _door_showing(d: StringName) -> bool:
	if _home.is_door_open(d):
		_shut_at[d] = -1.0
		return true
	var t: float = _shut_at.get(d, -1.0)
	var now := _clock
	if t < 0.0:
		_shut_at[d] = now
		return true
	return now - t < DOOR_SWING


## Tell the shader where the doors are and which side of them you are.
func _update_view(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var inside := cam != null and _past_threshold(cam.global_position)
	portal_mode = 2 if inside else 1
	RenderingServer.global_shader_parameter_set(&"late_portal", float(portal_mode))
	var names := [&"late_door_a", &"late_door_b"]
	for i in DOORS.size():
		var base: String = names[i]
		var o: Dictionary = _openings.get(DOORS[i], {})
		var open := not o.is_empty() and _door_showing(DOORS[i])
		var c: Vector3 = o.get("centre", Vector3.ZERO)
		var r: Vector3 = o.get("right", Vector3.RIGHT)
		var u: Vector3 = o.get("up", Vector3.UP)
		RenderingServer.global_shader_parameter_set(StringName(base + "_c"), Vector4(c.x, c.y, c.z, 1.0 if open else 0.0))
		RenderingServer.global_shader_parameter_set(StringName(base + "_r"), Vector4(r.x, r.y, r.z, o.get("half_w", 0.0)))
		RenderingServer.global_shader_parameter_set(StringName(base + "_u"), Vector4(u.x, u.y, u.z, o.get("half_h", 0.0)))
	for n in _flat_today:
		if is_instance_valid(n):
			n.visible = not inside
	for n in _flat_1979:
		if is_instance_valid(n):
			n.visible = inside
	if inside and not _was_inside:
		_was_inside = true
		LateCity.fade_look(1.0, 1.2)


## Inside the house, or standing in an open doorway (so the camera's near
## plane never cuts the opening as you step through).
func _past_threshold(p: Vector3) -> bool:
	if _in_box(p, 0.0):
		return true
	for d: StringName in _openings:
		if not _door_showing(d):
			continue
		var o: Dictionary = _openings[d]
		var h: Vector3 = p - o.centre
		var n: Vector3 = (o.right as Vector3).cross(o.up)
		if absf(h.dot(n)) < DOORWAY and absf(h.dot(o.right)) < float(o.half_w) + 0.1 \
				and absf(h.dot(o.up)) < float(o.half_h) + 0.1:
			return true
	return false


## Today's things inside the house get the today side of the shader, and the
## lamps stop lighting the 1979 side.
func _today_aside() -> void:
	var shell := _home.get_node_or_null(^"House")
	var world := _home.get_parent()
	while world and not (world.name == &"World"):
		world = world.get_parent()
	if world == null:
		world = _home.get_parent()
	var skip := [shell, _home.get_node_or_null(^"Site")]
	for name in [&"PerthMap", &"Traffic", &"Car", &"CameraRig", &"Player"]:
		skip.append(world.get_node_or_null(NodePath(String(name))))
	_dimmed.clear()
	_collect(world, skip)
	# The house itself sits under the map (MapStreamer's Home), so its own
	# furniture is gone through separately.
	if world.is_ancestor_of(_home) and skip.any(func(n: Variant) -> bool: return n is Node and n.is_ancestor_of(_home)):
		_collect(_home, skip)
	# Today's lamps belong to the shell (HomeBase turns them on by the clock).
	if shell:
		for l in _lights(shell):
			if _in_box(l.global_position, 0.0):
				_dim(l)


func _dim(l: Light3D) -> void:
	_dimmed.append([l, l.light_cull_mask])
	l.light_cull_mask &= ~LAYER_1979


static func _lights(node: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	if node is Light3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_lights(c))
	return out


func _collect(node: Node, skip: Array) -> void:
	for c in node.get_children():
		if c in skip or c == self or c == _dressing:
			continue
		if c is Light3D:
			if _in_box((c as Light3D).global_position, 0.0):
				_dim(c)
		elif c is GeometryInstance3D and (c as Node3D).visible:
			var g := c as GeometryInstance3D
			if _in_box(g.global_transform * g.get_aabb().get_center(), 0.0):
				if not _side(g, 1):
					_flat_today.append(g)
		_collect(c, skip)


## Give a mesh's PS1 surfaces their `side` copy. False if it has none.
func _side(g: GeometryInstance3D, side: int) -> bool:
	if g.material_override is ShaderMaterial and (g.material_override as ShaderMaterial).shader == PS1Model.SHADER:
		g.material_override = late_material(g.material_override, side)
		return true
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return false
	var any := false
	var plain: Array[int] = []
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i)
		if m is ShaderMaterial and (m as ShaderMaterial).shader == PS1Model.SHADER:
			_overrides.append([mi, i, mi.get_surface_override_material(i)])
			mi.set_surface_override_material(i, late_material(m, side))
			any = true
		elif m is BaseMaterial3D:
			plain.append(i)
	# A mesh that's mostly PS1 with a stray plain surface (the canisters' lids):
	# that surface gets a PS1 stand-in in its colour, so it keeps to its side too.
	if any:
		for i in plain:
			var m := mi.get_active_material(i) as BaseMaterial3D
			if not _plain_cache.has(m):
				_plain_cache[m] = PS1Material.make(m.albedo_color)
			_overrides.append([mi, i, mi.get_surface_override_material(i)])
			mi.set_surface_override_material(i, late_material(_plain_cache[m], side))
	return any


## The 1979 house: the 1979 side, lit only by its own lamps.
func _dress_1979(node: Node) -> void:
	for c in node.get_children():
		if c is Light3D:
			(c as Light3D).light_cull_mask = LAYER_1979
		elif c is GeometryInstance3D:
			var g := c as GeometryInstance3D
			g.layers = LAYER_1979
			if not _side(g, 2):
				_flat_1979.append(g)
		_dress_1979(c)


## The shell's walls, floors and ceilings: today's paint where it's today, and
## a copy of just those surfaces papered and carpeted for 1979.
func _retint(on: bool) -> void:
	if not on:
		return
	var shell := _home.get_node_or_null(^"House")
	if shell == null:
		return
	for mi in _meshes(shell):
		if String(mi.name).begins_with("Door") or mi.name == &"Late1979":
			continue
		var surfaces: Array[int] = []
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null and RETINT.has(StringName(m.resource_name)):
				surfaces.append(i)
		if surfaces.is_empty():
			continue
		var copy := MeshInstance3D.new()
		copy.name = "Late1979"
		copy.mesh = _papered(mi.mesh, surfaces)
		copy.layers = LAYER_1979
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(copy)
		_copies.append(copy)
		for i in surfaces:
			var m := mi.get_active_material(i)
			if m is ShaderMaterial:
				_overrides.append([mi, i, mi.get_surface_override_material(i)])
				mi.set_surface_override_material(i, late_material(m, 1))


## Just the papered surfaces of `mesh`, in their 1979 materials (kept for next time).
func _papered(mesh: Mesh, surfaces: Array[int]) -> ArrayMesh:
	var key := "%d:%s" % [mesh.get_instance_id(), form]
	if _papered_cache.has(key):
		return _papered_cache[key]
	var out := ArrayMesh.new()
	for i in surfaces:
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), mesh.surface_get_arrays(i))
		var kind: String = RETINT[StringName(mesh.surface_get_material(i).resource_name)]
		out.surface_set_material(out.get_surface_count() - 1, late_material(_material(kind), 2))
	_papered_cache[key] = out
	return out


## A copy of a PS1 material on the late-sides shader, showing `side`.
func late_material(source: ShaderMaterial, side: int) -> ShaderMaterial:
	var key := "%d:%d" % [source.get_instance_id(), side]
	if _late_cache.has(key):
		return _late_cache[key]
	var m := ShaderMaterial.new()
	m.shader = late_shader()
	for u: Dictionary in source.shader.get_shader_uniform_list():
		m.set_shader_parameter(u.name, source.get_shader_parameter(u.name))
	m.set_shader_parameter("late_side", side)
	m.resource_name = source.resource_name
	for meta in source.get_meta_list():
		m.set_meta(meta, source.get_meta(meta))
	_late_cache[key] = m
	return m


## The PS1 shader with LATE_SIDES on (built once, from the same source).
static func late_shader() -> Shader:
	if _late_shader == null:
		_late_shader = Shader.new()
		_late_shader.code = PS1Model.SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define LATE_SIDES")
	return _late_shader


func _material(kind: String) -> ShaderMaterial:
	var key := "%s:%s" % [kind, form]
	if _materials.has(key):
		return _materials[key]
	var m: ShaderMaterial
	if form == &"abandoned":
		m = _abandoned_material(kind)
		m.set_meta(&"late_1979", true)
		_materials[key] = m
		return m
	match kind:
		"wallpaper":
			m = PS1Material.textured(_pattern(Color(0.8, 0.62, 0.32), Color(0.55, 0.33, 0.14), "flowers"), Color.WHITE, Vector2(3, 3))
		"carpet":
			m = PS1Material.textured(_pattern(Color(0.5, 0.32, 0.14), Color(0.42, 0.26, 0.11), "shag"), Color.WHITE, Vector2(4, 4))
		"lino":
			m = PS1Material.textured(_pattern(Color(0.78, 0.5, 0.2), Color(0.55, 0.32, 0.12), "check"), Color.WHITE, Vector2(4, 4))
		"ceiling":
			m = PS1Material.make(Color(0.84, 0.77, 0.6))
		"tiles":
			m = PS1Material.textured(_pattern(Color(0.56, 0.6, 0.3), Color(0.44, 0.48, 0.22), "check"), Color.WHITE, Vector2(6, 6))
		"firebox":
			m = PS1Material.glowing(Color(0.9, 0.38, 0.1), 1.6)
		_:
			m = PS1Material.make(Color(0.5, 0.4, 0.3))
	m.set_meta(&"late_1979", true)
	_materials[key] = m
	return m


## The same house after decades shut up: the wallpaper faded and stained,
## the carpet gone to bare boards, the lino worn, the ceiling grey. Tidy (on
## Gentle) is the same, clean.
func _abandoned_material(kind: String) -> ShaderMaterial:
	var tidy := Story.gentle()
	match kind:
		"wallpaper":
			return PS1Material.textured(_pattern(Color(0.66, 0.6, 0.48), Color(0.5, 0.42, 0.32), "flowers" if tidy else "faded"), Color.WHITE, Vector2(3, 3))
		"carpet":
			return PS1Material.textured(_pattern(Color(0.42, 0.34, 0.26), Color(0.3, 0.24, 0.18), "boards"), Color.WHITE, Vector2(2, 2))
		"lino":
			return PS1Material.textured(_pattern(Color(0.6, 0.5, 0.36), Color(0.46, 0.38, 0.28), "check"), Color.WHITE, Vector2(4, 4))
		"ceiling":
			return PS1Material.make(Color(0.6, 0.58, 0.52) if not tidy else Color(0.74, 0.72, 0.66))
		"tiles":
			return PS1Material.textured(_pattern(Color(0.5, 0.52, 0.42), Color(0.4, 0.42, 0.34), "check"), Color.WHITE, Vector2(6, 6))
		"firebox":
			return PS1Material.make(Color(0.08, 0.07, 0.06))
	return PS1Material.make(Color(0.45, 0.4, 0.34))


## Little 32 px patterns, drawn here so there are no files to keep in step:
## seventies flowers on wallpaper, flecked shag, a lino check.
static func _pattern(base: Color, ink: Color, kind: String) -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"flowers":
			# Big round seventies flowers in a half-drop, with stripes between.
			for x in n:
				if x % 16 == 0 or x % 16 == 1:
					for y in n:
						img.set_pixel(x, y, base.lerp(ink, 0.35))
			for c: Vector2i in [Vector2i(8, 8), Vector2i(24, 24)]:
				for y in range(-6, 7):
					for x in range(-6, 7):
						var d := Vector2(x, y).length()
						var p := Vector2i(posmod(c.x + x, n), posmod(c.y + y, n))
						if d < 2.0:
							img.set_pixel(p.x, p.y, Color(0.9, 0.75, 0.35))
						elif d < 5.5 and int(atan2(y, x) * 3.0 / PI + 6.0) % 2 == 0:
							img.set_pixel(p.x, p.y, ink)
		"shag":
			for i in 260:
				var x := rng.randi_range(0, n - 1)
				var y := rng.randi_range(0, n - 1)
				img.set_pixel(x, y, ink if rng.randf() < 0.7 else base.lightened(0.12))
		"check":
			for y in n:
				for x in n:
					if (x / 8 + y / 8) % 2 == 0:
						img.set_pixel(x, y, ink)
		"faded":
			# The flowers gone to ghosts, and brown damp blooms over them.
			for c: Vector2i in [Vector2i(8, 8), Vector2i(24, 24)]:
				for y in range(-6, 7):
					for x in range(-6, 7):
						var d := Vector2(x, y).length()
						var p := Vector2i(posmod(c.x + x, n), posmod(c.y + y, n))
						if d < 5.5 and int(atan2(y, x) * 3.0 / PI + 6.0) % 2 == 0:
							img.set_pixel(p.x, p.y, base.lerp(ink, 0.45))
			for i in 4:
				var c := Vector2(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1))
				var r := rng.randf_range(3.0, 7.0)
				for y in n:
					for x in n:
						if Vector2(x, y).distance_to(c) < r and rng.randf() < 0.7:
							img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.18))
		"boards":
			# Bare floorboards: long planks with dark seams and the odd knot.
			for y in n:
				for x in n:
					if y % 8 == 0:
						img.set_pixel(x, y, ink.darkened(0.3))
					elif (x + (y / 8) * 11) % 32 == 0:
						img.set_pixel(x, y, ink)
					elif rng.randf() < 0.08:
						img.set_pixel(x, y, base.lerp(ink, 0.5))
	return ImageTexture.create_from_image(img)


func _play_radio() -> void:
	if not Audio.has("oddity/odd_midnight_station"):
		return
	_radio = AudioStreamPlayer3D.new()
	_radio.stream = Audio.variant("oddity/odd_midnight_station")
	_radio.bus = "SFX"
	_radio.unit_size = 2.0
	_radio.max_distance = 18.0
	_radio.volume_db = -6.0
	_home.add_child(_radio)
	_radio.position = House1979.at(House1979.RADIO_AT)
	_radio.finished.connect(func() -> void:
		if _radio and _active:
			_radio.stream = Audio.variant("oddity/odd_midnight_station")
			_radio.play())
	_radio.play()


func _in_box(world_pos: Vector3, margin: float) -> bool:
	var p := _home.global_transform.affine_inverse() * world_pos
	var b := Vector3(p.x, -p.z, p.y)
	return b.x >= BOX_MIN.x - margin and b.x <= BOX_MAX.x + margin \
		and b.y >= BOX_MIN.y - margin and b.y <= BOX_MAX.y + margin \
		and b.z >= BOX_MIN.z - margin and b.z <= BOX_MAX.z + margin


func _eyes() -> Node3D:
	var player := get_tree().root.find_child("Player", true, false) as Node3D
	if player == null or player.get("in_car") != false:
		return null
	var cam := player.get_viewport().get_camera_3d()
	return cam if cam else player


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


func save_state() -> Dictionary:
	return {"last_day": last_day, "took_drawing": _took_drawing, "took_tape": _took_tape}


func load_state(data: Dictionary) -> void:
	last_day = int(data.get("last_day", -100))
	_took_drawing = bool(data.get("took_drawing", false))
	_took_tape = bool(data.get("took_tape", false))
