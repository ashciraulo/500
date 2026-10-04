// Full-screen lo-fi pass, applied to the SubViewportContainer that shows the
// low-res 3D render. Reduces colour depth with an ordered (Bayer) dither in
// low-res pixel space, like the PS1's 15-bit output.
shader_type canvas_item;

uniform float color_levels = 32.0;
uniform bool dither_enabled = true;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;
// Gentle contrast/saturation grade for the "faded VHS" look.
uniform float saturation = 0.92;
uniform float contrast = 1.04;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5;

	if (dither_enabled) {
		ivec2 px = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
		float threshold = BAYER[(px.y % 4) * 4 + (px.x % 4)] / 16.0 - 0.5;
		c += threshold * dither_strength / color_levels;
	}
	c = floor(clamp(c, 0.0, 1.0) * (color_levels - 1.0) + 0.5) / (color_levels - 1.0);
	COLOR = vec4(c, 1.0);
}
