shader_type spatial;
// Lake surface over the FFT cascades (ocean_fft.gd). Above water: screen-space
// reflections that fall back to the physical sky, refraction with Beer-Lambert
// absorption through the real water column, subsurface light in the crests,
// Jacobian whitecaps, shore foam and GGX sun glints whose roughness grows with
// distance so the glitter path widens instead of aliasing. From below: Snell's
// window and total internal reflection. Fog under water is the post pass's job.
// The engine's sky reflection would double ours, so ambient/IBL is off and
// the foam's share of sky light is added by hand.
render_mode blend_mix, depth_draw_always, cull_disabled, ambient_light_disabled;

#include "res://src/sky/atmosphere.gdshaderinc"
#include "res://src/water/water_look.gdshaderinc"

global uniform sampler2DArray water_displacement : filter_linear_mipmap, repeat_enable;
global uniform sampler2DArray water_derivatives : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform vec4 water_tiles;
global uniform vec4 water_cascade_weights;

uniform sampler2D near_height : filter_linear, repeat_disable;
uniform sampler2D far_height : filter_linear, repeat_disable;
uniform vec4 near_rect;
uniform vec4 far_rect;
uniform vec3 surface_camera;
uniform float water_level = 0.72;

// Scattering by water and suspended matter (1/m); with absorption it sets the
// lake body's glow seen from below (matches the underwater lens pass).
uniform vec3 scattering = vec3(0.041, 0.046, 0.052);
uniform float shore_foam = 1.0;
// 0 = normal, 1 = faces (red front / blue back), 2 = ground depth, 3 = cascade slopes
uniform int debug_view = 0;

#include "res://src/lakeside/shore_common.gdshaderinc"
uniform vec4 lake_wakes[16];
uniform sampler2D lake_refraction : filter_linear, repeat_disable;
uniform sampler2D lake_refraction_frame : filter_nearest, repeat_disable;
uniform vec4 lake_boat_pose = vec4(1000000.0); // x,z,yaw,height
uniform bool refraction_ready = false;
uniform float refraction_guard = 1.25;
// Height and analytical derivatives in a single loop (no four extra marches).
vec3 lake_wake(vec2 xz) {
	vec3 result = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		float age = lake_shore_clock.x - lake_wakes[i].z;
		if (age < 0.0 || age > 8.0) continue;
		vec2 radial = xz - lake_wakes[i].xy;
		float radius = length(radial);
		float d = radius - age * 1.3;
		if (abs(d) > 2.5) continue;
		float envelope = exp(-d*d*2.0 - age*0.4) * lake_wakes[i].w;
		float height = sin(d*9.0) * envelope;
		float derivative = (9.0*cos(d*9.0) - 4.0*d*sin(d*9.0)) * envelope;
		result += vec3(height, derivative * radial / max(radius, 0.001));
	}
	return result;
}
varying vec3 world_pos;
varying vec2 grid_xz;
varying float wave_scale;
varying float glint_roughness;
varying float crest;

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
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec4 info = INSTANCE_CUSTOM;
	vec2 grid = VERTEX.xz * info.z;
	vec2 xz = origin.xz + VERTEX.xz * size;
	float dist = distance(surface_camera, vec3(xz.x, water_level, xz.y));
	float morph = clamp((dist - info.x) / max(info.y - info.x, 1e-3), 0.0, 1.0);
	vec2 odd = fract(grid * 0.5) * 2.0;
	vec2 local = (grid - odd * morph) / info.z;
	xz = origin.xz + local * size;
	dist = distance(surface_camera, vec3(xz.x, water_level, xz.y));

	// Waves shrink over shallows and die on the beach.
	float depth = water_level - ground_height(xz);
	float shore = mix(0.08, 1.0, smoothstep(0.0, 7.0, depth));
	// Wind gusts: wave energy varies over the lake, which also hides tiling.
	float gust = 0.72 + 0.56 * textureLod(macro_noise, xz / 1700.0, 0.0).r;
	wave_scale = shore * gust;
	vec3 fade = cascade_fade(dist) * water_cascade_weights.xyz * wave_scale;
	vec4 d = vec4(0.0);
	for (int c = 0; c < 3; c++) {
		if (fade[c] == 0.0) {
			continue;
		}
		d += textureLod(water_displacement, vec3(xz / water_tiles[c], float(c)), 0.0) * fade[c];
	}
	d.y += lake_runup(xz, depth) + lake_wake(xz).x;
	crest = d.y;
	grid_xz = xz;
	world_pos = vec3(xz.x + d.x, water_level + d.y, xz.y + d.z);
	VERTEX = vec3(local.x + d.x / size, water_level + d.y, local.y + d.z / size);
	NORMAL = vec3(0.0, 1.0, 0.0);
	// Distant water: unresolved waves read as a rougher, wider sun path.
	glint_roughness = water_glint_roughness(dist);
}

