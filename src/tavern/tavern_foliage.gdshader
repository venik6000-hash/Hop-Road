shader_type spatial;
// Leaves and flowers of the tavern's plants (tools/pipeline/tavern/plants.py):
// cards cut from the generated atlas (plant_textures.py), alpha tested and
// seen from both sides, each face lit as the side it shows.
//
// COLOR.rgb is the card's tint over `color_range`; COLOR.a how freely the
// corner moves (0 where the stalk holds it, 1 at a free tip): the cards
// flutter a little in the moving air, each in its own time. Light as the
// trees' leaves: wrapped diffuse, light passing through the thin blades from
// behind, a glossy sheen (ivy is waxy); the sun dimmed by cloud shadows.
render_mode cull_disabled, depth_draw_opaque;

#include "res://src/vegetation/shaders/vegetation.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 tint = vec3(1.0);
uniform float color_range = 2.0;
uniform float roughness_value = 0.42;
uniform float normal_strength = 0.7;
uniform float leaf_wrap = 0.3;
uniform float leaf_transmission = 0.55;
// Metres a free tip moves.
uniform float flutter = 0.012;
uniform vec2 flutter_dir = vec2(0.57, 0.82);

varying float sun_vis;
varying vec3 card_tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sun_vis = cloud_sun_visibility(world);
	card_tint = COLOR.rgb * color_range;
	if (COLOR.a > 0.0 && flutter > 0.0) {
		// Leaves a hand apart move out of step.
		vec3 cell = floor(world * 5.0);
		float seed = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float t = TIME * (1.6 + 1.1 * seed) + seed * TAU;
		float gust = 0.55 + 0.45 * sin(TIME * 0.41 + dot(world.xz, flutter_dir) * 0.2);
		vec3 push = vec3(flutter_dir.x, 0.0, flutter_dir.y) * (0.6 + 0.4 * sin(t)) * gust
			+ vec3(0.0, 0.45, 0.0) * sin(t * 1.9 + 1.3)
			+ vec3(-flutter_dir.y, 0.0, flutter_dir.x) * 0.35 * sin(t * 2.7 + seed * 5.0);
		VERTEX += (vec4(push * flutter * COLOR.a, 0.0) * MODEL_MATRIX).xyz;
	}
}

void fragment() {
	vec4 leaf = texture(albedo_map, UV);
	// Mip averaging thins alpha-tested cards with distance; lift the
	// coverage by the mip level so a far clump stays closed.
	float level = max(textureQueryLod(albedo_map, UV).y, 0.0);
	ALPHA = leaf.a * (1.0 + 0.3 * level);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = leaf.rgb * tint * card_tint;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.5;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}

void light() {
	bool is_sun = light_is_sun(LIGHT_IS_DIRECTIONAL, LIGHT, INV_VIEW_MATRIX);
	foliage_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, is_sun, sun_vis, leaf_wrap, leaf_transmission,
		ROUGHNESS, 0.04, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}
