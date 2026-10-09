#[compute]
#version 450
// Water surface height under given world x/z points, for swimming and floating.
// The surface is a displaced grid, so the grid point that lands on the query
// is found by fixed-point iteration before its height is read.
#include "fft_common.glslinc"

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2DArray displacement;
layout(set = 0, binding = 1, std430) restrict readonly buffer Queries {
	vec4 points[];
} queries;
layout(set = 0, binding = 2, std430) restrict writeonly buffer Results {
	vec4 values[];
} results;

layout(push_constant, std430) uniform Params {
	vec4 tiles;
	vec4 weights;
	uint count;
	uint pad0;
	uint pad1;
	uint pad2;
} p;

vec4 surface(vec2 xz) {
	vec4 sum = vec4(0.0);
	for (uint c = 0u; c < 3u; c++) {
		sum += textureLod(displacement, vec3(xz / p.tiles[c], float(c)), 0.0) * p.weights[c];
	}
	return sum;
}

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= p.count) {
		return;
	}
	vec2 target = queries.points[i].xy;
	// The surface shader damps waves over shallows and varies them with gusts;
	// the caller passes that factor so heights match what is drawn.
	float scale = queries.points[i].z;
	vec2 origin = target;
	for (int iteration = 0; iteration < 4; iteration++) {
		origin = target - surface(origin).xz * scale;
	}
	vec4 s = surface(origin) * scale;
	results.values[i] = vec4(s.y, s.x, s.z, s.w);
}
