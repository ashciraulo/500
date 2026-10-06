shader_type canvas_item;
// A road layer from MapData: vertices sit on the centreline and UV is the
// way out to the edge times the road's width. Roads draw at their real width
// but never thinner than `min_px` screen pixels, and `outline_px` widens them
// for the dark casing drawn underneath.

uniform vec4 color : source_color = vec4(1.0);
uniform float min_px = 1.0;
uniform float outline_px = 0.0;

void vertex() {
	float w = length(UV);
	if (w > 0.0) {
		// Metres per pixel, from the layer's own scale.
		float mpp = 1.0 / max(length(MODEL_MATRIX[0].xy), 0.000001);
		float s = max(1.0, min_px * mpp / w);
		VERTEX += UV * 0.5 * s + UV / w * outline_px * mpp;
	}
}

void fragment() {
	COLOR = color;
}
