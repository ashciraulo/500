// The late city's tape shimmer (scripts/autoload/late_city.gd): faint
// horizontal bands crawling up the screen over anything that belongs to the
// late city, like a paused VHS frame. Used as a material_overlay, so the
// thing keeps its own look underneath. Nothing from our world ever has it.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.58, 1.0);

// The overlay redraws the same triangles as the thing under it, so it must
// snap its vertices exactly as ps1_surface.gdshader does: otherwise the two
// depths disagree and the bands break into stripes across big flat panels.
global uniform vec2 ps1_snap_resolution;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		vec2 half_res = ps1_snap_resolution * 0.5;
		vec2 ndc = clip.xy / clip.w;
		vec2 snapped = round(ndc * half_res) / half_res;
		clip.xy = mix(ndc, snapped, 1.0) * clip.w;
	}
	POSITION = clip;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Fine scan lines drifting upward, and one broad tracking band rolling
	// slowly through.
	float lines = smoothstep(0.55, 1.0, sin(SCREEN_UV.y * 260.0 + TIME * 9.0));
	float roll = smoothstep(0.9, 1.0, sin(SCREEN_UV.y * 2.6 - TIME * 1.1));
	// Blocky grain that changes a dozen times a second.
	float grain = hash(floor(SCREEN_UV * vec2(180.0, 100.0)) + floor(TIME * 12.0));
	ALBEDO = tint.rgb;
	ALPHA = amount * clamp(0.09 * lines + 0.32 * roll + 0.07 * grain, 0.0, 1.0);
}
