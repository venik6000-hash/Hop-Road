#[compute]
#version 450
// The fog between the eye and everything it sees, after Bauer 2019,
// "Creating the Atmospheric World of Red Dead Redemption 2": one data model
// (haze thinning with height, a fog map's bank lying on the lowland and the
// lake, rain fog under the rain clouds, the damp a wood holds under its
// crowns, a building the fog stays out of), one
// lighting model (the sun through the mountains' and the clouds' shadows, two
// phase octaves with a back-scatter floor, the sky's ambient, the moon,
// lightning), marched once per column of a view-aligned grid and kept at
// every depth, so the picture looks the result up by its own depth and no
// edge of a tree against the sky is fogged by its neighbour.
//
// Slices grow with distance, so thin layers are not sampled but integrated:
// the haze and the bank are exponentials of height and a ray's height is
// linear along it. One jittered sample per slice stands for what is not
// (the shadows, the bank's noise, the cloud above).
//
// The import does not follow the include: see fog_apply.glsl. Block of 236 floats.
#include "../sky/atmosphere_common.glslinc"
#include "fog_params.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// rgb: light scattered toward the eye up to a slice's far edge, a: what is
// left of the light from beyond it.
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image3D fog_volume;
// Sunlit drops up to there (the rainbow's light, coloured by the apply pass).
layout(r16f, set = 0, binding = 2) uniform restrict writeonly image3D bow_volume;
// For a column that looks at the lake: the fog between the surface and what it
// mirrors, as fog_volume keeps it for the last slice.
layout(rgba16f, set = 0, binding = 7) uniform restrict writeonly image2D mirror_fog;
layout(set = 0, binding = 3) uniform sampler2D shadow_field;
layout(set = 0, binding = 4) uniform sampler2D cloud_weather;
layout(set = 0, binding = 5) uniform sampler2D skyview_lut;
layout(set = 0, binding = 6) uniform sampler2D ground_height;
// How much of the sky the crowns close over the ground, a metre to a texel
// with its mips (src/vegetation/canopy_field.gd).
layout(set = 0, binding = 8) uniform sampler2D canopy_cover;

const vec3 HAZE_ALBEDO = vec3(0.9, 0.94, 1.0);
const vec3 MIST_ALBEDO = vec3(0.985);
const vec3 RAIN_ALBEDO = vec3(0.86, 0.88, 0.92);
const vec3 LIGHTNING_LIGHT = vec3(0.72, 0.8, 1.0) * 0.7;
// Anisotropy of the first phase octave; the second has half of it.
const float PHASE_G = 0.8;
// Extinction (1/m) over which the back-scatter floor comes up.
const vec2 BACK_SCATTER = vec2(0.004, 0.03);
const float SUN_SHADOW_SPREAD = 0.0093;
// The cover of a stand between which it holds no fog and all of it.
const vec2 WOOD_COVER = vec2(0.1, 0.5);
// The mips of the cover a stretch reads: no finer than a stand (CANOPY_WIDE_LEVEL
// of the surfaces' shaders), no coarser than a wood.
const vec2 WOOD_LEVELS = vec2(2.0, 6.0);
// Metres from the field's edge over which its fog fades: beyond it the woods
// are impostors and nothing says where they stand.
const float WOOD_EDGE = 80.0;

float henyey_greenstein(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 1e-4), 1.5));
}

// Two octaves of the lobe stand in for the light scattered more than once;
// a dense medium also scatters back, which the lobe alone never does.
float fog_phase(float cos_theta, float extinction) {
	float phase = 0.5 * (henyey_greenstein(cos_theta, PHASE_G) + henyey_greenstein(cos_theta, PHASE_G * 0.5));
	float back = clamp((extinction - BACK_SCATTER.x) / (BACK_SCATTER.y - BACK_SCATTER.x), 0.0, 1.0);
	return max(phase, back * 0.25 / PI);
}

// Mean of exp(-y / height) over heights ya..yb.
float mean_falloff(float ya, float yb, float height) {
	float a = ya / height;
	float b = yb / height;
	if (abs(b - a) < 1e-3) {
		return exp(-0.5 * (a + b));
	}
	return (exp(-a) - exp(-b)) / (b - a);
}

