shader_type sky;
// Physically based sky (Hillaire 2020 LUTs, see atmosphere.gd) with a
// raymarched volumetric cloud layer after Schneider 2015 ("The real-time
// volumetric cloudscapes of Horizon Zero Dawn") and Hillaire 2016 (energy-
// conserving integration). Clouds are marched in the quarter-resolution pass
// with a per-frame jitter that TAA/FSR resolves; the radiance cubemap gets a
// cheaper march so reflections and ambient light still see the clouds.
// The weather (WeatherSystem) adds what Bauer 2019, "Creating the Atmospheric
// World of Red Dead Redemption 2", puts on top of that layer: a storm's dark
// base, lightning as lights inside the clouds, and a cirrus layer far above
// that is one texture lookup lit by the same model.
render_mode use_quarter_res_pass;

#include "res://src/sky/atmosphere.gdshaderinc"

global uniform vec4 cloud_params;   // x coverage 0..1, y density, z cumulus bias, w darkness of the base 0..1
global uniform vec2 cloud_offset;   // wind drift in km
global uniform vec3 moon_direction;
global uniform float night_factor;
global uniform vec4 weather_sky;    // x cirrus 0..1, y light a closed layer lets through its base 0..1
// Strikes shining in the clouds: xz km of world space, y km above the layer's
// base, w their light now.
global uniform vec4 lightning_a;
global uniform vec4 lightning_b;

uniform sampler3D cloud_shape : filter_linear_mipmap, repeat_enable;
uniform sampler3D cloud_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_weather : filter_linear_mipmap, repeat_enable;
// r fibres, g rippled cells, b veil (tools/pipeline/sky/cirrus_noise.py).
uniform sampler2D cloud_cirrus : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cirrus_altitude_km = 8.0;
uniform float cirrus_frequency = 0.021;
uniform float cirrus_optical = 0.85;
uniform float lightning_radiance = 90.0;
uniform float cloud_bottom_km = 1.7;
uniform float cloud_thickness_km = 3.2;
uniform float shape_frequency = 0.12;
uniform float detail_frequency = 1.6;
uniform float weather_frequency = 0.016;
uniform float extinction_per_km = 32.0;
uniform int march_steps = 64;
uniform float max_distance_km = 90.0;
uniform float sun_disk_radiance_cap = 900.0;
// Only enabled when array reflections rebuild mip2 from full radiance before
// it can be sampled. Single-texture incremental reflections need the old pass.
uniform bool skip_cubemap_quarter_pass = false;
// The clear sky as the eye sees it, deeper overhead than the light it sheds:
// its colour times this at dir.y = zenith_reach and above, untouched at the
// horizon. The radiance cubemap (ambient light, reflections, the colour of
// the haze) keeps the atmosphere's own.
uniform vec3 zenith_tint = vec3(0.48, 0.6, 0.78);
uniform float zenith_reach = 0.5;
// The hand's own copy of this sky (viewmodel_lighting.gd) stands in for the
// world round the hand, which the hand's viewport cannot see: below the low
// sky lies the land, lit by the sun, as the valley's slopes and stands hide
// the horizon. Without it the haze under the horizon lit and mirrored the
// mug from below. The level's own sky leaves it off.
uniform bool land_below = false;
uniform vec3 land_radiance = vec3(0.0);

float remap01(float value, float low, float high) {
	return clamp((value - low) / max(high - low, 1e-5), 0.0, 1.0);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float henyey_greenstein(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * ATMO_PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 1e-4), 1.5));
}

// Strong forward lobe (silver lining) plus a weak back lobe.
float cloud_phase(float cos_theta, float eccentricity) {
	return mix(henyey_greenstein(cos_theta, 0.82 * eccentricity), henyey_greenstein(cos_theta, -0.35 * eccentricity), 0.28);
}

vec4 weather_at(vec2 xz_km) {
	return textureLod(cloud_weather, (xz_km + cloud_offset) * weather_frequency, 0.0);
}

