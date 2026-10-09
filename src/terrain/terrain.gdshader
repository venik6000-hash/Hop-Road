shader_type spatial;
// Terrain: CDLOD vertex morphing over two heightfields, 14 scanned material
// layers blended by height, triplanar rock, heightfield self-shadowing and
// cloud shadows in the light function. See terrain_system.gd.
render_mode cull_back, depth_draw_opaque;

#include "res://src/sky/atmosphere.gdshaderinc"
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/water/underwater_light.gdshaderinc"
#include "res://src/terrain/terrain_fields.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"
uniform sampler2DArray layer_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_rah : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 terrain_camera;
uniform float layer_tile[14];
// Per-layer grade: rgb tint, a saturation. Scans come from different places
// and lights; this pulls them into one alpine palette.
uniform vec4 layer_grade[14];
uniform float normal_strength = 1.0;
// Ground under the grass near the camera (grass_field.gd): what is seen of it
// between the plants is their shaded feet, so its albedo takes this factor,
// darker and greener; and the distances over which that gives way to the
// unshaded ground that stands in for the meadow's lit top farther out.
uniform vec3 grass_shade = vec3(0.3, 0.48, 0.18);
uniform vec2 grass_shade_range = vec2(20.0, 55.0);

const float L_GRASS = 0.0;
const float L_SPARSE = 1.0;
const float L_FOREST = 2.0;
const float L_TRAIL = 3.0;
const float L_SCREE = 4.0;
const float L_ROCK = 5.0;
const float L_ROCK_DARK = 6.0;
const float L_MOUNTAIN = 7.0;
const float L_PEBBLES = 8.0;
const float L_SHORE_ROCKS = 9.0;
const float L_SAND = 10.0;
const float L_LAKEBED = 11.0;
const float L_SNOW = 12.0;
const float L_MOSS = 13.0;

varying vec3 world_pos;
// How much of the sun gets through the clouds and past the mountains.
varying float cloud_shadow;
// Sunlight on the lake bed relative to the sky light there: the longer
// refracted path through the water and the caustics.
varying vec3 sun_under_water;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec4 info = INSTANCE_CUSTOM;   // morph start, morph end, quads per side, level
	vec2 grid = VERTEX.xz * info.z;
	vec2 xz = origin.xz + VERTEX.xz * size;
	float h = height_at(xz);
	float dist = distance(terrain_camera, vec3(xz.x, h, xz.y));
	float morph = clamp((dist - info.x) / max(info.y - info.x, 1e-3), 0.0, 1.0);
	vec2 odd = fract(grid * 0.5) * 2.0;
	vec2 local = (grid - odd * morph) / info.z;
	xz = origin.xz + local * size;
	h = height_at(xz);
	VERTEX = vec3(local.x, h, local.y);
	NORMAL = vec3(0.0, 1.0, 0.0);
	world_pos = vec3(xz.x, h, xz.y);
}

vec3 grade(vec3 c, float layer) {
	vec4 g = layer_grade[int(layer)];
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(luma), c, g.w) * g.rgb, vec3(0.0));
}

struct Layer {
	vec3 albedo;
	vec3 normal;   // world space
	float rough;
	float ao;
	float height;
};

vec3 tangent_normal(float layer, vec2 uv) {
	vec3 n = texture(layer_normal, vec3(uv, layer)).rgb * 2.0 - 1.0;
	// OpenGL maps: green points up the image, i.e. toward -v.
	n.y = -n.y;
	n.xy *= normal_strength;
	n.z = sqrt(max(1.0 - dot(n.xy, n.xy), 0.0));
	return n;
}

// Whiteout blend of a top-down projected tangent normal onto the geometric normal.
vec3 top_normal(vec3 n_ts, vec3 geo) {
	vec3 t = vec3(n_ts.xy + geo.xz, abs(n_ts.z) * geo.y);
	return normalize(vec3(t.x, t.z, t.y));
}

Layer planar_turned(float layer, vec2 xz, vec3 geo, float scale, mat2 turn, vec2 shift) {
	vec2 uv = (turn * xz) / (layer_tile[int(layer)] * scale) + shift;
	Layer l;
	l.albedo = grade(texture(layer_albedo, vec3(uv, layer)).rgb, layer);
	vec3 rah = texture(layer_rah, vec3(uv, layer)).rgb;
	l.rough = rah.r;
	l.ao = rah.g;
	l.height = rah.b;
	vec3 n = tangent_normal(layer, uv);
	// Tangent space follows the turned uv; turn it back to world x/z.
	mat2 rotation = mat2(normalize(turn[0]), normalize(turn[1]));
	n.xy = transpose(rotation) * n.xy;
	l.normal = top_normal(n, geo);
	return l;
}

