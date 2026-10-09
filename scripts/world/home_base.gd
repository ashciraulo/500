class_name HomeBase
extends Node3D
## 15 Little Shenton Lane: the player's townhouse, its courtyard, the shared
## carport and the locked shed. Built in Blender (art/models/home/shenton/).
##
## Converts the imported models to PS1 materials, puts warm lamps at the
## `Light_*` markers (on after dusk), gives every door a collider that swings
## with it, and exposes doors, spawn points, the shed and the bed.
##
##   home.toggle_door(&"Door_Front")      # opens or closes; false if locked
##   home.spawn_transform(&"Spawn_Car")   # where the Pop is parked
##   home.sleep()                         # bed: skip to 7:00 the next day
##   home.sleep(HomeBase.DUSK_HOUR)       # or sleep through to dusk
##   home.unlock_shed()                   # once the player has found the key

signal door_toggled(door_name: StringName, open: bool)
signal slept(day: int)
signal shed_unlocked
## Someone tried the locked shed door. A listener may unlock it (the mystery,
## once you have the key), and then the door opens as normal.
signal shed_tried

const DOOR_OPEN_ANGLE := deg_to_rad(100.0)
## Doors that swing the other way (clockwise seen from above), so they open
## into the room (the shed door swings in, clear of the parked car). Keep in
## step with OPEN_CLOCKWISE in build_shenton.py.
const OPEN_CLOCKWISE := [&"Door_French_R", &"Door_Balcony_R", &"Shed_Door"]
const SLIDE_DISTANCE := 1.05
const WAKE_HOUR := 7.0
## Sleeping through the day: wake as the light goes (Perth dusk is about 7).
const DUSK_HOUR := 18.5
## An invisible ramp over the stair nosings so walking up and down is smooth,
## in house coordinates (Blender: x across, y back from the street, z up).
## Keep in step with the stairs in build_shenton.py.
const STAIR_X := Vector2(0.0, 1.0)
const STAIR_FOOT := Vector2(9.053, 0.15)  # (y, z) where the nosing line meets the hall floor
const STAIR_HEAD := Vector2(5.0, 3.16)    # (y, z) at the landing edge

## Roofed boxes in house coordinates [min, max], keep in step with
## build_shenton.py: the house to the ridge, the porch under the balcony, and
## the carport roof over the bays and the sheds.
const RAIN_SHELTERS := [
	[Vector3(-0.2, -0.2, -0.5), Vector3(5.6, 12.2, 7.6)],
	[Vector3(0.0, -1.6, -0.5), Vector3(5.4, -0.2, 2.9)],
	[Vector3(-0.2, 17.18, -0.5), Vector3(11.2, 23.0, 2.6)],
]

## The rooms inside, in house coordinates [min, max]: what's in here (the
## interior model and anything put in it later, furniture, decor, the cat) is
## marked indoor. The PS1 shader keeps most of the sky's fill out and warms
## what's left, and it sits on INDOOR_LAYER only, which car headlights leave
## out, so they don't shine through the walls.
const INDOOR_BOX := [Vector3(0.02, 0.02, -0.3), Vector3(5.38, 11.98, 7.4)]
const INDOOR_LAYER := 1 << 17
## The shell's surfaces that only face the rooms (the shell is one mesh, so
## these are marked per material).
const INDOOR_SURFACES := [&"WallPaint", &"Ceiling", &"Firebox", &"WallTiles", &"Jarrah", &"FloorTiles",
	&"Carpet", &"StairCarpet", &"DoorWhite"]

## Lamp colour, energy and range by marker name. Unlisted markers use DEFAULT_LAMP.
const LAMPS := {
	&"Light_Lounge_Lamp": [Color(1.0, 0.72, 0.42), 0.6, 4.0],
	&"Light_Bed1_Lamp": [Color(1.0, 0.7, 0.42), 0.5, 3.0],
	&"Light_Bed2_Desk": [Color(1.0, 0.74, 0.46), 0.5, 3.0],
	&"Light_Bar": [Color(1.0, 0.74, 0.44), 0.55, 3.5],
	&"Light_Storage": [Color(1.0, 0.85, 0.65), 0.4, 2.0],
	&"Light_Porch": [Color(1.0, 0.82, 0.55), 0.9, 5.0],
	&"Light_Courtyard": [Color(1.0, 0.8, 0.5), 1.0, 7.0],
	&"Light_Carport": [Color(0.85, 0.9, 1.0), 0.8, 6.0],
}
const DEFAULT_LAMP := [Color(1.0, 0.72, 0.44), 0.4, 4.5]
## The upstairs toilet light is never quite right.
const FLICKER_LAMP := &"Light_WC_Up"

var shed_is_unlocked := false