// Mean over heights ya..yb of a bank that is full below `top` and falls off
// by exp over `height` above it.
float mean_bank(float ya, float yb, float top, float height) {
	float low = min(ya, yb);
	float high = max(ya, yb);
	if (high <= top) {
		return 1.0;
	}
	if (high - low < 1e-3) {
		return exp(-max(low - top, 0.0) / height);
	}
	float above = max(low, top) - top;
	return (max(top - low, 0.0) + height * (exp(-above / height) - exp(-(high - top) / height))) / (high - low);
}

// The sky's cloud cover over a point of the map, from the weather map the
// ground shaders read their cloud shadows from (src/sky/cloud_shadow.gdshaderinc).
float cloud_cover(vec2 xz) {
	vec4 weather = textureLod(cloud_weather, (xz * 0.001 + p.drift.xy) * p.lit.w, 0.0);
	float coverage = clamp(p.cloud.x + (weather.r - 0.5) * 0.95, 0.0, 1.0);
	return smoothstep(0.35, 0.75, coverage * weather.b * 1.25);
}

// 1 in the sun .. 0 in a ridge's shadow (src/terrain/sun_shadow.gdshaderinc,
// the far field alone: a shaft through the haze needs no finer edge).
float ridge_visibility(vec3 at) {
	if (p.shadow_rect.w <= 0.0) {
		return 1.0;
	}
	vec3 field = textureLod(shadow_field, ((at.xz - p.shadow_rect.xy) / p.shadow_rect.z + 0.5) / p.shadow_rect.w, 0.0).rgb;
	float soft = p.shadow_rect.z * 0.3;
	float half_width = max(soft, field.g * SUN_SHADOW_SPREAD);
	return 1.0 - smoothstep(0.0, 2.0 * half_width, field.r - max(at.y - field.b, 0.0) - soft * 0.5);
}

// How much of its fog a wood holds round `at`, 0..1: the crowns' cover there,
// taken from the mip whose texel is as long as the stretch of `length_m`
// metres, so that the stretch's one sample stands for all of it.
float wood_cover(vec3 at, float length_m) {
	if (p.wood.x <= 0.0 || p.canopy_rect.w <= 0.0) {
		return 0.0;
	}
	vec2 uv = ((at.xz - p.canopy_rect.xy) / p.canopy_rect.z + 0.5) / p.canopy_rect.w;
	vec2 inside = min(uv, 1.0 - uv) * p.canopy_rect.w * p.canopy_rect.z;
	float edge = clamp(min(inside.x, inside.y) / WOOD_EDGE, 0.0, 1.0);
	if (edge <= 0.0) {
		return 0.0;
	}
	float level = clamp(log2(max(length_m / p.canopy_rect.z, 1.0)), WOOD_LEVELS.x, WOOD_LEVELS.y);
	return smoothstep(WOOD_COVER.x, WOOD_COVER.y, textureLod(canopy_cover, uv, level).r) * edge;
}

