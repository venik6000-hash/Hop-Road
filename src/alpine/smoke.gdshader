shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * size, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * size, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * size, 0.0), MODEL_MATRIX[3]);
}
void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.80, 0.85, 0.87);
	ALPHA = smoothstep(1.0, 0.12, radius) * COLOR.a * 0.10;
}
