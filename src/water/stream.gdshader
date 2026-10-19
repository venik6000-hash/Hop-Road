shader_type spatial;
// The shelf stream between the falls (WaterfallSystem): the lake's own water
// (water_look.gdshaderinc) running along a ribbon. UV = (across 0..1, metres
// along the flow), UV2 = (metres from the centre line, flow speed m/s),
// COLOR.r = the ribbon's half width / 8 m, TANGENT across, BINORMAL downstream.
//
// The ripples are the lake's smallest FFT cascade, shrunk, turned so that its
// waves run across the flow and carried downstream in two phases that
// cross-fade so they never smear. The foam is the lake's too: boiling where
// the upper fall lands, and breaking over stones that come up to the surface
// of the fast water before the lip. The ribbon runs into its banks; where they
// do not hide its edges, over the rock at the lip, they thin out.
//
// Near the lip the eye looks through the water past the rock's edge, down to
// the lake: the path through the water is cut at the stream's greatest depth,
// and the lake's surface, missing from the screen copy, is let through from
// the framebuffer as the falls do (waterfall.gdshader).
render_mode blend_mix, depth_draw_always, cull_back, ambient_light_disabled;

#include "res://src/sky/atmosphere.gdshaderinc"
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/water/water_look.gdshaderinc"
#include "res://src/water/flow_noise.gdshaderinc"

global uniform sampler2DArray water_derivatives : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform vec4 water_tiles;
// The way the lake's waves run on its tiles (OceanFFT.wave_way).
global uniform vec2 water_wave;

// Where the upper fall lands (world x, z) and how far its boil reaches.
uniform vec2 landing = vec2(0.0);
uniform float landing_reach = 3.0;
// The ripples: the lake's 7.3 m cascade shrunk by ripple_scale, and their
// slope; under them, the swirls of the current (m high).
uniform float ripple_scale = 0.45;
uniform float ripple_strength = 0.7;
uniform float swirl_height = 0.03;
// Seconds each phase of the flowing ripples and foam lasts.
uniform float flow_cycle = 1.6;
// White water where the flow is fastest (steps of a brook); 0 = none, as on
// the shelf, whose stream breaks only over stones and under the fall.
uniform float rapids = 0.0;
// The stream is nowhere deeper than this (m, in its basin).
uniform float max_depth = 1.6;
// The lake's surface (world y), far below.
uniform float water_level = 0.72;
// 0 = normal, 1 = refraction only, 2 = reflection * fresnel, 3 = foam, 4 = path / 2 m,
// 5 = where the lake below shows through instead of the screen copy
uniform int debug_view = 0;

varying vec3 world_pos;
varying float glint_roughness;
varying float sun_vis;
varying float own_light;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	glint_roughness = water_glint_roughness(distance(CAMERA_POSITION_WORLD, world_pos));
	sun_vis = cloud_sun_visibility(world_pos);
}