var _doors := {}    # StringName -> {node, rest: Transform3D, open: bool, slide: bool}
var _lamps: Array[OmniLight3D] = []
var _flicker: OmniLight3D
var _markers := {}  # StringName -> Node3D
var _indoor_mats: Array[ShaderMaterial] = []
var _indoor_copies := {}  # shared shell material -> its indoor copy
var _daylight := 0.0


func _ready() -> void:
	add_to_group(&"home_base")
	add_to_group(&"rain_shelters")
	for model in get_children():
		var mats := PS1Model.apply(model)
		if model.name == &"House":
			for m_name in INDOOR_SURFACES:
				if mats.get(m_name) is ShaderMaterial:
					_set_indoor(mats[m_name])
			_split_shell(model)
	_collect(self)
	for door_name in _doors:
		_add_door_collider(_doors[door_name].node)
	_set_collision_layers(self)
	_add_stair_ramp()
	var interior := get_node_or_null(^"Interior")
	if interior:
		_mark_indoor(interior)
	get_tree().node_added.connect(_on_node_added)
	_sweep_indoor.call_deferred()


## Anything already standing inside when the game starts (decor, furniture
## and the cat are put in by other nodes, some before this one).
func _sweep_indoor() -> void:
	var world := get_parent()
	while world and world.get_parent() and not world is SubViewport:
		world = world.get_parent()
	if world:
		_sweep_node(world)


func _sweep_node(node: Node) -> void:
	if node == get_node_or_null(^"House") or node == get_node_or_null(^"Site") or node is CarController \
			or node.name == &"PerthMap" or node.name == &"Traffic":
		return
	if node is GeometryInstance3D and _inside(node):
		_mark(node)
	for child in node.get_children():
		_sweep_node(child)


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_check_added.call_deferred(node)


func _check_added(node: GeometryInstance3D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.layers & OtherHouse.LAYER_1979 \
			or not _inside(node):
		return
	for skip in [get_node_or_null(^"House"), get_node_or_null(^"Site")]:
		if skip and skip.is_ancestor_of(node):
			return
	var n: Node = node
	while n:
		if n is CarController:
			return
		n = n.get_parent()
	_mark(node)


func _inside(g: GeometryInstance3D) -> bool:
	var p := global_transform.affine_inverse() * g.global_transform * g.get_aabb().get_center()
	return _in_box(Vector3(p.x, -p.z, p.y))  # local (x, y, z) is house (x, -z, y)


## The shell is one mesh inside and out. Its room-facing surfaces (and the
## triangles of shared ones, like the white trim, that sit inside the rooms)
## move to a child mesh on INDOOR_LAYER, so headlights light the outside
## walls but not the rooms through them; inside doors go whole.
func _split_shell(shell: Node) -> void:
	var to_house := global_transform.affine_inverse()
	for mi: MeshInstance3D in PS1Model._meshes(shell):
		if mi.mesh == null:
			continue
		if String(mi.name).begins_with("Door"):
			for i in mi.mesh.get_surface_count():
				var dm := mi.get_active_material(i)
				if dm and StringName(dm.resource_name) in INDOOR_SURFACES:
					_mark(mi)
					break
			continue
		var local := to_house * mi.global_transform
		var outer := ArrayMesh.new()
		var inner := ArrayMesh.new()
		var outer_mats: Array[Material] = []
		var inner_mats: Array[Material] = []
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			var arrays := mi.mesh.surface_get_arrays(i)
			var prim: Mesh.PrimitiveType = mi.mesh.surface_get_primitive_type(i)
			if m and StringName(m.resource_name) in INDOOR_SURFACES:
				inner.add_surface_from_arrays(prim, arrays)
				inner_mats.append(m)
				continue
			var parts: Array = _split_triangles(arrays, local) if prim == Mesh.PRIMITIVE_TRIANGLES else [arrays, null]
			if parts[0] != null:
				outer.add_surface_from_arrays(prim, parts[0])
				outer_mats.append(m)
			if parts[1] != null:
				inner.add_surface_from_arrays(prim, parts[1])
				inner_mats.append(_indoor_copy(m))
		if inner.get_surface_count() == 0:
			continue
		var rooms := MeshInstance3D.new()
		rooms.name = String(mi.name) + "_Rooms"
		rooms.mesh = inner
		rooms.cast_shadow = mi.cast_shadow
		rooms.layers = INDOOR_LAYER
		mi.add_child(rooms)
		for i in inner_mats.size():
			rooms.set_surface_override_material(i, inner_mats[i])
			inner.surface_set_material(i, inner_mats[i])
		_keep_faces(mi)
		mi.mesh = outer
		for i in outer_mats.size():
			outer.surface_set_material(i, outer_mats[i])
			mi.set_surface_override_material(i, outer_mats[i])


## The trimesh collision under `mi` numbers its faces by the unsplit mesh, and
## footsteps read the floor's material through the collider's parent mesh: move
## the collider under a hidden copy of the whole mesh so that still lines up.
func _keep_faces(mi: MeshInstance3D) -> void:
	var bodies := mi.get_children().filter(func(c: Node) -> bool: return c is StaticBody3D)
	if bodies.is_empty():
		return
	var faces := MeshInstance3D.new()
	faces.name = String(mi.name) + "_Faces"
	faces.mesh = mi.mesh
	faces.visible = false
	faces.layers = 0
	faces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mi.mesh.get_surface_count():
		faces.set_surface_override_material(i, mi.get_active_material(i))
	mi.add_child(faces)
	for body: Node in bodies:
		body.reparent(faces, false)


## [outside, inside] index arrays for a triangle surface, by whether each
## triangle's middle is in INDOOR_BOX (either is null when empty).
func _split_triangles(arrays: Array, local: Transform3D) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for k in verts.size():
			idx[k] = k
	var out_idx := PackedInt32Array()
	var in_idx := PackedInt32Array()
	for t in range(0, idx.size() - 2, 3):
		var c := local * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
		var target := in_idx if _in_box(Vector3(c.x, -c.z, c.y)) else out_idx
		target.append(idx[t])
		target.append(idx[t + 1])
		target.append(idx[t + 2])
	var res := [null, null]
	for k in 2:
		var part: PackedInt32Array = out_idx if k == 0 else in_idx
		if part.is_empty():
			continue
		var copy := arrays.duplicate()
		copy[Mesh.ARRAY_INDEX] = part
		res[k] = copy
	return res


func _in_box(h: Vector3) -> bool:
	var lo: Vector3 = INDOOR_BOX[0]
	var hi: Vector3 = INDOOR_BOX[1]
	return h.x > lo.x and h.x < hi.x and h.y > lo.y and h.y < hi.y and h.z > lo.z and h.z < hi.z


## An indoor copy of a material shared with the outside (one per material).
func _indoor_copy(m: Material) -> Material:
	if not m is ShaderMaterial or (m as ShaderMaterial).shader != PS1Model.SHADER:
		return m
	if not _indoor_copies.has(m):
		var copy := m.duplicate() as ShaderMaterial
		_indoor_copies[m] = copy
		_set_indoor(copy)
	return _indoor_copies[m]


func _mark_indoor(node: Node) -> void:
	if node is GeometryInstance3D:
		_mark(node)
	for child in node.get_children():
		_mark_indoor(child)


func _mark(g: GeometryInstance3D) -> void:
	if g.layers & OtherHouse.LAYER_1979:
		return
	g.layers = INDOOR_LAYER
	if g.material_override is ShaderMaterial:
		_set_indoor(g.material_override)
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i)
		if m is ShaderMaterial:
			_set_indoor(m)


