// The mountains' shadow on whatever stands in the valley, from the fields
// SunShadowField builds (r: how far the shadow stands above the ground, 0 in
// the sun; g: distance to its caster, m; b: the ground's height). Needs the
// global `sun_direction` declared before it.

global uniform sampler2D sun_shadow_near : filter_linear, repeat_disable;
global uniform sampler2D sun_shadow_far : filter_linear, repeat_disable;
// origin x, origin z, cell (m), samples (0 until the first field is built).
global uniform vec4 sun_shadow_near_rect;
global uniform vec4 sun_shadow_far_rect;

// The sun's disc is 0.53 degrees wide: a shadow's edge is that much of the
// distance to its caster.
const float SUN_SHADOW_SPREAD = 0.0093;

// r, g, b of the field at `xz`; `soft` is the least half-width (m, in height)
// a shadow's edge can have at the field's grain there.
vec3 sun_shadow_field(vec2 xz, out float soft) {
	vec3 field = textureLod(sun_shadow_far, ((xz - sun_shadow_far_rect.xy) / sun_shadow_far_rect.z + 0.5)
		/ sun_shadow_far_rect.w, 0.0).rgb;
	soft = sun_shadow_far_rect.z * 0.3;
	vec2 local = (xz - sun_shadow_near_rect.xy) / sun_shadow_near_rect.z;
	vec2 edge = min(local, vec2(sun_shadow_near_rect.w - 1.0) - local) * sun_shadow_near_rect.z;
	float w = clamp(min(edge.x, edge.y) / 40.0, 0.0, 1.0);
	if (w > 0.0) {
		field = mix(field, textureLod(sun_shadow_near, (local + 0.5) / sun_shadow_near_rect.w, 0.0).rgb, w);
		soft = mix(soft, sun_shadow_near_rect.z * 0.4, w);
	}
	return field;
}

float sun_shadow_edge(vec3 field, float above, float soft) {
	float half_width = max(soft, field.g * SUN_SHADOW_SPREAD);
	return 1.0 - smoothstep(0.0, 2.0 * half_width, field.r - above - soft * 0.5);
}

// 1 in the sun .. 0 in a ridge's shadow, for a point of the ground itself.
float ground_sun_visibility(vec2 xz) {
	if (sun_shadow_far_rect.w <= 0.0 || sun_direction.y <= 0.02) {
		return 1.0;
	}
	float soft;
	vec3 field = sun_shadow_field(xz, soft);
	return sun_shadow_edge(field, 0.0, soft);
}

// The same for a point anywhere: what stands above the shadow's top is lit
// (a crown catches the last sun over a meadow already in shade).
float ridge_sun_visibility(vec3 p) {
	if (sun_shadow_far_rect.w <= 0.0 || sun_direction.y <= 0.02) {
		return 1.0;
	}
	float soft;
	vec3 field = sun_shadow_field(p.xz, soft);
	return sun_shadow_edge(field, max(p.y - field.b, 0.0), soft);
}
