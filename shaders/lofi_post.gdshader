// Full-screen lo-fi pass, applied to the SubViewportContainer that shows the
// low-res 3D render. Reduces colour depth with an ordered (Bayer) dither in
// low-res pixel space, like the PS1's 15-bit output.
shader_type canvas_item;

uniform float color_levels = 32.0;
uniform bool dither_enabled = true;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;
// Blends the hard nearest-neighbour pixels towards a smooth (bilinear)
// upscale, taking the sting out of the stair-steps without losing the
// low-res look.
uniform float softness : hint_range(0.0, 1.0) = 0.0;
// Gentle contrast/saturation grade for the "faded VHS" look.
uniform float saturation = 0.92;
uniform float contrast = 1.04;
// Photo-mode filters: a colour tint and a soft vignette.
uniform vec3 tint : source_color = vec3(1.0);
uniform float vignette : hint_range(0.0, 1.5) = 0.0;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	if (softness > 0.0) {
		vec2 texel = UV / TEXTURE_PIXEL_SIZE - 0.5;
		vec2 f = fract(texel);
		vec2 base = (floor(texel) + 0.5) * TEXTURE_PIXEL_SIZE;
		vec3 a = texture(TEXTURE, base).rgb;
		vec3 b = texture(TEXTURE, base + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).rgb;
		vec3 d = texture(TEXTURE, base + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).rgb;
		vec3 e = texture(TEXTURE, base + TEXTURE_PIXEL_SIZE).rgb;
		vec3 smooth_c = mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
		c = mix(c, smooth_c, softness);
	}
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint;
	vec2 v = UV - 0.5;
	c *= 1.0 - vignette * dot(v, v) * 1.6;

	if (dither_enabled) {
		ivec2 px = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
		float threshold = BAYER[(px.y % 4) * 4 + (px.x % 4)] / 16.0 - 0.5;
		c += threshold * dither_strength / color_levels;
	}
	c = floor(clamp(c, 0.0, 1.0) * (color_levels - 1.0) + 0.5) / (color_levels - 1.0);
	COLOR = vec4(c, 1.0);
}
