#[compute]
#version 450
// Transmittance from a point at radius r toward view-zenith cosine mu, to space.
#include "atmosphere_common.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D out_lut;
layout(push_constant, std430) uniform Params {
	vec4 tune;
	vec4 size;
} params;

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(texel, ivec2(params.size.xy)))) {
		return;
	}
	vec2 uv = (vec2(texel) + 0.5) / params.size.xy;
	uv = (uv * params.size.xy - 0.5) / (params.size.xy - 1.0);
	float r;
	float mu;
	transmittance_params(uv, r, mu);
	vec3 origin = vec3(0.0, r, 0.0);
	vec3 dir = vec3(sqrt(max(0.0, 1.0 - mu * mu)), mu, 0.0);
	float t_max = ray_sphere(origin, dir, R_TOP);
	vec3 optical_depth = vec3(0.0);
	const int STEPS = 48;
	float dt = max(t_max, 0.0) / float(STEPS);
	for (int i = 0; i < STEPS; i++) {
		vec3 p = origin + dir * (float(i) + 0.5) * dt;
		optical_depth += sample_medium(length(p) - R_GROUND, params.tune).extinction * dt;
	}
	imageStore(out_lut, texel, vec4(exp(-optical_depth), 1.0));
}
