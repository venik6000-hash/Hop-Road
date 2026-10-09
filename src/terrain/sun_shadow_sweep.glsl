#[compute]
#version 450
// The height up to which the terrain shadows each point of a field, and the
// distance to what shadows it. Seeded with the ground itself, then swept
// toward the sun in steps that double: after pass k a texel knows every
// occluder within 2^(k+1) - 1 cells, so ten passes cross 1024 cells.
#include "sun_shadow_common.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 2) uniform sampler2D source;       // r shadow height, g distance
layout(set = 0, binding = 3) uniform sampler2D coarse_field; // the finished far field
layout(rg32f, set = 0, binding = 4) uniform restrict writeonly image2D target;

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	int size = int(params.field_rect.w);
	if (any(greaterThanEqual(texel, ivec2(size)))) {
		return;
	}
	vec2 xz = field_xz(texel);
	if (params.mode.x < 0.5) {
		imageStore(target, texel, vec4(height_at(xz), 0.0, 0.0, 0.0));
		return;
	}
	vec2 here = texelFetch(source, texel, 0).rg;
	vec2 at = xz + params.sweep.xy * params.sweep.z;
	vec2 local = (at - params.field_rect.xy) / params.field_rect.z;
	vec2 from = vec2(-1e9, 0.0);
	if (all(greaterThanEqual(local, vec2(0.0))) && all(lessThanEqual(local, vec2(float(size) - 1.0)))) {
		from = textureLod(source, (local + 0.5) / float(size), 0.0).rg;
	} else if (params.coarse_rect.w > 0.0) {
		// Beyond the near field the far one already knows the mountains.
		vec2 coarse = (at - params.coarse_rect.xy) / params.coarse_rect.z;
		if (all(greaterThanEqual(coarse, vec2(0.0))) && all(lessThanEqual(coarse, vec2(params.coarse_rect.w - 1.0)))) {
			vec3 far = textureLod(coarse_field, (coarse + 0.5) / params.coarse_rect.w, 0.0).rgb;
			from = vec2(far.b + far.r, far.g);
		}
	}
	float shadow = from.x - params.sweep.w;
	if (shadow > here.x) {
		here = vec2(shadow, from.y + params.sweep.z * params.mode.y);
	}
	imageStore(target, texel, vec4(here, 0.0, 0.0));
}
