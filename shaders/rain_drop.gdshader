shader_type spatial;
// Rain streaks: unshaded, see-through, turned to face the camera about the
// vertical (like a fixed-Y billboard), and gone wherever there's a roof.
// EnvironmentController fills `shelters` with boxes (house interiors, the
// carport, shops, the car) as world -> unit-cube transforms: a drop whose
// centre lands inside [-1, 1] of any of them isn't drawn.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

const int MAX_SHELTERS = 8;

uniform vec4 albedo : source_color = vec4(0.72, 0.78, 0.88, 0.35);
uniform int shelter_count = 0;
uniform mat4 shelters[MAX_SHELTERS];

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	bool sheltered = false;
	for (int i = 0; i < MAX_SHELTERS; i++) {
		if (i >= shelter_count) {
			break;
		}
		vec3 p = (shelters[i] * vec4(centre, 1.0)).xyz;
		if (all(lessThanEqual(abs(p), vec3(1.0)))) {
			sheltered = true;
		}
	}
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	vec3 facing = normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(facing, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	if (sheltered) {
		// Collapse the quad to a point: nothing is drawn.
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
}
