shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// What lives under the lake: fish, the drowned wood and stones, the
// freshwater plants. Lit by the lake's own optics (underwater_light): sky
// light dimmed by the water above, the sun through its refracted path and the
// caustics of the surface waves. Motion only deforms the meshes.
global uniform vec3 sun_direction;
#include "res://src/water/underwater_light.gdshaderinc"
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_roughness = false;
// Channel of roughness_map that holds roughness (Poly Haven packs it in green).
uniform int roughness_channel = 0;
uniform float roughness = 0.8;
uniform float normal_strength = 1.0;
// Plants built with vertex colours: rgb the tint, alpha the height fraction.
uniform bool vertex_color = false;
// Light through thin leaves when the sun is behind them.
uniform float translucency = 0.0;
// Algal film over sunken wood and stone, and the silt that settles on their
// upper faces: 0 fresh, 1 long drowned.
uniform float biofilm = 0.0;
uniform float water_level = 0.72;
uniform int motion = 0; // 1 rooted plant, 2 unrigged fish tail
uniform float plant_height = 1.0;
uniform float fish_length = 0.5;
uniform float current = 1.0;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 sun_under;
varying vec3 tint;
// The gloss of the wet surface for the sun's sheen in light(). The sky does
// not mirror in it under the water (wood, leaf and water differ too little in
// index), so the engine's own reflection is put out below the waterline.
varying float sheen;

void vertex() {
	vec3 anchor = MODEL_MATRIX[3].xyz;
	float phase = anchor.x * 0.31 + anchor.z * 0.23;
	tint = vertex_color ? COLOR.rgb : vec3(1.0);
	if (motion == 1) {
		float tip = vertex_color ? COLOR.a : clamp(VERTEX.y / plant_height, 0.0, 1.0);
		float bend = tip * tip;
		// The foot stays rooted; the slow seiche of the lake drags the tips
		// one way and back, with a smaller flutter running down the blade.
		float drift = sin(TIME * 0.42 + phase - tip * 1.6) * 0.14 + sin(TIME * 0.97 + phase * 1.7 - tip * 3.0) * 0.045;
		VERTEX.x += drift * plant_height * bend * current;
		VERTEX.z += cos(TIME * 0.33 + phase - tip * 2.2) * plant_height * 0.07 * bend * current;
		VERTEX.y -= (drift * drift) * plant_height * bend * 0.35 * current;
	} else if (motion == 2) {
		float tail = smoothstep(-0.12, 0.42, VERTEX.z / fish_length);
		VERTEX.x += sin(TIME * 7.0 + phase - VERTEX.z / fish_length * 5.0) * fish_length * 0.085 * tail * tail;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Private underwater capture camera; discard above-water fragments only there.
	if (CAMERA_VISIBLE_LAYERS == 262144u && world_pos.y > water_level + 0.4) { discard; }
	vec4 color = base_color;
	if (has_albedo) color *= texture(albedo_map, UV);
	if (color.a < 0.28) discard;
	vec3 albedo = color.rgb * tint;
	float rough = roughness;
	if (has_roughness) {
		vec4 packed = texture(roughness_map, UV);
		rough = roughness_channel == 1 ? packed.g : (roughness_channel == 2 ? packed.b : (roughness_channel == 3 ? packed.a : packed.r));
	}
	float depth = water_level - world_pos.y;
	if (biofilm > 0.0 && depth > 0.0) {
		// Wood keeps its grain under a thin olive film; silt settles on the
		// faces that look up, heavier the deeper and flatter they lie.
		float film = biofilm * smoothstep(0.0, 1.2, depth);
		float up = clamp(world_normal.y, 0.0, 1.0);
		float silt = film * up * up * (0.45 + 0.4 * smoothstep(2.0, 7.0, depth));
		albedo = mix(albedo, albedo * vec3(0.62, 0.68, 0.46), film * 0.6);
		albedo = mix(albedo, vec3(0.37, 0.36, 0.31), silt * 0.7);
		rough = mix(rough, 0.92, silt);
	}
	ALBEDO = albedo;
	sheen = 1.0 - rough;
	float submerged = smoothstep(-0.05, 0.3, depth);
	ROUGHNESS = mix(rough, 1.0, submerged);
	SPECULAR = 0.32 * (1.0 - submerged);
	if (has_normal) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	sun_under = vec3(1.0);
	if (depth > 0.0) ALBEDO *= underwater_light(world_pos.xz, depth, length(world_pos - CAMERA_POSITION_WORLD), 1.0, sun_under);
}

void light() {
	vec3 shade = LIGHT_COLOR * ATTENUATION * (LIGHT_IS_DIRECTIONAL ? sun_under : vec3(1.0));
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = max(ndl, 0.0);
	// Thin leaves glow when lit from behind, most looking into the sun.
	float through = translucency * (0.45 * clamp(-ndl, 0.0, 1.0) + 0.55 * pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0));
	DIFFUSE_LIGHT += ALBEDO * shade * (diffuse + through) / PI;
	// A modest wet sheen; the caustic focus does not sharpen it.
	vec3 h = normalize(VIEW + LIGHT);
	float gloss = sheen;
	SPECULAR_LIGHT += min(shade, LIGHT_COLOR * ATTENUATION) * diffuse * pow(max(dot(NORMAL, h), 0.0), mix(6.0, 60.0, gloss * gloss)) * gloss * 0.12;
}
