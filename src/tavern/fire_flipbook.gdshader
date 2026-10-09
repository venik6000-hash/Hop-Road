shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D fire_atlas : source_color, filter_linear, repeat_disable;
instance uniform float phase = 0.0;
instance uniform float speed = 24.0;
uniform float intensity = 2.8;

vec4 frame_sample(float frame, vec2 uv) {
	vec2 cell = vec2(mod(frame, 16.0), floor(frame / 16.0));
	// Half-texel inset keeps adjacent flame cells from bleeding together.
	vec2 inset = vec2(0.5 / 64.0, 0.5 / 128.0);
	return texture(fire_atlas, (cell + mix(inset, vec2(1.0) - inset, uv)) / vec2(16.0, 4.0));
}

void fragment() {
	float clock = mod(TIME * speed + phase, 64.0);
	vec4 fire = mix(frame_sample(floor(clock), UV), frame_sample(mod(floor(clock) + 1.0, 64.0), UV), fract(clock));
	float luminance = max(fire.r, max(fire.g, fire.b));
	ALBEDO = fire.rgb;
	EMISSION = fire.rgb * intensity;
	ALPHA = smoothstep(0.018, 0.25, luminance) * fire.a;
}
