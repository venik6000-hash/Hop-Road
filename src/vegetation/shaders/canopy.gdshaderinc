// Where the crowns of the trees close the sky over the ground: the field
// CanopyField stamps of every tree that has a mesh (r: 0 under the open sky
// .. 1 under a spruce; a metre to a texel, coarser views of it in the mips).
// Under the crowns the sky's light is dimmed by it, and beyond the reach of
// the sun's shadow map it is the trees' shadow as well. Needs the global
// `sun_direction` declared before it.

global uniform sampler2D canopy_cover : filter_linear_mipmap, repeat_disable;
// origin x, origin z, cell (m), samples (0 until the field is made).
global uniform vec4 canopy_rect;
// x: the share of the sky's light closed crowns keep from what is under
// them; y: the share of the sun they keep from it where no shadow map does.
global uniform vec2 canopy_light;
// View depths (m) between which the sun's shadow map fades out (RenderQuality).
global uniform vec2 sun_shadow_reach;

// The field gives way to what lies beyond it over its outer metres.
const float CANOPY_EDGE = 24.0;
// The cover of a closed stand, averaged over crowns and the gaps between
// them: what a forest mask (0..1) is worth where the field does not reach.
const float CANOPY_STAND = 0.7;
// Where the crowns of a wood are thickest (m above the ground): a ray from
// the ground to the sun meets them there.
const float CANOPY_HEIGHT = 8.0;
// The mip in which single crowns and the gaps between them run together into
// a stand, four metres to a texel: how wooded the ground is. WIDE_LEVEL of
// CanopyField.
const float CANOPY_WIDE_LEVEL = 2.0;

// The cover at `xz`, blurred to the mip `level` (each one doubles the cell);
// `beyond` where the field does not reach.
float canopy_at(vec2 xz, float level, float beyond) {
	if (canopy_rect.w <= 0.0) {
		return beyond;
	}
	vec2 local = (xz - canopy_rect.xy) / canopy_rect.z;
	vec2 edge = min(local, vec2(canopy_rect.w - 1.0) - local) * canopy_rect.z;
	float inside = clamp(min(edge.x, edge.y) / CANOPY_EDGE, 0.0, 1.0);
	if (inside <= 0.0) {
		return beyond;
	}
	return mix(beyond, textureLod(canopy_cover, (local + 0.5) / canopy_rect.w, level).r, inside);
}

// How much of the ground is a wood's floor of needles and leaves where the
// stand round it is `wooded` (canopy_at() at CANOPY_WIDE_LEVEL or blurrier).
// FLOOR of CanopyField: the grass's jobs grow a wood's plants by the same
// number.
float canopy_floor(float wooded) {
	return smoothstep(0.12, 0.45, wooded);
}

// How far along the ground a ray to the sun has run by the time it has
// climbed `rise` metres. A sun on the horizon would run it out of the wood.
vec2 canopy_run(float rise) {
	return sun_direction.xz * (rise / max(sun_direction.y, 0.2));
}

// The share of the sky's light the crowns over `xz` keep from what is under
// them.
float canopy_sky_shade(vec2 xz, float level, float beyond) {
	return canopy_light.x * canopy_at(xz, level, beyond);
}

// The share of the sun the crowns keep from a point at `xz` whose ray to the
// sun has `rise` metres to climb to them: none at a view depth the shadow
// map still covers, all they hold past its end. The farther the ray runs,
// the more crowns it may meet, and the blurrier the answer.
float canopy_sun_shade(vec2 xz, float rise, float depth, float beyond) {
	float past = smoothstep(sun_shadow_reach.x, sun_shadow_reach.y, depth);
	if (past <= 0.0 || sun_direction.y <= 0.02) {
		return 0.0;
	}
	vec2 run = canopy_run(rise);
	float level = clamp(log2(max(length(run) * 0.4, 1.0)), 1.0, 4.0);
	return canopy_light.y * past * canopy_at(xz + run, level, beyond);
}