## Set on the material itself, not a copy: lamps and decor keep driving their
## own materials (glow at night), and these are the house's own.
func _set_indoor(m: ShaderMaterial) -> void:
	if m.shader == PS1Model.SHADER:
		m.set_shader_parameter(&"indoor", 1.0)
		m.set_shader_parameter(&"indoor_daylight", _daylight)
		if not m in _indoor_mats:
			_indoor_mats.append(m)


## Day's bounce light in the rooms follows the clock, set only when it moves.
func _update_daylight(clock: Node) -> void:
	var d: float = clock.daylight() if clock else 1.0
	if absf(d - _daylight) < 0.02:
		return
	_daylight = d
	for m in _indoor_mats:
		if is_instance_valid(m):
			m.set_shader_parameter(&"indoor_daylight", d)


func _process(_delta: float) -> void:
	var clock := get_node_or_null(^"/root/GameClock")
	_update_daylight(clock)
	var on: bool = clock == null or clock.daylight() < 0.55
	for lamp in _lamps:
		lamp.visible = on
	if _flicker and on:
		var cozy: bool = Settings.cozy_mode if get_node_or_null(^"/root/Settings") else false
		_flicker.light_energy = 0.15 if not cozy and randf() < 0.04 else 1.0


func toggle_door(door_name: StringName) -> bool:
	if not _doors.has(door_name):
		return false
	if door_name == &"Shed_Door" and not shed_is_unlocked:
		shed_tried.emit()
		if not shed_is_unlocked:
			return false
	var door: Dictionary = _doors[door_name]
	door.open = not door.open
	var node: Node3D = door.node
	var target: Transform3D = door.rest
	if door.open:
		if door.slide:
			target = target.translated_local(Vector3(SLIDE_DISTANCE, 0, 0))
		else:
			var angle := -DOOR_OPEN_ANGLE if door_name in OPEN_CLOCKWISE else DOOR_OPEN_ANGLE
			target = target * Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	var tween := create_tween()
	tween.tween_property(node, "transform", target, 0.6).set_trans(Tween.TRANS_SINE)
	door_toggled.emit(door_name, door.open)
	return true


