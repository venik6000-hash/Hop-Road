shader_type spatial;
// Falling water (WaterfallSystem): the lake's own water (water_look.gdshaderinc)
// on a sheet along the ballistic path from a lip. UV = (across 0..1, seconds
// since the water left the lip), UV2 = (metres from the centre line, share of
// the fall 0..1), COLOR = (layer: 0 the front sheet, 1 the narrower one behind
// it; the water's thickness over the lip in metres; its speed there / 10 m/s),
// TANGENT across the sheet.
//
// Over the lip it is the stream's clear water, thinning as it speeds up: what
// lies behind shows through it bent and tinted as through the lake, under the
// sky's reflection and the sun's glints, with the lake's ripples stretched
// down the fall. Within half a second it tears into ropes with thin veils
// between them, fraying at the edges, and air works into the ropes as they
// fall: they whiten from their most churned water (the lake's foam, lit as
// the lake lights it) until near the bottom they are white through. Features
// ride with the water: they are looked up at the moment it left the lip
// (TIME - t), so they lengthen as it speeds up.
//
// The screen copy it refracts is taken before any transparent is drawn, so it
// holds the bed under the water the fall lands in, not that water's surface.
// Where what lies behind the sheet is below that surface (floor_level), the
// sheet does not refract: it lets the framebuffer, where the water is already
// drawn, through by its alpha, and adds its own light over it.
render_mode blend_mix, depth_draw_always, cull_disabled, ambient_light_disabled;

#include "res://src/sky/atmosphere.gdshaderinc"
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/water/water_look.gdshaderinc"
#include "res://src/water/flow_noise.gdshaderinc"

global uniform sampler2DArray water_derivatives : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform vec4 water_tiles;

// Seconds of fall until the water is torn by air.
uniform float breakup = 0.55;
// Slope of the lake's ripples on the glassy water over the lip.
uniform float ripple_strength = 0.6;
// The way the lake's waves run on its tiles (radians from +x; WaterfallSystem
// copies the lake's wind).
uniform float wind_heading = 0.96;
// 0 = normal, 1 = refraction only, 2 = reflection * fresnel, 3 = foam, 4 = view normal, 5 = coverage,
// 6 = where the water below shows through instead of the screen copy
uniform int debug_view = 0;
// The surface this fall lands in (world y): the lake, or the stream's basin.
instance uniform float floor_level = 0.72;

varying float layer;
varying float sun_vis;
varying float glint_roughness;
varying float lift;
varying float glitter;
// The sheet's own light, scaled up where it keeps only part of its alpha.
varying float own_light;

void vertex() {
	layer = COLOR.r;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sun_vis = cloud_sun_visibility(world);
	glint_roughness = water_glint_roughness(distance(CAMERA_POSITION_WORLD, world));
}

