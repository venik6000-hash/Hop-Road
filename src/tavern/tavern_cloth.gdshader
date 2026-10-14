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
// cut into threads here, each its own length. At 0.5 the strip is a lace
// edging: its UVs are the length along the hem and the distance out from it,
// both in widths of the strip, and the lace is cut out of it here (scallops, a
// shell in each, a diamond mesh between), pale thread, seen from afar a band.
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
// Needlework: R of the map is gold thread, laid over `emblem_size` metres of UV (0: none).
uniform sampler2D emblem_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 emblem_size = vec2(0.0);
uniform vec3 emblem_color : source_color = vec3(0.8, 0.62, 0.3);

// Lace: the strip's alpha, the thread's colour over the piece's own, the length of one scallop and
// the side of one diamond of the mesh, in widths of the strip.
const float LACE_ALPHA = 0.5;
const vec3 LACE_COLOR = vec3(0.55, 0.53, 0.48);
const float LACE_SCALLOP = 0.5;
const float LACE_MESH = 0.25;

varying vec3 world_pos;
varying float sun_vis;
varying vec4 piece;
varying float nap;

float lot(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// 1 where the lace has thread at p (along the hem, out from it), 0 where it is open. `cell` is how
// many pixels one diamond of the mesh takes: where they are too small to tell apart the mesh is solid.
float lace_thread(vec2 p, float cell) {
	float along = fract(p.x / LACE_SCALLOP);
	float arc = along * 2.0 - 1.0;
	float reach = 0.76 + 0.24 * sqrt(max(1.0 - arc * arc, 0.0));
	if (p.y > reach) {
		return 0.0;
	}
	// The heading sewn to the cloth and the edge of each scallop are close-worked.
	if (p.y < 0.16 || p.y > reach - 0.09) {
		return 1.0;
	}
	// The shell in the middle of a scallop: a ring of thread round an eyelet.
	float shell = length(vec2((along - 0.5) * LACE_SCALLOP, p.y - 0.46));
	if (shell < 0.16) {
		return (shell > 0.1 || cell < 4.5) ? 1.0 : 0.0;
	}
	if (cell < 4.5) {
		return 1.0;
	}
	float up = abs(fract((p.x + p.y) / LACE_MESH) - 0.5);
	float down = abs(fract((p.x - p.y) / LACE_MESH) - 0.5);
	return max(up, down) > 0.36 ? 1.0 : 0.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sun_vis = cloud_sun_visibility(world_pos);
	piece = COLOR;
}

void fragment() {
	if (abs(piece.a - LACE_ALPHA) < 0.03) {
		float cell = LACE_MESH / max(max(fwidth(UV.x), fwidth(UV.y)), 0.00001);
		if (lace_thread(UV, cell) < 0.5) {
			discard;
		}
		// What is a mesh up close is a paler, thinner band from afar.
		float afar = 1.0 - smoothstep(4.5, 8.0, cell);
		ALBEDO = min(piece.rgb * color_range * LACE_COLOR * mix(1.0, 0.8, afar), vec3(0.8));
		ROUGHNESS = 0.9;
		SPECULAR = 0.2;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
		NORMAL_MAP_DEPTH = 1.0;
		nap = 0.1;
	} else {
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
