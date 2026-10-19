shader_type spatial;
// A lens of the lighthouse for the eye its beam sweeps over: a glow that
// faces the eye and flares while the beam points at it (LighthouseOptic), so
// the light is seen turning from the far shore. It burns when the lanterns
// do, by the same measure of dusk.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// How far the lamps are lit, 0 by day .. 1 at night (SkySystem.dusk_of).
global uniform float lamp_dusk;

uniform vec3 beam_color : source_color = vec3(1.0, 0.78, 0.46);
// Radius of the lens, m, and the half angle of its beam, radians.
uniform float radius = 0.32;
uniform float spread = 0.122;
// The glow never gets smaller than this on the screen (fraction of its height).
uniform float least_size = 0.006;
uniform float brightness = 8.0;

varying vec3 glow;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// The beam leaves along the node's -z.
	vec3 beam = -normalize(MODEL_MATRIX[2].xyz);
	vec3 to_eye = CAMERA_POSITION_WORLD - origin;
	float distance_to_eye = length(to_eye);
	to_eye /= max(distance_to_eye, 1e-4);
	float dusk = lamp_dusk;
	// Whole in the middle of the beam, gone at twice its half angle.
	float swept = smoothstep(cos(spread * 2.0), cos(spread * 0.4), dot(beam, to_eye));
	float size = max(radius, least_size * distance_to_eye / PROJECTION_MATRIX[1][1]);
	// The same light spread over a larger disc is dimmer.
	float thinned = (radius * radius) / (size * size);
	glow = beam_color * (brightness * dusk * swept * mix(thinned, 1.0, 0.5));
	vec3 centre = (VIEW_MATRIX * vec4(origin + to_eye * 0.1, 1.0)).xyz;
	VERTEX = centre + vec3(VERTEX.xy * size * 2.0, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	if (dusk * swept <= 0.0) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = exp(-r * r * 9.0);
	float halo = pow(max(1.0 - r, 0.0), 3.0) * 0.25;
	ALBEDO = glow * (core + halo);
}
