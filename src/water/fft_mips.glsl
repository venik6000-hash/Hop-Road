#[compute]
#version 450
// Box-filtered mip level of a 2D array: distant water samples averaged waves
// instead of aliasing single texels into sparkle noise.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2DArray source;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2DArray target;
// The two wave fields are independent; retain the same four-tap order for each.
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2DArray derivatives_source;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2DArray derivatives_target;

layout(push_constant, std430) uniform Params {
	uint size;   // target size
	uint pad0;
	uint pad1;
	uint pad2;
} p;

void main() {
	uvec3 id = gl_GlobalInvocationID;
	if (id.x >= p.size || id.y >= p.size) {
		return;
	}
	ivec2 base = ivec2(id.xy) * 2;
	vec4 sum = imageLoad(source, ivec3(base, id.z)) + imageLoad(source, ivec3(base + ivec2(1, 0), id.z))
			+ imageLoad(source, ivec3(base + ivec2(0, 1), id.z)) + imageLoad(source, ivec3(base + ivec2(1, 1), id.z));
	imageStore(target, ivec3(id.xy, id.z), sum * 0.25);
	vec4 derivatives_sum = imageLoad(derivatives_source, ivec3(base, id.z)) + imageLoad(derivatives_source, ivec3(base + ivec2(1, 0), id.z))
			+ imageLoad(derivatives_source, ivec3(base + ivec2(0, 1), id.z)) + imageLoad(derivatives_source, ivec3(base + ivec2(1, 1), id.z));
	imageStore(derivatives_target, ivec3(id.xy, id.z), derivatives_sum * 0.25);
}
