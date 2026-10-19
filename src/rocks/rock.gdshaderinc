// The scanned rocks of RockField: rock.gdshader draws its boulders and stones,
// rock_cliff.gdshader the faces of the waterfall cliff. Each is a MultiMesh
// instance with INSTANCE_CUSTOM = (array layer, moss, tone seed, 0).
//
// The scans come from different places and lights; a grade per layer pulls
// them into the valley's palette, as the terrain does with its ground scans,
// and their warm stone is held to grey. On top: the grain of the stone close
// by, lichen on the open dry faces, moss on what faces the sky away from the
// water, the earth-stained foot where the stone meets the ground, the dark
// wet margin at the lake (the terrain's own), the lake's light under water,
// the sun dimmed by cloud shadows and the sky by the trees' crowns like
// everything else outdoors.

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/vegetation/shaders/canopy.gdshaderinc"
#include "res://src/water/underwater_light.gdshaderinc"
// The terrain's heights: RockField shares them.
#include "res://src/terrain/terrain_fields.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"

uniform sampler2DArray rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
// R roughness, G ambient occlusion.
uniform sampler2DArray rock_rah : filter_linear_mipmap_anisotropic, repeat_enable;
// Per array layer: rgb tint (carrying the exposure gain) and saturation.
uniform vec4 layer_grade[8];
// Stone is grey. Some scans are of brown rock under yellow growth, which a
// grade cannot part: what is warm in a scan (the stone, not the olive and green
// on it) keeps no more of its colour than y, taken x of the way there (0: the
// scan as graded).
uniform vec2 rock_grey = vec2(1.0, 0.25);
// Moss is the terrain's mossy rock scan (its layer array), laid on from above.
#include "res://src/terrain/moss.gdshaderinc"
uniform float moss_layer = 13.0;
uniform float moss_tile = 2.4;
uniform vec4 moss_grade = vec4(0.92, 1.03, 0.9, 1.05);
// A scan is stretched over the whole of its stone and runs out of detail
// close by. There the stone takes its grain from the terrain's rock scan (the
// normals of its layer array), laid on along the world's axes. x: how strong
// (0 none); y: metres to a repeat; z, w: the eye's distances (m) over which
// it is gone.
uniform vec4 rock_grain = vec4(0.6, 1.5, 6.0, 10.0);
uniform sampler2DArray grain_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grain_layer = 5.0;
// Lichen crusts the open, dry faces of a stone, where the moss, which wants
// the damp and a face to the sky, does not grow. x: how much of it there is
// (0 none); y, z: metres to a repeat of the noise its colonies and its single
// crusts are cut from; w: the eye's distance (m) at which it is gone.
uniform vec4 lichen_growth = vec4(0.85, 2.7, 0.75, 60.0);
// Most crusts are pale grey-green, some ochre.
uniform vec3 lichen_pale = vec3(0.3, 0.32, 0.26);
uniform vec3 lichen_ochre = vec3(0.33, 0.26, 0.09);
// A stone stands in the ground, not on it. At its foot the rain splashes
// earth on it and the grass keeps it damp: it is darker there, and the moss
// climbs its sides. x: how far the foot takes the colour of foot_soil (0: no
// foot at all); y: how high the stain reaches (m); z: how much more readily
// moss grows at the ground; w: the eye's distance (m) at which all of it is
// gone.
uniform vec4 rock_foot = vec4(0.8, 0.4, 0.6, 40.0);
uniform vec3 foot_soil = vec3(0.6, 0.52, 0.42);
// Stone under the lake: a film of algae over it and the bed's silt settled
// on its upper faces, fading in over the first metre of depth (0 bare).
uniform float lake_film = 1.0;

varying vec3 world_pos;
varying flat vec4 rock;
varying float sun_vis;
// How closed the crowns overhead are (the canopy field, 0..1).
varying float crown_cover;
varying vec3 sun_under;
// Metres above the terrain, where the eye is near enough for the stone's foot.
varying float foot_height;
// 1 below the waterline: stone and water differ too little in index for the
// face to mirror anything, so the sky's reflection and the sun's glint go.
varying float submerged;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rock = INSTANCE_CUSTOM;
	sun_vis = cloud_sun_visibility(world_pos)
		* (1.0 - canopy_sun_shade(world_pos.xz, CANOPY_HEIGHT, -(VIEW_MATRIX * vec4(world_pos, 1.0)).z, 0.0));
	crown_cover = canopy_at(world_pos.xz, 1.0, 0.0);
	// Worked out a little past where fragment() stops asking, so that no
	// triangle it still shades has a corner left out.
	foot_height = 0.0;
	if (rock_foot.x > 0.0 && distance(world_pos, CAMERA_POSITION_WORLD) < rock_foot.w * 1.3) {
		foot_height = world_pos.y - height_at(world_pos.xz);
	}
}

