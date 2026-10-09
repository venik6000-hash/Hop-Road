shader_type spatial;
// Foam where the lower fall plunges into the lake (WaterfallSystem), drawn
// just over the lake's surface: the lake's shader is left as it is, so this
// rides the same FFT waves (water.gdshader's vertex()) and is the lake's foam
// (water_look.gdshaderinc) in pattern, colour and light. It boils under the
// fall and streams outward, breaking up with distance.
render_mode blend_mix, depth_draw_never, cull_back, ambient_light_disabled, world_vertex_coords;

#include "res://src/sky/atmosphere.gdshaderinc"
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/water/water_look.gdshaderinc"

global uniform sampler2DArray water_displacement : filter_linear_mipmap, repeat_enable;
global uniform sampler2DArray water_derivatives : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform vec4 water_tiles;
global uniform vec4 water_cascade_weights;

uniform sampler2D near_height : filter_linear, repeat_disable;
uniform sampler2D far_height : filter_linear, repeat_disable;
uniform vec4 near_rect;
uniform vec4 far_rect;
uniform float water_level = 0.72;
// Where the fall lands (world x, z), how far its foam reaches (m), strength.
uniform vec4 plunge = vec4(0.0, 0.0, 8.0, 1.0);

varying vec2 grid_xz;
varying float wave_scale;
varying float sun_vis;

vec2 near_uv(vec2 xz) {
	return ((xz - near_rect.xy) / near_rect.z + 0.5) / near_rect.w;
}

vec2 far_uv(vec2 xz) {
	return ((xz - far_rect.xy) / far_rect.z + 0.5) / far_rect.w;
}

float ground_height(vec2 xz) {
	float h = textureLod(far_height, far_uv(xz), 0.0).r;
	vec2 local = (xz - near_rect.xy) / near_rect.z;
	vec2 edge = min(local, vec2(near_rect.w - 1.0) - local) * near_rect.z;
	float w = clamp(min(edge.x, edge.y) / 40.0, 0.0, 1.0);
	if (w > 0.0) {
		h = mix(h, textureLod(near_height, near_uv(xz), 0.0).r, w);
	}
	return h;
}

// Per-cascade fade with distance: small waves go first, before they alias.
vec3 cascade_fade(float dist) {
	return vec3(1.0, 1.0 - smoothstep(900.0, 2200.0, dist), 1.0 - smoothstep(90.0, 260.0, dist));
}

void vertex() {
	// The lake's waves, shrunk over shallows and varied by gusts.
	vec2 xz = VERTEX.xz;
	float dist = distance(CAMERA_POSITION_WORLD, vec3(xz.x, water_level, xz.y));
	float depth = water_level - ground_height(xz);
	float shore = mix(0.08, 1.0, smoothstep(0.0, 7.0, depth));
	float gust = 0.72 + 0.56 * textureLod(macro_noise, xz / 1700.0, 0.0).r;
	wave_scale = shore * gust;
	vec3 fade = cascade_fade(dist) * water_cascade_weights.xyz * wave_scale;
	vec4 d = vec4(0.0);
	for (int c = 0; c < 3; c++) {
		d += textureLod(water_displacement, vec3(xz / water_tiles[c], float(c)), 0.0) * fade[c];
	}
	grid_xz = xz;
	// A couple of centimetres over the water so it never sinks into it.
	VERTEX = vec3(xz.x + d.x, water_level + d.y + 0.03, xz.y + d.z);
	NORMAL = vec3(0.0, 1.0, 0.0);
	sun_vis = cloud_sun_visibility(VERTEX);
}

void fragment() {
	vec2 xz = grid_xz;
	float dist = length(VERTEX);
	vec3 fade = cascade_fade(dist) * water_cascade_weights.xyz * wave_scale;
	vec4 slopes = vec4(0.0);
	for (int c = 0; c < 3; c++) {
		slopes += texture(water_derivatives, vec3(xz / water_tiles[c], float(c))) * fade[c];
	}
	vec2 slope = vec2(slopes.x / (1.0 + slopes.z), slopes.y / (1.0 + slopes.w));
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	// Two phases of the pattern carried outward, cross-faded, so the foam
	// keeps streaming away without the pattern stretching.
	vec2 away = xz - plunge.xy;
	float d = length(away);
	float reach = 1.0 - smoothstep(plunge.z * 0.2, plunge.z, d);
	vec2 outward = away / max(d, 0.4);
	float f0 = fract(TIME * 0.4);
	float f1 = fract(TIME * 0.4 + 0.5);
	float p0 = foam_pattern(xz - outward * f0 * 3.2 + slope);
	float p1 = foam_pattern(xz - outward * f1 * 3.2 + slope + vec2(0.37, 0.61));
	float streaming = mix(p0, p1, abs(f0 - 0.5) * 2.0);
	// Solid where the water comes down, in drifting patches further out.
	float boil = (1.0 - smoothstep(0.0, plunge.z * 0.25, d)) * (0.5 + 0.5 * foam_pattern(xz * 1.7 - TIME * 0.3));
	float foam = clamp(plunge.w * (reach * reach * streaming * 0.95 + boil * 0.85), 0.0, 1.0);
	// The lake's foam: sky light here, the sun in light().
	EMISSION = foam_color * water_ambient() * 0.8;
	ALBEDO = foam_color;
	ALPHA = foam;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
}

void light() {
	bool is_sun = LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (is_sun ? sun_vis : 1.0) * clamp(dot(NORMAL, LIGHT), 0.0, 1.0) / PI;
}
