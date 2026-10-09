// PS1-style surface shader for world geometry.
//
// - Vertices snap to the low-res pixel grid (the classic PS1 wobble).
// - Textures can be partly affine-mapped (Strong and Medium filters only),
//   capped to a few pixels so they never slide across big map polygons.
// - Nearest-neighbour texture filtering.
// - Optional world-space grid pattern for test/blockout geometry.
// - Surfaces marked `wet_response` darken and turn glossy as the roads get wet.
// - Optional car liveries (stripes, chequered roof...) drawn in the car's own
//   space, so they follow the body over every panel (car_body.gd sets them).
//
// The snap resolution, affine amount and wetness are global shader uniforms
// (project.godot [shader_globals]) driven by RenderSettings and Weather.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

global uniform vec2 ps1_snap_resolution;
global uniform float ps1_affine_strength;
global uniform float ps1_wetness;
// The story's empty road (scripts/world/late_city/empty_road.gd): 0 normally;
// as it rises to 1 everything goes dark into the void except materials with
// late_keep (the one road left).
global uniform float late_void;
uniform bool late_keep = false;
// Inside the townhouse (HomeBase marks the rooms and what's put in them): the
// flat sky fill mostly stays outside and what gets in is warm, so the lamps
// carry the rooms at night. 0 outdoors, 1 indoors.
// indoor_daylight (0 night, 1 midday, HomeBase sets it) adds the warm
// light that comes in off the courtyard and bounces round the rooms by day.
uniform float indoor = 0.0;
uniform float indoor_daylight = 0.0;
const float INDOOR_FILL = 0.3;
const vec3 INDOOR_TINT = vec3(1.0, 0.9, 0.76);
const vec3 INDOOR_BOUNCE = vec3(0.34, 0.27, 0.19);
#ifdef LATE_SIDES
// The story's other house (scripts/world/late_city/other_house.gd) builds a
// copy of this shader with LATE_SIDES defined, for the house's insides only,
// so the discard below never touches the rest of the world. late_portal: 0 off,
// 1 looking in from outside (1979 only through an open door), 2 inside (all
// 1979). Each door: c = centre (w 1 when open), r and u = unit right and up
// with half the opening's width and height in w.
global uniform float late_portal;
global uniform vec4 late_door_a_c;
global uniform vec4 late_door_a_r;
global uniform vec4 late_door_a_u;
global uniform vec4 late_door_b_c;
global uniform vec4 late_door_b_r;
global uniform vec4 late_door_b_u;
// 1: today's (hidden where 1979 shows), 2: 1979's (only where it shows).
uniform int late_side = 0;

bool late_through(vec4 c, vec4 r, vec4 u, vec3 eye, vec3 p) {
	if (c.w < 0.5) {
		return false;
	}
	vec3 n = cross(r.xyz, u.xyz);
	vec3 d = p - eye;
	float dn = dot(d, n);
	if (abs(dn) < 1e-5) {
		return false;
	}
	float t = dot(c.xyz - eye, n) / dn;
	if (t < 0.0 || t > 1.0) {
		return false;
	}
	vec3 h = eye + d * t - c.xyz;
	return abs(dot(h, r.xyz)) < r.w && abs(dot(h, u.xyz)) < u.w;
}
#endif

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// Optional emission mask (e.g. lit windows). White by default, so emission_color
// alone still works as before. No mipmaps: lit windows stay distinct pixels far
// away instead of averaging into a glowing wall.
uniform sampler2D emission_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
// 0 = ignores rain, 1 = road surface (darkens and gets glossy when wet).
uniform float wet_response : hint_range(0.0, 1.0) = 0.0;
// World-space blockout grid. 0 disables it.
uniform float grid_size = 0.0;
uniform vec4 grid_line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 grid_alt_color : source_color = vec4(1.0);
uniform float vertex_snap : hint_range(0.0, 1.0) = 1.0;
// Car livery. 0 = none, 1 = twin stripes, 2 = chequered roof, 3 = scorpion
// (gold sill band and pinstripes), 4 = side stripe, 5 = two-tone roof.
// livery_space takes world space to the car's model space (X right, Y up,
// -Z forward); livery_min/max are the body's bounds in that space.
uniform int livery_mode = 0;
uniform vec4 livery_color : source_color = vec4(1.0);
uniform mat4 livery_space = mat4(1.0);
uniform vec3 livery_min = vec3(-0.8, 0.2, -1.8);
uniform vec3 livery_max = vec3(0.8, 1.7, 1.8);
// Door number for the rally roundels (livery mode 6), 0..99.
uniform int livery_number = 0;

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

// 1 inside a lit segment of a seven-segment digit. p is in the digit's box:
// x 0..1 left to right, y 0..2 bottom to top.
float seven_segment(vec2 p, int digit) {
	if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 2.0) {
		return 0.0;
	}
	int bits[10] = int[](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);
	int on = bits[clamp(digit, 0, 9)];
	float t = 0.24;
	float lit = 0.0;
	lit = max(lit, float((on & 1) != 0) * step(2.0 - t, p.y));                       // a
	lit = max(lit, float((on & 2) != 0) * step(1.0 - t, p.x) * step(1.0, p.y));      // b
	lit = max(lit, float((on & 4) != 0) * step(1.0 - t, p.x) * step(p.y, 1.0));      // c
	lit = max(lit, float((on & 8) != 0) * step(p.y, t));                             // d
	lit = max(lit, float((on & 16) != 0) * step(p.x, t) * step(p.y, 1.0));           // e
	lit = max(lit, float((on & 32) != 0) * step(p.x, t) * step(1.0, p.y));           // f
	lit = max(lit, float((on & 64) != 0) * step(abs(p.y - 1.0), t * 0.5));           // g
	return lit;
}

