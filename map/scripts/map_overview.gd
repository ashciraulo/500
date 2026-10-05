class_name MapOverview
extends MeshInstance3D
## The far-distance backdrop: a coarse heightfield painted with a top-down map
## of the city, drawn only beyond `near_cut` metres from the camera. Built by
## tools/osm_import into map/tiles/overview.p5o.

const SHADER := preload("res://map/shaders/overview.gdshader")
const TOWER_SHADER := preload("res://map/shaders/overview_towers.gdshader")

## Sits a little under the real ground so it never pokes through tiles.
@export var sink := 1.2
@export var near_cut := 750.0

## The skyline blocks (null when the backdrop has none).
var towers: MeshInstance3D
## The sea past the streamed tiles (null when the backdrop has none).
var sea: MeshInstance3D
## Material for the sea; MapStreamer passes the tiles' water so it matches.
var sea_material: Material


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
	return true


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
