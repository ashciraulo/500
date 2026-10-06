shader_type canvas_item;
// The overview's painted ground (map/tiles/overview.p5o, 10 m a pixel) drawn
// as a street-directory page. Each texel is matched to the painter's colours
// (tools/osm_import/osm_import/overview.py COLORS) and sorted into a layer;
// each layer's coverage is blended between texels and cut at half, so the
// coast and the river come out as smooth curves instead of 10 m steps.

uniform vec4 land : source_color = vec4(0.953, 0.918, 0.843, 1.0);
uniform vec4 built : source_color = vec4(0.906, 0.867, 0.784, 1.0);
uniform vec4 green : source_color = vec4(0.808, 0.851, 0.69, 1.0);
uniform vec4 sand : source_color = vec4(0.965, 0.906, 0.749, 1.0);
uniform vec4 water : source_color = vec4(0.62, 0.8, 0.784, 1.0);
uniform vec4 shore : source_color = vec4(0.38, 0.62, 0.62, 1.0);
// How strongly built-up blocks show (0 hides them).
uniform float built_amount = 1.0;
// Night: dims the page a little.
uniform float night = 0.0;

// Layers: 0 land, 1 built, 2 green, 3 sand, 4 water.
int layer_of(vec3 c) {
	vec3 cols[15] = vec3[](
		vec3(150, 146, 132), vec3(40, 72, 88), vec3(92, 116, 60), vec3(74, 84, 50),
		vec3(88, 128, 60), vec3(210, 194, 152), vec3(70, 82, 60), vec3(150, 148, 142),
		vec3(132, 108, 78), vec3(160, 158, 152), vec3(64, 64, 66), vec3(52, 52, 54),
		vec3(176, 170, 160), vec3(120, 136, 150), vec3(100, 92, 84));
	int layers[15] = int[](0, 4, 2, 2, 2, 3, 2, 0, 0, 0, 0, 0, 1, 1, 0);
	vec3 p = c * 255.0;
	float best = 1e9;
	int out_layer = 0;
	for (int i = 0; i < 15; i++) {
		vec3 d = p - cols[i];
		float dd = dot(d, d);
		if (dd < best) {
			best = dd;
			out_layer = layers[i];
		}
	}
	return out_layer;
}

float cut(float m) {
	float e = max(fwidth(m), 0.0001) * 0.75;
	return smoothstep(0.5 - e, 0.5 + e, m);
}

// Cubic B-spline weights for a fraction f (sum to 1): smoother edges than
// blending only the four nearest texels.
vec4 bspline(float f) {
	float g = 1.0 - f;
	return vec4(g * g * g, 3.0 * f * f * f - 6.0 * f * f + 4.0, 3.0 * g * g * g - 6.0 * g * g + 4.0, f * f * f) / 6.0;
}

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	vec2 p = UV * vec2(size) - 0.5;
	ivec2 b = ivec2(floor(p));
	vec2 f = fract(p);
	vec4 wx = bspline(f.x);
	vec4 wy = bspline(f.y);
	float m[5] = float[](0.0, 0.0, 0.0, 0.0, 0.0);
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			ivec2 at = clamp(b + ivec2(i - 1, j - 1), ivec2(0), size - 1);
			int l = layer_of(texelFetch(TEXTURE, at, 0).rgb);
			m[l] += wx[i] * wy[j];
		}
	}
	vec3 col = land.rgb;
	col = mix(col, built.rgb, cut(m[1]) * built_amount);
	col = mix(col, green.rgb, cut(m[2]));
	col = mix(col, sand.rgb, cut(m[3]));
	float wet = cut(m[4]);
	col = mix(col, water.rgb, wet);
	// A darker line along the shore, about a pixel and a half wide.
	float px = abs(m[4] - 0.5) / max(fwidth(m[4]), 0.0001);
	col = mix(col, shore.rgb, (1.0 - smoothstep(0.6, 1.6, px)) * 0.8);
	col *= mix(1.0, 0.72, night);
	COLOR = vec4(col, 1.0);
}