void fragment() {
	vec3 p = world_pos;
	vec2 boat_delta = p.xz - lake_boat_pose.xy;
	float boat_cos = cos(lake_boat_pose.z);
	float boat_sin = sin(lake_boat_pose.z);
	vec2 boat_local = vec2(boat_cos*boat_delta.x-boat_sin*boat_delta.y, boat_sin*boat_delta.x+boat_cos*boat_delta.y);
	float hull_width = sqrt(max(cos(boat_local.y*3.14159265/3.9), 0.0))*0.60;
	// Only uncover the boat floor, never punch a clear hole through the lake bed.
	if (abs(boat_local.y) < 1.65 && abs(boat_local.x) < hull_width && p.y < lake_boat_pose.w + 0.40) {
		if (linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX) + VERTEX.z < 0.7) discard;
	}
	vec2 xz = grid_xz;
	float dist = length(p - CAMERA_POSITION_WORLD);
	vec3 fade = cascade_fade(dist) * water_cascade_weights.xyz * wave_scale;
	vec4 slopes = vec4(0.0);
	float whitecap = 0.0;
	for (int c = 0; c < 3; c++) {
		// Only uniform zero weights skip fragment reads: varying distance
		// fades must keep the implicit mip/anisotropic gradients unchanged.
		if (water_cascade_weights[c] == 0.0) {
			continue;
		}
		vec3 uvw = vec3(xz / water_tiles[c], float(c));
		slopes += texture(water_derivatives, uvw) * fade[c];
		whitecap += texture(water_displacement, uvw).a * fade[c];
	}
	vec2 slope = vec2(slopes.x / (1.0 + slopes.z), slopes.y / (1.0 + slopes.w));
	slope += lake_wake(xz).yz;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - p);

	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	vec3 eye_ray = normalize(VERTEX);
	float surface_depth = -VERTEX.z;
	float ground_depth = water_level - ground_height(xz);

	if (FRONT_FACING) {
		float fresnel = water_fresnel(n_world, view_dir_world);

		// Refraction: offset by the normal, but never pull in foreground objects.
		vec2 edge_fade = smoothstep(vec2(0.0), vec2(0.06), SCREEN_UV) * smoothstep(vec2(0.0), vec2(0.06), 1.0 - SCREEN_UV);
		vec2 offset = n_view.xy * refraction_strength * clamp(ground_depth * 0.5, 0.0, 1.0) * edge_fade.x * edge_fade.y;
		vec2 refract_uv = SCREEN_UV + offset;
		float behind = linear_depth(refract_uv, INV_PROJECTION_MATRIX);
		if (behind < surface_depth) {
			refract_uv = SCREEN_UV;
			behind = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
		}
		// Path through water along the eye ray, not just along the view axis.
		float path = max(behind - surface_depth, 0.0) / max(-eye_ray.z, 0.15);
		vec3 scene = textureLod(screen_texture, refract_uv, 0.0).rgb;
		if (refraction_ready) {
			vec2 capture_uv = (SCREEN_UV + offset - 0.5) / refraction_guard + 0.5;
			vec4 below = texture(lake_refraction, capture_uv);
			if (texture(lake_refraction_frame, capture_uv).a > 0.0 && below.a > surface_depth && below.a < 190.0) {
				scene = below.rgb;
				path = (below.a - surface_depth) / max(-eye_ray.z, 0.15);
			}
		}
		// Light scattered by the water body toward the eye.
		vec3 ambient = water_ambient();
		vec3 refracted = water_refracted(scene, path, ambient);
		vec3 reflection = water_reflection(VERTEX, n_view, fresnel, INV_VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);

		// Foam: folded crests, shallows over sand and stones, and around anything
		// standing in the water.
		float contact = 1.0 - smoothstep(0.0, 0.35, path);
		float shallows = 1.0 - smoothstep(0.05, 0.9, ground_depth);
		float foam = clamp(whitecap * 1.2, 0.0, 1.0);
		foam = max(foam, (contact * 0.8 + shallows * 0.6) * shore_foam * wave_scale * 1.6);
		foam = max(foam, lake_shore_at(xz).r);
		foam *= foam_pattern(xz + slope * 0.6);
		foam = clamp(foam, 0.0, 1.0);

		vec3 color = mix(refracted, reflection, fresnel);
		EMISSION = color * (1.0 - foam) + foam_color * foam * ambient * 0.8;
		ALBEDO = foam_color * foam;
		ROUGHNESS = mix(glint_roughness, 0.85, foam);
	} else {
		// Seen from below: the sky and shore through Snell's window, the lake's
		// own dimness reflected beyond the critical angle (48.6 deg).
		vec3 n_under = -n_world;
		float cos_view = dot(n_under, view_dir_world);
		float window = smoothstep(0.62, 0.7, dot(-view_dir_world, vec3(0.0, 1.0, 0.0)));
		vec2 refract_uv = SCREEN_UV + n_view.xy * 0.06;
		vec3 above = textureLod(screen_texture, refract_uv, 0.0).rgb;
		// Beyond the critical angle the surface mirrors the lake below: the
		// water body's own scattered light, as the underwater lens sees it
		// looking down (lens_post.glsl).
		vec3 sunlight = sun_radiance_scale * atmo_transmittance_to_space(atmo_view_radius, max(sun_direction.y, 0.0)) * max(sun_direction.y, 0.0);
		vec3 irradiance = atmo_sky_radiance(vec3(0.0, 1.0, 0.0)) * ATMO_PI * 0.8 + sunlight;
		vec3 inner = scattering / (absorption + scattering) * irradiance * 0.08 * 0.45;
		float transmit = 1.0 - (0.02 + 0.98 * pow(1.0 - max(cos_view, 0.0), 5.0));
		EMISSION = mix(inner, above * transmit, window);
		ALBEDO = vec3(0.0);
		ROUGHNESS = 0.1;
	}
	if (debug_view == 1) {
		EMISSION = FRONT_FACING ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
		ALBEDO = vec3(0.0);
	} else if (debug_view == 2) {
		EMISSION = vec3(clamp(ground_depth / 10.0, 0.0, 1.0), clamp(-ground_depth, 0.0, 1.0), 0.0);
		ALBEDO = vec3(0.0);
	}
	ALPHA = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	NORMAL = FRONT_FACING ? n_view : -n_view;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * clamp(n_dot_l, 0.0, 1.0) / PI;
	if (n_dot_l > 0.0) {
		// Sun glints: GGX on the wave normal.
		vec3 h = normalize(VIEW + LIGHT);
		float n_dot_h = clamp(dot(NORMAL, h), 0.0, 1.0);
		float n_dot_v = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
		float a = glint_roughness * glint_roughness;
		float a2 = a * a;
		float d = a2 / (PI * pow(n_dot_h * n_dot_h * (a2 - 1.0) + 1.0, 2.0));
		float k = a * 0.5;
		float vis = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
		float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(VIEW, h), 0.0, 1.0), 5.0);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * n_dot_l * d * vis * fresnel;
	}
	// Subsurface: sunlight through thin wave crests toward the viewer.
	float through = pow(clamp(dot(VIEW, -LIGHT + NORMAL * 0.4), 0.0, 1.0), 4.0);
	float lift = clamp(crest * 0.6 + 0.3, 0.0, 1.5);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * scatter_color * through * lift * sss_strength * 0.25;
}
