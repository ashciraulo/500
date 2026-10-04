class_name MapTileLoader
extends RefCounted
## Decodes the .p5t tiles written by tools/osm_import (tile format 1) into
## nodes. `build()` is safe to run on a worker thread: it makes meshes and
## multimeshes. `make_collision()` (static bodies and their baked concave
## shapes, outside the scene tree) runs on a worker too; only adding the
## result to the tree happens on the main thread.

const FORMAT := 1
const MAGIC := "P5TB"  # brotli
const MAGIC_ZLIB := "P5TZ"  # older tiles
const POS_SCALE := 1.0 / 32.0
const NRM_SCALE := 1.0 / 127.0

## Collision layer bits.
const LAYER_WORLD := 1
const LAYER_BUILDINGS := 2

## Which `surface` the car feels on each material (see CarController.SURFACES).
const SURFACE_OF := {
	&"asphalt": &"asphalt", &"line_white": &"asphalt",
	&"sidewalk": &"concrete", &"kerb": &"concrete", &"paving": &"concrete", &"concrete": &"concrete",
	&"tunnel_wall": &"concrete", &"path": &"brick",
	&"grass": &"grass", &"turf": &"grass", &"ground_urban": &"grass",
	&"bush": &"dirt", &"wetland": &"dirt", &"dirt": &"dirt",
	&"sand": &"sand", &"riverbed": &"sand", &"ballast": &"gravel",
}

## Detail meshes are hidden past these distances (metres from the camera to
## the mesh's bounds centre, so roughly tile centre: keep them generous).
const VISIBILITY_END := {&"markings": 600.0, &"rail": 750.0, &"landmark_detail": 600.0}
## Meshes that cast shadows (the rest only receive them).
const SHADOW_MESHES := [&"buildings", &"bridges", &"props", &"landmarks"]


class TileResult:
	extends RefCounted
	var key := Vector2i.ZERO
	var root: Node3D
	## Each entry: {faces: PackedVector3Array, surface: StringName, layer: int}
	var collision: Array[Dictionary] = []
	## Street light positions in world space (for the night light pool).
	var lights := PackedVector3Array()
	## Road data for traffic (the tile's .p5r), filled in by MapStreamer.
	var traffic: Dictionary = {}
	var error := ""


