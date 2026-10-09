shader_type spatial;
// A lightning bolt: ribbons along the channel (LightningFx.bolt_mesh) turned
// to the eye and kept at least a pixel or two wide however far away. Drawn
// opaque, so the fog pass dims it by its own distance, not the sky's.
render_mode unshaded, cull_disabled, shadows_disabled, world_vertex_coords;

uniform float half_width = 1.6;
// The least half width, as an angle seen from the eye.
uniform float least_angle = 0.0011;
// The strike's light now, 0..1.
uniform float light = 1.0;
uniform vec3 bolt_color : source_color = vec3(0.78, 0.85, 1.0);
uniform float radiance = 420.0;

varying float brightness;

void vertex() {
	// NORMAL is the way the ribbon runs, UV.x the side of it.
	vec3 to_eye = CAMERA_POSITION_WORLD - VERTEX;
	vec3 side = normalize(cross(NORMAL, to_eye));
	brightness = COLOR.r;
	VERTEX += side * UV.x * max(half_width * mix(0.45, 1.0, COLOR.r), length(to_eye) * least_angle);
}

void fragment() {
	// A dead bolt is not drawn at all between its strokes.
	if (light * brightness < 0.01) {
		discard;
	}
	ALBEDO = bolt_color * radiance * light * brightness;
}