// The light a fog takes from the sky. Fog scatters forward, so most of what
// it sends to the eye is the sky that lies behind it along the view (far
// haze takes the colour of the sky over it, a sunset's glow stays in the
// haze under it); the rest is the sky's mean.
vec3 sky_ambient(vec3 dir) {
	vec2 lut = vec2(textureSize(skyview_lut, 0));
	float radius = p.sky_light.a;
	vec3 zenith = textureLod(skyview_lut, skyview_uv(radius, 1.0, 1.0, false, lut), 0.0).rgb;
	vec3 toward = textureLod(skyview_lut, skyview_uv(radius, 0.62, 1.0, false, lut), 0.0).rgb;
	vec3 away = textureLod(skyview_lut, skyview_uv(radius, 0.62, -1.0, false, lut), 0.0).rgb;
	vec3 mean = (zenith + toward + away) * (1.0 / 3.0);
	// Below the horizon the eye would meet haze, not the planet: hold it there.
	vec3 up_dir = normalize(vec3(dir.x, max(dir.y, 0.03), dir.z));
	float sun_side = 1.0;
	if (dot(up_dir.xz, up_dir.xz) > 1e-8 && dot(p.sun.xz, p.sun.xz) > 1e-8) {
		sun_side = dot(normalize(up_dir.xz), normalize(p.sun.xz));
	}
	vec3 behind = textureLod(skyview_lut, skyview_uv(radius, up_dir.y, sun_side, false, lut), 0.0).rgb;
	vec3 clear = mix(mean, behind, 0.65) * p.sky_light.rgb;
	// Under a closed layer the light is the clouds' grey, less of it the
	// darker their base.
	float closed = p.cloud.z;
	float grey = dot(mean * p.sky_light.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 night = vec3(0.0015, 0.0028, 0.006) * (1.0 - smoothstep(-0.12, 0.02, p.sun.y));
	return mix(clear, vec3(grey) * mix(0.9, 0.3, p.cloud.w), closed) + night;
}

// What the stretch ta..tb (m) of a ray from `from` along `dir` adds to the
// light scattered toward its start and takes from what comes from beyond.
// `noise` 0..1 places the stretch's one sample; `level` is the lake's.
void add_stretch(vec3 from, vec3 dir, float ta, float tb, float noise, float level, vec3 ambient, float sun_cos,
		float moon_cos, bool sun_up, inout vec3 scattered, inout float transmittance, inout float bow) {
	float length_m = tb - ta;
	vec3 at = from + dir * (ta + length_m * noise);
	float ya = from.y + dir.y * ta - level;
	float yb = from.y + dir.y * tb - level;
	if (p.room_min.w > 0.5 && all(greaterThan(at, p.room_min.xyz)) && all(lessThan(at, p.room_max.xyz))) {
		return;
	}
	float haze = p.haze.x * mean_falloff(max(ya, 0.0), max(yb, 0.0), p.haze.y);
	float mist = 0.0;
	float wood = wood_cover(at, length_m) * p.wood.x;
	float ground = 0.0;
	if (p.mist.x > 0.0 || wood > 0.0) {
		ground = textureLod(ground_height, ((at.xz - p.height_rect.xy) / p.height_rect.z + 0.5) / p.height_rect.w, 0.0).r - level;
	}
	if (wood > 0.0) {
		// The damp a wood keeps fills it to the crowns and thins above them.
		wood *= mean_bank(ya, yb, ground + p.wood.y, p.wood.z);
	}
	if (p.mist.x > 0.0) {
		// Thick on the water, thinner on the shore, gone up the slopes.
		float low = mix(1.0, 0.45, smoothstep(0.2, 2.5, ground)) * (1.0 - smoothstep(p.mist.w * 0.35, p.mist.w, ground));
		if (low > 0.0) {
			vec4 lie = textureLod(cloud_weather, (at.xz + p.drift.zw) / 900.0, 0.0);
			float banks = mix(0.08, 1.0, smoothstep(0.35, 0.65, lie.g));
			float top = max(ground, 0.0) + p.mist.y * (0.5 + lie.b);
			mist = p.mist.x * low * banks * mean_bank(ya, yb, top, p.mist.z);
		}
	}
	float under_cloud = 1.0 - smoothstep(p.rain.y - 350.0, p.rain.y + 150.0, at.y);
	float rain = 0.0;
	if (p.rain.x > 0.0 && under_cloud > 0.0) {
		rain = p.rain.x * mix(0.35, 1.0, cloud_cover(at.xz)) * under_cloud;
	}
	float extinction = haze + mist + rain + wood;
	float drops = p.rain.w * under_cloud;
	if (extinction + drops <= 1e-9) {
		return;
	}
	float sun_seen = 0.0;
	if (sun_up) {
		sun_seen = ridge_visibility(at);
		if (sun_seen > 0.0) {
			// The clouds of a broken sky shade the sun in patches, as on the
			// ground (src/sky/cloud_shadow.gdshaderinc); a closed layer has
			// none, and its share of the sun is in p.sun_light already.
			float broken = 1.0 - p.cloud.z;
			vec2 above = at.xz + p.sun.xz / p.sun.y * (p.moon.w - at.y);
			sun_seen *= 1.0 - cloud_cover(above) * p.sun_light.a * broken;
		}
	}
	vec3 beams = p.sun_light.rgb * sun_seen * fog_phase(sun_cos, extinction)
		+ p.moon_light.rgb * fog_phase(moon_cos, extinction);
	// The crowns stand between a wood's fog and the sun; the sky's light
	// comes down through them from all round.
	vec3 open_air = haze * HAZE_ALBEDO + mist * MIST_ALBEDO + rain * RAIN_ALBEDO;
	vec3 sent = open_air * (beams + ambient) + wood * MIST_ALBEDO * (beams * p.wood.w + ambient);
	float through = exp(-extinction * length_m);
	// Light a stretch adds is itself dimmed on the way out of it.
	float thickness = extinction > 1e-7 ? (1.0 - through) / extinction : length_m;
	scattered += transmittance * sent * thickness;
	bow += transmittance * sun_seen * drops * thickness;
	transmittance *= through;
}

void main() {
	ivec3 cells = imageSize(fog_volume);
	ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
	if (cell.x >= cells.x || cell.y >= cells.y) {
		return;
	}
	vec2 uv = (vec2(cell) + 0.5) / vec2(cells.xy);
	vec4 view_h = p.inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 eye = p.camera[3].xyz;
	vec3 dir = normalize(mat3(p.camera) * normalize(view_h.xyz / view_h.w));
	float level = p.sun.w;
	// Nothing of this is under the lake: the ray's fog ends at its surface.
	float reach = dir.y < -1e-5 ? max(eye.y - level, 0.0) / -dir.y : 1e12;
	float noise = frame_noise(vec2(cell));

	bool sun_up = p.sun.y > 0.02 && dot(p.sun_light.rgb, vec3(1.0)) > 1e-4;
	vec3 lightning = LIGHTNING_LIGHT * p.moon_light.a;
	vec3 ambient = sky_ambient(dir) + lightning;
	float sun_cos = dot(dir, p.sun.xyz);
	float moon_cos = dot(dir, p.moon.xyz);

	vec3 scattered = vec3(0.0);
	float transmittance = 1.0;
	float bow = 0.0;
	for (int k = 0; k < cells.z; k++) {
		float ta = slice_edge(k);
		float tb = min(slice_edge(k + 1), reach);
		if (tb > ta && transmittance > 0.002) {
			add_stretch(eye, dir, ta, tb, noise, level, ambient, sun_cos, moon_cos, sun_up, scattered, transmittance, bow);
		}
		imageStore(fog_volume, ivec3(cell, k), vec4(scattered, transmittance));
		imageStore(bow_volume, ivec3(cell, k), vec4(bow));
	}

	// Where the ray meets the lake, the fog its mirror image lies behind: the
	// same march from there along the mirrored ray, until the land stops it.
	vec4 mirrored = vec4(0.0, 0.0, 0.0, 1.0);
	if (reach < p.range.y && eye.y > level) {
		vec3 from = eye + dir * reach;
		vec3 up = vec3(dir.x, -dir.y, dir.z);
		ambient = sky_ambient(up) + lightning;
		sun_cos = dot(up, p.sun.xyz);
		moon_cos = dot(up, p.moon.xyz);
		scattered = vec3(0.0);
		transmittance = 1.0;
		bow = 0.0;
		for (int k = 0; k < cells.z && transmittance > 0.002; k++) {
			float ta = slice_edge(k);
			float tb = slice_edge(k + 1);
			vec3 at = from + up * (ta + (tb - ta) * noise);
			float ground = textureLod(ground_height, ((at.xz - p.height_rect.xy) / p.height_rect.z + 0.5) / p.height_rect.w, 0.0).r;
			if (at.y < ground) {
				break;
			}
			add_stretch(from, up, ta, tb, noise, level, ambient, sun_cos, moon_cos, sun_up, scattered, transmittance, bow);
		}
		mirrored = vec4(scattered, transmittance);
	}
	imageStore(mirror_fog, cell, mirrored);
}
