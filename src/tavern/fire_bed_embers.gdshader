shader_type spatial;
// Charred wood and the bed of embers of a hearth's fire bed (FireBed).
// The baked mask holds where it can glow: R the cracks, B the surface;
// G is roughness. Heat drifts slowly through it, the cracks breathe, and as
// `heat` falls only the hottest cracks stay lit, dull red.
render_mode shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
// The embers' glow, 0..1 (FireBed follows the fire up fast and lets it die slowly).
uniform float heat : hint_range(0.0, 1.0) = 1.0;
// Emission of a fully glowing crack.
uniform float energy = 5.0;
// Darkens the baked albedo: soot and charcoal fines in a working hearth.
uniform float albedo_scale = 1.0;
// Scale of the drifting heat, cycles per metre.
uniform float drift_scale = 9.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Colour of glowing wood by its temperature, 0 dull red to 1 yellow-orange.
vec3 ember_colour(float t) {
	vec3 c = mix(vec3(0.3, 0.012, 0.0), vec3(1.0, 0.16, 0.012), smoothstep(0.0, 0.55, t));
	return mix(c, vec3(1.0, 0.42, 0.08), smoothstep(0.55, 1.0, t));
}

void fragment() {
	vec4 mask = texture(mask_tex, UV);
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_scale;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = mask.g;
	vec3 p = v_local * drift_scale;
	float drift = value_noise(p + vec3(0.0, -TIME * 0.11, TIME * 0.04)) * 0.65
			+ value_noise(p * 2.3 + vec3(TIME * 0.08, -TIME * 0.19, 0.0)) * 0.35;
	float breath = 0.72 + 0.28 * sin(TIME * 0.8 + drift * 9.0);
	// A cooling fire leaves only its hottest places lit.
	float reach = clamp(heat * 1.35 - (1.0 - drift) * 0.55, 0.0, 1.0);
	float crack = mask.r * breath * reach;
	float surface = mask.b * smoothstep(0.3, 0.9, drift) * heat;
	float glow = crack + surface * 0.45;
	float temperature = clamp(glow * (0.35 + 0.75 * heat), 0.0, 1.0);
	EMISSION = ember_colour(temperature) * glow * energy * sqrt(heat);
	// Glowing places are not lit from outside: their own light drowns it.
	ALBEDO *= 1.0 - clamp(glow * heat, 0.0, 0.8);
}