vec3 grade(vec3 c, vec4 g) {
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(luma), c, g.w) * g.rgb, vec3(0.0));
}

// The colour of a scan with its warm stone held to rock_grey. Stone is the
// hues from red to orange; where green has caught up with red it is growth.
vec3 greyed(vec3 c) {
	float top = max(c.r, max(c.g, c.b));
	float colour = (top - min(c.r, min(c.g, c.b))) / max(top, 1e-4);
	float stone = 1.0 - smoothstep(0.6, 0.9, (c.g - c.b) / max(c.r - c.b, 1e-3));
	float keep = min(rock_grey.y / max(colour, 1e-4), 1.0);
	return mix(c, mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, keep), rock_grey.x * stone);
}

// How far a face is turned to each world axis, for what is laid on it along
// the three of them: the shares sum to 1, and a small one counts as none.
vec3 axis_shares(vec3 face) {
	vec3 w = pow(abs(face), vec3(4.0));
	w *= step(0.08 * (w.x + w.y + w.z), w);
	return w / (w.x + w.y + w.z);
}

// How the grain tilts a face of any direction, in world space: the grain's
// normals read along each axis the face is turned to (`shares`), `tile`
// metres to a repeat. Their green points up the image, as the terrain's do.
vec3 grain_tilt(vec3 p, vec3 shares, float tile) {
	vec3 tilt = vec3(0.0);
	if (shares.x > 0.0) {
		vec2 t = texture(grain_normal, vec3(p.zy / tile, grain_layer)).rg * 2.0 - 1.0;
		tilt += vec3(0.0, -t.y, t.x) * shares.x;
	}
	if (shares.y > 0.0) {
		vec2 t = texture(grain_normal, vec3(p.xz / tile, grain_layer)).rg * 2.0 - 1.0;
		tilt += vec3(t.x, 0.0, -t.y) * shares.y;
	}
	if (shares.z > 0.0) {
		vec2 t = texture(grain_normal, vec3(p.xy / tile, grain_layer)).rg * 2.0 - 1.0;
		tilt += vec3(t.x, -t.y, 0.0) * shares.z;
	}
	return tilt;
}

// The noise single crusts of lichen are cut from, on a face of any direction:
// read along each axis the face is turned to (`shares`), `tile` metres to a
// repeat.
float crust_noise(vec3 p, vec3 shares, float tile) {
	float cut = 0.0;
	if (shares.x > 0.0) {
		vec3 n = texture(cloud_weather, p.zy / tile).rgb;
		cut += (n.r * 0.75 + n.b * 0.25) * shares.x;
	}
	if (shares.y > 0.0) {
		vec3 n = texture(cloud_weather, p.xz / tile + 0.37).rgb;
		cut += (n.r * 0.75 + n.b * 0.25) * shares.y;
	}
	if (shares.z > 0.0) {
		vec3 n = texture(cloud_weather, p.xy / tile + 0.71).rgb;
		cut += (n.r * 0.75 + n.b * 0.25) * shares.z;
	}
	return cut;
}

#include "res://src/lakeside/shore_common.gdshaderinc"

