shader_type spatial;
// Models that stand outdoors and came with a plain material (OutdoorScan,
// outdoor_scan.gd): the stumps, roots, logs, fallen branches and bracken of
// the forest's floor and the animals of the land. Several of the scans came as
// unlit photogrammetry, which the engine draws with no light on it at all:
// they shone in the rain and at night; and the rain did not wet the rest.
// Here every one stands in the light of the ground it is on: the sun dimmed
// by the clouds' and the ridges' shadows, the sky by the crowns overhead, and
// the rain soaks it.
render_mode cull_disabled, depth_draw_opaque;

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/vegetation/shaders/canopy.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// glTF's packing, G roughness; a scan without the map has roughness_value alone.
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness_value = 0.9;
uniform float normal_strength = 1.0;
// How much of the film the rain leaves shines on the surface: all of it on
// wood and stone; fur and feathers soak and darken and take no shine (0).
uniform float wet_shine = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float sun_vis;
// How closed the crowns overhead are (the canopy field, 0..1).
varying float crown_cover;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	sun_vis = cloud_sun_visibility(world_pos)
		* (1.0 - canopy_sun_shade(world_pos.xz, CANOPY_HEIGHT, -(VIEW_MATRIX * vec4(world_pos, 1.0)).z, 0.0));
	crown_cover = canopy_at(world_pos.xz, 1.0, 0.0);
}

void fragment() {
	vec3 albedo = texture(albedo_map, UV).rgb * tint.rgb;
	float rough = texture(roughness_map, UV).g * roughness_value;
	vec3 face = normalize(world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	float rained = 0.0;
	if (rain_is_wet()) {
		rained = rain_film(rain_reach(world_pos, face));
		float dry = rough;
		wet_surface(rained, 0.0, albedo, rough);
		rough = mix(dry, rough, wet_shine);
	}
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.4 * wet_specular_under(rained,
		reflect(normalize(world_pos - CAMERA_POSITION_WORLD), face).y, 1.0 - crown_cover);
	AO = 1.0 - canopy_light.x * crown_cover;
	AO_LIGHT_AFFECT = 0.0;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}

void light() {
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Both terms carry n_dot_l and ATTENUATION as factors: a back-facing or
	// fully shadowed light adds exactly nothing.
	if (n_dot_l > 0.0 && ATTENUATION > 0.0) {
		// The clouds' and the ridges' shadows belong to the sun alone.
		float shade = ATTENUATION;
		if (LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999) {
			shade *= sun_vis;
		}
		DIFFUSE_LIGHT += LIGHT_COLOR * shade * n_dot_l / PI;
		vec3 h = normalize(VIEW + LIGHT);
		float n_dot_h = clamp(dot(NORMAL, h), 0.0, 1.0);
		float n_dot_v = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
		float a = ROUGHNESS * ROUGHNESS;
		float a2 = a * a;
		float d = a2 / (PI * pow(n_dot_h * n_dot_h * (a2 - 1.0) + 1.0, 2.0));
		float k = a * 0.5;
		float vis = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
		float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(dot(VIEW, h), 0.0, 1.0), 5.0);
		SPECULAR_LIGHT += LIGHT_COLOR * shade * n_dot_l * d * vis * fresnel;
	}
}
