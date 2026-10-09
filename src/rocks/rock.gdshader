shader_type spatial;
// Scanned rocks placed by RockField: boulders, stones and the faces of the
// waterfall cliff. Each is a MultiMesh instance with INSTANCE_CUSTOM =
// (array layer, moss, tone seed, 0).
//
// The scans come from different places and lights; a grade per layer pulls
// them into the valley's palette, as the terrain does with its ground scans.
// On top: moss on what faces the sky away from the water, the dark wet margin
// at the lake (the terrain's own), the lake's light under water, and the sun
// dimmed by cloud shadows like everything else outdoors.
render_mode cull_back, depth_draw_opaque;

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/water/underwater_light.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"

uniform float water_level = 0.72;
uniform sampler2DArray rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
// R roughness, G ambient occlusion.
uniform sampler2DArray rock_rah : filter_linear_mipmap_anisotropic, repeat_enable;
// Per array layer: rgb tint (carrying the exposure gain) and saturation.
uniform vec4 layer_grade[8];
// Moss is the terrain's mossy rock scan (its layer array), laid on from above.
uniform sampler2DArray moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_layer = 13.0;
uniform float moss_tile = 2.4;
uniform vec4 moss_grade = vec4(0.92, 1.03, 0.9, 1.05);
// Stone under the lake: a film of algae over it and the bed's silt settled
// on its upper faces, fading in over the first metre of depth (0 bare).
uniform float lake_film = 1.0;

varying vec3 world_pos;
varying flat vec4 rock;
varying float sun_vis;
varying vec3 sun_under;
// 1 below the waterline: stone and water differ too little in index for the
// face to mirror anything, so the sky's reflection and the sun's glint go.
varying float submerged;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rock = INSTANCE_CUSTOM;
	sun_vis = cloud_sun_visibility(world_pos);
}

vec3 grade(vec3 c, vec4 g) {
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(luma), c, g.w) * g.rgb, vec3(0.0));
}

#include "res://src/lakeside/shore_common.gdshaderinc"

void fragment() {
	// Private underwater capture camera; discard above-water fragments only there.
	if (CAMERA_VISIBLE_LAYERS == 262144u && world_pos.y > water_level + 0.4) { discard; }
	vec3 uvw = vec3(UV, floor(rock.x + 0.5));
	vec3 rah = texture(rock_rah, uvw).rgb;
	vec3 albedo = grade(texture(rock_albedo, uvw).rgb, layer_grade[int(uvw.z)]);
	// Neighbouring stones differ a little in tone.
	albedo *= mix(0.86, 1.1, rock.z);
	// OpenGL tangent normals (glTF), z rebuilt as Godot does for NORMAL_MAP.
	vec3 t = texture(rock_normal, uvw).rgb * 2.0 - 1.0;
	t.z = sqrt(max(1.0 - dot(t.xy, t.xy), 0.0));
	vec3 n_view = normalize(TANGENT * t.x + BINORMAL * t.y + NORMAL * t.z);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	float rough = rah.r;
	float ao = rah.g;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float above = world_pos.y - water_level;

	// Moss grows where rain and shade keep the stone damp, not where waves or
	// rockfall scour it: on faces toward the sky and in hollows, in patches.
	float grow = rock.y * smoothstep(0.5, 1.8, above);
	if (grow > 0.01) {
		float patch = texture(cloud_weather, world_pos.xz / 4.3 + rock.z * 7.0).g;
		float cover = smoothstep(0.5, 0.85, n_world.y + (patch - 0.5) * 0.9 + (0.85 - ao) * 0.6) * grow;
		if (cover > 0.01) {
			vec3 moss = grade(texture(moss_albedo, vec3(world_pos.xz / moss_tile, moss_layer)).rgb, moss_grade);
			albedo = mix(albedo, moss, cover);
			rough = mix(rough, 0.92, cover);
			// A cushion of moss softens the relief of the stone under it.
			vec3 geometric = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			n_world = normalize(mix(n_world, geometric, cover * 0.6));
		}
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
		vec3 face = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		rained = rain_film(rain_reach(world_pos, face)) * smoothstep(0.0, 0.12, above) * (1.0 - wet);
		wet_surface(rained, 0.0, albedo, rough);
	}

	sun_under = vec3(1.0);
	float depth = water_level - world_pos.y;
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
	SPECULAR = 0.4 * (1.0 - submerged) * wet_specular(rained, reflect(normalize(world_pos - CAMERA_POSITION_WORLD), n_world).y);
	AO = ao;
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