static func read(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8:
		return {}
	var magic := bytes.slice(0, 4).get_string_from_ascii()
	if magic != MAGIC and magic != MAGIC_ZLIB:
		return {}
	var size := bytes.decode_u32(4)
	var mode := FileAccess.COMPRESSION_BROTLI if magic == MAGIC else FileAccess.COMPRESSION_DEFLATE
	var raw := bytes.slice(8).decompress(size, mode)
	if raw.size() != size:
		return {}
	var data: Variant = bytes_to_var(raw)
	return data if data is Dictionary else {}


## materials: StringName -> Material. props: StringName -> Mesh.
static func build(path: String, materials: Dictionary, props: Dictionary) -> TileResult:
	var result := TileResult.new()
	var data := read(path)
	if data.is_empty() or int(data.get("format", 0)) != FORMAT:
		result.error = "unreadable tile %s" % path
		return result
	var tile: Array = data.tile
	result.key = Vector2i(tile[0], tile[1])
	var root := Node3D.new()
	root.name = "Tile_%d_%d" % [result.key.x, result.key.y]
	var origin: Array = data.origin
	root.position = Vector3(origin[0], origin[1], origin[2])
	result.root = root

	for mesh_data: Dictionary in data.meshes:
		var mesh_name := StringName(mesh_data.name)
		var collision := StringName(mesh_data.collision)
		for surface: Dictionary in mesh_data.surfaces:
			var material_name := StringName(surface.material)
			var arrays := _decode_surface(surface)
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material: Material = materials.get(material_name)
			if material:
				mesh.surface_set_material(0, material)
			var instance := MeshInstance3D.new()
			instance.name = "%s_%s" % [mesh_name, material_name]
			instance.mesh = mesh
			if not mesh_name in SHADOW_MESHES:
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if VISIBILITY_END.has(mesh_name):
				instance.visibility_range_end = VISIBILITY_END[mesh_name]
			root.add_child(instance)
			if collision != &"":
				result.collision.append({
					faces = _faces(arrays),
					surface = SURFACE_OF.get(material_name, &"concrete"),
					layer = LAYER_WORLD | (LAYER_BUILDINGS if collision == &"buildings" else 0),
					name = instance.name,
				})

	var instances: Dictionary = data.get("instances", {})
	for kind: String in instances:
		var mesh: Mesh = props.get(StringName(kind))
		var values: PackedFloat32Array = instances[kind]
		var count := values.size() / 5
		if count == 0:
			continue
		if kind == "street_light":
			var pools := MultiMesh.new()
			pools.transform_format = MultiMesh.TRANSFORM_3D
			pools.mesh = props.get(&"light_pool")
			pools.instance_count = count if pools.mesh else 0
			for i in count:
				var o := i * 5
				var base := Vector3(values[o], values[o + 1], values[o + 2])
				var lamp := Basis(Vector3.UP, values[o + 3]) * Vector3(0, 6.6, 1.8)
				result.lights.append(root.position + base + lamp)
				if pools.mesh:
					pools.set_instance_transform(i, Transform3D(Basis(), base + Vector3(lamp.x, 0.05, lamp.z)))
			if pools.mesh:
				var glow := MultiMeshInstance3D.new()
				glow.name = "light_pools"
				glow.multimesh = pools
				glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				glow.visibility_range_end = 600.0
				glow.add_to_group(&"map_light_pools")
				root.add_child(glow)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = count
		for i in count:
			var o := i * 5
			var basis := Basis(Vector3.UP, values[o + 3]).scaled(Vector3.ONE * values[o + 4])
			mm.set_instance_transform(i, Transform3D(basis, Vector3(values[o], values[o + 1], values[o + 2])))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "props_" + kind
		mmi.multimesh = mm
		mmi.visibility_range_end = 750.0
		root.add_child(mmi)
	return result


## Static bodies for the tile's collision meshes, not yet in the tree. Safe on
## a worker thread (MapStreamer builds them there).
static func make_collision(result: TileResult) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Collision"
	for entry: Dictionary in result.collision:
		var body := StaticBody3D.new()
		body.name = entry.name
		body.collision_layer = entry.layer
		body.collision_mask = 0
		body.set_meta("surface", entry.surface)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(entry.faces)
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = shape
		body.add_child(collision_shape)
		holder.add_child(body)
	return holder


static func _decode_surface(s: Dictionary) -> Array:
	var n: int = s.count
	var pos: PackedByteArray = s.pos
	var nrm: PackedByteArray = s.nrm
	var uvb: PackedByteArray = s.uv
	var uv_scale := 1.0 / float(s.uvq)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n)
	normals.resize(n)
	uvs.resize(n)
	# Arrays are stored component by component (all x, then all y, ...).
	var oy := n * 2
	var oz := n * 4
	for i in n:
		var o := i * 2
		verts[i] = Vector3(pos.decode_s16(o), pos.decode_s16(oy + o), pos.decode_s16(oz + o)) * POS_SCALE
		normals[i] = Vector3(nrm.decode_s8(i), nrm.decode_s8(n + i), nrm.decode_s8(n + n + i)) * NRM_SCALE
		uvs[i] = Vector2(uvb.decode_s16(o), uvb.decode_s16(oy + o)) * uv_scale
	var indices: PackedInt32Array = s.idx
	var acc := 0
	for i in indices.size():
		acc += indices[i]
		indices[i] = acc
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _faces(arrays: Array) -> PackedVector3Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = verts[indices[i]]
	return faces
