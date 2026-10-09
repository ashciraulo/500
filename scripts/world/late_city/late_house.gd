class_name LateHouse
extends Node3D
## The one house on the empty road (EmptyRoad): red brick and a tiled hip
## roof the way they built them in the seventies, the porch light on, lamps
## on behind the curtains, a 1971 Fiat 500 L under the carport and number 15
## on the letterbox. It faces -Z (the road). Built from boxes in the PS1
## look; every material has `late_keep`, so it stays lit in the void.

const BRICK := Color(0.47, 0.26, 0.19)
const MORTAR := Color(0.36, 0.3, 0.26)
const ROOF := Color(0.42, 0.2, 0.14)
const TRIM := Color(0.82, 0.78, 0.68)
const LAWN := Color(0.05, 0.07, 0.04)
const CONCRETE := Color(0.32, 0.31, 0.29)
const WINDOW := Color(1.0, 0.7, 0.38)
const CAR := "res://art/models/cars/classic_l/classic_l.glb"

## House size (m): width across the front, depth, wall height.
const W := 11.0
const D := 8.0
const H := 2.7

var _letterbox: Node3D


func _ready() -> void:
	name = "LateHouse"
	_box(Vector3(W + 8.0, 0.1, D + 9.0), Vector3(1.5, -0.05, 1.0), LAWN)
	# Walls, with a slightly darker plinth.
	_box(Vector3(W, H, D), Vector3(0, H * 0.5, 0), BRICK)
	_box(Vector3(W + 0.06, 0.45, D + 0.06), Vector3(0, 0.22, 0), MORTAR)
	_roof()
	# The front: a door between two big lit windows.
	var front := -D * 0.5 - 0.03
	_box(Vector3(0.95, 2.1, 0.08), Vector3(-1.1, 1.05, front), Color(0.22, 0.14, 0.09))
	_box(Vector3(0.08, 0.08, 0.1), Vector3(-0.75, 1.0, front - 0.05), Color(0.8, 0.65, 0.3))
	for x: float in [-3.7, 1.6]:
		_window(Vector3(x, 1.55, front))
	# The porch and its light.
	_box(Vector3(2.4, 0.18, 1.6), Vector3(-1.1, 0.09, front - 0.8), CONCRETE)
	_box(Vector3(2.6, 0.12, 1.8), Vector3(-1.1, 2.55, front - 0.85), TRIM)
	for x: float in [-2.2, 0.0]:
		_box(Vector3(0.1, 2.5, 0.1), Vector3(x, 1.25, front - 1.6), TRIM)
	var lamp := _box(Vector3(0.16, 0.24, 0.12), Vector3(-0.35, 1.95, front - 0.06), WINDOW, 3.0)
	var porch := OmniLight3D.new()
	porch.light_color = WINDOW
	porch.light_energy = 1.4
	porch.omni_range = 7.0
	porch.position = lamp.position + Vector3(0, 0, -0.5)
	add_child(porch)
	# The carport to one side, and Mick's car in it.
	var cx := W * 0.5 + 1.7
	_box(Vector3(3.2, 0.1, 6.0), Vector3(cx, 2.45, -0.6), TRIM)
	for p: Vector2 in [Vector2(-1.5, -3.5), Vector2(1.5, -3.5), Vector2(-1.5, 2.3), Vector2(1.5, 2.3)]:
		_box(Vector3(0.1, 2.4, 0.1), Vector3(cx + p.x, 1.2, p.y), TRIM)
	_box(Vector3(3.0, 0.06, 13.0), Vector3(cx, 0.02, -5.5), CONCRETE)
	_car(Vector3(cx, 0.0, -1.2))


