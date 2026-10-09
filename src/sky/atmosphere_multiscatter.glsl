#[compute]
#version 450
// Multiple-scattering transfer (Hillaire 2020, eq. 5-10): one workgroup per
// texel, 64 threads integrate 64 directions of a uniform sphere.
#include "atmosphere_common.glslinc"

layout(local_size_x = 1, local_size_y = 1, local_size_z = 64) in;
layout(set = 0, binding = 0) uniform sampler2D transmittance_lut;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D out_lut;
layout(push_constant, std430) uniform Params {
	vec4 tune;
	vec4 size;
} params;

#include "atmosphere_integrate.glslinc"

shared vec3 shared_multi[64];
shared vec3 shared_luminance[64];

void main() {
	ivec2 texel = ivec2(gl_WorkGroupID.xy);
	uint index = gl_LocalInvocationID.z;
	vec2 uv = (vec2(texel) + 0.5) / params.size.xy;
	uv = (uv * params.size.xy - 0.5) / (params.size.xy - 1.0);
	float sun_zenith_cos = uv.x * 2.0 - 1.0;
	vec3 sun_dir = vec3(sqrt(max(0.0, 1.0 - sun_zenith_cos * sun_zenith_cos)), sun_zenith_cos, 0.0);
	float r = R_GROUND + clamp(uv.y + 1e-4, 0.0, 1.0) * (R_TOP - R_GROUND - 1e-3);
	vec3 origin = vec3(0.0, r, 0.0);

	float a = (float(index % 8u) + 0.5) / 8.0;
	float b = (float(index / 8u) + 0.5) / 8.0;
	float theta = 2.0 * PI * a;
	float phi = acos(1.0 - 2.0 * b);
	vec3 dir = vec3(cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi));
	ScatterResult result = integrate_scattering(origin, dir, sun_dir, 20, true, true, params.tune);
	shared_multi[index] = result.multi_scatter_as_1 / 64.0;
	shared_luminance[index] = result.luminance / 64.0;
	barrier();
	for (uint stride = 32u; stride > 0u; stride >>= 1u) {
		if (index < stride) {
			shared_multi[index] += shared_multi[index + stride];
			shared_luminance[index] += shared_luminance[index + stride];
		}
		barrier();
	}
	if (index == 0u) {
		vec3 transfer = shared_multi[0];
		vec3 psi = shared_luminance[0] / max(vec3(1.0) - transfer, vec3(1e-3));
		imageStore(out_lut, texel, vec4(psi, 1.0));
	}
}
