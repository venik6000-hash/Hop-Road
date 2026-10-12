shader_type spatial;
// The cut-out leaves of the forest floor's ferns and clover (village_pack.gd):
// they sway, take the light from both sides and stand in the light of the
// ground under them: the sun dimmed by the clouds' and the ridges' shadows,
// the sky by the crowns overhead. In the rain they darken.
render_mode cull_disabled;

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/vegetation/shaders/canopy.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
// The share of the light on a leaf's back that comes through it.
uniform float transmission = 0.22;
// The leaves' share of the wetness of open ground: darker in the rain and no
// film to shine, as the meadow's blades (grass.gdshader). 0: they keep dry.
uniform float rain_darkens = 0.3;

varying float sun_vis;
// What the crowns overhead leave of the sky's light.
varying float sky_vis;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float stem = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 1.7 + world.x * 0.55 + world.z * 0.4) * stem * 0.07;
	sun_vis = cloud_sun_visibility(world)
		* (1.0 - canopy_sun_shade(world.xz, CANOPY_HEIGHT, -(VIEW_MATRIX * vec4(world, 1.0)).z, 0.0));
	sky_vis = 1.0 - canopy_sky_shade(world.xz, 1.0, 0.0);
}

void fragment() {
	vec4 c = texture(albedo_map, UV) * tint;
	vec3 leaf = c.rgb;
	if (rain_is_wet() && rain_darkens > 0.0) {
		leaf = soaked_colour(leaf, rain_film(rain_darkens));
	}
	ALBEDO = leaf;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.92;
	// No mirror of the sky on a leaf: in dim light it greys the whole plant
	// (as on the trees' leaf cards, tree.gdshaderinc).
	SPECULAR = 0.0;
	AO = sky_vis;
	AO_LIGHT_AFFECT = 0.0;
}

void light() {
	// The clouds' and the ridges' shadows belong to the sun alone.
	float shade = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999) {
		shade *= sun_vis;
	}
	float n_dot_l = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR * shade * (max(n_dot_l, 0.0) + transmission * max(-n_dot_l, 0.0)) / PI;
}
