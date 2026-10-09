shader_type spatial;
// Spray and mist where a waterfall lands (WaterfallSystem's GPU particles): soft
// camera-facing puffs lit by the sun and brightest looking into it, faded
// where they would cut into the scene behind them, the water or the camera.
// INSTANCE_CUSTOM.x is the particle's spin (ParticleProcessMaterial).
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform float water_level = 0.72;
// Metres over which a puff fades into what lies behind it.
uniform float softness = 1.5;

varying vec3 world_pos;
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
	// Billboard that keeps the particle's scale and spin (as BaseMaterial3D's
	// particle billboards do).
	float spin = INSTANCE_CUSTOM.x;
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(cos(spin), -sin(spin), 0.0, 0.0),
		vec4(sin(spin), cos(spin), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0),
		vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_pos = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	seed = float(INSTANCE_ID) * 7.31;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float puff = value_noise(c * 1.7 + seed) * 0.6 + value_noise(c * 4.1 - seed) * 0.4;
	float shape = 1.0 - smoothstep(0.25, 1.0, length(c) + (puff - 0.5) * 0.7);
	// Soft against the scene behind, the lake surface and the camera.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float gap = -behind.z / behind.w + VERTEX.z;
	float soft = smoothstep(0.0, softness, gap);
	soft *= smoothstep(water_level - 0.1, water_level + 0.8, world_pos.y);
	soft *= smoothstep(0.8, 3.5, -VERTEX.z);
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(shape * COLOR.a * soft, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Droplets scatter mostly forward: the mist glows against the sun.
	float n_dot_l = dot(NORMAL, LIGHT);
	float wrap = clamp((n_dot_l + 1.0) * 0.5, 0.0, 1.0);
	float forward = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 6.0) * 2.5;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.35 + 0.65 * wrap + forward) / PI;
}
