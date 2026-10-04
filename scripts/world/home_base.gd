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
##   home.unlock_shed()                   # once the player has found the key

signal door_toggled(door_name: StringName, open: bool)
signal slept(day: int)
signal shed_unlocked

const DOOR_OPEN_ANGLE := deg_to_rad(100.0)
## Doors that swing the other way (clockwise seen from above), so they open
## into the room. Keep in step with OPEN_CLOCKWISE in build_shenton.py.
const OPEN_CLOCKWISE := [&"Door_French_R", &"Door_Balcony_R"]
const SLIDE_DISTANCE := 1.05
const WAKE_HOUR := 7.0
## An invisible ramp over the stair nosings so walking up and down is smooth,
## in house coordinates (Blender: x across, y back from the street, z up).
## Keep in step with the stairs in build_shenton.py.
const STAIR_X := Vector2(0.0, 1.0)
const STAIR_FOOT := Vector2(9.053, 0.15)  # (y, z) where the nosing line meets the hall floor
const STAIR_HEAD := Vector2(5.0, 3.16)    # (y, z) at the landing edge

## Lamp colour, energy and range by marker name. Unlisted markers use DEFAULT_LAMP.
const LAMPS := {
	&"Light_Lounge_Lamp": [Color(1.0, 0.78, 0.5), 0.9, 4.0],
	&"Light_Bed1_Lamp": [Color(1.0, 0.75, 0.48), 0.7, 3.0],
	&"Light_Bed2_Desk": [Color(1.0, 0.8, 0.55), 0.7, 3.0],
	&"Light_Bar": [Color(1.0, 0.8, 0.52), 0.8, 3.5],
	&"Light_Storage": [Color(1.0, 0.85, 0.65), 0.4, 2.0],
	&"Light_Porch": [Color(1.0, 0.82, 0.55), 0.9, 5.0],
	&"Light_Courtyard": [Color(1.0, 0.8, 0.5), 1.0, 7.0],
	&"Light_Carport": [Color(0.85, 0.9, 1.0), 0.8, 6.0],
}
const DEFAULT_LAMP := [Color(1.0, 0.84, 0.62), 1.0, 5.0]
## The upstairs toilet light is never quite right.
const FLICKER_LAMP := &"Light_WC_Up"

var shed_is_unlocked := false

var _doors := {}    # StringName -> {node, rest: Transform3D, open: bool, slide: bool}
var _lamps: Array[OmniLight3D] = []
var _flicker: OmniLight3D
var _markers := {}  # StringName -> Node3D


func _ready() -> void:
	add_to_group(&"home_base")
	for model in get_children():
		PS1Model.apply(model)
	_collect(self)
	for door_name in _doors:
		_add_door_collider(_doors[door_name].node)
	_set_collision_layers(self)
	_add_stair_ramp()


func _process(_delta: float) -> void:
	var clock := get_node_or_null(^"/root/GameClock")
	var on: bool = clock == null or clock.daylight() < 0.55
	for lamp in _lamps:
		lamp.visible = on
	if _flicker and on:
		_flicker.light_energy = 0.15 if randf() < 0.04 else 1.0


func toggle_door(door_name: StringName) -> bool:
	if not _doors.has(door_name):
		return false
	if door_name == &"Shed_Door" and not shed_is_unlocked:
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


func spawn_transform(marker_name: StringName) -> Transform3D:
	var marker: Node3D = _markers.get(marker_name)
	return marker.global_transform if marker else global_transform


func has_marker(marker_name: StringName) -> bool:
	return _markers.has(marker_name)


## Go to bed: the clock jumps to WAKE_HOUR the next morning.
func sleep() -> void:
	var clock := get_node_or_null(^"/root/GameClock")
	if clock:
		var hours := fposmod(WAKE_HOUR - clock.time_of_day, 24.0)
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