void fragment() {
	float t = max(UV.y, 0.0);
	float across = UV2.x;
	float launch = TIME - UV.y;
	float seed = layer * 23.7;
	float lip_speed = COLOR.b * 10.0;
	// The sheet tears into ropes within `breakup` seconds; air works into the
	// ropes over the whole fall.
	float tear = smoothstep(0.04, breakup, t);
	float aeration = smoothstep(0.15, 1.9, t);
	// Detail finer than a pixel only flickers: fewer octaves far away.
	float dist = length(VERTEX);
	int octaves = dist < 60.0 ? 4 : 2;
	// Ropes: columns of water that wander slowly across the sheet...
	float ropes = smoothstep(0.34, 0.62, flow_fbm(vec2(across * 3.2 + seed, launch * 0.55), octaves));
	// ...clumps of denser water running down them...
	float clumps = flow_fbm(vec2(across * 6.5 - seed, launch * 5.0), octaves);
	// ...fine streaks, faded out where they would be under a pixel...
	float fine = 1.0 - smoothstep(25.0, 70.0, dist);
	float streak = mix(0.5, flow_fbm(vec2(across * 18.0 + seed * 3.0, launch * 3.0), 2), fine);
	// ...and a skin of water sliding faster than the ropes it runs over.
	float slide = mix(0.5, flow_fbm(vec2(across * 9.0 - seed, launch * 2.5 - TIME * 1.2), 2), fine);
	float density = ropes * (0.5 + 0.65 * clumps) + (streak - 0.5) * 0.4 + (slide - 0.5) * 0.25;

	// The torn water stands out of the sheet in its ropes and clumps, and the
	// light runs along their flanks: a bump from the screen-space derivatives
	// of that relief (Mikkelsen's surface gradient). On it, the lake's ripples,
	// carried with the water and stretched as it speeds up.
	vec3 bumped = flow_bump(VERTEX, NORMAL, (density - 0.35) * 0.09 * tear);
	// The ripples are turned so that their waves run across the flow and
	// drawn out three times along it, so that their crests run down it as
	// streaks.
	float stretch = length(vec2(lip_speed, 9.81 * t)) / lip_speed;
	vec2 wave = vec2(cos(wind_heading), sin(wind_heading));
	mat2 onto_tile = mat2(wave, vec2(-wave.y, wave.x));
	vec4 d = texture(water_derivatives, vec3(onto_tile * vec2(across, launch * lip_speed / 3.0) / (water_tiles.z * 0.5), 2.0));
	vec2 slope = transpose(onto_tile) * vec2(d.x / (1.0 + d.z), d.y / (1.0 + d.w));
	slope = vec2(slope.x, slope.y / (stretch * 3.0)) * ripple_strength;
	vec3 n_view = normalize(bumped - TANGENT * slope.x - BINORMAL * slope.y);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 eye_ray = normalize(VERTEX);
	float surface_depth = -VERTEX.z;
	float fresnel = water_fresnel(n_world, view_dir_world);

	// The water thins as it speeds up and gathers into the ropes once torn;
	// the eye looks through it slantwise, and the bubbles in it scatter light
	// as a longer path through the lake would.
	float thickness = COLOR.g / stretch * mix(1.0, 0.35 + 1.3 * density, tear);
	float path = thickness / max(abs(dot(n_view, eye_ray)), 0.2) * (1.0 + 8.0 * aeration);
	// A sheet this thin bends what lies behind it only by its ripples and
	// ropes, not by which way it faces.
	float behind;
	vec2 refract_uv = water_refract_uv(SCREEN_UV, n_view - NORMAL, clamp(thickness * 3.0, 0.25, 1.0), surface_depth, INV_PROJECTION_MATRIX, behind);
	float water_below = water_between(refract_uv, behind, floor_level, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, CAMERA_POSITION_WORLD);
	vec3 ambient = water_ambient();
	vec3 transmittance = exp(-absorption * path);
	vec3 scene = textureLod(screen_texture, refract_uv, 0.0).rgb;
	// The light the water body scatters, and what lies behind it through the
	// water unless the framebuffer supplies that.
	vec3 body = water_refracted(vec3(0.0), path, ambient);
	vec3 refracted = scene * transmittance * (1.0 - water_below) + body;
	vec3 reflection = water_reflection(VERTEX, n_view, fresnel, INV_VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);

	// Foam: the ropes whiten from their densest, most churned water as air
	// gets into them, mottled by the lake's foam pattern, until near the
	// bottom they are white through; the veils between them turn milky. Foam
	// deep in a clump is in its own shade.
	float pattern = foam_pattern(vec2(across * 0.8 + seed, launch * lip_speed * 0.5));
	float churn = density + (streak - 0.5) * 0.5 + (pattern - 0.5) * 0.3;
	// Hair-fine streaks in the white, where they are still over a pixel wide.
	float hair = mix(1.0, 0.6 + 0.4 * flow_noise(vec2(across * 24.0 + seed, launch * 6.0)), 1.0 - smoothstep(12.0, 30.0, dist));
	float white = tear * smoothstep(0.6 - 0.45 * aeration, 0.95 - 0.35 * aeration, churn) * hair;
	float foam = clamp(white + tear * aeration * 0.3, 0.0, 1.0);
	float foam_shade = 0.68 + 0.32 * clumps;
	// Edges thin out and fray as the sheet falls; the torn sheet thins
	// between its ropes into veils, with gaps only where it is thinnest.
	float edge = 0.5 - abs(UV.x - 0.5);
	float fray = smoothstep(0.02, 0.1 + 0.25 * tear, edge + (clumps - 0.5) * 0.22 * tear);
	float coverage = mix(1.0, 0.3 + 0.7 * smoothstep(0.1, 0.45, density), tear) * fray;

	// Over the water below, the share of the framebuffer the sheet lets
	// through where it is (its transmittance taken as grey); what the sheet
	// adds itself is scaled up by what that takes off its alpha, so that
	// blending gives it back as it was.
	float through = min(water_below * (1.0 - fresnel) * (1.0 - foam) * dot(transmittance, vec3(1.0 / 3.0)), 0.95);
	own_light = 1.0 / (1.0 - through);
	vec3 color = mix(refracted, reflection, fresnel);
	EMISSION = (color * (1.0 - foam) + foam_color * foam_shade * foam * ambient * 0.8) * own_light;
	ALBEDO = foam_color * foam_shade * foam * own_light;
	ROUGHNESS = mix(glint_roughness, 0.85, foam);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	NORMAL = n_view;
	ALPHA = clamp(coverage * (layer > 0.5 ? 0.75 : 1.0) * (1.0 - through), 0.0, 1.0);
	if (debug_view > 0) {
		EMISSION = debug_view == 1 ? scene * transmittance + body : debug_view == 2 ? reflection * fresnel
			: debug_view == 3 ? vec3(foam) : debug_view == 4 ? n_view * 0.5 + 0.5 : debug_view == 5 ? vec3(coverage)
			: vec3(water_below);
		ALBEDO = vec3(0.0);
		ALPHA = 1.0;
		own_light = 0.0;
	}
	// Thin clear water lets the most sunlight through.
	lift = 0.3 + 0.9 * (1.0 - tear) * (1.0 - smoothstep(0.05, 0.6, thickness));
	// Droplets flung off the torn water glitter in the sun: the sharpest
	// peaks of a fast, fine noise, where they are still over a pixel wide.
	glitter = pow(flow_noise(vec2(across * 40.0 + seed, launch * 9.0 - TIME * 3.0)), 14.0) * 60.0
		* (foam + tear * 0.3) * (1.0 - smoothstep(10.0, 35.0, dist));
}

void light() {
	bool is_sun = LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999;
	float shade = ATTENUATION * (is_sun ? sun_vis : 1.0);
	float n_dot_l = dot(NORMAL, LIGHT);
	// As on the lake, but a fall's foam is thick and scatters light from
	// every side: wrapped, and glowing where the sun is behind it.
	float wrap = clamp((n_dot_l + 0.5) / 1.5, 0.0, 1.0);
	float glow = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * 0.5;
	DIFFUSE_LIGHT += LIGHT_COLOR * shade * (wrap + glow) / PI;
	SPECULAR_LIGHT += LIGHT_COLOR * shade * own_light * water_glint(NORMAL, VIEW, LIGHT, glint_roughness);
	SPECULAR_LIGHT += LIGHT_COLOR * shade * own_light * scatter_color * water_through(NORMAL, VIEW, LIGHT) * lift * sss_strength * 0.25;
	if (is_sun) {
		SPECULAR_LIGHT += LIGHT_COLOR * shade * own_light * glitter * 0.05;
	}
}
