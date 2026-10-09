// Rain on what stands outdoors: the film of water that darkens a porous
// surface and lets it shine, the puddles on level ground, and the rings the
// drops leave in them.
//
// WeatherSystem keeps the global `weather_wet`: x how wet the open ground is
// (0..1), y how full its puddles are, z the rain falling now, w a clock in
// seconds (not TIME: a material that reads TIME is animated to the renderer,
// and a lamp redraws its shadow map for every animated caster in it).
// RainShelter draws `rain_shelter`, the height of what the rain falls on
// first over each x/z; `rain_shelter_rect` is that map's corner (x, z), its
// side (m) and 1 once it is drawn.
//
// With dry weather none of this runs: a shader asks rain_is_wet() first.

global uniform vec4 weather_wet;
global uniform sampler2D rain_shelter : filter_linear, repeat_disable;
global uniform vec4 rain_shelter_rect;

// A soaked porous surface: the share of the light it loses outright, how much
// deeper its colour gets (albedo to the power of 1 + this: water fills the
// pores and the light is absorbed on more bounces, the dark hues most), and
// the gloss of the film, as the lake's wet margin on the terrain has it.
const float WET_DARK = 0.25;
const float WET_DEPTH = 0.35;
const float WET_ROUGHNESS = 0.28;
// Standing water over the ground: darker still, and a mirror.
const float PUDDLE_ALBEDO = 0.5;
const float PUDDLE_ROUGHNESS = 0.05;

// How far below the roof over it (m) a wall starts to get the slanting rain,
// and where it gets all of it.
const vec2 EAVES_REACH = vec2(1.5, 3.5);

bool rain_is_wet() {
	return weather_wet.x > 0.002;
}

// How much of the rain reaches a surface at `world` that faces `normal`
// (world space): all of it on what looks up, half on a wall, none on what
// looks down or lies under a roof.
float rain_reach(vec3 world, vec3 normal) {
	float upward = smoothstep(0.0, 0.7, normal.y);
	float reach = smoothstep(-0.25, 0.15, normal.y) * mix(0.5, 1.0, upward);
	if (rain_shelter_rect.w > 0.5) {
		// A wall is asked a step out from its face: under the eaves it is dry.
		vec2 from_above = (world.xz + normal.xz * 0.45 - rain_shelter_rect.xy) / rain_shelter_rect.z;
		if (all(greaterThan(from_above, vec2(0.0))) && all(lessThan(from_above, vec2(1.0)))) {
			float roof = textureLod(rain_shelter, from_above, 0.0).r - world.y;
			// The drops slant: this far below its eaves a wall is wet again.
			float slanting = (1.0 - upward) * smoothstep(EAVES_REACH.x, EAVES_REACH.y, roof);
			reach *= 1.0 - smoothstep(0.25, 0.8, roof) * (1.0 - slanting);
		}
	}
	return reach;
}

// The film of water, 0..1, on a surface the rain reaches by `reach`.
float rain_film(float reach) {
	return weather_wet.x * reach;
}

// `wet` 0..1 of water on a surface: darker where it soaks in (the rougher
// and the less metallic, the more) and smoother.
void wet_surface(float wet, float metallic, inout vec3 albedo, inout float roughness) {
	float soaked = wet * smoothstep(0.15, 0.55, roughness) * (1.0 - metallic);
	albedo = pow(max(albedo, vec3(0.0)), vec3(1.0 + WET_DEPTH * soaked)) * (1.0 - WET_DARK * soaked);
	roughness = mix(roughness, WET_ROUGHNESS, wet * 0.8);
}

// Standing water, 0..1, where the ground is level (`level` 0..1) and dips
// (`hollow`, a noise 0..1); the fuller the puddles, the shallower a dip holds
// one.
float puddle_cover(float level, float hollow) {
	float brim = 1.0 - 0.4 * weather_wet.y;
	return level * smoothstep(brim, brim + 0.07, hollow) * step(0.002, weather_wet.y);
}

void puddle_surface(float cover, inout vec3 albedo, inout float roughness) {
	albedo *= mix(1.0, PUDDLE_ALBEDO, cover);
	roughness = mix(roughness, PUDDLE_ROUGHNESS, cover);
}

// What is left of the SPECULAR of a surface `wet` 0..1 whose mirror looks along
// a ray of height `mirror` (the world y of the reflected eye ray). The engine
// shows the sky in every mirror; a ray that leaves the ground low meets land,
// walls and trees instead, far darker than a cloud layer.
float wet_specular(float wet, float mirror) {
	float sky = mix(0.15, 1.0, smoothstep(0.05, 0.5, mirror));
	return mix(1.0, sqrt(sky), wet);
}

vec3 ring_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yxx) * q.zyx);
}

// The slopes (dh/dx, dh/dz) of the rings the drops leave on still water at
// `xz`: each cell of two grids takes a drop now and then, and its ring runs
// out and dies in about a second. The lake's rings are the same
// (src/render/refraction_post.glsl: rain_rings).
vec2 rain_rings(vec2 xz) {
	vec2 slope = vec2(0.0);
	float rain = weather_wet.z;
	if (rain <= 0.01) {
		return slope;
	}
	for (int layer = 0; layer < 2; layer++) {
		float size = layer == 0 ? 0.45 : 0.75;
		float period = layer == 0 ? 0.9 : 1.2;
		vec2 grid = xz / size + float(layer) * 17.3;
		vec2 cell = floor(grid);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 here = cell + vec2(float(i), float(j));
				vec3 chance = ring_hash(here);
				float turn = weather_wet.w / period + chance.z;
				float age = fract(turn);
				// A new place, and a new chance to fall at all, each turn.
				vec3 drop = ring_hash(here + floor(turn) * 7.13);
				if (drop.z > rain) {
					continue;
				}
				vec2 from = grid - (here + 0.2 + drop.xy * 0.6);
				float away = length(from) * size;
				float offset = away - age * size * 0.7;
				float fade = (1.0 - age) * (1.0 - age);
				slope += from / max(length(from), 1e-4) * sin(offset * 70.0) * exp(-offset * offset * 260.0) * fade;
			}
		}
	}
	return slope * 0.3;
}
