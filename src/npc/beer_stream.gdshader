shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// A stream of beer from a tap (NpcBarWork): golden, clear at the edges, with
// streaks and small bubbles running down its length (UV.x along the stream).
uniform vec3 beer_color : source_color = vec3(0.86, 0.55, 0.14);
uniform float speed = 2.4;
varying float along;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	along = UV.x;
}

void fragment() {
	float flow = noise(vec2(UV.y * 6.0, (along - TIME * speed) * 40.0));
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = beer_color * (0.75 + 0.35 * flow);
	ROUGHNESS = 0.05;
	SPECULAR = 0.6;
	EMISSION = beer_color * 0.08 * flow;
	ALPHA = mix(0.88, 0.55, rim);
}