// Density 0..1 at a world position (km); h = height fraction in the layer.
float cloud_density(vec3 world_km, float h, vec4 weather, bool detail) {
	// Zero coverage multiplies the old remapped density by exactly zero.
	// Check it before sampling the 3D noise; all samples here use explicit LOD.
	float coverage = clamp(cloud_params.x + (weather.r - 0.5) * 0.95, 0.0, 1.0);
	if (coverage == 0.0) {
		return 0.0;
	}
	float cumulus = clamp(weather.g * 0.85 + cloud_params.z, 0.0, 1.0);
	float top = mix(0.32, 1.0, cumulus);
	float envelope = smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(top * 0.5, top, h));
	if (envelope <= 0.0) {
		return 0.0;
	}
	vec3 drift = vec3(cloud_offset.x, 0.0, cloud_offset.y);
	// Wind shears the tops ahead of the bases.
	vec3 sheared = world_km + drift + vec3(cloud_offset.x, 0.0, cloud_offset.y) * h * 0.08;
	vec4 shape = textureLod(cloud_shape, sheared * shape_frequency, 0.0);
	float low = shape.g * 0.625 + shape.b * 0.25 + shape.a * 0.125;
	float base = remap01(shape.r, low - 1.0, 1.0) * envelope;
	base = remap01(base, 1.0 - coverage, 1.0) * coverage;
	if (base <= 0.0 || !detail) {
		return base * weather.b;
	}
	vec3 fine = textureLod(cloud_detail, sheared * detail_frequency, 0.0).rgb;
	float high = fine.r * 0.625 + fine.g * 0.25 + fine.b * 0.125;
	// Wispy erosion at the base, billows toward the top.
	float erosion = mix(high, 1.0 - high, clamp(h * 4.0, 0.0, 1.0));
	return remap01(base, erosion * 0.32, 1.0) * weather.b;
}

// A strike's light at a cloud sample: it falls off with distance, scatters
// forward, and the cloud around the sample stands in for the shadowing on
// the way (no march toward a strike).
vec3 lightning_at(vec3 world_km, vec3 dir, float density) {
	float light = 0.0;
	for (int i = 0; i < 2; i++) {
		vec4 strike = i == 0 ? lightning_a : lightning_b;
		if (strike.w > 0.0) {
			vec3 from_strike = world_km - strike.xyz;
			float away = length(from_strike);
			float fall = exp(-away * 1.6) / (0.05 + away * away);
			float forward = henyey_greenstein(dot(from_strike / max(away, 1e-3), -dir), 0.35);
			light += strike.w * fall * forward * exp(-density * away * 3.0);
		}
	}
	return vec3(0.72, 0.8, 1.0) * light * lightning_radiance;
}

// What the moonlit air gives a cloud by night, a little over the glow of
// the sky behind it (night_sky): without it clouds are black holes in it.
const vec3 NIGHT_CLOUD = vec3(0.012, 0.016, 0.026);

vec3 sky_ambient() {
	vec3 across = normalize(vec3(sun_direction.x, 0.0, sun_direction.z) + vec3(1e-4, 0.0, 0.0));
	vec3 zenith = atmo_sky_radiance(vec3(0.0, 1.0, 0.0));
	vec3 toward = atmo_sky_radiance(normalize(across + vec3(0.0, 0.8, 0.0)));
	vec3 away = atmo_sky_radiance(normalize(-across + vec3(0.0, 0.8, 0.0)));
	return (zenith + toward + away) * (1.0 / 3.0);
}

