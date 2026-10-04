// PS1-style surface shader for world geometry.
//
// - Vertices snap to the low-res pixel grid (the classic PS1 wobble).
// - Textures are partly affine-mapped (they swim a little on big polygons).
// - Nearest-neighbour texture filtering.
// - Optional world-space grid pattern for test/blockout geometry.
// - Surfaces marked `wet_response` darken and turn glossy as the roads get wet.
//
// The snap resolution, affine amount and wetness are global shader uniforms
// (project.godot [shader_globals]) driven by RenderSettings and Weather.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

global uniform vec2 ps1_snap_resolution;
global uniform float ps1_affine_strength;
global uniform float ps1_wetness;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// 0 = ignores rain, 1 = road surface (darkens and gets glossy when wet).
uniform float wet_response : hint_range(0.0, 1.0) = 0.0;
// World-space blockout grid. 0 disables it.
uniform float grid_size = 0.0;
uniform vec4 grid_line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 grid_alt_color : source_color = vec4(1.0);
uniform float vertex_snap : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;
varying vec2 affine_uv;
varying float affine_w;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (vertex_snap > 0.0 && clip.w > 0.0) {
		vec2 half_res = ps1_snap_resolution * 0.5;
		vec2 ndc = clip.xy / clip.w;
		vec2 snapped = round(ndc * half_res) / half_res;
		clip.xy = mix(ndc, snapped, vertex_snap) * clip.w;
	}
	POSITION = clip;
	// Interpolating uv*w and w perspective-correctly, then dividing, gives
	// screen-linear (affine) UVs, like the PS1 had.
	affine_uv = UV * uv_scale * clip.w;
	affine_w = clip.w;
}

void fragment() {
	vec2 uv = mix(UV * uv_scale, affine_uv / affine_w, ps1_affine_strength);
	vec4 tex = texture(albedo_texture, uv);
	vec3 color = albedo_color.rgb * tex.rgb;

	if (grid_size > 0.0) {
		vec2 cell = floor(world_pos.xz / grid_size);
		float checker = mod(cell.x + cell.y, 2.0);
		color = mix(color, color * grid_alt_color.rgb, checker);
		vec2 line = abs(fract(world_pos.xz / grid_size + 0.5) - 0.5) * grid_size;
		float on_line = step(min(line.x, line.y), 0.06);
		color = mix(color, grid_line_color.rgb, on_line * grid_line_color.a);
	}

	float wet = ps1_wetness * wet_response;
	ALBEDO = color * mix(1.0, 0.55, wet);
	ROUGHNESS = mix(roughness, 0.12, wet);
	METALLIC = metallic;
	SPECULAR = mix(0.15, 0.8, wet);
	EMISSION = emission_color.rgb * emission_energy;
}
