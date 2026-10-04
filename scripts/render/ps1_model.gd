class_name PS1Model
extends RefCounted
## Converts the materials of an imported glTF model to the shared PS1 surface
## shader, so Blender-built models wobble and get wet like the rest of the
## world. Transparent materials (glass) stay standard but get nearest
## filtering. Call `PS1Model.apply(model_root)` once, e.g. from `_ready()`.
##
## Returns the converted materials by their Blender name, so callers can
## drive lamps or recolour paint afterwards.

const SHADER := preload("res://shaders/ps1_surface.gdshader")


static func apply(root: Node, wet_names: PackedStringArray = PackedStringArray()) -> Dictionary:
	var by_name := {}
	var cache := {}
	for mesh_instance in _meshes(root):
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var source := mesh_instance.get_active_material(i)
			if source == null:
				continue
			if not cache.has(source):
				cache[source] = to_ps1(source, source.resource_name in wet_names)
			var converted: Material = cache[source]
			mesh_instance.set_surface_override_material(i, converted)
			if source.resource_name != "":
				by_name[source.resource_name] = converted
	return by_name


static func to_ps1(source: Material, wet := false) -> Material:
	var standard := source as BaseMaterial3D
	if standard == null:
		return source
	if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		var glass := standard.duplicate() as BaseMaterial3D
		glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		return glass
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.resource_name = standard.resource_name
	material.set_shader_parameter("albedo_color", standard.albedo_color)
	if standard.albedo_texture:
		material.set_shader_parameter("albedo_texture", standard.albedo_texture)
	material.set_shader_parameter("roughness", standard.roughness)
	material.set_shader_parameter("metallic", standard.metallic)
	if standard.emission_enabled:
		material.set_shader_parameter("emission_color", standard.emission)
		material.set_shader_parameter("emission_energy", standard.emission_energy_multiplier)
	material.set_shader_parameter("wet_response", 1.0 if wet else 0.0)
	return material


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
