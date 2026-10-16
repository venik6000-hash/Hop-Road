shader_type spatial;
render_mode cull_disabled;
// The level surface of beer in a tankard (Tankard): a flat disc kept level in
// the world, cut to the tankard's inside in the tankard's own space. A head
// of fine foam with larger bubbles, thinner at the wall where the beer shows.
uniform mat4 to_tankard;
uniform float inner_radius = 0.095;
uniform float rim = 0.24;
uniform float foam : hint_range(0.0, 1.0) = 1.0;
uniform vec3 beer_color : source_color = vec3(0.55, 0.30, 0.06);
uniform vec3 foam_color : source_color = vec3(0.92, 0.86, 0.72);
varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
// Bubbles: a cell grid, a round bubble of its own size in some cells.
float bubbles(vec2 p, float size) {
	vec2 cell = floor(p / size), f = fract(p / size);
	float h = hash(cell);
	vec2 centre = 0.3 + 0.4 * vec2(hash(cell + 3.1), hash(cell + 7.7));
	float r = 0.18 + 0.25 * h;
	return h > 0.55 ? 1.0 - smoothstep(r * 0.6, r, length(f - centre)) : 0.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 local = (to_tankard * vec4(world_pos, 1.0)).xyz;
	float out_r = length(local.xz) / inner_radius;
	if (out_r > 1.0 || local.y > rim) {
		discard;
	}
	vec2 p = world_pos.xz;
	float edge = smoothstep(0.78, 1.0, out_r);
	float cover = foam * (1.0 - 0.55 * edge) * (0.85 + 0.15 * noise(p * 60.0));
	float holes = bubbles(p, 0.006) * 0.5 + bubbles(p + 0.37, 0.011) * 0.35;
	vec3 head = foam_color * (0.9 + 0.1 * noise(p * 140.0)) * (1.0 - 0.35 * holes);
	ALBEDO = mix(beer_color, head, clamp(cover, 0.0, 1.0));
	ROUGHNESS = mix(0.08, 0.75, cover);
	SPECULAR = 0.5;
	NORMAL_MAP = vec3(0.5 + 0.25 * (noise(p * 90.0) - 0.5), 0.5 + 0.25 * (noise(p * 90.0 + 5.0) - 0.5), 1.0);
	// Light that goes into the foam comes back warm.
	SSS_STRENGTH = 0.3 * cover;
}