void fragment() {
	float speed = UV2.y;
	vec2 flow_uv = vec2(UV2.x, UV.y);
	// Two phases of the pattern ride downstream, each jumping back while the
	// other one shows.
	float phase0 = fract(TIME / flow_cycle);
	float phase1 = fract(TIME / flow_cycle + 0.5);
	float w0 = 1.0 - abs(phase0 * 2.0 - 1.0);
	float w1 = 1.0 - w0;
	vec2 uv0 = flow_uv - vec2(0.0, phase0 * flow_cycle * speed);
	vec2 uv1 = flow_uv - vec2(0.0, phase1 * flow_cycle * speed) + vec2(2.37, 5.61);
	// The lake's smallest cascade of ripples, shrunk, turned so that its waves
	// run across the flow and drawn out along it: their crests become the
	// streaks of running water, where waves running with the flow would cross
	// it in bars. (Its larger cascades have the regular crests of a wind sea,
	// which a stream does not.)
	// The lake's waves run on its tiles along `water_wave`, whatever way the
	// wind over the ground blows.
	vec2 wave = water_wave;
	mat2 onto_tile = mat2(wave, vec2(-wave.y, wave.x));
	vec2 drawn = vec2(1.0, 0.45);
	float tile = water_tiles.z * ripple_scale;
	vec4 d0 = texture(water_derivatives, vec3(onto_tile * (uv0 * drawn) / tile, 2.0));
	vec4 d1 = texture(water_derivatives, vec3(onto_tile * (uv1 * drawn) / tile, 2.0));
	vec2 s0 = transpose(onto_tile) * vec2(d0.x / (1.0 + d0.z), d0.y / (1.0 + d0.w)) * drawn;
	vec2 s1 = transpose(onto_tile) * vec2(d1.x / (1.0 + d1.z), d1.y / (1.0 + d1.w)) * drawn;
	// Weights normalised by their length keep the contrast through the fade.
	float norm = 1.0 / sqrt(w0 * w0 + w1 * w1);
	vec2 slope = (s0 * w0 + s1 * w1) * norm;
	// Under them, the swirls and boils of the current itself.
	float swirl = ((flow_fbm(uv0 * vec2(1.6, 0.8), 3) - 0.5) * w0 + (flow_fbm(uv1 * vec2(1.6, 0.8), 3) - 0.5) * w1) * norm;
	// Faster water is choppier.
	float rough = mix(0.5, 1.4, smoothstep(0.4, 2.5, speed));
	slope *= ripple_strength * rough;
	vec3 swirled = flow_bump(VERTEX, NORMAL, swirl * swirl_height * rough);
	vec3 n_view = normalize(swirled - TANGENT * slope.x - BINORMAL * slope.y);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 eye_ray = normalize(VERTEX);
	float surface_depth = -VERTEX.z;
	float fresnel = water_fresnel(n_world, view_dir_world);

	// Refraction, bent more where there is more water under the surface.
	float under = max(linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - surface_depth, 0.0) * max(-eye_ray.z, 0.15);
	float behind;
	vec2 refract_uv = water_refract_uv(SCREEN_UV, n_view, clamp(under * 0.5, 0.0, 1.0), surface_depth, INV_PROJECTION_MATRIX, behind);
	// Path through water along the eye ray, not just along the view axis, and
	// no longer than the deepest water: beyond that the ray has left it.
	float path = max(behind - surface_depth, 0.0) / max(-eye_ray.z, 0.15);
	path = min(path, max_depth / max(view_dir_world.y, 0.1));
	float water_below = water_between(refract_uv, behind, water_level, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, CAMERA_POSITION_WORLD);
	vec3 ambient = water_ambient();
	vec3 transmittance = exp(-absorption * path);
	vec3 scene = textureLod(screen_texture, refract_uv, 0.0).rgb;
	vec3 body = water_refracted(vec3(0.0), path, ambient);
	vec3 refracted = scene * transmittance * (1.0 - water_below) + body;
	vec3 reflection = water_reflection(VERTEX, n_view, fresnel, INV_VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);

	// Foam: the upper fall's boil, and the fast water over the lip breaking
	// where stones come up to its surface; the calm channel runs clear to its
	// banks, and the fast water slides along its banks unbroken.
	// Only stones that come within a few centimetres of the surface break it,
	// measured straight down rather than along the eye ray.
	float from_landing = length(world_pos.xz - landing);
	float boil = 1.0 - smoothstep(landing_reach * 0.25, landing_reach, from_landing);
	float over_stone = path * max(view_dir_world.y, 0.1);
	float midstream = 1.0 - smoothstep(0.35, 0.6, abs(UV2.x) / (COLOR.r * 8.0));
	float contact = (1.0 - smoothstep(0.0, 0.05, over_stone)) * 0.9 * smoothstep(1.2, 2.6, speed) * midstream;
	float pattern = foam_pattern(uv0 * 0.9 + slope * 0.6) * w0 + foam_pattern(uv1 * 0.9 + slope * 0.6) * w1;
	float white = rapids * smoothstep(2.4, 4.2, speed) * mix(0.3, 1.0, pattern);
	float foam = clamp(contact * 1.2 * pattern + boil * mix(0.55, 1.0, pattern) + white, 0.0, 1.0);

	// Over the lake, the share of the framebuffer let through, and the
	// stream's own light scaled up by what that takes off its alpha.
	float through = min(water_below * (1.0 - fresnel) * (1.0 - foam) * dot(transmittance, vec3(1.0 / 3.0)), 0.95);
	own_light = 1.0 / (1.0 - through);
	vec3 color = mix(refracted, reflection, fresnel);
	EMISSION = (color * (1.0 - foam) + foam_color * foam * ambient * 0.8) * own_light;
	ALBEDO = foam_color * foam * own_light;
	ROUGHNESS = mix(glint_roughness, 0.85, foam);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	NORMAL = n_view;
	ALPHA = smoothstep(0.0, 0.5, COLOR.r * 8.0 - abs(UV2.x)) * (1.0 - through);
	if (debug_view > 0) {
		EMISSION = debug_view == 1 ? scene * transmittance + body : debug_view == 2 ? reflection * fresnel
			: debug_view == 3 ? vec3(foam) : debug_view == 4 ? vec3(path * 0.5) : vec3(water_below);
		ALBEDO = vec3(0.0);
		ALPHA = 1.0;
		own_light = 0.0;
	}
}

void light() {
	bool is_sun = LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999;
	float shade = ATTENUATION * (is_sun ? sun_vis : 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * shade * clamp(dot(NORMAL, LIGHT), 0.0, 1.0) / PI;
	SPECULAR_LIGHT += LIGHT_COLOR * shade * own_light * water_glint(NORMAL, VIEW, LIGHT, glint_roughness);
	// Calm water: the lake's subsurface lift for a flat crest.
	SPECULAR_LIGHT += LIGHT_COLOR * shade * own_light * scatter_color * water_through(NORMAL, VIEW, LIGHT) * 0.3 * sss_strength * 0.25;
}
