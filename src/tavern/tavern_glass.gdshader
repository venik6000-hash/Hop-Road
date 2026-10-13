shader_type spatial;
// Old window glass of the tavern: nearly clear with a faint green, the
// slow waves of crown and cylinder glass bending what it reflects, a little
// dust. Premultiplied blending keeps the reflections at full strength while
// the room behind shows through; UV is metres across the pane.
render_mode blend_premul_alpha, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec3 glass_tint : source_color = vec3(0.86, 0.92, 0.88);
uniform float clarity = 0.1;
uniform float roughness_value = 0.04;
uniform float wave = 0.05;
// Leaded lights: UV counts quarries of `pane` metres, and each is set a
// little out of true, by `quarry_tilt`, so no two catch the light alike.
uniform float quarry_tilt = 0.0;
uniform float pane = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float ripple(vec2 p) {
	return sin(p.x * 3.1 + sin(p.y * 2.3) * 1.7) * 0.5 + sin(p.y * 4.3 + sin(p.x * 1.9) * 1.3) * 0.5;
}

void fragment() {
	// Each pane its own waves: the pane's position seeds them.
	vec2 p = UV * pane * 9.0 + world_pos.xz * 0.37;
	float e = 0.02;
	vec2 slope = vec2(ripple(p + vec2(e, 0.0)) - ripple(p - vec2(e, 0.0)),
		ripple(p + vec2(0.0, e)) - ripple(p - vec2(0.0, e))) / (2.0 * e);
	vec2 lean = slope * wave;
	if (quarry_tilt > 0.0) {
		vec2 quarry = floor(UV);
		lean += (fract(sin(vec2(dot(quarry, vec2(127.1, 311.7)), dot(quarry, vec2(269.5, 183.3)))) * 43758.5453) - 0.5)
			* quarry_tilt;
	}
	NORMAL = normalize(NORMAL + TANGENT * lean.x + BINORMAL * lean.y);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 5.0);
	float dust = smoothstep(0.35, 0.9, sin(world_pos.x * 7.3 + world_pos.y * 5.1) * sin(world_pos.z * 6.7 - world_pos.y * 3.9));
	ALBEDO = glass_tint * 0.25;
	ALPHA = clamp(clarity + dust * 0.04 + fresnel * 0.6, 0.0, 0.92);
	ROUGHNESS = roughness_value + dust * 0.1;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
