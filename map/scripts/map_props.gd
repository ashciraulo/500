class_name MapProps
extends RefCounted
## Low-poly meshes for the props the importer scatters (trees, street lights).
## Built in code so they share the map's PS1 materials; swap any of them for a
## Blender model by putting a Mesh resource at res://map/props/<kind>.tres.

const KINDS := [&"tree_round", &"tree_gum", &"tree_palm", &"shrub", &"street_light"]


static func build_all(materials: Dictionary) -> Dictionary:
	var out := {}
	for kind: StringName in KINDS:
		var override := "res://map/props/%s.tres" % kind
		if ResourceLoader.exists(override):
			out[kind] = load(override)
			continue
		match kind:
			&"tree_round":
				out[kind] = _tree(materials, 2.4, 0.18, 2.3, &"tree_leaves", 1)
			&"tree_gum":
				out[kind] = _tree(materials, 4.2, 0.22, 2.6, &"tree_gum", 3)
			&"tree_palm":
				out[kind] = _palm(materials)
			&"shrub":
				out[kind] = _tree(materials, 0.2, 0.08, 1.1, &"tree_gum", 1)
			&"street_light":
				out[kind] = _street_light(materials)
	out[&"light_pool"] = light_pool()
	return out


## A flat 18 m quad for the glow under each street light (shader: light_pool).
static func light_pool() -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(18.0, 18.0)
	var material := ShaderMaterial.new()
	material.shader = load("res://map/shaders/light_pool.gdshader")
	material.resource_name = "light_pool"
	plane.material = material
	return plane


static func _tree(materials: Dictionary, trunk_h: float, trunk_r: float, crown_r: float, leaves: StringName, blobs: int) -> ArrayMesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(bark, Vector3.ZERO, trunk_r, trunk_r * 0.7, trunk_h + crown_r * 0.5, 5)
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(leaves) + blobs
	for b in blobs:
		var offset := Vector3.ZERO
		if blobs > 1:
			var a := TAU * b / blobs + rng.randf() * 0.6
			offset = Vector3(cos(a), rng.randf_range(-0.3, 0.6), sin(a)) * crown_r * 0.55
		_blob(crown, Vector3(0, trunk_h + crown_r * 0.6, 0) + offset, crown_r * (1.0 if blobs == 1 else 0.75), rng)
	return _commit([bark, crown], [materials.get(&"tree_bark"), materials.get(leaves)])


static func _palm(materials: Dictionary) -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(trunk, Vector3.ZERO, 0.25, 0.18, 7.5, 5)
	var fronds := SurfaceTool.new()
	fronds.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 7.4, 0)
	for i in 7:
		var a := TAU * i / 7.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP) * 0.45
		var mid := top + dir * 1.6 + Vector3(0, 0.35, 0)
		var tip := top + dir * 3.0 + Vector3(0, -0.9, 0)
		for quad in [[top, mid - side, mid + side], [mid - side, tip, mid + side]]:
			_tri_two_sided(fronds, quad[0], quad[1], quad[2])
	return _commit([trunk, fronds], [materials.get(&"tree_bark"), materials.get(&"tree_leaves")])


static func _street_light(materials: Dictionary) -> ArrayMesh:
	var pole := SurfaceTool.new()
	pole.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(pole, Vector3.ZERO, 0.09, 0.07, 7.0, 6)
	_box(pole, Vector3(0, 6.95, 0.9), Vector3(0.08, 0.08, 1.8))
	var head := SurfaceTool.new()
	head.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(head, Vector3(0, 6.85, 1.8), Vector3(0.35, 0.14, 0.6))
	return _commit([pole, head], [materials.get(&"light_pole"), materials.get(&"light_head")])


static func _commit(tools: Array, mats: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in tools.size():
		var st: SurfaceTool = tools[i]
		st.generate_normals()
		st.commit(mesh)
		if mats[i]:
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[i])
	return mesh


## Tapered n-sided prism standing on `base`.
static func _prism(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, sides: int) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := base + Vector3(cos(a0), 0, sin(a0)) * r0
		var b1 := base + Vector3(cos(a1), 0, sin(a1)) * r0
		var t0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var t1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		_quad(st, b0, b1, t1, t0, Vector2(float(i) / sides, 1), Vector2(float(i + 1) / sides, 0))


## A lumpy low-poly sphere (octahedron, subdivided once, jittered).
static func _blob(st: SurfaceTool, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var p := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 4, 3], [0, 3, 5], [0, 5, 2], [0, 2, 4], [1, 3, 4], [1, 5, 3], [1, 2, 5], [1, 4, 2]]
	var jitter := {}
	for f in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var d: Vector3 = p[f[2]]
		var ab := (a + b).normalized()
		var bd := (b + d).normalized()
		var da := (d + a).normalized()
		for t in [[a, ab, da], [ab, b, bd], [da, bd, d], [ab, bd, da]]:
			var pts: Array[Vector3] = []
			for v: Vector3 in t:
				var k := v.snapped(Vector3.ONE * 0.01)
				if not jitter.has(k):
					jitter[k] = rng.randf_range(0.8, 1.15)
				pts.append(c + v * r * Vector3(1.0, 0.8, 1.0) * jitter[k])
			# Octahedron faces above are listed clockwise seen from outside.
			st.set_uv(Vector2(pts[0].x, pts[0].y) * 0.4)
			st.add_vertex(pts[0])
			st.set_uv(Vector2(pts[1].x, pts[1].y) * 0.4)
			st.add_vertex(pts[1])
			st.set_uv(Vector2(pts[2].z, pts[2].y) * 0.4)
			st.add_vertex(pts[2])


static func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var corners := []
	for i in 8:
		corners.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		_quad(st, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], Vector2(0, 1), Vector2(1, 0))


## Quad a-b-c-d, counter-clockwise seen from the front (Godot wants clockwise, so we flip).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	var uva := uv0
	var uvb := Vector2(uv1.x, uv0.y)
	var uvc := uv1
	var uvd := Vector2(uv0.x, uv1.y)
	for t in [[a, uva, c, uvc, b, uvb], [a, uva, d, uvd, c, uvc]]:
		st.set_uv(t[1])
		st.add_vertex(t[0])
		st.set_uv(t[3])
		st.add_vertex(t[2])
		st.set_uv(t[5])
		st.add_vertex(t[4])


static func _tri_two_sided(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for t in [[a, b, c], [a, c, b]]:
		st.set_uv(Vector2(0, 0))
		st.add_vertex(t[0])
		st.set_uv(Vector2(1, 0))
		st.add_vertex(t[1])
		st.set_uv(Vector2(0.5, 1))
		st.add_vertex(t[2])
