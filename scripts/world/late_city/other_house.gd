class_name OtherHouse
extends Node3D
## The other house (STORY.md, event 1). From outside, late at night, your
## townhouse looks exactly as you left it. Open the front door or the sliding
## door and it's 1979 inside: the Dorans' house (House1979), the walls papered,
## brown carpet, the fire going, Mick's radio on the midnight station. Step
## back out and shut the door, and it's yours again.
##
## The look is the late city's: the deck clicks on as the door opens, the
## light goes sodium, the tape hisses, the counter turns. The windows always
## show your real house from outside, because nothing changes until a door
## opens. Act 2 on, once the first tape has turned up, at most once every few
## nights, never in cozy mode.

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
## The shell's materials and what they become in 1979.
const RETINT := {
	&"WallPaint": "wallpaper", &"Carpet": "carpet", &"Jarrah": "carpet",
	&"StairCarpet": "carpet", &"FloorTiles": "lino", &"Ceiling": "ceiling",
	&"WallTiles": "tiles", &"Firebox": "firebox",
}

## Tests and the dev panel: ignore the act, the clock and the gap between nights.
var force := false
var last_day := -100

var _home: HomeBase
var _active := false
var _dressing: House1979
var _hidden: Array[Node3D] = []
var _overrides: Array = []   # [MeshInstance3D, surface, previous override]
var _dimmed: Array = []      # [Light3D, previous cull mask]: today's lamps, switched off
var _materials := {}         # "wallpaper" -> ShaderMaterial
var _radio: AudioStreamPlayer3D
var _out_time := 0.0
var _check := 0.0
var _took_drawing := false


func _ready() -> void:
	add_to_group(&"interactables")
	SaveGame.register("other_house", self)


func _exit_tree() -> void:
	SaveGame.unregister("other_house")
	if _radio:
		_radio.stop()


func _process(delta: float) -> void:
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
	# Back outside with the doors shut, or well clear of the house: it's yours again.
	var eyes := _eyes()
	var inside := eyes != null and _in_box(eyes.global_position, -OUT_MARGIN)
	if eyes == null or not inside:
		_out_time += delta
		var shut := true
		for d in DOORS:
			shut = shut and not _home.is_door_open(d)
		var far := eyes == null or not _in_box(eyes.global_position, 4.0)
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


## Make the inside 1979 (also called by tests).
func swap_in() -> void:
	if _active or _home == null or not LateCity.begin(EVENT):
		return
	_active = true
	_out_time = 0.0
	last_day = GameClock.day
	_hide_today()
	_retint(true)
	_dressing = House1979.new()
	_home.add_child(_dressing)
	_play_radio()
	LateCity.fade_look(1.0, 0.8)
	LateCity.set_hiss(true)
	Discoveries.discover("oddity/other_house_1979")
	Story.log_night(&"other_house_1979",
		"Opened the door and it was 1979 inside: orange lamps, brown carpet, the fire going, a child's drawings on the fridge.")


## Back to your own house.
func swap_out() -> void:
	if not _active:
		return
	_active = false
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for d: Array in _dimmed:
		if is_instance_valid(d[0]):
			(d[0] as Light3D).light_cull_mask = d[1]
	_dimmed.clear()
	_retint(false)
	if _dressing:
		_dressing.queue_free()
		_dressing = null
	if _radio:
		_radio.stop()
		_radio.queue_free()
		_radio = null
	LateCity.end(EVENT)


# --- Taking the drawing (interactables) ------------------------------------------

func interact_point() -> Vector3:
	if not _active or _took_drawing or _home == null:
		return Vector3(0, -10000, 0)
	return _home.to_global(House1979.at(House1979.DRAWING_AT))


func interact_hint() -> String:
	return "Take the drawing" if _active and not _took_drawing else ""


func interact() -> void:
	if not _active or _took_drawing:
		return
	_took_drawing = true
	if _dressing and _dressing.drawing:
		_dressing.drawing.visible = false
	Story.set_flag(&"drawing_1979")
	Notices.post("A child's drawing in crayon: a small round car, a lane, a shed. Signed ROBYN, 8.", "odd")
	Story.log_night(&"drawing_1979", "Took a drawing off the 1979 fridge. A little round car, the lane, the shed. ROBYN, 8.")


# --- Inside -------------------------------------------------------------------------

## Hide everything of today's that's inside the house: the furniture, the
## decor, the lamps, the plants, the cat's bowl. The shell and its doors stay.
func _hide_today() -> void:
	_hidden.clear()
	var shell := _home.get_node_or_null(^"House")
	var world := _home.get_parent()
	while world and not (world.name == &"World"):
		world = world.get_parent()
	if world == null:
		world = _home.get_parent()
	var skip := [shell, _home.get_node_or_null(^"Site")]
	for name in [&"PerthMap", &"Traffic", &"Car", &"CameraRig", &"Player"]:
		skip.append(world.get_node_or_null(NodePath(String(name))))
	_collect(world, skip)
	# The house itself sits under the map (MapStreamer's Home), so its own
	# furniture is gone through separately.
	if world.is_ancestor_of(_home) and skip.any(func(n: Variant) -> bool: return n is Node and n.is_ancestor_of(_home)):
		_collect(_home, skip)
	# Today's lamps belong to the shell (HomeBase turns them on and off by
	# the clock), so they're switched off by what they light instead.
	_dimmed.clear()
	if shell:
		for l in _lights(shell):
			if _in_box(l.global_position, 0.0):
				_dimmed.append([l, l.light_cull_mask])
				l.light_cull_mask = 0


static func _lights(node: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	if node is Light3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_lights(c))
	return out


func _collect(node: Node, skip: Array) -> void:
	for c in node.get_children():
		if c in skip or c == self:
			continue
		if c is VisualInstance3D and (c as Node3D).visible:
			var v := c as VisualInstance3D
			var centre := v.global_transform * v.get_aabb().get_center()
			if v is Light3D:
				centre = v.global_position
			if _in_box(centre, 0.0):
				v.visible = false
				_hidden.append(v)
				continue
		_collect(c, skip)


func _retint(on: bool) -> void:
	if not on:
		for o: Array in _overrides:
			if is_instance_valid(o[0]):
				(o[0] as MeshInstance3D).set_surface_override_material(o[1], o[2])
		_overrides.clear()
		return
	var shell := _home.get_node_or_null(^"House")
	if shell == null:
		return
	for mi in _meshes(shell):
		if String(mi.name).begins_with("Door"):
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m == null or not RETINT.has(StringName(m.resource_name)):
				continue
			_overrides.append([mi, i, mi.get_surface_override_material(i)])
			mi.set_surface_override_material(i, _material(RETINT[StringName(m.resource_name)]))


func _material(kind: String) -> ShaderMaterial:
	if _materials.has(kind):
		return _materials[kind]
	var m: ShaderMaterial
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
	_materials[kind] = m
	return m


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
	return {"last_day": last_day, "took_drawing": _took_drawing}


func load_state(data: Dictionary) -> void:
	last_day = int(data.get("last_day", -100))
	_took_drawing = bool(data.get("took_drawing", false))