## The letterbox at the edge of the road (global position).
func place_letterbox(at: Vector3) -> void:
	if _letterbox:
		_letterbox.queue_free()
	_letterbox = Node3D.new()
	add_child(_letterbox)
	_letterbox.global_position = at
	_letterbox.global_basis = global_basis
	var pillar := _box(Vector3(0.48, 1.05, 0.48), Vector3(0, 0.52, 0), BRICK, 0.0, _letterbox)
	_box(Vector3(0.56, 0.08, 0.56), Vector3(0, 1.08, 0), TRIM, 0.0, _letterbox)
	_box(Vector3(0.26, 0.04, 0.02), Vector3(0, 0.82, -0.25), Color(0.05, 0.05, 0.05), 0.0, _letterbox)
	var number := Label3D.new()
	number.text = "15"
	number.font_size = 64
	number.pixel_size = 0.004
	number.modulate = Color(0.85, 0.7, 0.35)
	number.outline_size = 0
	number.position = Vector3(0, 0.55, -0.25)
	number.rotation.y = PI
	number.shaded = true
	_letterbox.add_child(number)
	pillar.name = "Letterbox"


func _window(at: Vector3) -> void:
	_box(Vector3(2.5, 1.45, 0.06), at, TRIM)
	_box(Vector3(2.3, 1.25, 0.06), at + Vector3(0, 0, -0.01), WINDOW, 1.1)
	# Curtains drawn, a gap in the middle, and the frame's bars.
	for side in [-1.0, 1.0]:
		_box(Vector3(0.95, 1.25, 0.02), at + Vector3(side * 0.62, 0, -0.04), Color(0.55, 0.32, 0.14), 0.35)
	_box(Vector3(0.05, 1.3, 0.04), at + Vector3(0, 0, -0.06), TRIM)


func _roof() -> void:
	# A hip roof: four slopes up to a short ridge.
	var e := 0.45
	var x0 := -W * 0.5 - e
	var x1 := W * 0.5 + e
	var z0 := -D * 0.5 - e
	var z1 := D * 0.5 + e
	var r := 2.4
	var top := H + 1.7
	var a := Vector3(x0, H, z0)
	var b := Vector3(x1, H, z0)
	var c := Vector3(x1, H, z1)
	var d := Vector3(x0, H, z1)
	var p := Vector3(-r, top, 0)
	var q := Vector3(r, top, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri: Array in [[a, p, q], [a, q, b], [b, q, c], [c, q, p], [c, p, d], [d, p, a]]:
		for v: Vector3 in tri:
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(ROOF)
	add_child(mi)
	# Under the eaves.
	_box(Vector3(x1 - x0, 0.06, z1 - z0), Vector3(0, H - 0.03, 0), TRIM)


func _car(at: Vector3) -> void:
	if not ResourceLoader.exists(CAR):
		return
	var model := (load(CAR) as PackedScene).instantiate() as Node3D
	add_wheels(model)
	PS1Model.apply(model)
	add_child(model)
	model.position = at
	# Nose out towards the road.
	model.rotation.y = 0.0
	for g in _meshes(model):
		for i in g.mesh.get_surface_count():
			var m := g.get_active_material(i)
			if m is ShaderMaterial:
				var keep := (m as ShaderMaterial).duplicate() as ShaderMaterial
				keep.set_shader_parameter("late_keep", true)
				g.set_surface_override_material(i, keep)


## A parked car body has no wheels of its own (the car rig fits them): put
## its style's wheels on its `Hub_FL`... empties.
static func add_wheels(model: Node3D) -> void:
	var style := ""
	for node in model.get_children():
		if node.name.begins_with("WheelStyle_"):
			style = String(node.name).trim_prefix("WheelStyle_")
	for hub_name: String in ["Hub_FL", "Hub_FR", "Hub_RL", "Hub_RR"]:
		var hub := model.find_child(hub_name, true, false) as Node3D
		var path := "res://art/models/cars/parts/wheel_%s_%s.glb" % [style, "l" if hub_name.ends_with("L") else "r"]
		if hub == null or style == "" or not ResourceLoader.exists(path):
			continue
		var wheel := (load(path) as PackedScene).instantiate() as Node3D
		hub.add_child(wheel)


func _box(size: Vector3, at: Vector3, colour: Color, glow := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _material(colour, glow)
	mi.position = at
	(parent if parent else self).add_child(mi)
	return mi


static func _material(colour: Color, glow := 0.0) -> ShaderMaterial:
	var m := PS1Material.glowing(colour, glow) if glow > 0.0 else PS1Material.make(colour)
	m.set_shader_parameter("late_keep", true)
	return m


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
