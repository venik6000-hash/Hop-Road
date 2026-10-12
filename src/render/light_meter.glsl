#[compute]
#version 450
// The light meter (LightMeter): the mean log2 luminance of the HDR image, as
// it is before exposure, in each cell of a coarse grid, from a few taps a cell.
layout(local_size_x = 8, local_size_y = 8) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D meter_image;
layout(push_constant, std430) uniform Params {
	vec2 size;  // of the picture, pixels
	vec2 pad;
} p;

const int TAPS = 4;

void main() {
	ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
	ivec2 cells = imageSize(meter_image);
	if (cell.x >= cells.x || cell.y >= cells.y) return;
	float sum = 0.0;
	for (int j = 0; j < TAPS; j++) {
		for (int i = 0; i < TAPS; i++) {
			vec2 at = (vec2(cell) + (vec2(i, j) + 0.5) / float(TAPS)) / vec2(cells);
			vec3 colour = imageLoad(color_image, ivec2(at * p.size)).rgb;
			sum += log2(max(dot(colour, vec3(0.2126, 0.7152, 0.0722)), 1e-5));
		}
	}
	imageStore(meter_image, cell, vec4(sum / float(TAPS * TAPS)));
}
