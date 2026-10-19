shader_type spatial;
// Scanned ground plants of the village (VillageFlora): alpha-cut leaves that
// take light from both sides, lean with the weather's wind by their height
// (src/weather/wind.gdshaderinc), vary a
// little in tone from plant to plant (COLOR of the MultiMesh instance) and
// darken in the rain.
render_mode cull_disabled, depth_draw_opaque;

#include "res://src/weather/wetness.gdshaderinc"
#include "res://src/weather/wind.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
// Metres the top of a plant of unit height sways in a fresh breeze.
uniform float sway = 0.05;
uniform float transmission = 0.35;
// The leaves' share of the wetness of open ground: darker in the rain and no
// film to shine, as the meadow's blades (grass.gdshader). 0: they keep dry.
uniform float rain_darkens = 0.3;

varying vec3 tone;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float stem = max(VERTEX.y, 0.0);
	float blow = min(wind_strength(MODEL_MATRIX[3].xz) / BREEZE_STRENGTH, 3.0);
	// The wind's way in the plant's frame (its basis is a turn times a scale).
	float scale = length(MODEL_MATRIX[1].xyz);
	vec3 downwind = transpose(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y) / scale;
	vec3 across = transpose(mat3(MODEL_MATRIX)) * vec3(-wind.y, 0.0, wind.x) / scale;
	float gust = sin(TIME * 1.3 + world.x * 0.45 + world.z * 0.35) + 0.5 * sin(TIME * 2.9 + world.x * 1.7 - world.z * 1.3);
	VERTEX += (downwind * (0.5 + gust) + across * cos(TIME * 1.1 + world.z * 0.5) * 0.6) * stem * sway * blow;
	tone = COLOR.rgb;
}

void fragment() {
	vec4 c = texture(albedo_map, UV);
	vec3 leaf = c.rgb * tint * tone;
	if (rain_is_wet() && rain_darkens > 0.0) {
		leaf = soaked_colour(leaf, rain_film(rain_darkens));
	}
	ALBEDO = leaf;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	BACKLIGHT = leaf * transmission;
}
