// Shared optics for the lake, the shelf stream, the falls and the foam where
// the lower fall plunges in (WaterfallSystem): refraction with
// Beer-Lambert absorption and the light the water body scatters, screen-space
// reflections over the physical sky, Schlick Fresnel, the foam pattern and
// its sky light, GGX sun glints whose roughness grows with distance, and
// subsurface light through thin water. WaterfallSystem copies the parameter
// values below from the lake's material.
//
// Needs atmosphere.gdshaderinc included before it. The shader composes the
// surface as the lake does:
//   EMISSION = mix(refracted, reflection, fresnel) * (1 - foam) + foam_color * foam * ambient * 0.8
//   ALBEDO = foam_color * foam, lit in light() by the sun (water_glint, water_through).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform vec3 absorption = vec3(0.42, 0.075, 0.036);
uniform vec3 scatter_color : source_color = vec3(0.035, 0.24, 0.26);
uniform vec3 deep_color : source_color = vec3(0.012, 0.075, 0.1);
uniform float refraction_strength = 0.045;
uniform float base_roughness = 0.035;
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform float sss_strength = 1.2;

float linear_depth(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_texture, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -view.z / view.w;
}

// Reflection from the screen, marching the reflected ray in view space.
// Returns rgb and a confidence in a.
vec4 screen_reflection(vec3 view_pos, vec3 view_dir, mat4 projection, mat4 inv_projection) {
	float t = 0.5;
	float previous = 0.0;
	for (int i = 0; i < 13; i++) {
		vec3 p = view_pos + view_dir * t;
		if (p.z > -0.05) {
			break;
		}
		vec4 clip = projection * vec4(p, 1.0);
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
			return vec4(0.0);
		}
		float scene = linear_depth(uv, inv_projection);
		float ray = -p.z;
		if (ray > scene && ray - scene < max(0.6, t * 0.08)) {
			// Refine between the last miss and this hit.
			float lo = previous;
			float hi = t;
			for (int j = 0; j < 4; j++) {
				float mid = (lo + hi) * 0.5;
				vec3 q = view_pos + view_dir * mid;
				vec4 qc = projection * vec4(q, 1.0);
				vec2 quv = qc.xy / qc.w * 0.5 + 0.5;
				if (-q.z > linear_depth(quv, inv_projection)) {
					hi = mid;
				} else {
					lo = mid;
				}
			}
			vec3 q = view_pos + view_dir * hi;
			vec4 qc = projection * vec4(q, 1.0);
			vec2 quv = qc.xy / qc.w * 0.5 + 0.5;
			vec2 edge = smoothstep(vec2(0.0), vec2(0.08), quv) * smoothstep(vec2(0.0), vec2(0.08), 1.0 - quv);
			return vec4(textureLod(screen_texture, quv, 0.0).rgb, edge.x * edge.y);
		}
		previous = t;
		t *= 1.75;
	}
	// No hit: the ray escapes. Where the sky is on screen in that direction,
	// take it from there (clouds and all); the caller falls back otherwise.
	vec4 clip = projection * vec4(view_pos + view_dir * 20000.0, 1.0);
	if (clip.w <= 0.0) {
		return vec4(0.0);
	}
	vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec4(0.0);
	}
	if (texture(depth_texture, uv).r > 0.00001) {
		return vec4(0.0);
	}
	vec2 edge = smoothstep(vec2(0.0), vec2(0.1), uv) * smoothstep(vec2(0.0), vec2(0.1), 1.0 - uv);
	return vec4(textureLod(screen_texture, uv, 0.0).rgb, edge.x * edge.y);
}

float foam_pattern(vec2 xz) {
	float a = textureLod(macro_noise, xz / 3.1, 0.0).g;
	float b = textureLod(macro_noise, xz / 1.3 + vec2(0.31, 0.77), 0.0).b;
	return smoothstep(0.35, 0.75, a * 0.6 + b * 0.55);
}

// Distant water: unresolved waves read as a rougher, wider sun path.
float water_glint_roughness(float dist) {
	return base_roughness + 0.16 * smoothstep(40.0, 2500.0, dist);
}

float water_fresnel(vec3 n_world, vec3 view_dir_world) {
	float cos_view = max(dot(n_world, view_dir_world), 0.0);
	return 0.02 + 0.98 * pow(1.0 - cos_view, 5.0);
}

