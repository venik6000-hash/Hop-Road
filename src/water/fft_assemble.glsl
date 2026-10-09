#[compute]
#version 450
// After both FFT passes: undo the centred-spectrum shift ((-1)^(x+z)), apply
// choppiness, and write what the surface shader samples:
//   displacement[c] = (x, y, z displacement, foam)
//   derivatives[c]  = (dh/dx, dh/dz, dDx/dx, dDz/dz)
// Foam is the folding of the surface (Jacobian of the horizontal map below a
// threshold), kept from frame to frame and fading, so whitecaps linger.
#include "fft_common.glslinc"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2DArray signals;
layout(rgba16f, set = 0, binding = 1) uniform restrict image2DArray displacement;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2DArray derivatives;

layout(push_constant, std430) uniform Params {
	vec4 choppiness;
	vec4 foam_weight;
	float foam_bias;
	float foam_scale;
	float foam_decay;
	float delta_time;
} p;

void main() {
	uvec3 id = gl_GlobalInvocationID;
	if (id.x >= N || id.y >= N) {
		return;
	}
	uint cascade = id.z;
	float shift = ((id.x + id.y) & 1u) == 1u ? -1.0 : 1.0;
	vec4 a = imageLoad(signals, ivec3(id.xy, cascade * 2u)) * shift;       // Dx, Dz, h, dDx/dz
	vec4 b = imageLoad(signals, ivec3(id.xy, cascade * 2u + 1u)) * shift;  // dh/dx, dh/dz, dDx/dx, dDz/dz
	float lambda = p.choppiness[cascade];
	vec3 offset = vec3(lambda * a.x, a.z, lambda * a.y);
	float jxx = 1.0 + lambda * b.z;
	float jzz = 1.0 + lambda * b.w;
	float jxz = lambda * a.w;
	float jacobian = jxx * jzz - jxz * jxz;
	float previous = imageLoad(displacement, ivec3(id.xy, cascade)).a;
	float fresh = clamp((p.foam_bias - jacobian) * p.foam_scale, 0.0, 1.0) * p.foam_weight[cascade];
	float foam = max(previous * exp(-p.foam_decay * p.delta_time), fresh);
	imageStore(displacement, ivec3(id.xy, cascade), vec4(offset, foam));
	imageStore(derivatives, ivec3(id.xy, cascade), vec4(b.x, b.y, lambda * b.z, lambda * b.w));
}
