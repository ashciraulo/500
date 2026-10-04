class_name PS1Material
extends RefCounted
## Helpers for building materials that use the shared PS1 surface shader.
## Map and model code can call these instead of making StandardMaterial3Ds,
## so everything in the world wobbles and gets wet the same way.

const SHADER := preload("res://shaders/ps1_surface.gdshader")


static func make(color: Color, roughness := 0.9, wet_response := 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("albedo_color", color)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("wet_response", wet_response)
	return material


static func textured(texture: Texture2D, tint := Color.WHITE, uv_scale := Vector2.ONE) -> ShaderMaterial:
	var material := make(tint)
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("uv_scale", uv_scale)
	return material


static func road(color := Color(0.22, 0.22, 0.24)) -> ShaderMaterial:
	return make(color, 0.85, 1.0)


static func glowing(color: Color, energy := 2.0) -> ShaderMaterial:
	var material := make(color)
	material.set_shader_parameter("emission_color", color)
	material.set_shader_parameter("emission_energy", energy)
	return material


static func blockout(color: Color, grid := 1.0) -> ShaderMaterial:
	var material := make(color, 0.95, 0.6)
	material.set_shader_parameter("grid_size", grid)
	material.set_shader_parameter("grid_alt_color", Color(0.9, 0.9, 0.9))
	material.set_shader_parameter("grid_line_color", Color(0.0, 0.0, 0.0, 0.35))
	return material
