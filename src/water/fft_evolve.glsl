#[compute]
#version 450
// h(k, t) and the spectra of everything the surface needs, packed two real
// fields per complex signal (4 signals, 2 layers per cascade):
//   layer 2c:   (Dx + i Dz, h + i dDx/dz)
//   layer 2c+1: (dh/dx + i dh/dz, dDx/dx + i dDz/dz)
#include "fft_common.glslinc"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2DArray h0_in;
layout(rgba32f, set = 0, binding = 1) uniform restrict writeonly image2DArray signals;

layout(push_constant, std430) uniform Params {
	vec4 tiles;     // tile size per cascade
	float time;
	float gravity;
	float depth;
	float pad;
} p;

void main() {
	uvec3 id = gl_GlobalInvocationID;
	if (id.x >= N || id.y >= N) {
		return;
	}
	uint cascade = id.z;
	vec2 k = wave_vector(id.xy, p.tiles[cascade]);
	float kl = length(k);
	vec4 h0 = imageLoad(h0_in, ivec3(id.xy, cascade));
	float omega = sqrt(p.gravity * kl * tanh(min(kl * p.depth, 20.0)));
	float phase = omega * p.time;
	vec2 spin = vec2(cos(phase), sin(phase));
	vec2 h = cmul(h0.xy, spin) + cmul(h0.zw, cconj(spin));
	float inv_k = kl > 1e-6 ? 1.0 / kl : 0.0;
	vec2 ih = ci(h);
	// Choppy displacement D = -i k/|k| h; derivatives multiply by i k.
	vec2 dx = -ih * k.x * inv_k;
	vec2 dz = -ih * k.y * inv_k;
	vec2 dxdz = h * (k.x * k.y * inv_k);
	vec2 dhdx = ih * k.x;
	vec2 dhdz = ih * k.y;
	vec2 dxdx = h * (k.x * k.x * inv_k);
	vec2 dzdz = h * (k.y * k.y * inv_k);
	imageStore(signals, ivec3(id.xy, cascade * 2u), vec4(pack(dx, dz), pack(h, dxdz)));
	imageStore(signals, ivec3(id.xy, cascade * 2u + 1u), vec4(pack(dhdx, dhdz), pack(dxdx, dzdz)));
}
