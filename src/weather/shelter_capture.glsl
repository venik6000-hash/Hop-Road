#[compute]
#version 450
// RainShelter's map of what the rain falls on first: for each x/z, the height
// of the highest roof, awning, rock or ground.
//
// mode 0 turns one view from straight above (its depth) into heights and puts
// them where they belong in the map. Modes 1 and 2 are the two halves of an
// opening, a lowest and then a highest value over a small disc: it takes out
// of the map what is too thin to shelter anything (a post, a walker's head)
// and leaves roofs, slopes and their edges where they were.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// mode 0: the view's depth; modes 1 and 2: the map so far.
layout(set = 0, binding = 0) uniform sampler2D source;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D target;

layout(push_constant, std430) uniform Params {
	mat4 to_world;  // mode 0: NDC of the view's image (y down) -> world
	vec4 map;       // x, z of the map's corner (m), metres a texel, the mode
} p;

// A texel nothing was drawn over.
const float NOTHING = -10000.0;
// Texels the opening reaches each way.
const int REACH = 2;

void main() {
	ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
	int mode = int(p.map.w + 0.5);
	if (mode == 0) {
		ivec2 size = textureSize(source, 0);
		if (any(greaterThanEqual(cell, size))) {
			return;
		}
		// Reversed depth: 0 is the far plane, with nothing before it.
		float raw = texelFetch(source, cell, 0).r;
		vec4 world = p.to_world * vec4((vec2(cell) + 0.5) / vec2(size) * 2.0 - 1.0, raw, 1.0);
		world /= world.w;
		ivec2 texel = ivec2(floor((world.xz - p.map.xy) / p.map.z));
		if (any(lessThan(texel, ivec2(0))) || any(greaterThanEqual(texel, imageSize(target)))) {
			return;
		}
		imageStore(target, texel, vec4(raw > 0.0 ? world.y : NOTHING));
		return;
	}
	ivec2 size = imageSize(target);
	if (any(greaterThanEqual(cell, size))) {
		return;
	}
	float value = mode == 1 ? 1e9 : -1e9;
	for (int dz = -REACH; dz <= REACH; dz++) {
		for (int dx = -REACH; dx <= REACH; dx++) {
			if (dx * dx + dz * dz > REACH * REACH + 1) {
				continue;
			}
			float beside = texelFetch(source, clamp(cell + ivec2(dx, dz), ivec2(0), size - 1), 0).r;
			value = mode == 1 ? min(value, beside) : max(value, beside);
		}
	}
	imageStore(target, cell, vec4(value));
}
