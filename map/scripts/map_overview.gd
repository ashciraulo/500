class_name MapOverview
extends MeshInstance3D
## The far-distance backdrop: a coarse heightfield painted with a top-down map
## of the city, drawn only beyond `near_cut` metres from the camera. Built by
## tools/osm_import into map/tiles/overview.p5o.

const SHADER := preload("res://map/shaders/overview.gdshader")

## Sits a little under the real ground so it never pokes through tiles.
@export var sink := 1.2
@export var near_cut := 750.0


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
	return true
