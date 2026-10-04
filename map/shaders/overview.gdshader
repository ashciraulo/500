// Far-distance backdrop for the Perth map (see map/scripts/map_overview.gd).
// PS1 vertex snapping like the world shader, but fragments near the camera
// are discarded (with a dithered edge) so the detailed tiles take over there.
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform vec2 ps1_snap_resolution;

uniform sampler2D map_texture : source_color, filter_nearest, repeat_disable;
uniform float near_cut = 750.0;
uniform float fade = 120.0;
// Set by MapStreamer.set_night_amount(): unshaded, so it dims by hand at night.
uniform float brightness = 1.0;

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

void fragment() {
	float d = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	// 4x4 ordered dither for the hand-over edge.
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	float bayer = float((p.x * 4 + p.y) * 7 % 16) / 16.0;
	if (d < near_cut + fade * bayer) {
		discard;
	}
	ALBEDO = texture(map_texture, UV).rgb * brightness;
}
