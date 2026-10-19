shader_type spatial;
// Flames of candles, lanterns and hearths: crossed quads whose UV runs 0..1
// across and up the flame. Additive light with a teardrop core, licking and
// flickering over time; each flame its own rhythm from where it stands.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// How far the lamps are lit, 0 by day .. 1 at night (SkySystem.dusk_of).
global uniform float lamp_dusk;

uniform vec3 flame_color : source_color = vec3(1.0, 0.62, 0.25);
uniform float energy = 4.0;
// The hotter colour low in the flame's middle (linear).
uniform vec3 core_color = vec3(1.0, 0.92, 0.75);
// 0 for a steady candle, toward 1 for a roaring hearth fire.
uniform float wildness = 0.2;
// 1: lit from dusk to dawn only, as TavernSystem lights the lanterns outdoors.
uniform float dusk_only = 0.0;

varying vec3 origin;

void vertex() {
	origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	float lit = mix(1.0, lamp_dusk, dusk_only);
	if (lit < 0.01) {
		discard;
	}
	float seed = dot(origin, vec3(3.7, 1.3, 5.1));
	float t = TIME * (1.6 + wildness * 2.0) + seed;
	vec2 uv = UV;
	// Licks: the flame's body wavers and tears near the top.
	float n = noise(vec2(uv.x * 3.0 + seed, uv.y * 2.5 - t * 1.7));
	uv.x += (n - 0.5) * (0.12 + wildness * 0.35) * uv.y;
	float x = (uv.x - 0.5) * 2.0;
	float y = uv.y;
	// Teardrop: wide low, drawn to a point at the top.
	float width = mix(0.9, 0.05, pow(y, 0.8)) * (1.0 - smoothstep(0.85, 1.0, y));
	float body = smoothstep(width, width * 0.35, abs(x)) * smoothstep(0.0, 0.12, y);
	float tear = mix(1.0, smoothstep(0.25, 0.75, noise(vec2(uv.x * 6.0, y * 4.0 - t * 2.3))), wildness * y);
	float flicker = 0.85 + 0.15 * sin(t * 9.0) * sin(t * 5.3 + 1.0);
	// Hotter, whiter core low in the flame.
	vec3 core = mix(flame_color, core_color, smoothstep(0.6, 0.0, abs(x) + y * 0.7));
	ALBEDO = core * body * tear * flicker * energy * lit;
}