Layer planar(float layer, vec2 xz, vec3 geo, float scale) {
	return planar_turned(layer, xz, geo, scale, mat2(1.0), vec2(0.0));
}

// Two turned samples stirred by low-frequency noise hide the repeat.
Layer planar_untiled(float layer, vec2 xz, vec3 geo, float scale, float stir) {
	Layer a = planar(layer, xz, geo, scale);
	if (stir < 0.35) {
		return a;
	}
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * 1.37;
	Layer b = planar_turned(layer, xz, geo, scale, turn, vec2(0.173, 0.051));
	float t = smoothstep(0.35, 0.65, stir);
	a.albedo = mix(a.albedo, b.albedo, t);
	a.normal = normalize(mix(a.normal, b.normal, t));
	a.rough = mix(a.rough, b.rough, t);
	a.ao = mix(a.ao, b.ao, t);
	a.height = mix(a.height, b.height, t);
	return a;
}

Layer triplanar(float layer, vec3 p, vec3 geo, float scale) {
	vec3 w = pow(abs(geo), vec3(5.0));
	w /= w.x + w.y + w.z;
	float tile = layer_tile[int(layer)] * scale;
	Layer l;
	l.albedo = vec3(0.0);
	l.rough = 0.0;
	l.ao = 0.0;
	l.height = 0.0;
	vec3 n = vec3(0.0);
	if (w.x > 0.02) {
		vec2 uv = p.zy / tile;
		vec3 t = tangent_normal(layer, uv);
		t = vec3(t.xy + geo.zy, abs(t.z) * geo.x);
		n += t.zyx * w.x;
		vec3 rah = texture(layer_rah, vec3(uv, layer)).rgb;
		l.albedo += texture(layer_albedo, vec3(uv, layer)).rgb * w.x;
		l.rough += rah.r * w.x;
		l.ao += rah.g * w.x;
		l.height += rah.b * w.x;
	}
	if (w.y > 0.02) {
		vec2 uv = p.xz / tile;
		vec3 t = tangent_normal(layer, uv);
		t = vec3(t.xy + geo.xz, abs(t.z) * geo.y);
		n += t.xzy * w.y;
		vec3 rah = texture(layer_rah, vec3(uv, layer)).rgb;
		l.albedo += texture(layer_albedo, vec3(uv, layer)).rgb * w.y;
		l.rough += rah.r * w.y;
		l.ao += rah.g * w.y;
		l.height += rah.b * w.y;
	}
	if (w.z > 0.02) {
		vec2 uv = p.xy / tile;
		vec3 t = tangent_normal(layer, uv);
		t = vec3(t.xy + geo.xy, abs(t.z) * geo.z);
		n += t.xyz * w.z;
		vec3 rah = texture(layer_rah, vec3(uv, layer)).rgb;
		l.albedo += texture(layer_albedo, vec3(uv, layer)).rgb * w.z;
		l.rough += rah.r * w.z;
		l.ao += rah.g * w.z;
		l.height += rah.b * w.z;
	}
	float total = max(w.x * step(0.02, w.x) + w.y * step(0.02, w.y) + w.z * step(0.02, w.z), 1e-3);
	l.albedo = grade(l.albedo / total, layer);
	l.rough /= total;
	l.ao /= total;
	l.height /= total;
	l.normal = normalize(n);
	return l;
}

// Height-aware blend (weight t of b over a): stones poke through grass first.
Layer blend(Layer a, Layer b, float t) {
	if (t <= 0.001) {
		return a;
	}
	if (t >= 0.999) {
		return b;
	}
	float depth = 0.22;
	float ha = a.height + (1.0 - t);
	float hb = b.height + t;
	float top = max(ha, hb) - depth;
	float wa = max(ha - top, 0.0);
	float wb = max(hb - top, 0.0);
	float k = wb / max(wa + wb, 1e-4);
	a.albedo = mix(a.albedo, b.albedo, k);
	a.normal = normalize(mix(a.normal, b.normal, k));
	a.rough = mix(a.rough, b.rough, k);
	a.ao = mix(a.ao, b.ao, k);
	a.height = mix(a.height, b.height, k);
	return a;
}

