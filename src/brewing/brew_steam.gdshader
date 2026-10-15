shader_type spatial;
// Steam over a hot vessel (BrewHouse's CPU particles): thin camera-facing
// wisps lit by the room's lamps and the fire, brightest looking into a light,
// faded where they would cut into the vessel, the wall or the camera.
// INSTANCE_CUSTOM.x is the particle's spin.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
// How thick the steam is at its densest.
uniform float density = 0.12;
// Metres over which a wisp fades into what lies behind it.
uniform float softness = 0.35;

varying flat float seed;

float hash(vec2 p) {
	vec3 q = fract(p.xyx * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Billboard that keeps the particle's scale and spin (mist.gdshader).
	float spin = INSTANCE_CUSTOM.x;
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(cos(spin), -sin(spin), 0.0, 0.0),
		vec4(sin(spin), cos(spin), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0),
		vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = float(INSTANCE_ID) * 7.31;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	// Wisps, not balls: the noise eats into the puff and streaks it upwards.
	vec2 drift = vec2(seed, seed * 0.37 - TIME * 0.15);
	float wisp = value_noise(c * vec2(2.2, 1.2) + drift) * 0.55 + value_noise(c * vec2(5.3, 2.6) - drift * 1.7) * 0.3
		+ value_noise(c * 11.0 + drift * 2.3) * 0.15;
	float shape = smoothstep(0.35, 0.8, wisp) * (1.0 - smoothstep(0.2, 1.0, length(c)));
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float gap = -behind.z / behind.w + VERTEX.z;
	float soft = smoothstep(0.0, softness, gap) * smoothstep(0.15, 0.9, -VERTEX.z);
	ALBEDO = vec3(0.76, 0.78, 0.8);
	ALPHA = clamp(shape * COLOR.a * density * soft, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Droplets scatter mostly forward: steam glows against a lamp or the fire.
	float wrap = clamp((dot(NORMAL, LIGHT) + 1.0) * 0.5, 0.0, 1.0);
	float forward = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 6.0) * 2.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.3 + 0.7 * wrap + forward) / PI;
}