// Sky light falling on the water, which also lights its foam.
vec3 water_ambient() {
	return atmo_sky_radiance(vec3(0.0, 1.0, 0.0)) * 0.9;
}

// Screen uv to refract through: offset by the view-space normal, by up to
// refraction_strength scaled by `amount`, but never pulling in foreground
// objects. `behind` is the view depth of the scene found there.
vec2 water_refract_uv(vec2 screen_uv, vec3 n_view, float amount, float surface_depth, mat4 inv_projection, out float behind) {
	vec2 edge_fade = smoothstep(vec2(0.0), vec2(0.06), screen_uv) * smoothstep(vec2(0.0), vec2(0.06), 1.0 - screen_uv);
	vec2 uv = screen_uv + n_view.xy * refraction_strength * amount * edge_fade.x * edge_fade.y;
	behind = linear_depth(uv, inv_projection);
	if (behind < surface_depth) {
		uv = screen_uv;
		behind = linear_depth(screen_uv, inv_projection);
	}
	return uv;
}

// Whether the scene found at screen `uv`, `behind` metres deep, lies under a
// water surface at `level` (world y), seen from above it: that surface is a
// transparent drawn before this one, missing from the screen copy but already
// in the framebuffer. 1 there, fading over 0.3 m either side of the level.
float water_between(vec2 uv, float behind, float level, mat4 inv_projection, mat4 inv_view, vec3 camera) {
	vec4 near_point = inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 ray = near_point.xyz / near_point.w;
	float y = (inv_view * vec4(ray * (behind / max(-ray.z, 1e-5)), 1.0)).y;
	return smoothstep(level + 0.3, level - 0.3, y) * step(level, camera.y);
}

// What lies behind seen through `path` metres of water: absorbed on the way,
// plus the light the water body scatters toward the eye.
vec3 water_refracted(vec3 scene, float path, vec3 ambient) {
	vec3 transmittance = exp(-absorption * path);
	vec3 sunlight = sun_radiance_scale * atmo_transmittance_to_space(atmo_view_radius, max(sun_direction.y, 0.0)) * max(sun_direction.y, 0.0);
	vec3 body = scatter_color * (ambient + sunlight * 0.25) * 0.35;
	return scene * transmittance + mix(body, deep_color * ambient, 0.4) * (1.0 - transmittance);
}

// The reflection: the scene on screen where the reflected ray finds it, the
// physical sky elsewhere.
vec3 water_reflection(vec3 view_pos, vec3 n_view, float fresnel, mat4 inv_view, mat4 projection, mat4 inv_projection) {
	vec3 reflect_view = reflect(normalize(view_pos), n_view);
	vec3 reflect_world = normalize((inv_view * vec4(reflect_view, 0.0)).xyz);
	reflect_world.y = abs(reflect_world.y);
	vec3 reflection = atmo_sky_radiance(reflect_world);
	// Looking steeply down the water hardly reflects; skip the march.
	if (fresnel > 0.03) {
		vec4 ssr = screen_reflection(view_pos, reflect_view, projection, inv_projection);
		reflection = mix(reflection, ssr.rgb, ssr.a);
	}
	return reflection;
}

// light(): sun glints, GGX on the water's normal (times LIGHT_COLOR * ATTENUATION).
float water_glint(vec3 normal, vec3 view, vec3 light, float roughness) {
	float n_dot_l = dot(normal, light);
	if (n_dot_l <= 0.0) {
		return 0.0;
	}
	vec3 h = normalize(view + light);
	float n_dot_h = clamp(dot(normal, h), 0.0, 1.0);
	float n_dot_v = clamp(dot(normal, view), 1e-3, 1.0);
	float a = roughness * roughness;
	float a2 = a * a;
	float d = a2 / (PI * pow(n_dot_h * n_dot_h * (a2 - 1.0) + 1.0, 2.0));
	float k = a * 0.5;
	float vis = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(view, h), 0.0, 1.0), 5.0);
	return n_dot_l * d * vis * fresnel;
}

// light(): sunlight through thin water toward the viewer (times LIGHT_COLOR *
// ATTENUATION * scatter_color * lift * sss_strength * 0.25).
float water_through(vec3 normal, vec3 view, vec3 light) {
	return pow(clamp(dot(view, -light + normal * 0.4), 0.0, 1.0), 4.0);
}
