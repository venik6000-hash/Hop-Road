shader_type spatial;
render_mode cull_disabled;
uniform bool waterfall = false;
varying vec3 water_position;

void vertex() {
	water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = water_position;
	float wave = sin(p.x * 1.7 + p.z * 2.4 + sin(p.z * 0.35) * 2.0 + TIME * 1.0);
	float ripple = sin(p.x * 4.3 - p.z * 3.0 + sin(p.x * 0.73 + p.z * 0.41) + TIME * 1.5);
	if (waterfall) {
		float stream = sin(p.y * 5.0 + TIME * 7.0 + sin(p.x * 16.0));
		ALBEDO = mix(vec3(0.18, 0.48, 0.60), vec3(0.78, 0.91, 0.95), stream * 0.35 + 0.6);
		ROUGHNESS = 0.3;
		EMISSION = ALBEDO * 0.10;
	} else {
		ALBEDO = vec3(0.024, 0.19, 0.30) + vec3(0.017, 0.030, 0.038) * wave;
		vec3 world_normal = normalize(vec3(wave * 0.08, 1.0, ripple * 0.06));
		NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
		ROUGHNESS = 0.17;
		METALLIC = 0.25;
		SPECULAR = 0.35;
	}
}
