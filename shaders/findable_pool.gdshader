shader_type spatial;
// The lilac pool on the ground under something you can pick up
// (scripts/world/findable_marker.gd). Drawn additively on a flat quad, like
// the street lamps' pools (map/shaders/light_pool.gdshader), so it shows
// however many real lights are near; breathes with the sparkle above it.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(0.72, 0.5, 1.0);
/// 0 by day, 1 at night (FindableMarker drives it).
uniform float energy = 0.0;
uniform float speed = 0.5;

void fragment() {
	float breath = 0.5 + 0.5 * sin(TIME * speed * 6.2831853);
	float d = length(UV * 2.0 - 1.0);
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.5);
	// Coarse rings keep it in the PS1 look instead of a smooth gradient.
	a = floor(a * 5.0 + 0.5) / 5.0;
	ALBEDO = colour * a * energy * (0.45 + 0.55 * breath);
}