// Returns premultiplied cloud radiance (rgb) and opacity (a).
vec4 march_clouds(vec3 camera, vec3 dir, int steps, int light_steps, bool detail, float jitter) {
	float ground_r = atmo_view_radius - camera.y * 0.001;
	float inner = ground_r + cloud_bottom_km;
	float outer = inner + cloud_thickness_km;
	vec3 origin = vec3(0.0, atmo_view_radius, 0.0);
	float t_start = atmo_ray_sphere(origin, dir, inner);
	float t_end = atmo_ray_sphere(origin, dir, outer);
	if (t_start < 0.0 || t_end < 0.0) {
		return vec4(0.0);
	}
	float t_ground = atmo_ray_sphere(origin, dir, ground_r);
	if (t_ground > 0.0 && t_ground < t_start) {
		return vec4(0.0);
	}
	if (t_start > max_distance_km) {
		return vec4(0.0);
	}
	t_end = min(t_end, t_start + 40.0);
	// Longer grazing paths get more steps, capped.
	int count = int(float(steps) * mix(1.0, 1.6, clamp(1.0 - dir.y * 3.0, 0.0, 1.0)));
	float dt = (t_end - t_start) / float(count);
	float cos_theta = dot(dir, sun_direction);
	// The phase of each scattering octave depends on the ray alone, not on the
	// step: work it out once (eccentricity 1, 0.55, 0.55^2, 0.55^3).
	float octave_phase[4];
	float octave_c = 1.0;
	for (int o = 0; o < 4; o++) {
		octave_phase[o] = cloud_phase(cos_theta, octave_c);
		octave_c *= 0.55;
	}
	vec3 ambient = sky_ambient() + NIGHT_CLOUD * night_factor;
	float darkness = cloud_params.w;
	bool struck = lightning_a.w + lightning_b.w > 0.0;
	vec2 camera_xz = camera.xz * 0.001;
	vec3 radiance = vec3(0.0);
	float transmittance = 1.0;
	float depth_sum = 0.0;
	float depth_weight = 0.0;
	float t = t_start + dt * jitter;
	for (int i = 0; i < count; i++) {
		if (transmittance < 0.01) {
			break;
		}
		vec3 p = origin + dir * t;
		float r = length(p);
		float h = (r - inner) / cloud_thickness_km;
		vec3 world_km = vec3(camera_xz.x + p.x, r - inner, camera_xz.y + p.z);
		vec4 weather = weather_at(world_km.xz);
		float density = cloud_density(world_km, h, weather, detail);
		if (density > 0.001) {
			vec3 up = p / r;
			// Optical depth toward the sun, cone steps growing geometrically.
			float optical = 0.0;
			float step_len = 0.07;
			vec3 q = p;
			for (int j = 0; j < light_steps; j++) {
				q += sun_direction * step_len;
				float rq = length(q);
				float hq = (rq - inner) / cloud_thickness_km;
				if (hq > 1.0 || hq < 0.0) {
					break;
				}
				vec3 wq = vec3(camera_xz.x + q.x, rq - inner, camera_xz.y + q.z);
				optical += cloud_density(wq, hq, weather_at(wq.xz), detail && j < 2) * step_len;
				step_len *= 1.7;
			}
			optical *= extinction_per_km * cloud_params.y;
			// The LUT has no planet in it: a sun under this point's horizon
			// must be blocked explicitly or it shines through the Earth.
			float planet = atmo_ray_sphere(p, sun_direction, ATMO_R_GROUND);
			vec3 sun_at_point = planet >= 0.0 ? vec3(0.0)
					: sun_radiance_scale * atmo_transmittance_to_space(r, dot(up, sun_direction));
			// Multiple scattering as attenuated octaves (Wrenninge 2015).
			float scatter = 0.0;
			float a = 1.0;
			float b = 1.0;
			for (int o = 0; o < 4; o++) {
				scatter += a * octave_phase[o] * exp(-optical * b);
				a *= 0.52;
				b *= 0.42;
			}
			// A closed layer is lit from within: what a thick slab passes on
			// after many scatterings falls off with its depth, not by exp
			// (two-stream). It is what makes an overcast sky pale, not black.
			scatter += weather_sky.y * 0.36 / (1.0 + 0.11 * optical);
			// Dark edges where the sun-facing side has not built up scattering yet.
			float powder = mix(1.0 - exp(-density * 6.0), 1.0, 0.5 + 0.5 * cos_theta);
			// Under a closed, dark layer the base sees little of the sky above.
			vec3 source = sun_at_point * scatter * powder * mix(1.0, 0.7, darkness)
				+ ambient * mix(0.45, 1.0, h) * mix(1.0, 0.3, darkness * (1.0 - h * 0.7));
			if (struck) {
				source += lightning_at(world_km, dir, density);
			}
			float sigma = density * extinction_per_km * cloud_params.y;
			float step_t = exp(-sigma * dt);
			radiance += transmittance * source * (1.0 - step_t);
			float absorbed = transmittance * (1.0 - step_t);
			depth_sum += t * absorbed;
			depth_weight += absorbed;
			transmittance *= step_t;
		}
		t += dt;
	}
	float alpha = 1.0 - transmittance;
	if (depth_weight > 0.0) {
		// Aerial perspective between the eye and the cloud.
		float depth = depth_sum / depth_weight;
		float haze = 1.0 - exp(-depth / 45.0);
		radiance = mix(radiance, atmo_sky_radiance(dir) * alpha, haze);
		alpha *= 1.0 - smoothstep(max_distance_km * 0.55, max_distance_km, depth);
		radiance *= 1.0 - smoothstep(max_distance_km * 0.55, max_distance_km, depth);
	}
	return vec4(radiance, alpha);
}

