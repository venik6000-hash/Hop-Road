shader_type spatial;
// What stands in a brewery vessel: water, wort, mash. `boil` rolls the
// surface and breaks it into bubbles, `foam` lays a pale scum on it; the
// mash is thick and dull (`thick`).
render_mode specular_schlick_ggx, cull_disabled;

uniform vec4 tint : source_color = vec4(0.4, 0.22, 0.06, 1.0);
uniform float boil : hint_range(0.0, 1.0) = 0.0;
uniform float foam : hint_range(0.0, 1.0) = 0.0;
uniform float thick : hint_range(0.0, 1.0) = 0.0;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Domes that swell and burst in cells: the top of each rises, then it is gone.
float bubbles(vec2 p, float time) {
	vec2 cell = floor(p);
	vec2 inside = fract(p) - 0.5;
	float seed = hash(cell);
	float life = fract(time * (0.6 + seed) + seed * 7.0);
	vec2 off = vec2(hash(cell + 3.1), hash(cell + 5.7)) - 0.5;
	float size = 0.12 + 0.25 * life;
	float d = length(inside - off * 0.4) / size;
	return sqrt(max(0.0, 1.0 - d * d)) * sin(life * 3.14159);
}

float height(vec2 p, float time) {
	float swell = noise(p * 3.0 + vec2(time * 0.7, -time * 0.5)) * 0.6 + noise(p * 7.0 - time * 1.3) * 0.4;
	float broken = bubbles(p * 9.0, time * 1.6) + bubbles(p * 14.0 + 4.0, time * 2.1);
	// The mash is grist in water: lumps and husks break its face.
	float grist = thick * (noise(p * 45.0) * 0.6 + noise(p * 140.0) * 0.4);
	return mix(noise(p * 6.0 + time * 0.05) * 0.08, swell + broken * 0.8, boil) + grist;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float e = 0.01;
	float h = height(p, TIME);
	vec2 slope = vec2(height(p + vec2(e, 0.0), TIME) - h, height(p + vec2(0.0, e), TIME) - h) / e;
	float bump = mix(mix(0.004, 0.02, boil), 0.006, thick);
	vec3 n = normalize(vec3(-slope.x * bump, 1.0, -slope.y * bump));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float scum = foam * smoothstep(0.35, 0.75, noise(p * 5.0 + TIME * 0.2 * boil) + 0.3 * boil * h);
	vec3 cream = vec3(0.86, 0.78, 0.6);
	float husk = noise(p * 260.0);
	ALBEDO = mix(tint.rgb * mix(1.0, 0.7 + 0.5 * husk, thick), cream, scum);
	ROUGHNESS = mix(mix(0.05, 0.75, thick), 0.6, scum);
	SPECULAR = 0.5;
}
