// The sparkle over something you can pick up (scripts/world/findable_marker.gd):
// a soft four-point star that always faces you and breathes slowly. It never
// shrinks below a few pixels however far off you are, so it reads from the
// road, and fades out past `far` so it doesn't give itself away across the
// city. Unshaded: it shows the same by day and by night.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 colour : source_color = vec4(0.72, 0.5, 1.0, 1.0);
/// Its size (m) up close.
uniform float size = 1.6;
/// Never smaller than this fraction of its distance (keeps it a few pixels wide far off).
uniform float min_angle = 0.09;
/// Fully faded out by this distance (m).
uniform float far = 160.0;
/// Breaths per second.
uniform float speed = 0.5;

varying float v_fade;
varying float v_pulse;

void vertex() {
	vec4 centre = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float dist = max(-centre.z, 0.01);
	v_pulse = 0.5 + 0.5 * sin((TIME * speed) * 6.2831853);
	float s = max(size, dist * min_angle) * (0.85 + 0.2 * v_pulse);
	centre.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * centre;
	v_fade = 1.0 - smoothstep(far * 0.75, far, dist);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float core = exp(-r2 * 9.0);
	float halo = exp(-r2 * 3.5) * (0.55 + 0.35 * v_pulse);
	float ray_x = exp(-abs(p.y) * 14.0) * max(1.0 - abs(p.x), 0.0);
	float ray_y = exp(-abs(p.x) * 14.0) * max(1.0 - abs(p.y), 0.0);
	float rays = max(ray_x, ray_y) * (0.6 + 0.4 * v_pulse);
	float a = clamp(core * 1.5 + halo + rays, 0.0, 1.0);
	ALBEDO = mix(colour.rgb, vec3(1.0), clamp(core - 0.35, 0.0, 1.0));
	ALPHA = a * colour.a * v_fade;
}