// The high ice cloud: one lookup where the view ray meets its altitude, lit
// by the sun through the air above it. Returns premultiplied radiance and
// opacity, to go between the sky and the cloud layer.
vec4 cirrus_layer(vec3 camera, vec3 dir) {
	float amount = weather_sky.x;
	if (amount <= 0.0 || dir.y < 0.005) {
		return vec4(0.0);
	}
	float shell = atmo_view_radius - camera.y * 0.001 + cirrus_altitude_km;
	vec3 origin = vec3(0.0, atmo_view_radius, 0.0);
	float t = atmo_ray_sphere(origin, dir, shell);
	if (t < 0.0) {
		return vec4(0.0);
	}
	vec3 p = origin + dir * t;
	vec3 up = p / shell;
	vec2 xz = camera.xz * 0.001 + p.xz + cloud_offset * 2.2;
	vec3 kinds = texture(cloud_cirrus, xz * cirrus_frequency).rgb;
	vec4 region = texture(cloud_weather, xz * 0.006 + vec2(0.37, 0.11));
	// Fibres over most of the sky, a mackerel field here and there, a veil
	// once the sky fills.
	float fibres = kinds.r * mix(0.55, 1.5, region.g) + kinds.b * 0.35 * smoothstep(0.6, 1.0, amount);
	float ripples = kinds.g * smoothstep(0.45, 0.75, region.r) * 1.2;
	float density = smoothstep(1.0 - amount, 1.6 - amount * 0.7, max(fibres, ripples)) * amount;
	float tau = density * cirrus_optical / max(dot(dir, up), 0.12);
	float alpha = 1.0 - exp(-tau);
	if (alpha <= 0.001) {
		return vec4(0.0);
	}
	vec3 sun_there = atmo_ray_sphere(p, sun_direction, ATMO_R_GROUND) >= 0.0 ? vec3(0.0)
			: sun_radiance_scale * atmo_transmittance_to_space(shell, dot(up, sun_direction));
	float cos_theta = dot(dir, sun_direction);
	// Ice scatters hard forward: bright near the sun, pale away from it.
	float phase = mix(henyey_greenstein(cos_theta, 0.7), henyey_greenstein(cos_theta, -0.15), 0.3);
	vec3 radiance = sun_there * phase * alpha * 2.2
		+ (atmo_sky_radiance(vec3(0.0, 1.0, 0.0)) * 0.6 + NIGHT_CLOUD * night_factor) * alpha;
	// The air below it, and no edge where the layer meets the horizon.
	float haze = 1.0 - exp(-t / 70.0);
	radiance = mix(radiance, atmo_sky_radiance(dir) * alpha, haze);
	float fade = 1.0 - smoothstep(180.0, 310.0, t);
	return vec4(radiance, alpha) * fade;
}

