class_name MapOverview
extends MeshInstance3D
## The far-distance backdrop: a coarse heightfield painted with a top-down map
## of the city, drawn only beyond `near_cut` metres from the camera. Built by
## tools/osm_import into map/tiles/overview.p5o.

const SHADER := preload("res://map/shaders/overview.gdshader")
const TOWER_SHADER := preload("res://map/shaders/overview_towers.gdshader")

## Sits a little under the real ground so it never pokes through tiles.
@export var sink := 1.2
## The far lakes' water sits this far under the tiles' (more than `sink`: the
## two waters must not fight a kilometre out), the ground under it much lower.
const LAKE_DROP := 3.0
const LAKE_BED := 40.0
@export var near_cut := 750.0

## The skyline blocks (null when the backdrop has none).
var towers: MeshInstance3D
## The sea past the streamed tiles (null when the backdrop has none).
var sea: MeshInstance3D
## Material for the sea; MapStreamer passes the tiles' water so it matches.
var sea_material: Material
## Lakes and ponds (MapStreamer.get_lakes()). The coarse ground is lowered
## under them so it can't stand over the lake tiles' water. They get their own
## water past the streamed tiles, like the sea.
var lakes: Array[Dictionary] = []
## The lakes' water past the streamed tiles (null without lakes).
var lake_water: MeshInstance3D


func load_from(path: String) -> bool:
	var data := MapTileLoader.read(path)
	if data.is_empty():
		return false
	var nx: int = data.nx
	var nz: int = data.nz
	var step: float = data.step
	var origin: Array = data.origin
	var rect: Array = data.texture_rect
	var heights: PackedFloat32Array = data.heights
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	uvs.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var p := Vector3(origin[0] + i * step, heights[k] - sink, origin[2] - j * step)
			verts[k] = p
			uvs[k] = Vector2((p.x - rect[0]) / rect[2], (p.z - rect[1]) / rect[3])
	verts = _sink_lakes(verts, nx, nz, step, origin)
	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var w := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# Rows run north (towards -Z); clockwise seen from above.
			for v in [a, c, b, b, c, d]:
				indices[w] = v
				w += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var array_mesh := st.commit()
	var image := Image.new()
	image.load_png_from_buffer((data.texture_png as PackedByteArray))
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("map_texture", ImageTexture.create_from_image(image))
	material.set_shader_parameter("near_cut", near_cut)
	array_mesh.surface_set_material(0, material)
	mesh = array_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if data.has("tower_pos") and (data.tower_pos as PackedVector3Array).size() > 0:
		_build_towers(data)
	if data.has("sea_xz") and (data.sea_xz as PackedVector2Array).size() > 0:
		_build_sea(data.sea_xz)
	if not lakes.is_empty():
		_build_lakes()
	return true


## Lowers the ground in and just around each lake. The 50 m grid otherwise
## takes its height from the banks and stands over the lake tiles' water.
## Under the water it goes well down, so the far lake surface doesn't flicker
## against it (depth is coarse a few kilometres out).
func _sink_lakes(verts: PackedVector3Array, nx: int, nz: int, step: float, origin: Array) -> PackedVector3Array:
	for lake: Dictionary in lakes:
		var outline: PackedVector2Array = lake.outline
		var bank_y: float = lake.level - sink - 1.0
		var bed_y: float = lake.level - LAKE_BED
		var box: Rect2 = (lake.box as Rect2).grow(step)
		var i0 := maxi(0, ceili((box.position.x - origin[0]) / step))
		var i1 := mini(nx - 1, floori((box.end.x - origin[0]) / step))
		var j0 := maxi(0, ceili((origin[2] - box.end.y) / step))
		var j1 := mini(nz - 1, floori((origin[2] - box.position.y) / step))
		if i0 > i1 or j0 > j1:
			continue
		var shore := Geometry2D.offset_polygon(outline, step)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var k := j * nx + i
				var at := Vector2(verts[k].x, verts[k].z)
				if Geometry2D.is_point_in_polygon(at, outline):
					verts[k] = Vector3(at.x, minf(verts[k].y, bed_y), at.y)
					continue
				if verts[k].y <= bank_y:
					continue
				for shape: PackedVector2Array in shore:
					if Geometry2D.is_point_in_polygon(at, shape):
						verts[k] = Vector3(at.x, bank_y, at.y)
						break
	return verts


## Each lake's water, a little under the tiles' so the tiles win where they're loaded.
func _build_lakes() -> void:
	var verts := PackedVector3Array()
	for lake: Dictionary in lakes:
		var outline: PackedVector2Array = lake.outline
		var tris := Geometry2D.triangulate_polygon(outline)
		var y: float = lake.level - LAKE_DROP
		# Wound the other way from the outline when it runs clockwise.
		var flip := Geometry2D.is_polygon_clockwise(outline)
		for t in range(0, tris.size(), 3):
			for k in ([0, 1, 2] if flip else [0, 2, 1]):
				var p := outline[tris[t + k]]
				verts.append(Vector3(p.x, y, p.y))
	if verts.is_empty():
		return
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	uvs.resize(verts.size())
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	for i in verts.size():
		uvs[i] = Vector2(verts[i].x, verts[i].z) / 16.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var lake_mesh := ArrayMesh.new()
	lake_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if sea_material:
		lake_mesh.surface_set_material(0, sea_material)
	lake_water = MeshInstance3D.new()
	lake_water.name = "Lakes"
	lake_water.mesh = lake_mesh
	lake_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake_water)


## Skyline material, for MapStreamer's day/night changes.
func tower_material() -> ShaderMaterial:
	return towers.mesh.surface_get_material(0) as ShaderMaterial if towers else null


func _build_towers(data: Dictionary) -> void:
	var pos: PackedVector3Array = data.tower_pos
	var col_bytes: PackedByteArray = data.tower_col
	var colors := PackedColorArray()
	colors.resize(pos.size())
	for i in pos.size():
		var o := i * 4
		colors[i] = Color8(col_bytes[o], col_bytes[o + 1], col_bytes[o + 2], col_bytes[o + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_TEX_UV] = data.tower_uv
	arrays[Mesh.ARRAY_COLOR] = colors
	var tower_mesh := ArrayMesh.new()
	tower_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = TOWER_SHADER
	material.set_shader_parameter("near_cut", near_cut)
	tower_mesh.surface_set_material(0, material)
	towers = MeshInstance3D.new()
	towers.name = "Towers"
	towers.mesh = tower_mesh
	towers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(towers)


func _build_sea(xz: PackedVector2Array) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(xz.size())
	uvs.resize(xz.size())
	for i in xz.size():
		verts[i] = Vector3(xz[i].x, 0.0, xz[i].y)
		uvs[i] = xz[i] / 16.0
	var normals := PackedVector3Array()
	normals.resize(xz.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var sea_mesh := ArrayMesh.new()
	sea_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if sea_material:
		sea_mesh.surface_set_material(0, sea_material)
	sea = MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = sea_mesh
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
