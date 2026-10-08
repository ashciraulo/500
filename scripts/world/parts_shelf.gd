class_name PartsShelf
extends Node
## The parts shelf in your carport: everything you own for the car you're
## driving but haven't fitted (Garage.spare_parts) waits here. A steel
## shelving unit to the left of the shed door holds the small parts, boxed
## or as themselves when they fit; spare wheels lean against the wall to the
## right of the door, with flat-packed racks and bumpers behind them.
##
## Built in code at the shed's front wall (build_shenton.py: the player's
## shed spans x -0.1..2.2, its front wall faces the bay at y 18.78, the door
## is centred on x 1.05). Facing out from the wall along local +Z.

## Shed wall in the home model's coordinates (Blender x, y).
const WALL_X := 1.05
const WALL_Y := 18.78
## Shelving unit, left of the door: centre across (local x), size.
const UNIT_X := 0.75
const UNIT_SIZE := Vector3(0.58, 1.6, 0.3)
const LEVELS := [0.08, 0.5, 0.92, 1.34]
const PER_LEVEL := 2
## Right of the door, under the neon sign.
const LEAN_X := -0.8
const MAX_WHEELS := 2
const MAX_FLAT := 2
## Slots whose parts are too big for the shelf and come flat-packed.
const FLAT_SLOTS := [&"roof", &"rear_rack", &"bumpers", &"towbar"]
## Largest model that goes on a shelf as itself rather than in a box (m).
const SHELF_FIT := 0.27
const CARDBOARD := Color(0.62, 0.48, 0.32)
const STEEL := Color(0.42, 0.44, 0.45)

var _home: Node3D
var _items: Node3D
var _shown := "-"
var _check := 0.0


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	refresh()


## Restock the shelf from what you own; cheap when nothing changed.
func refresh() -> void:
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		_shown = "-"
		if _home == null:
			return
		_build_unit()
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	if car == null:
		return
	var spares := Garage.spare_parts(car)
	var key := ",".join(spares.map(func(p: CarPart) -> String: return String(p.id)))
	if key == _shown and _items and is_instance_valid(_items):
		return
	_shown = key
	if _items and is_instance_valid(_items):
		_items.free()
	_items = Node3D.new()
	_items.name = "Spares"
	_unit_root().add_child(_items)
	var on_shelf := 0
	var wheels := 0
	var flats := 0
	for part in spares:
		if part.slot == &"wheels":
			if wheels < MAX_WHEELS:
				_lean_wheel(part, wheels)
				wheels += 1
		elif part.slot in FLAT_SLOTS:
			if flats < MAX_FLAT:
				_flat_pack(part, flats)
				flats += 1
		elif on_shelf < LEVELS.size() * PER_LEVEL:
			_on_shelf(part, on_shelf)
			on_shelf += 1


## How many spares are showing (the test reads this).
func shown_count() -> int:
	return _items.get_child_count() if _items and is_instance_valid(_items) else 0


func _unit_root() -> Node3D:
	var root := _home.get_node_or_null(^"CarportShelf") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "CarportShelf"
		# Blender (x, y, z) is Godot (x, z, -y) in the home's frame; turn to face the bay.
		root.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(WALL_X, 0.0, -WALL_Y))
		_home.add_child(root)
	return root


func _build_unit() -> void:
	var unit := Node3D.new()
	unit.name = "Unit"
	_unit_root().add_child(unit)
	var half := UNIT_SIZE * 0.5
	for x: float in [-half.x + 0.02, half.x - 0.02]:
		for z: float in [0.02, UNIT_SIZE.z - 0.02]:
			HomeDecor._box(unit, Vector3(0.03, UNIT_SIZE.y, 0.03), Vector3(UNIT_X + x, half.y, z), STEEL)
	for y: float in LEVELS + [UNIT_SIZE.y]:
		HomeDecor._box(unit, Vector3(UNIT_SIZE.x, 0.02, UNIT_SIZE.z), Vector3(UNIT_X, y, half.z), STEEL.darkened(0.15))