vec3 night_sky(vec3 dir) {
	vec3 result = vec3(0.008, 0.014, 0.03) * night_factor;
	vec3 p = dir * 420.0;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h > 0.9965) {
		vec3 center = cell + 0.5 + (vec3(hash13(cell + 7.1), hash13(cell + 3.3), hash13(cell + 5.9)) - 0.5) * 0.6;
		float d = length(p - center);
		float twinkle = 0.7 + 0.3 * sin(TIME * (2.0 + h * 6.0) + h * 40.0);
		result += vec3(0.8, 0.85, 1.0) * smoothstep(0.32, 0.0, d) * (h - 0.9965) * 900.0 * twinkle * night_factor;
	}
	float moon_cos = dot(dir, moon_direction);
	if (moon_cos > 0.99996) {
		result += vec3(0.9, 0.92, 1.0) * 2.5 * night_factor;
	}
	result += vec3(0.02, 0.025, 0.035) * pow(max(moon_cos, 0.0), 300.0) * night_factor;
	return result * max(atmo_transmittance_to_space(atmo_view_radius, max(dir.y, 0.02)), vec3(0.0));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	if (AT_CUBEMAP_PASS && AT_QUARTER_RES_PASS && skip_cubemap_quarter_pass) {
		// Full cubemap rendering below computes its own clouds and does not
		// consume QUARTER_RES_COLOR. The visible quarter-res pass is unchanged.
		COLOR = vec3(0.0);
		ALPHA = 0.0;
	} else if (AT_QUARTER_RES_PASS) {
		float jitter = fract(hash13(vec3(FRAGCOORD.xy, 1.0)) + fract(TIME * 7.123) * 0.61803);
		vec4 clouds = march_clouds(POSITION, dir, march_steps, 6, true, jitter);
		COLOR = clouds.rgb;
		ALPHA = clouds.a;
	} else if (AT_CUBEMAP_PASS) {
		vec3 sky_color = atmo_sky_radiance(dir) + night_sky(dir);
		vec4 high = cirrus_layer(POSITION, dir);
		sky_color = sky_color * (1.0 - high.a) + high.rgb;
		vec4 clouds = march_clouds(POSITION, dir, 14, 2, false, 0.5);
		COLOR = sky_color * (1.0 - clouds.a) + clouds.rgb;
		if (land_below) {
			COLOR = mix(land_radiance, COLOR, smoothstep(-0.05, 0.2, dir.y));
		}
	} else {
		vec3 sky_color = atmo_sky_radiance(dir) * mix(vec3(1.0), zenith_tint, smoothstep(0.0, zenith_reach, dir.y))
			+ night_sky(dir);
		float cos_sun = dot(dir, sun_direction);
		const float SUN_RADIUS = 0.00475;
		bool sun_up = atmo_ray_sphere(vec3(0.0, atmo_view_radius, 0.0), sun_direction, ATMO_R_GROUND) < 0.0;
		if (sun_up && cos_sun > cos(SUN_RADIUS)) {
			float centre = acos(clamp(cos_sun, -1.0, 1.0)) / SUN_RADIUS;
			float limb = 1.0 - 0.6 * (1.0 - sqrt(max(0.0, 1.0 - centre * centre)));
			vec3 through = atmo_transmittance_to_space(atmo_view_radius, dir.y);
			vec3 disk = sun_radiance_scale * through * limb / (ATMO_PI * SUN_RADIUS * SUN_RADIUS);
			sky_color += min(disk, vec3(sun_disk_radiance_cap));
		}
		vec4 high = cirrus_layer(POSITION, dir);
		sky_color = sky_color * (1.0 - high.a) + high.rgb;
		vec4 clouds = QUARTER_RES_COLOR;
		COLOR = sky_color * (1.0 - clouds.a) + clouds.rgb;
	}
}
