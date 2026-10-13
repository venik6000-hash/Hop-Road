shader_type spatial;
// The glow round a candle's flame (TavernLights.add_halos): a square that
// faces the eye, one instance a flame, as wide as the instance's scale. It is
// drawn over everything and put out as the flame itself goes behind
// something, so no wall cuts it.
render_mode unshaded, blend_add, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled,
	fog_disabled, skip_vertex_transform;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 halo_color : source_color = vec3(1.0, 0.62, 0.28);
uniform float energy = 0.4;

varying float seen;
varying float seed;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float radius = length(MODEL_MATRIX[0].xyz);
	seed = dot((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, vec3(3.7, 1.3, 5.1));
	// How much of the flame shows: five looks at the depth around it.
	vec4 clip = PROJECTION_MATRIX * vec4(centre, 1.0);
	vec2 at = clip.xy / clip.w * 0.5 + 0.5;
	vec4 edge = PROJECTION_MATRIX * vec4(centre + vec3(0.02, 0.0, 0.0), 1.0);
	float spread = abs(edge.x / edge.w * 0.5 + 0.5 - at.x);
	seen = 0.0;
	for (int i = 0; i < 5; i++) {
		vec2 offset = i == 0 ? vec2(0.0) : vec2(i < 3 ? 1.0 : -1.0, (i & 1) == 1 ? 1.0 : -1.0);
		vec2 uv = clamp(at + offset * spread, vec2(0.001), vec2(0.999));
		vec4 behind = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, textureLod(depth_texture, uv, 0.0).r, 1.0);
		seen += step(-centre.z - 0.06, -behind.z / behind.w) * 0.2;
	}
	seen *= step(0.0, -centre.z);
	VERTEX = centre + vec3(VERTEX.xy * radius, 0.0);
}

void fragment() {
	if (seen < 0.01) {
		discard;
	}
	float r = length(UV * 2.0 - 1.0);
	float glow = (exp(-r * r * 9.0) * 0.55 + exp(-r * r * 60.0)) * (1.0 - smoothstep(0.6, 1.0, r));
	float flicker = 0.9 + 0.1 * sin(TIME * 9.0 + seed) * sin(TIME * 5.3 + seed * 1.7);
	ALBEDO = halo_color * (energy * glow * seen * flicker);
}