func _on_shelf(part: CarPart, i: int) -> void:
	var level: float = LEVELS[i / PER_LEVEL]
	var across := UNIT_X + (float(i % PER_LEVEL) - 0.5) * (UNIT_SIZE.x / PER_LEVEL)
	var at := Vector3(across, level + 0.01, UNIT_SIZE.z * 0.5)
	var model := _part_model(part)
	if model:
		var box := _bounds(model)
		var biggest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if biggest <= SHELF_FIT * 1.6:
			var s := minf(1.0, SHELF_FIT / maxf(biggest, 0.01))
			var holder := Node3D.new()
			holder.name = "Part_%s" % part.id
			holder.position = at
			holder.rotation.y = 0.3 if i % 2 else -0.25
			holder.scale = Vector3.ONE * s
			model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
			holder.add_child(model)
			PS1Model.apply(model)
			_items.add_child(holder)
			return
		model.free()
	_box_of(part, at, Vector3(0.24, 0.22 if i % 3 == 0 else 0.18, 0.22))


func _lean_wheel(part: CarPart, i: int) -> void:
	var model := _part_model(part, "_l")
	if model == null:
		_box_of(part, Vector3(LEAN_X + 0.2 * (i - 0.5), 0.0, 0.3), Vector3(0.26, 0.3, 0.26))
		return
	var box := _bounds(model)
	var holder := Node3D.new()
	holder.name = "Wheel_%s" % part.id
	# Flat face out, axle along +Z, leaning back against the wall.
	holder.position = Vector3(LEAN_X + 0.2 * (i - 0.5), box.size.y * 0.5, 0.22 + 0.1 * i)
	holder.rotation = Vector3(-0.12, 0.0, 0.0)
	var spin := Node3D.new()
	spin.rotation.y = PI * 0.5
	holder.add_child(spin)
	model.position = -box.get_center()
	spin.add_child(model)
	PS1Model.apply(model)
	_items.add_child(holder)


func _flat_pack(part: CarPart, i: int) -> void:
	var at := Vector3(LEAN_X - 0.05 + 0.12 * i, 0.0, 0.06 + 0.07 * i)
	var box := _box_of(part, at, Vector3(0.62, 1.05 - 0.15 * i, 0.06))
	box.rotation.x = -0.06


## A cardboard box with the part's name on it in marker pen, sat on `at`.
func _box_of(part: CarPart, at: Vector3, size: Vector3) -> Node3D:
	var box := Node3D.new()
	box.name = "Box_%s" % part.id
	box.position = at
	var shade := float(hash(part.id) % 100) / 100.0
	HomeDecor._box(box, size, Vector3(0, size.y * 0.5, 0), CARDBOARD.lerp(Color(0.5, 0.4, 0.3), shade * 0.5))
	# Packing tape over the top.
	HomeDecor._box(box, Vector3(size.x * 0.25, 0.004, size.z + 0.004), Vector3(0, size.y, 0), Color(0.75, 0.68, 0.5))
	var label := Label3D.new()
	label.text = part.display_name
	label.font_size = 32
	label.pixel_size = 0.0011 * clampf(size.x / 0.24, 0.8, 1.8)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = size.x * 0.9 / label.pixel_size
	label.outline_size = 0
	label.modulate = Color(0.12, 0.1, 0.1)
	label.position = Vector3(0, size.y * 0.6, size.z * 0.5 + 0.003)
	box.add_child(label)
	_items.add_child(box)
	return box


func _part_model(part: CarPart, suffix := "") -> Node3D:
	if part.visual == "":
		return null
	for path: String in [CarController.PART_MODEL_PATH % (part.visual + suffix), CarController.PART_MODEL_PATH % part.visual]:
		if ResourceLoader.exists(path):
			# Not PS1-converted yet: a model too big for the shelf is freed
			# outside the tree, and freeing converted materials that way
			# leaves the renderer holding dead material ids.
			return (load(path) as PackedScene).instantiate() as Node3D
	return null


## The model's mesh bounds in its own frame (it needn't be in the tree yet).
static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mesh: MeshInstance3D in meshes:
		var t := Transform3D.IDENTITY
		var n: Node = mesh
		while n and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var b := t * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
