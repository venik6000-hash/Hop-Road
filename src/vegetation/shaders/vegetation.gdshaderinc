// Shared by every vegetation shader: wind, LOD cross-fade, cloud shadows, the
// shade of the crowns and the foliage light model. VegetationSystem sets the
// uniforms on each material every frame (there are few materials, so no
// global parameters are needed).

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/vegetation/shaders/canopy.gdshaderinc"

// x, y: wind direction on the ground (x, z), unit length; z: strength
// (0 calm .. 1 fresh breeze .. 2 storm); w: gust travel speed (m/s).
uniform vec4 wind = vec4(0.57, 0.82, 0.5, 5.0);
// Tileable noise; its red channel is the gust field, scrolled downwind.
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
// Main camera, used for LOD distances in every pass (shadow passes included,
// where CAMERA_POSITION_WORLD would be the light's camera).
uniform vec3 lod_camera;

const float GUST_SCALE = 180.0;

// 0..1 gust strength at a ground position; shared by trees and grass, so a
// gust visibly travels from the meadow into the forest.
float wind_gust(vec2 xz, float time) {
	vec2 uv = (xz - wind.xy * wind.w * time) / GUST_SCALE;
	float a = texture(wind_noise, uv).r;
	float b = texture(wind_noise, uv * 2.7 + vec2(0.31, 0.77)).r;
	return clamp((a * 0.7 + b * 0.3 - 0.35) * 2.2, 0.0, 1.0);
}

// Wind pressure grows with the square of speed; `wind.z` is already that.
float wind_strength(vec2 xz, float time) {
	return wind.z * (0.45 + 0.9 * wind_gust(xz, time));
}

// Per-instance LOD weight from (fade-in start, fade-in end, fade-out start,
// fade-out end); adjacent LODs share their bands so the weights sum to one.
float lod_weight(float d, vec4 range) {
	float fade_in = range.y > range.x ? smoothstep(range.x, range.y, d) : 1.0;
	float fade_out = 1.0 - smoothstep(range.z, range.w, d);
	return fade_in * fade_out;
}

// Interleaved gradient noise: a screen-space dither that TAA resolves into a
// smooth cross-fade.
float dither_noise(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

// True if this fragment of a LOD with weight `w` must be discarded. `fading_in`
// flips the dither so the incoming LOD fills exactly the pixels the outgoing
// one leaves.
bool lod_dither_discard(float w, bool fading_in, vec2 frag) {
	if (w >= 0.999) {
		return false;
	}
	float n = dither_noise(frag);
	return fading_in ? (1.0 - n) >= w : n >= w;
}

// Foliage lighting: wrapped diffuse for the soft, many-layered crown, light
// transmitted through thin leaves when the sun is behind them, and a broad,
// weak specular. `sun_vis` only applies to the sun (cloud and terrain shadow).
void foliage_light(vec3 normal, vec3 light, vec3 view, vec3 light_color, float attenuation, bool is_sun,
		float sun_vis, float wrap, float transmission, float roughness, float specular,
		inout vec3 diffuse_light, inout vec3 specular_light) {
	float shade = attenuation * (is_sun ? sun_vis : 1.0);
	float ndl = dot(normal, light);
	float diffuse = clamp((ndl + wrap) / ((1.0 + wrap) * (1.0 + wrap)), 0.0, 1.0);
	// Forward-scattered light through the leaf, strongest looking into the sun.
	float through = clamp(-ndl, 0.0, 1.0) * 0.4 + pow(clamp(dot(view, -light), 0.0, 1.0), 4.0) * 0.6;
	diffuse_light += light_color * shade * (diffuse + transmission * through) / PI;
	vec3 h = normalize(view + light);
	float ndh = clamp(dot(normal, h), 0.0, 1.0);
	float ndv = clamp(dot(normal, view), 1e-3, 1.0);
	float nl = clamp(ndl, 0.0, 1.0);
	float a = roughness * roughness;
	float a2 = a * a;
	float dist = a2 / (PI * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	float k = a * 0.5;
	float vis = 0.25 / ((nl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	float fresnel = specular + (1.0 - specular) * pow(1.0 - clamp(dot(view, h), 0.0, 1.0), 5.0);
	specular_light += light_color * shade * nl * dist * vis * fresnel;
}

bool light_is_sun(bool directional, vec3 light_view, mat4 inv_view) {
	return directional && dot((inv_view * vec4(light_view, 0.0)).xyz, sun_direction) > 0.999;
}
