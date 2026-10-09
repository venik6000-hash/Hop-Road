#[compute]
#version 450
// One 256-point inverse FFT per workgroup, in shared memory, on two complex
// signals at once (an rgba32f texel). Stockham radix-2 auto-sort (Govindaraju
// et al. 2008): natural order in, natural order out, no bit reversal.
// Run once along rows, once along columns.
#include "fft_common.glslinc"

layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;
layout(rgba32f, set = 0, binding = 0) uniform restrict image2DArray signals;

layout(push_constant, std430) uniform Params {
	uint vertical;
	uint pad0;
	uint pad1;
	uint pad2;
} p;

shared vec4 buffer_a[N];
shared vec4 buffer_b[N];

ivec3 texel(uint line, uint index, uint layer) {
	return p.vertical == 1u ? ivec3(line, index, layer) : ivec3(index, line, layer);
}

void main() {
	uint line = gl_WorkGroupID.x;
	uint layer = gl_WorkGroupID.y;
	uint t = gl_LocalInvocationID.x;
	buffer_a[t] = imageLoad(signals, texel(line, t, layer));
	buffer_a[t + N / 2u] = imageLoad(signals, texel(line, t + N / 2u, layer));
	barrier();
	bool from_a = true;
	for (uint ns = 1u; ns < N; ns <<= 1u) {
		uint j = t;
		float angle = TAU * float(j % ns) / float(ns * 2u);
		vec2 w = vec2(cos(angle), sin(angle));
		vec4 a = from_a ? buffer_a[j] : buffer_b[j];
		vec4 b = from_a ? buffer_a[j + N / 2u] : buffer_b[j + N / 2u];
		b = vec4(cmul(b.xy, w), cmul(b.zw, w));
		uint destination = (j / ns) * ns * 2u + (j % ns);
		if (from_a) {
			buffer_b[destination] = a + b;
			buffer_b[destination + ns] = a - b;
		} else {
			buffer_a[destination] = a + b;
			buffer_a[destination + ns] = a - b;
		}
		from_a = !from_a;
		barrier();
	}
	vec4 lo = from_a ? buffer_a[t] : buffer_b[t];
	vec4 hi = from_a ? buffer_a[t + N / 2u] : buffer_b[t + N / 2u];
	imageStore(signals, texel(line, t, layer), lo);
	imageStore(signals, texel(line, t + N / 2u, layer), hi);
}