func is_door_open(door_name: StringName) -> bool:
	return _doors.has(door_name) and _doors[door_name].open


func door_names() -> Array:
	return _doors.keys()


func is_door(door_name: StringName) -> bool:
	return _doors.has(door_name)


func unlock_shed() -> void:
	if shed_is_unlocked:
		return
	shed_is_unlocked = true
	var lock := find_child("Padlock", true, false) as Node3D
	if lock:
		lock.visible = false
	shed_unlocked.emit()


## Where rain doesn't fall (EnvironmentController): the house up to its
## ridge, the porch under the balcony, and the carport with its sheds. Each is
## the unit cube [-1, 1] mapped to the box in the world.
func rain_shelters() -> Array:
	var out := []
	for box: Array in RAIN_SHELTERS:
		var lo: Vector3 = box[0]
		var hi: Vector3 = box[1]
		# House (x, y, z) is local (x, z, -y).
		var centre := (lo + hi) * 0.5
		var half := (hi - lo) * 0.5
		out.append(global_transform * Transform3D(Basis.from_scale(Vector3(half.x, half.z, half.y)),
			Vector3(centre.x, centre.z, -centre.y)))
	return out


func spawn_transform(marker_name: StringName) -> Transform3D:
	var marker: Node3D = _markers.get(marker_name)
	return marker.global_transform if marker else global_transform


func has_marker(marker_name: StringName) -> bool:
	return _markers.has(marker_name)


## Go to bed: the clock jumps to `wake_hour` (WAKE_HOUR, the next morning, or
## DUSK_HOUR to sleep the day away), at least half an hour on.
func sleep(wake_hour := WAKE_HOUR) -> void:
	var clock := get_node_or_null(^"/root/GameClock")
	if clock:
		var hours := fposmod(wake_hour - clock.time_of_day, 24.0)
		clock.advance(hours if hours > 0.5 else hours + 24.0)
		slept.emit(clock.day)


func _collect(node: Node) -> void:
	var node_name := StringName(node.name)
	if node is Node3D:
		if node.name.begins_with("Door_") or node_name == &"Shed_Door":
			_doors[node_name] = {"node": node, "rest": node.transform, "open": false,
				"slide": node_name == &"Door_Sliding"}
		elif (node.name.begins_with("Spawn_") or node_name == &"Bed") and not node is MeshInstance3D:
			_markers[node_name] = node
		elif node.name.begins_with("Light_") and not node is MeshInstance3D:
			_markers[node_name] = node
			_add_lamp(node)
	for child in node.get_children():
		_collect(child)


func _add_lamp(marker: Node3D) -> void:
	var spec: Array = LAMPS.get(StringName(marker.name), DEFAULT_LAMP)
	var lamp := OmniLight3D.new()
	lamp.light_color = spec[0]
	lamp.light_energy = spec[1]
	lamp.omni_range = spec[2]
	lamp.shadow_enabled = false
	marker.add_child(lamp)
	_lamps.append(lamp)
	if StringName(marker.name) == FLICKER_LAMP:
		_flicker = lamp


func _add_door_collider(door: Node3D) -> void:
	var mesh := _first_mesh(door)
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var body := AnimatableBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	# Synced bodies only follow their own transform, not the swinging mesh above them.
	body.sync_to_physics = false
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = box.get_center()
	body.add_child(shape)
	mesh.add_child(body)


func _add_stair_ramp() -> void:
	# House (x, y, z) is local (x, z, -y).
	var foot := Vector3(STAIR_X.x, STAIR_FOOT.y, -STAIR_FOOT.x)
	var head := Vector3(STAIR_X.x, STAIR_HEAD.y, -STAIR_HEAD.x)
	var along := head - foot
	var thick := 0.1
	var tilt := Basis(Vector3.RIGHT, -atan2(along.y, along.z))
	var shape := BoxShape3D.new()
	shape.size = Vector3(STAIR_X.y - STAIR_X.x, thick, along.length())
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = Transform3D(tilt, (foot + head) * 0.5 + Vector3((STAIR_X.y - STAIR_X.x) * 0.5, 0, 0)
		+ tilt.y * (0.01 - thick * 0.5))
	var body := StaticBody3D.new()
	body.name = &"StairRamp"
	body.set_meta(&"surface", "stairs")  # for FootstepAudio
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(col)
	add_child(body)


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found:
			return found
	return null


## Walls and furniture are buildings (layer 2); ground and floors are world (layer 1).
func _set_collision_layers(node: Node) -> void:
	if node is StaticBody3D:
		var owner_name := String(node.get_parent().name)
		node.collision_layer = 1 if owner_name.begins_with("Site") or owner_name.begins_with("Floor") else 3
	for child in node.get_children():
		_set_collision_layers(child)
