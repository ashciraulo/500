// Tall buildings in the far-distance backdrop (see map/scripts/map_overview.gd).
// Blocks with baked wall shading in COLOR.rgb; at night a grid of windows
// lights up, a different pattern per building (seed in COLOR.a).
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform vec2 ps1_snap_resolution;

uniform float near_cut = 750.0;
uniform float fade = 120.0;
uniform float brightness = 1.0;
// 0 = day, 1 = night.
uniform float night = 0.0;
uniform vec3 window_color : source_color = vec3(1.0, 0.82, 0.5);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		vec2 half_res = ps1_snap_resolution * 0.5;
		clip.xy = round(clip.xy / clip.w * half_res) / half_res * clip.w;
	}
	POSITION = clip;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float d = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	float bayer = float((p.x * 4 + p.y) * 7 % 16) / 16.0;
	if (d < near_cut + fade * bayer) {
		discard;
	}
	vec3 col = COLOR.rgb * brightness;
	if (UV.x >= 0.0 && night > 0.01) {
		vec2 cell = floor(UV / vec2(3.2, 3.4));
		vec2 f = fract(UV / vec2(3.2, 3.4));
		float pane = step(0.2, f.x) * step(f.x, 0.8) * step(0.25, f.y) * step(f.y, 0.75);
		float lit = step(0.62, hash(cell + COLOR.a * 97.0));
		col += window_color * pane * lit * night * 0.9;
	}
	ALBEDO = col;
}
