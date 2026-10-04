shader_type spatial;
// The pool of light a street lamp throws on the road at night. Drawn additively
// on a flat quad under every lamp, so the whole street glows without hundreds
// of real lights. MapStreamer drives `energy` from the time of day.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.72, 0.42);
uniform float energy = 0.0;

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.7);
	// Coarse rings keep it in the PS1 look instead of a smooth gradient.
	a = floor(a * 6.0 + 0.5) / 6.0;
	ALBEDO = color * a * energy;
}