void fragment() {
	// Affine warp, capped to a few low-res pixels: on the map's big road and
	// ground triangles the full warp slides whole paving lines and windows
	// across the surface as the camera moves. Off at the Soft default.
	vec2 uv = UV * uv_scale;
	if (ps1_affine_strength > 0.0) {
		vec2 warp = (affine_uv / affine_w - uv) * ps1_affine_strength;
		float uv_per_px = max(max(length(dFdx(uv)), length(dFdy(uv))), 1e-6);
		float max_px = 4.0 * ps1_affine_strength;
		uv += warp * min(1.0, max_px * uv_per_px / max(length(warp), 1e-6));
	}
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

	if (livery_mode > 0) {
		vec3 local = (livery_space * vec4(world_pos, 1.0)).xyz;
		vec3 size = livery_max - livery_min;
		// Across: 0 at the centreline, 1 at the sides. Up: 0 sill, 1 roof.
		float across = abs(local.x - (livery_min.x + livery_max.x) * 0.5) / (size.x * 0.5);
		float up = (local.y - livery_min.y) / size.y;
		float mask = 0.0;
		vec3 paint = livery_color.rgb;
		if (livery_mode == 1) {
			mask = step(0.09, across) * step(across, 0.25);
		} else if (livery_mode == 2) {
			mask = step(0.8, up);
			vec2 cell = floor(local.xz / 0.2);
			paint = mix(vec3(0.05), livery_color.rgb, mod(cell.x + cell.y, 2.0));
		} else if (livery_mode == 3) {
			mask = max(step(0.12, across) * step(across, 0.16), step(0.86, across) * step(0.1, up) * step(up, 0.2));
		} else if (livery_mode == 4) {
			mask = step(0.86, across) * step(0.25, up) * step(up, 0.3);
		} else if (livery_mode == 5) {
			mask = step(0.8, up);
		} else if (livery_mode == 6) {
			// A white roundel on each door with the number in the colour.
			// Read along the side as someone standing beside the car sees it.
			float centre_z = (livery_min.z + livery_max.z) * 0.5 + size.z * 0.02;
			float side = sign(local.x - (livery_min.x + livery_max.x) * 0.5);
			vec2 at = vec2((local.z - centre_z) * -side, local.y - (livery_min.y + size.y * 0.37));
			float radius = size.y * 0.14;
			mask = step(0.82, across) * step(length(at), radius);
			vec2 cell = at / (radius * 0.55);
			int tens = livery_number / 10;
			int ones = livery_number - tens * 10;
			float digit = 0.0;
			if (tens > 0) {
				digit = max(seven_segment(cell + vec2(1.25, 1.0), tens),
					seven_segment(cell + vec2(-0.25, 1.0), ones));
			} else {
				digit = seven_segment(cell + vec2(0.5, 1.0), ones);
			}
			paint = mix(vec3(0.94, 0.93, 0.89), livery_color.rgb, digit);
		} else if (livery_mode == 7) {
			mask = step(across, 0.08);
		}
		// Livery paint weathers a little with the car's wear texture.
		color = mix(color, paint * mix(vec3(1.0), tex.rgb, 0.35), mask);
	}

	float wet = ps1_wetness * wet_response;
	ALBEDO = color * mix(1.0, 0.55, wet);
	ROUGHNESS = mix(roughness, 0.12, wet);
	METALLIC = metallic;
	SPECULAR = mix(0.15, 0.8, wet);
	EMISSION = emission_color.rgb * emission_energy * texture(emission_texture, uv).rgb;
	if (indoor > 0.0) {
		AO = mix(1.0, INDOOR_FILL, indoor);
		AO_LIGHT_AFFECT = 0.0;
		ALBEDO *= mix(vec3(1.0), INDOOR_TINT, indoor);
		EMISSION += ALBEDO * INDOOR_BOUNCE * indoor_daylight * indoor;
	}
	if (!late_keep && late_void > 0.0) {
		float keep = 1.0 - late_void;
		ALBEDO *= keep;
		EMISSION *= keep;
		SPECULAR *= keep;
	}
#ifdef LATE_SIDES
	if (late_side != 0) {
		bool past = late_portal > 1.5;
		// Directional shadow passes (orthographic) keep today's side.
		if (!past && late_portal > 0.5 && PROJECTION_MATRIX[3][3] < 0.5) {
			vec3 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			vec3 eye = CAMERA_POSITION_WORLD;
			past = late_through(late_door_a_c, late_door_a_r, late_door_a_u, eye, p)
				|| late_through(late_door_b_c, late_door_b_r, late_door_b_u, eye, p);
		}
		if ((late_side == 1 && past) || (late_side == 2 && !past)) {
			discard;
		}
	}
#endif
}
