shader_type spatial;
// A lamp or a lit window seen from far away: a small glow that faces the
// eye, drawn in place of the light itself (FarLights). It burns when the
// lanterns do, by the same measure of dusk.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec3 sun_direction;

// Metres from the eye over which a glow comes up (x .. y).
uniform vec2 rise = vec2(30.0, 60.0);
// A glow never gets smaller than this on the screen (fraction of its height).
uniform float least_size = 0.0035;
uniform float brightness = 3.0;

varying vec3 glow;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// The instance's basis is not a pose: its z axis is the way a window
	// faces (zero for a lamp, seen from all round), its x scale the radius.
	vec3 facing = MODEL_MATRIX[2].xyz;
	float radius = length(MODEL_MATRIX[0].xyz);
	vec3 to_eye = CAMERA_POSITION_WORLD - origin;
	float distance_to_eye = length(to_eye);
	to_eye /= max(distance_to_eye, 1e-4);
	float dusk = 1.0 - smoothstep(-0.02, 0.18, sun_direction.y);
	float seen = smoothstep(rise.x, rise.y, distance_to_eye);
	float sided = dot(facing, facing) > 0.01 ? smoothstep(0.05, 0.45, dot(normalize(facing), to_eye)) : 1.0;
	float size = max(radius, least_size * distance_to_eye / PROJECTION_MATRIX[1][1]);
	// The same light spread over a larger disc is dimmer.
	float spread = (radius * radius) / (size * size);
	glow = COLOR.rgb * brightness * dusk * seen * sided * mix(spread, 1.0, 0.35);
	// Toward the eye a little, clear of the lantern's own glass.
	vec3 centre = (VIEW_MATRIX * vec4(origin + to_eye * 0.35, 1.0)).xyz;
	VERTEX = centre + vec3(VERTEX.xy * size * 2.0, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	if (dusk * seen * sided <= 0.0) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = exp(-r * r * 9.0);
	float halo = pow(max(1.0 - r, 0.0), 3.0) * 0.25;
	ALBEDO = glow * (core + halo);
}