void fragment() {
	// Private underwater capture camera; discard above-water fragments only there.
	if (CAMERA_VISIBLE_LAYERS == 262144u && world_pos.y > lake_level + 0.4) { discard; }
	vec3 uvw = vec3(UV, floor(rock.x + 0.5));
	vec3 rah = texture(rock_rah, uvw).rgb;
	vec3 albedo = greyed(grade(texture(rock_albedo, uvw).rgb, layer_grade[int(uvw.z)]));
	// Neighbouring stones differ a little in tone.
	albedo *= mix(0.86, 1.1, rock.z);
	// OpenGL tangent normals (glTF), z rebuilt as Godot does for NORMAL_MAP.
	vec3 t = texture(rock_normal, uvw).rgb * 2.0 - 1.0;
	t.z = sqrt(max(1.0 - dot(t.xy, t.xy), 0.0));
	vec3 n_view = normalize(TANGENT * t.x + BINORMAL * t.y + NORMAL * t.z);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	// The face as the mesh has it, without the scan's relief.
	vec3 face = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float rough = rah.r;
	float ao = rah.g;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float above = world_pos.y - lake_level;

	// The grain of the stone, as near as the eye misses it in the scan.
	if (rock_grain.x > 0.0 && dist < rock_grain.w) {
		float close = 1.0 - smoothstep(rock_grain.z, rock_grain.w, dist);
		n_world = normalize(n_world + grain_tilt(world_pos, axis_shares(face), rock_grain.y) * (rock_grain.x * close));
	}

	// Lichen: crusts a hand wide, thick in colonies half a metre across and
	// few between them, on some stones more than on others. The moss, laid on
	// after it, covers it where the two would meet.
	if (lichen_growth.x > 0.0 && dist < lichen_growth.w) {
		float open = smoothstep(-0.35, 0.2, face.y) * smoothstep(0.5, 0.8, ao) * smoothstep(0.8, 2.0, above)
			* (1.0 - smoothstep(lichen_growth.w * 0.6, lichen_growth.w, dist))
			* lichen_growth.x * mix(0.35, 1.0, fract(rock.z * 13.7));
		if (open > 0.01) {
			// Sheared by the height, so that an upright face is not streaked.
			vec3 colony = texture(cloud_weather, (world_pos.xz + world_pos.y * vec2(0.83, -0.56)) / lichen_growth.y
				+ rock.z * 3.7).rgb;
			float thick = smoothstep(0.45, 0.7, colony.g);
			// Far off a pixel holds many crusts and takes their average.
			float many = smoothstep(15.0, 35.0, dist / lichen_growth.z);
			float crusted = mix(0.07, 0.55, thick);
			if (many < 1.0) {
				float cut = crust_noise(world_pos, axis_shares(face), lichen_growth.z);
				crusted = mix(smoothstep(-0.05, 0.05, cut - mix(0.8, 0.52, thick)), crusted, many);
			}
			crusted *= open;
			albedo = mix(albedo, mix(lichen_pale, lichen_ochre, smoothstep(0.66, 0.74, colony.r)), crusted * 0.85);
			rough = mix(rough, 0.92, crusted);
		}
	}

	// The foot of the stone: 1 at the ground, gone at a height that wanders
	// along it. The lake's own margin is another matter.
	float footing = 0.0;
	if (rock_foot.x > 0.0 && dist < rock_foot.w && foot_height < rock_foot.y * 1.5) {
		float ragged = texture(cloud_weather, world_pos.xz / 1.7 + rock.z * 11.0).r;
		footing = (1.0 - smoothstep(0.0, rock_foot.y * (0.5 + ragged), foot_height))
			* (1.0 - smoothstep(rock_foot.w * 0.7, rock_foot.w, dist)) * smoothstep(0.2, 0.8, above);
	}

	// Moss grows where rain and shade keep the stone damp, not where waves or
	// rockfall scour it: on faces toward the sky and in hollows, in patches,
	// and up the sides from the ground.
	float grow = rock.y * smoothstep(0.5, 1.8, above);
	if (grow > 0.01) {
		float patch = texture(cloud_weather, world_pos.xz / 4.3 + rock.z * 7.0).g;
		float cover = smoothstep(0.5, 0.85, n_world.y + (patch - 0.5) * 0.9 + (0.85 - ao) * 0.6 + rock_foot.z * footing)
			* grow;
		if (cover > 0.01) {
			vec3 moss = grade(texture(moss_albedo, vec3(world_pos.xz / moss_tile, moss_layer)).rgb, moss_grade);
			albedo = mix(albedo, moss, cover);
			rough = mix(rough, 0.92, cover);
			// A cushion of moss softens the relief of the stone under it.
			n_world = normalize(mix(n_world, face, cover * 0.6));
		}
	}

	if (footing > 0.0) {
		// Splashed earth over whatever grows there, and the shade of the ground.
		float stain = footing * rock_foot.x;
		albedo *= mix(vec3(1.0), foot_soil, stain);
		rough = mix(rough, 0.95, stain * 0.5);
		ao *= 1.0 - 0.4 * stain * footing;
	}

	// Wet margin: darker and glossier just above the waterline (as the terrain).
	// Under the water the stone stays as dark as its wet margin; only the
	// gloss of the film of water on it goes.
	float under = smoothstep(0.35, -0.9, above);
	float wet = smoothstep(0.04, -0.08, above);
	vec4 shore_memory = lake_shore_at(world_pos.xz);
	wet = max(wet, shore_memory.g * (1.0 - smoothstep(0.3, 0.7, above)));
	albedo *= mix(1.0, 0.62, wet);
	rough = mix(rough, 0.28, wet * 0.8 * (1.0 - under));
	// Rain wets the stone where the lake has not.
	float rained = 0.0;
	if (rain_is_wet() && above > 0.0) {
		rained = rain_film(rain_reach(world_pos, face)) * smoothstep(0.0, 0.12, above) * (1.0 - wet);
		wet_surface(rained, 0.0, albedo, rough);
	}

	sun_under = vec3(1.0);
	float depth = lake_level - world_pos.y;
	if (depth > 0.0) {
		if (lake_film > 0.0) {
			// Olive-brown periphyton in patches, and the pale marl of the bed
			// on the faces that look up, thicker the deeper the stone lies.
			float film = lake_film * smoothstep(0.0, 1.0, depth);
			float patch = texture(cloud_weather, world_pos.xz / 3.1 + rock.z * 5.0).g;
			float up = clamp(n_world.y, 0.0, 1.0);
			albedo = mix(albedo, albedo * vec3(0.72, 0.78, 0.5), film * (0.45 + 0.35 * patch));
			float silt = film * smoothstep(0.55, 1.05, up + (patch - 0.5) * 0.6) * (0.25 + 0.4 * smoothstep(2.0, 7.0, depth));
			albedo = mix(albedo, vec3(0.33, 0.32, 0.27), silt * 0.65);
			rough = mix(rough, 0.92, max(silt, film * 0.5));
		}
		albedo *= underwater_light(world_pos.xz, depth, dist, 1.0, sun_under);
	}
	float residue = shore_memory.b * smoothstep(-0.03, 0.04, above) * (1.0 - smoothstep(0.25, 0.5, above));
	albedo = mix(albedo, vec3(0.76, 0.79, 0.76), clamp(residue * 0.7, 0.0, 0.45));
	ALBEDO = albedo;
	submerged = smoothstep(0.05, -0.3, above);
	ROUGHNESS = mix(clamp(rough, 0.05, 1.0), 1.0, submerged);
	SPECULAR = 0.4 * (1.0 - submerged) * wet_specular_under(rained,
		reflect(normalize(world_pos - CAMERA_POSITION_WORLD), n_world).y, 1.0 - crown_cover);
	AO = ao * (1.0 - canopy_light.x * crown_cover);
	AO_LIGHT_AFFECT = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
}

