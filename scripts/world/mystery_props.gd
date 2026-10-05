class_name MysteryProps
extends RefCounted
## The mystery's small things, built in code like the trinkets: what waits at
## each clue's spot, what turns up in the cupboard under the stairs, and what
## is under the sheet in the shed. Each `build()` sits on its origin.


const CLUE_MODEL := "res://art/models/home/mystery/%s.glb"


## A clue's own model (art/models/home/mystery/<id>.glb, origin at its base),
## or the built prop for its kind if there isn't one.
static func for_clue(id: String, kind: String) -> Node3D:
	var path := CLUE_MODEL % id
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.name = id.capitalize()
		PS1Model.apply(model)
		return model
	return build(kind)


static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize() if kind != "" else "Thing"
	match kind:
		"cassette":
			_box(root, Vector3(0.1, 0.016, 0.064), Vector3(0, 0.008, 0), Color(0.12, 0.12, 0.13))
			_box(root, Vector3(0.08, 0.002, 0.03), Vector3(0, 0.017, -0.008), Color(0.92, 0.9, 0.82))
			_box(root, Vector3(0.05, 0.003, 0.012), Vector3(0, 0.017, 0.016), Color(0.3, 0.22, 0.16))
		"polaroid":
			_box(root, Vector3(0.088, 0.003, 0.107), Vector3(0, 0.0015, 0), Color(0.93, 0.92, 0.88))
			_box(root, Vector3(0.079, 0.001, 0.079), Vector3(0, 0.0035, -0.008), Color(0.12, 0.13, 0.18))
			_box(root, Vector3(0.016, 0.001, 0.009), Vector3(0.012, 0.004, -0.004), Color(0.95, 0.85, 0.55))
		"ticket":
			_box(root, Vector3(0.075, 0.002, 0.15), Vector3(0, 0.001, 0), Color(0.95, 0.88, 0.62))
			_box(root, Vector3(0.06, 0.001, 0.008), Vector3(0, 0.0025, -0.05), Color(0.7, 0.2, 0.18))
		"map":  # A street directory page, folded in half.
			_box(root, Vector3(0.14, 0.003, 0.19), Vector3(0, 0.0015, 0), Color(0.88, 0.86, 0.76))
			_box(root, Vector3(0.005, 0.001, 0.19), Vector3(0.03, 0.0035, 0), Color(0.75, 0.55, 0.35))
			_box(root, Vector3(0.14, 0.001, 0.005), Vector3(0, 0.0035, 0.02), Color(0.75, 0.55, 0.35))
			for p in [Vector2(-0.035, -0.055), Vector2(0.04, 0.015), Vector2(-0.015, 0.06)]:
				_cylinder(root, 0.009, 0.009, 0.001, Vector3(p.x, 0.0045, p.y), Color(0.3, 0.3, 0.32))
		"keyring":
			_torus(root, 0.016, 0.02, Vector3(0, 0.003, 0), Color(0.7, 0.7, 0.68))
			_box(root, Vector3(0.04, 0.002, 0.024), Vector3(0, 0.002, 0.04), Color(0.9, 0.86, 0.72))
		"key":
			_torus(root, 0.008, 0.013, Vector3(0, 0.003, -0.02), Color(0.78, 0.62, 0.3))
			_box(root, Vector3(0.008, 0.004, 0.04), Vector3(0, 0.003, 0.012), Color(0.78, 0.62, 0.3))
			_box(root, Vector3(0.008, 0.004, 0.006), Vector3(0.006, 0.003, 0.028), Color(0.78, 0.62, 0.3))
		_:
			_box(root, Vector3(0.08, 0.02, 0.06), Vector3(0, 0.01, 0), Color(0.5, 0.5, 0.5))
	return root


const SHED_MODEL := "res://art/models/home/mystery/shed_reveal.glb"


