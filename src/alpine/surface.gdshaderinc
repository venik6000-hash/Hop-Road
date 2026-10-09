// The map's surface: a colour with grain, wet in the rain. Shared by
// surface.gdshader (leaves, which sway) and surface_still.gdshader (everything
// else).
#include "res://src/weather/wetness.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.4, 0.4, 0.3, 1.0);
uniform float roughness_value = 0.8;
uniform float metallic_value = 0.0;
uniform float emission_value = 0.0;
uniform float noise_scale = 0.0;
uniform vec3 grain_stretch = vec3(1.0);
varying vec3 surface_position;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(cell), hash(cell + vec3(1,0,0)), f.x),
		mix(hash(cell + vec3(0,1,0)), hash(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(cell + vec3(0,0,1)), hash(cell + vec3(1,0,1)), f.x),
		mix(hash(cell + vec3(0,1,1)), hash(cell + vec3(1,1,1)), f.x), f.y), f.z);
}

void fragment() {
	float grain = 1.0;
	if (noise_scale > 0.0) {
		vec3 p = surface_position * grain_stretch * noise_scale;
		float n = noise3(p) * 0.65 + noise3(p * 3.7) * 0.25 + noise3(p * 12.0) * 0.1;
		grain = mix(0.62, 1.22, n);
	}
	vec3 base = base_color.rgb * grain;
	float rough = roughness_value;
	float shine = 1.0;
	if (rain_is_wet() && emission_value <= 0.0) {
		vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 face = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float wet = rain_film(rain_reach(world, face));
		wet_surface(wet, metallic_value, base, rough);
		shine = wet_specular(wet, reflect(normalize(world - CAMERA_POSITION_WORLD), face).y);
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	// 0.5 is the engine's own.
	SPECULAR = 0.5 * shine;
	METALLIC = metallic_value;
	EMISSION = base_color.rgb * emission_value;
}
