shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float stem = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 1.7 + world.x * 0.55 + world.z * 0.4) * stem * 0.07;
}
void fragment() {
	vec4 c = texture(albedo_map, UV) * tint;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.92;
	BACKLIGHT = c.rgb * 0.22;
}