// The whole layer stack at one texture scale.
Layer surface(vec3 p, vec3 geo, float scale, vec4 control, vec4 extra, vec4 far, vec4 macro, float stir,
		float wn, float dist) {
	vec2 xz = p.xz;
	float slope = 1.0 - geo.y;
	float above = p.y - water_level;
	// Ground: meadow grass, drier grass up high, forest floor, trodden earth.
	float alpine = smoothstep(600.0, 1100.0, p.y + (macro.g - 0.5) * 300.0);
	float dry = clamp(smoothstep(0.5, 0.82, macro.r) * 0.45 + alpine, 0.0, 1.0);
	Layer ground = planar_untiled(L_GRASS, xz, geo, scale, stir);
	if (dry > 0.02) {
		ground = blend(ground, planar_untiled(L_SPARSE, xz, geo, scale, stir), dry);
	}
	float forest = max(control.b, far.b * (1.0 - wn));
	if (forest > 0.02) {
		ground = blend(ground, planar_untiled(L_FOREST, xz, geo, scale, stir), forest);
	}
	// Far meadows read as the aerial scan: grass with rock breaking through.
	float far_meadow = smoothstep(220.0, 900.0, dist) * (1.0 - forest * 0.7);
	if (far_meadow > 0.02) {
		ground = blend(ground, planar(L_MOUNTAIN, xz, geo, 1.0), far_meadow);
	}
	float trail = clamp(control.r * 1.2, 0.0, 1.0);
	if (trail > 0.02) {
		ground = blend(ground, planar(L_TRAIL, xz, geo, scale), trail);
	}
	// Shore and lake floor.
	float beach = control.g;
	float under = smoothstep(0.35, -0.9, above);
	if (beach > 0.02 || under > 0.02) {
		Layer shore = planar(L_PEBBLES, xz, geo, scale);
		// Sand is the lake's; the stream bed on the shelf high above it is stones.
		float sand = smoothstep(0.4, 0.6, macro.a) * smoothstep(-0.2, 1.2, above) * (1.0 - smoothstep(6.0, 10.0, above));
		if (sand > 0.02) {
			shore = blend(shore, planar(L_SAND, xz, geo, scale), sand * 0.8);
		}
		float stones = smoothstep(0.55, 0.75, stir);
		if (stones > 0.02) {
			shore = blend(shore, planar(L_SHORE_ROCKS, xz, geo, scale), stones);
		}
		float deep = smoothstep(-0.8, -4.0, above);
		if (deep > 0.02) {
			shore = blend(shore, planar(L_LAKEBED, xz, geo, scale), deep);
		}
		ground = blend(ground, shore, max(beach, under));
	}
	// Scree where slopes steepen and below cliffs; bare rock on the steep.
	float scree = clamp(smoothstep(0.18, 0.38, slope) * 0.8 + far.a * 0.6 * (1.0 - wn) + far.g * 0.4, 0.0, 1.0);
	scree *= 1.0 - under;
	if (scree > 0.02) {
		ground = blend(ground, planar(L_SCREE, xz, geo, scale), scree);
	}
	float rock = clamp(smoothstep(0.34, 0.55, slope) + extra.r * 0.9 + far.g * smoothstep(0.2, 0.4, slope) * (1.0 - wn), 0.0, 1.0);
	if (rock > 0.02) {
		Layer stone = triplanar(L_ROCK, p, geo, scale);
		float dark = smoothstep(0.42, 0.62, macro.b);
		if (dark > 0.02) {
			stone = blend(stone, triplanar(L_ROCK_DARK, p, geo, scale), dark);
		}
		float mountain = smoothstep(350.0, 1400.0, dist);
		if (mountain > 0.02) {
			stone = blend(stone, triplanar(L_ROCK, p, geo, 9.0), mountain);
		}
		float mossy = smoothstep(0.4, 0.8, forest + extra.g * 0.5) * (1.0 - alpine);
		if (mossy > 0.02) {
			stone = blend(stone, planar(L_MOSS, xz, geo, scale), mossy * 0.7);
		}
		ground = blend(ground, stone, rock);
	}
	// Snow settles on the gentler high slopes.
	float snow = far.r * (1.0 - smoothstep(0.72, 0.92, slope));
	if (snow > 0.02) {
		ground = blend(ground, planar(L_SNOW, xz, geo, scale), snow);
	}
	return ground;
}