void light() {
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Both terms carry n_dot_l and ATTENUATION as factors: a back-facing or
	// fully shadowed light adds exactly nothing.
	if (n_dot_l > 0.0 && ATTENUATION > 0.0) {
		// Cloud shadows and the light under the lake belong to the sun alone.
		vec3 tint = vec3(1.0);
		if (LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999) {
			tint = sun_under * sun_vis;
		}
		DIFFUSE_LIGHT += LIGHT_COLOR * tint * ATTENUATION * n_dot_l / PI;
		// The glint carries (1 - submerged): exactly nothing well under water.
		if (submerged < 1.0) {
			vec3 h = normalize(VIEW + LIGHT);
			float n_dot_h = clamp(dot(NORMAL, h), 0.0, 1.0);
			float n_dot_v = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
			float a = ROUGHNESS * ROUGHNESS;
			float a2 = a * a;
			float d = a2 / (PI * pow(n_dot_h * n_dot_h * (a2 - 1.0) + 1.0, 2.0));
			float k = a * 0.5;
			float vis = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
			float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(dot(VIEW, h), 0.0, 1.0), 5.0);
			SPECULAR_LIGHT += LIGHT_COLOR * tint * ATTENUATION * n_dot_l * d * vis * fresnel * (1.0 - submerged);
		}
	}
}
