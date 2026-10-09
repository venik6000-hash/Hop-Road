// Shared sky lookups for sky, water and terrain shaders. Must match
// atmosphere_common.glslinc (same planet, same LUT parameterisations).

global uniform vec3 sun_direction;
// pi * top-of-atmosphere sun irradiance in Godot light units: LUT values are
// per unit irradiance, so sky radiance = LUT * sun_radiance_scale.
global uniform vec3 sun_radiance_scale;
global uniform sampler2D atmo_transmittance : filter_linear, repeat_disable;
global uniform sampler2D atmo_skyview : filter_linear, repeat_disable;
global uniform float atmo_view_radius;

const float ATMO_PI = 3.14159265358979;
const float ATMO_R_GROUND = 6360.0;
const float ATMO_R_TOP = 6460.0;

float atmo_ray_sphere(vec3 origin, vec3 dir, float radius) {
	float b = dot(origin, dir);
	float c = dot(origin, origin) - radius * radius;
	float disc = b * b - c;
	if (disc < 0.0) {
		return -1.0;
	}
	float s = sqrt(disc);
	if (-b - s >= 0.0) {
		return -b - s;
	}
	if (-b + s >= 0.0) {
		return -b + s;
	}
	return -1.0;
}

vec2 atmo_transmittance_uv(float r, float mu) {
	float h = sqrt(ATMO_R_TOP * ATMO_R_TOP - ATMO_R_GROUND * ATMO_R_GROUND);
	float rho = sqrt(max(0.0, r * r - ATMO_R_GROUND * ATMO_R_GROUND));
	float disc = r * r * (mu * mu - 1.0) + ATMO_R_TOP * ATMO_R_TOP;
	float d = max(0.0, -r * mu + sqrt(max(disc, 0.0)));
	float d_min = ATMO_R_TOP - r;
	float d_max = rho + h;
	vec2 uv = vec2((d - d_min) / (d_max - d_min), rho / h);
	return (uv * vec2(255.0, 63.0) + 0.5) / vec2(256.0, 64.0);
}

vec3 atmo_transmittance_to_space(float r, float mu) {
	return texture(atmo_transmittance, atmo_transmittance_uv(r, mu)).rgb;
}

// Sky radiance (per unit sun irradiance) seen from the viewer along `dir`.
// Directions below the horizon are held at the horizon: beyond the terrain
// the eye would meet distant haze, not the dark planet the LUT stores there.
vec3 atmo_sky_lut(vec3 dir) {
	float view_height = atmo_view_radius;
	dir = normalize(vec3(dir.x, max(dir.y, -0.015), dir.z));
	float v_horizon = sqrt(max(view_height * view_height - ATMO_R_GROUND * ATMO_R_GROUND, 0.0));
	float beta = acos(clamp(v_horizon / view_height, -1.0, 1.0));
	float zenith_horizon = ATMO_PI - beta;
	bool ground = atmo_ray_sphere(vec3(0.0, view_height, 0.0), dir, ATMO_R_GROUND) >= 0.0;
	vec2 uv;
	float view_zenith = acos(clamp(dir.y, -1.0, 1.0));
	if (!ground) {
		float coord = view_zenith / zenith_horizon;
		coord = 1.0 - sqrt(max(1.0 - coord, 0.0));
		uv.y = coord * 0.5;
	} else {
		float coord = (view_zenith - zenith_horizon) / beta;
		uv.y = sqrt(max(coord, 0.0)) * 0.5 + 0.5;
	}
	vec2 flat_dir = dir.xz;
	vec2 flat_sun = sun_direction.xz;
	float light_view_cos = 1.0;
	if (dot(flat_dir, flat_dir) > 1e-8 && dot(flat_sun, flat_sun) > 1e-8) {
		light_view_cos = dot(normalize(flat_dir), normalize(flat_sun));
	}
	uv.x = sqrt(clamp(-light_view_cos * 0.5 + 0.5, 0.0, 1.0));
	uv = (uv * vec2(191.0, 107.0) + 0.5) / vec2(192.0, 108.0);
	return texture(atmo_skyview, uv).rgb;
}

vec3 atmo_sky_radiance(vec3 dir) {
	return atmo_sky_lut(dir) * sun_radiance_scale;
}