Layer mix_layers(Layer a, Layer b, float t) {
	a.albedo = mix(a.albedo, b.albedo, t);
	a.normal = normalize(mix(a.normal, b.normal, t));
	a.rough = mix(a.rough, b.rough, t);
	a.ao = mix(a.ao, b.ao, t);
	a.height = mix(a.height, b.height, t);
	return a;
}

#include "res://src/lakeside/shore_common.gdshaderinc"

void fragment() {
	// Private underwater capture camera; discard above-water fragments only there.
	if (CAMERA_VISIBLE_LAYERS == 262144u && world_pos.y > water_level + 0.4) { discard; }
	vec3 p = world_pos;
	vec2 xz = p.xz;
	float dist = length(p - CAMERA_POSITION_WORLD);
	float wn = near_weight(xz);
	float fine_step = mix(far_rect.z * 1.5, near_rect.z, wn);
	vec3 geo = height_normal(xz, max(fine_step, dist * 0.004));

	vec4 control = vec4(0.0);
	vec4 extra = vec4(0.0, 0.0, 1.0, 1.0);
	if (wn > 0.0) {
		control = texture(near_control, mask_uv(xz)) * wn;
		extra = mix(extra, texture(near_extra, mask_uv(xz)), wn);
	}
	vec4 far = texture(far_masks, far_uv(xz));
	vec4 macro = texture(macro_noise, xz / 430.0);
	float stir = texture(macro_noise, xz / 61.0 + 0.37).r;

	// Texture repeat grows with distance in discrete steps, cross-faded, so
	// nothing slides while walking and far slopes do not show a grid.
	float mid = smoothstep(40.0, 110.0, dist);
	float remote = smoothstep(260.0, 650.0, dist);
	Layer ground;
	if (mid < 0.999) {
		ground = surface(p, geo, 1.0, control, extra, far, macro, stir, wn, dist);
		if (mid > 0.001) {
			ground = mix_layers(ground, surface(p, geo, 3.3, control, extra, far, macro, stir, wn, dist), mid);
		}
	} else {
		ground = surface(p, geo, 3.3, control, extra, far, macro, stir, wn, dist);
		if (remote > 0.001) {
			ground = mix_layers(ground, surface(p, geo, 11.0, control, extra, far, macro, stir, wn, dist), remote);
		}
	}

	float above = p.y - water_level;
	// Wet margin: darker and glossier just above the waterline.
	float wet = clamp(extra.g * smoothstep(0.35, 1.3, above) + smoothstep(0.04, -0.08, above), 0.0, 1.0);
	vec4 shore_memory = lake_shore_at(world_pos.xz);
	wet = max(wet, shore_memory.g * (1.0 - smoothstep(0.3, 0.7, above)));
	float grass = grass_cover(control, extra, far, 1.0 - geo.y, above) * smoothstep(0.0, 0.6, wn);
	// Rain: the same wet look on the open ground, less where blades cover it
	// (they stay as they are), and puddles where the ground is level and dips.
	// Turf and the forest's floor take the water in: darker, but no film to
	// shine and no standing water.
	float puddle = 0.0;
	float rained = 0.0;
	float turf = 0.0;
	if (rain_is_wet() && above > 0.0) {
		float reach = rain_reach(p, geo) * smoothstep(0.0, 0.12, above);
		turf = 1.0 - smoothstep(0.25, 0.7, bare_ground(control, extra, far, 1.0 - geo.y));
		// Not twice where the lake has wetted the ground already.
		rained = rain_film(reach * (1.0 - 0.7 * grass)) * (1.0 - wet);
		if (dist < 70.0) {
			float hollow = texture(macro_noise, xz / 11.0).b * 0.55 + texture(macro_noise, xz / 2.9).g * 0.45;
			puddle = puddle_cover(smoothstep(0.988, 0.998, geo.y), hollow) * reach * (1.0 - turf)
				* (1.0 - smoothstep(45.0, 70.0, dist));
		}
	}
	vec3 albedo = ground.albedo;
	albedo *= mix(1.0, 0.62, wet);
	// Thin ground holds its grass in patches (the gate of grass_tile_job.gd's
	// _survey): only under a patch is the ground the plants' shaded feet.
	float patchy = clamp(0.5 + (texture(macro_noise, xz / 19.0 + 0.47).g - 0.5) * 1.8, 0.0, 1.0);
	float stand = clamp((grass * 1.2 - patchy) * 5.0, 0.0, 1.0);
	albedo *= mix(vec3(1.0), grass_shade, stand * (1.0 - smoothstep(grass_shade_range.x, grass_shade_range.y, dist)));
	float rough = mix(ground.rough, 0.28, wet * 0.8);
	if (rained > 0.0) {
		float dry_rough = rough;
		wet_surface(rained, 0.0, albedo, rough);
		rough = mix(rough, dry_rough, turf * 0.85);
	}
	if (puddle > 0.0) {
		puddle_surface(puddle, albedo, rough);
		vec2 rings = dist < 24.0 ? rain_rings(xz) * (1.0 - smoothstep(14.0, 24.0, dist)) : vec2(0.0);
		ground.normal = normalize(mix(ground.normal, normalize(vec3(-rings.x, 1.0, -rings.y)), puddle));
	}
	// Large-scale variation in tone so the valley does not read as one texture.
	albedo *= 0.86 + 0.28 * macro.r;
	albedo = mix(albedo, albedo * vec3(1.06, 1.0, 0.86), macro.g * 0.35);

	sun_under_water = vec3(1.0);
	float depth = water_level - p.y;
	if (depth > 0.0) {
		// Below the wave-washed shallows the bed of a mountain lake is marl:
		// pale fine silt that settles over the cobbles, flattens them and
		// dulls them, thicker on the flats than on the slopes.
		float silt = smoothstep(1.5, 6.0, depth) * (0.6 + 0.4 * macro.g) * (1.0 - 0.7 * smoothstep(0.25, 0.6, 1.0 - geo.y));
		float grain = textureLod(macro_noise, xz / 9.0, 0.0).g;
		albedo = mix(albedo, vec3(0.36, 0.35, 0.30) * (0.8 + 0.3 * macro.r + 0.15 * grain), silt * 0.92);
		rough = mix(rough, 0.94, silt);
		ground.normal = normalize(mix(ground.normal, geo, silt * 0.9));
		// The waves, and with them the caustics, vary slowly over the lake.
		float gust = 0.72 + 0.56 * textureLod(macro_noise, xz / 1700.0, 0.0).r;
		albedo *= underwater_light(xz, depth, dist, gust, sun_under_water);
	}
	float residue = shore_memory.b * smoothstep(-0.03, 0.04, above) * (1.0 - smoothstep(0.25, 0.5, above));
	albedo = mix(albedo, vec3(0.76, 0.79, 0.76), clamp(residue * 0.7, 0.0, 0.45));
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.4 * wet_specular(max(rained * (1.0 - turf), puddle), reflect(normalize(p - CAMERA_POSITION_WORLD), ground.normal).y);
	AO = ground.ao * mix(1.0, extra.a, 0.85);
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(ground.normal, 0.0)).xyz);
	cloud_shadow = cloud_cover_visibility(p) * ground_sun_visibility(xz);
}

void light() {
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Both terms carry n_dot_l and ATTENUATION as factors: a back-facing or
	// fully shadowed light adds exactly nothing.
	if (n_dot_l > 0.0 && ATTENUATION > 0.0) {
		float shade = ATTENUATION;
		// The mountains' and the clouds' shadows belong to the sun alone, not to lamps or the moon.
		vec3 tint = vec3(1.0);
		if (LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999) {
			shade *= cloud_shadow;
			tint = sun_under_water;
		}
		DIFFUSE_LIGHT += LIGHT_COLOR * tint * shade * n_dot_l / PI;
		vec3 h = normalize(VIEW + LIGHT);
		float n_dot_h = clamp(dot(NORMAL, h), 0.0, 1.0);
		float n_dot_v = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
		float a = ROUGHNESS * ROUGHNESS;
		float a2 = a * a;
		float d = a2 / (PI * pow(n_dot_h * n_dot_h * (a2 - 1.0) + 1.0, 2.0));
		float k = a * 0.5;
		float vis = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
		float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(dot(VIEW, h), 0.0, 1.0), 5.0);
		SPECULAR_LIGHT += LIGHT_COLOR * tint * shade * n_dot_l * d * vis * fresnel;
	}
}
