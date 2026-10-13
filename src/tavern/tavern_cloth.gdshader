shader_type spatial;
// Cloth of the tavern's rooms (tools/pipeline/tavern/drape.py: napkins,
// towels, cloaks, the banners): a scan of the weave on UVs in metres, lit as
// cloth is: the light comes round a fold and a little of it through the
// sheet, and the nap shines where it is looked along.
//
// COLOR.rgb is the piece's tint over `color_range` with the shade of its
// folds in it. COLOR.a is 1 on the sheet; below that, a strip of loose
// threads left past an end: 0.95 at the hem down to 0.55 at the tips where
// the threads run along u, 0.45 to 0.05 where they run along v. The strip is
// cut into threads here, each its own length.
render_mode cull_back, depth_draw_opaque;

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R ambient occlusion, G roughness (Poly Haven "arm").
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// The weave up close, as tavern_surface.gdshader's detail.
uniform sampler2D detail_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 10.4;
uniform float detail_strength = 0.0;
const float DETAIL_NEAR = 2.5;
const float DETAIL_FAR = 7.0;
uniform vec3 tint = vec3(1.0);
uniform float desaturate = 0.0;
uniform float albedo_gain = 1.0;
uniform float uv_scale = 1.0;
uniform float normal_strength = 1.0;
uniform float roughness_scale = 1.0;
uniform float color_range = 2.0;
// How far the light comes round a fold, how much of it passes through the
// sheet, how bright the nap is looked along.
uniform float cloth_wrap = 0.35;
uniform float cloth_through = 0.15;
uniform float cloth_sheen = 0.3;
// Wine, grease and years: how dark the blots are.
uniform float stain = 0.0;
// Loose threads to a metre of hem.
uniform float threads = 700.0;
// Bands woven across v, `stripe_width` metres each, in three colours by turns (0: plain).
uniform float stripe_width = 0.0;
uniform vec3 stripe_a : source_color = vec3(1.0);
uniform vec3 stripe_b : source_color = vec3(1.0);
uniform vec3 stripe_c : source_color = vec3(1.0);
// Needlework: R of the map is gold thread, laid over `emblem_size` metres of UV (0: none).
uniform sampler2D emblem_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 emblem_size = vec2(0.0);
uniform vec3 emblem_color : source_color = vec3(0.8, 0.62, 0.3);

varying vec3 world_pos;
varying float sun_vis;
varying vec4 piece;
varying float nap;

float lot(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sun_vis = cloud_sun_visibility(world_pos);
	piece = COLOR;
}

void fragment() {
	if (piece.a < 0.975) {
		bool along_u = piece.a > 0.5;
		float out_of_hem = along_u ? (0.95 - piece.a) / 0.4 : (0.45 - piece.a) / 0.4;
		float run = (along_u ? UV.y : UV.x) * threads;
		float own = lot(floor(run));
		float aside = abs(fract(run) - 0.5);
		if (out_of_hem > mix(0.3, 1.0, own) || aside > mix(0.4, 0.16, out_of_hem)) {
			discard;
		}
	}
	vec2 uv = UV / uv_scale;
	vec2 detail_uv = UV * detail_scale;
	vec2 detail_dx = dFdx(detail_uv);
	vec2 detail_dy = dFdy(detail_uv);
	float detail_fade = detail_strength * (1.0 - smoothstep(DETAIL_NEAR, DETAIL_FAR, length(VERTEX)));
	vec3 base = texture(albedo_map, uv).rgb;
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = mix(base, vec3(luma), desaturate) * tint * albedo_gain * piece.rgb * color_range;
	vec3 orm = texture(orm_map, uv).rgb;
	float rough = orm.g * roughness_scale;
	nap = cloth_sheen;
	if (stripe_width > 0.0) {
		float band = floor(UV.y / stripe_width);
		float pick = lot(band * 0.37 + 3.0);
		// A broad ground with narrower bands of the two other wools between.
		vec3 wool = pick < 0.45 ? stripe_a : (pick < 0.75 ? stripe_b : stripe_c);
		base *= wool;
	}
	vec3 scan = texture(normal_map, uv).rgb;
	if (emblem_size.x > 0.0) {
		vec2 at = UV / emblem_size;
		float gold = texture(emblem_map, at).r;
		// The stitches stand off the cloth: the mask's slope tilts the surface at their edge,
		// and up close each stitch shows.
		vec2 rise = vec2(texture(emblem_map, at + vec2(0.002, 0.0)).r - gold, texture(emblem_map, at + vec2(0.0, 0.002)).r - gold);
		float thread = 1.0 + 0.2 * sin((UV.x + UV.y) * 2400.0) * (1.0 - smoothstep(0.8, 2.5, length(VERTEX)));
		base = mix(base, emblem_color * thread * mix(0.6, 1.0, orm.r), gold);
		rough = mix(rough, 0.5, gold);
		nap = mix(nap, 1.0, gold);
		scan.xy -= rise * 2.5 * smoothstep(0.0, 0.2, gold + 0.2);
	}
	if (stain > 0.0) {
		// A few broad blots where something was spilt, and a scatter of small spots.
		float blot = texture(cloud_weather, world_pos.xz * 0.9 + world_pos.y * vec2(0.7, 0.5)).g;
		float spot = texture(cloud_weather, world_pos.xz * 4.1 + world_pos.y * vec2(2.3, 3.7)).r;
		float dirt = smoothstep(0.55, 1.0, blot) * 0.7 + smoothstep(0.66, 0.9, spot) * 0.3;
		base *= mix(vec3(1.0), vec3(0.6, 0.47, 0.36), clamp(dirt, 0.0, 1.0) * stain);
	}
	ALBEDO = base;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.3;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	if (detail_fade > 0.0) {
		// Whiteout blend, as tavern_surface.gdshader.
		vec2 tilt = (textureGrad(detail_map, detail_uv, detail_dx, detail_dy).xy * 2.0 - 1.0)
			* (detail_fade / clamp(normal_strength, 0.3, 2.0));
		vec2 under = scan.xy * 2.0 - 1.0;
		vec3 blended = normalize(vec3(under + tilt, sqrt(max(1.0 - dot(under, under), 0.0))
				* sqrt(max(1.0 - dot(tilt, tilt), 0.0))));
		scan = vec3(blended.xy * 0.5 + 0.5, blended.z);
	}
	NORMAL_MAP = scan;
	NORMAL_MAP_DEPTH = normal_strength;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	vec3 shade = vec3(1.0);
	if (LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999) {
		shade = vec3(sun_vis);
	}
	vec3 come = LIGHT_COLOR * shade * ATTENUATION;
	float front = clamp((n_dot_l + cloth_wrap) / (1.0 + cloth_wrap), 0.0, 1.0);
	float back = clamp(-n_dot_l, 0.0, 1.0) * cloth_through;
	DIFFUSE_LIGHT += come * (front + back) / PI;
	float glance = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	SPECULAR_LIGHT += come * front * mix(vec3(0.3), ALBEDO, 0.7) * nap * glance * glance * glance;
}
