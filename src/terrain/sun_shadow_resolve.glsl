#[compute]
#version 450
// The swept field as the shaders read it: how far the shadow stands above
// the ground (0 in the sun), the distance to what casts it, the ground.
#include "sun_shadow_common.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 2) uniform sampler2D source;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D target;

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(texel, ivec2(int(params.field_rect.w))))) {
		return;
	}
	vec2 swept = texelFetch(source, texel, 0).rg;
	float ground = height_at(field_xz(texel));
	imageStore(target, texel, vec4(max(swept.x - ground, 0.0), swept.y, ground, 1.0));
}