## M.'s broadcasting table under the shed's sheet: the modelled one
## (art/models/README.md) with its lamps lit, or a stand-in built from boxes
## filling `size` (the sheet's footprint). Origin on the floor, centred, the
## wall side toward +Z.
static func build_shed(size: Vector3) -> Node3D:
	if ResourceLoader.exists(SHED_MODEL):
		return _shed_model()
	var root := Node3D.new()
	var w := clampf(size.x, 0.6, 1.2)
	var d := clampf(size.z, 0.5, 1.3)
	var h := clampf(size.y, 0.6, 0.85)
	var timber := Color(0.36, 0.26, 0.18)
	# The card table.
	_box(root, Vector3(w, 0.03, d), Vector3(0, h, 0), Color(0.18, 0.3, 0.22))
	for x in [-1, 1]:
		for z in [-1, 1]:
			_box(root, Vector3(0.03, h, 0.03), Vector3(x * (w * 0.5 - 0.04), h * 0.5, z * (d * 0.5 - 0.04)), timber)
	var top := h + 0.015
	# A cassette deck, running, with its red light.
	_box(root, Vector3(0.36, 0.1, 0.24), Vector3(-w * 0.18, top + 0.05, 0), Color(0.2, 0.2, 0.21))
	_box(root, Vector3(0.11, 0.06, 0.005), Vector3(-w * 0.18 - 0.06, top + 0.05, -0.121), Color(0.08, 0.08, 0.09))
	var tape := build("cassette")
	tape.rotation.x = PI * 0.5
	tape.position = Vector3(-w * 0.18 - 0.06, top + 0.02, -0.118)
	root.add_child(tape)
	_light(root, Vector3(-w * 0.18 + 0.12, top + 0.08, -0.122), Color(1.0, 0.12, 0.08))
	# The transmitter: a tin box, a dial, an aerial up into the rafters.
	_box(root, Vector3(0.24, 0.16, 0.18), Vector3(w * 0.22, top + 0.08, 0.02), Color(0.42, 0.44, 0.4))
	_cylinder(root, 0.025, 0.025, 0.02, Vector3(w * 0.22 - 0.05, top + 0.09, -0.08), Color(0.1, 0.1, 0.1), Vector3(PI * 0.5, 0, 0))
	_light(root, Vector3(w * 0.22 + 0.06, top + 0.13, -0.072), Color(1.0, 0.15, 0.1))
	_cylinder(root, 0.004, 0.004, 1.1, Vector3(w * 0.22 + 0.08, top + 0.7, 0.08), Color(0.7, 0.7, 0.7))
	_box(root, Vector3(0.008, 0.008, 0.6), Vector3(-w * 0.18 + 0.1, top + 0.012, 0.25), Color(0.1, 0.1, 0.1))  # a cable
	# Tapes stacked by the deck, numbered one to twelve.
	for i in 6:
		var stacked := build("cassette")
		stacked.position = Vector3(-w * 0.36, top + i * 0.017, d * 0.3)
		stacked.rotation.y = 0.1 * (i % 3 - 1)
		root.add_child(stacked)
	# The street directory map pinned to a board behind the table.
	var board := Node3D.new()
	board.position = Vector3(0, top + 0.02, d * 0.5 - 0.03)
	board.rotation.x = -0.25
	root.add_child(board)
	_box(board, Vector3(w * 0.8, 0.5, 0.012), Vector3(0, 0.25, 0), Color(0.55, 0.42, 0.3))
	_box(board, Vector3(w * 0.72, 0.42, 0.004), Vector3(0, 0.25, -0.008), Color(0.88, 0.86, 0.76))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	for i in 14:
		_sphere(board, 0.008, Vector3(rng.randf_range(-w * 0.32, w * 0.32), rng.randf_range(0.08, 0.44), -0.014), Color(0.85, 0.15, 0.12))
	# A bare bulb, low and warm.
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.72, 0.42)
	bulb.light_energy = 0.7
	bulb.omni_range = 3.0
	bulb.position = Vector3(0, top + 1.0, 0)
	root.add_child(bulb)
	return root


static func _shed_model() -> Node3D:
	var root := (load(SHED_MODEL) as PackedScene).instantiate() as Node3D
	PS1Model.apply(root)
	# [empty, colour, energy, range]
	for lamp: Array in [["DeckLight", Color(1.0, 0.15, 0.1), 0.12, 0.5],
			["TxLight", Color(1.0, 0.55, 0.2), 0.12, 0.5],
			["Valve", Color(1.0, 0.5, 0.18), 0.35, 0.9],
			["Bulb", Color(1.0, 0.72, 0.42), 0.7, 3.0]]:
		var at := root.find_child(lamp[0], true, false) as Node3D
		if at == null:
			continue
		var light := OmniLight3D.new()
		light.light_color = lamp[1]
		light.light_energy = lamp[2]
		light.omni_range = lamp[3]
		at.add_child(light)
	return root


static func _light(parent: Node3D, at: Vector3, color: Color) -> void:
	var led := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.007
	sphere.height = 0.014
	sphere.radial_segments = 6
	sphere.rings = 3
	led.mesh = sphere
	led.position = at
	led.material_override = PS1Material.glowing(color, 2.0)
	parent.add_child(led)
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 0.08
	glow.omni_range = 0.35
	glow.position = at
	parent.add_child(glow)


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	_add(parent, box, at, color)


static func _sphere(parent: Node3D, radius: float, at: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	_add(parent, sphere, at, color)


static func _cylinder(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = 8
	cylinder.rings = 1
	_add(parent, cylinder, at, color, rot)


static func _torus(parent: Node3D, inner: float, outer: float, at: Vector3, color: Color) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 10
	torus.ring_segments = 4
	_add(parent, torus, at, color)


static func _add(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rot
	instance.material_override = PS1Material.make(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
