// Mesh LODs of the trees (tools/pipeline/vegetation/build_trees.py, build_pine.py).
// Included by tree_bark.gdshader (BARK) and tree_foliage.gdshader (FOLIAGE).
//
// COLOR carries the wind rig: R bend weight (0 at the root, 1 at branch tips),
// G flutter (0 at a card's stem, 1 at its free edge), B branch phase, A sky
// visibility through the crown (baked AO). INSTANCE_CUSTOM is (seed, species,
// crown widening, 0), see TreeLodGrid.instance_row().

#include "res://src/vegetation/shaders/vegetation.gdshaderinc"

// Fade-in start, fade-in end, fade-out start, fade-out end of this LOD (m).
instance uniform vec4 lod_range;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
#ifdef BARK
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_texture : filter_linear_mipmap_anisotropic, repeat_enable;
#endif
#ifdef FOLIAGE
uniform bool broadleaf = false;
// Wrapped diffuse and light passed through the leaves (see foliage_light()).
uniform float leaf_wrap = 0.25;
uniform float leaf_transmission = 0.35;
// Leaf colour correction on top of the scanned atlas.
uniform vec3 leaf_tint = vec3(1.0);
// Sky light reaching into the crown, on top of the baked AO: the cards of
// one clump hide each other more than the volumetric AO estimate knows.
uniform float leaf_ambient = 1.0;
#endif
// Beyond the reach of the sun's shadow map the baked crown AO darkens the
// sun as well, as the impostors do (their albedo carries it).
uniform vec2 shadow_fade = vec2(125.0, 158.0);

varying float lod_fade;
varying flat float fading_in;
varying float crown_ao;
varying float sun_vis;
varying flat float tree_seed;

// Model height (m) at scale 1 per species (TreePlacer.SPECIES_HEIGHT).
float species_height(float species) {
	float heights[9] = float[9](22.0, 17.0, 27.0, 4.5, 17.3, 14.1, 20.3, 14.8, 17.5);
	return heights[clamp(int(species + 0.5), 0, 8)];
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float dist = distance(origin.xz, lod_camera.xz);
	lod_fade = lod_weight(dist, lod_range);
	fading_in = dist < lod_range.y ? 1.0 : 0.0;
	crown_ao = mix(1.0, COLOR.a, smoothstep(shadow_fade.x, shadow_fade.y, dist));
	tree_seed = INSTANCE_CUSTOM.x;
	sun_vis = 1.0;
	if (lod_fade <= 0.0) {
		// Out of this LOD's band: every triangle collapses to a point.
		VERTEX = vec3(0.0);
	} else {
		float scale = length(MODEL_MATRIX[1].xyz);
		float height = species_height(INSTANCE_CUSTOM.y);
		// Wind direction in model space (the basis is a rotation times scale).
		vec3 downwind = (transpose(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y)) / scale;
		float strength = wind_strength(origin.xz, TIME);
		float phase = COLOR.b * TAU + tree_seed * 17.0;
		// The whole tree leans with the wind and sways slowly about that lean.
		float sway = 0.7 + 0.3 * sin(TIME * (0.55 + 0.25 * tree_seed) + tree_seed * TAU);
		vec3 offset = downwind * (0.035 * height * strength * sway * COLOR.r);
		// Branches bob on their own phase, mostly up and down.
		float bob = sin(TIME * 1.7 + phase) * 0.6 + sin(TIME * 2.9 + phase * 1.3) * 0.4;
		offset += (vec3(0.0, 0.7, 0.0) + downwind * 0.3) * bob * 0.006 * height * strength * COLOR.r;
		// Leaf and needle cards flutter along their normal.
		float flutter = sin(TIME * 9.0 + dot(VERTEX, vec3(3.1, 2.3, 2.7)) + phase * 3.0);
		offset += NORMAL * flutter * 0.035 * strength * COLOR.g;
		VERTEX += offset;
		sun_vis = cloud_sun_visibility(origin + vec3(0.0, VERTEX.y * scale, 0.0));
	}
}

// Screen position with a per-frame offset, so TAA turns the dither into a blend.
vec2 dither_position(vec2 frag, float time) {
	return frag + floor(fract(time * 7.31) * 64.0) * vec2(5.588238, 3.169421);
}

void fragment() {
	if (lod_dither_discard(lod_fade, fading_in > 0.5, dither_position(FRAGCOORD.xy, TIME))) {
		discard;
	}
	// A little per-tree variety in tone.
	vec3 tint = mix(vec3(0.9, 0.96, 1.0), vec3(1.08, 1.03, 0.9), tree_seed);
#ifdef BARK
	vec3 arm = texture(arm_texture, UV).rgb;
	ALBEDO = texture(albedo_texture, UV).rgb * mix(vec3(1.0), tint, 0.5);
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	ROUGHNESS = arm.g;
	AO = arm.r * crown_ao;
	AO_LIGHT_AFFECT = 0.0;
#endif
#ifdef FOLIAGE
	vec4 leaf = texture(albedo_texture, UV);
	// Mip averaging thins alpha-tested foliage with distance; lift the
	// coverage by the mip level so far crowns stay closed.
	float level = max(textureQueryLod(albedo_texture, UV).y, 0.0);
	ALPHA = leaf.a * (1.0 + 0.3 * level);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = leaf.rgb * tint * leaf_tint;
	// Culling is off: undo the flip of back faces, the crown normal points out
	// of the crown on both sides of a card.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = broadleaf ? 0.62 : 0.78;
	// No reflection of the sky: mirrored about the crown normal, which may
	// face away from the eye, it paints whole cards flat grey, and nothing
	// in the crown hides the sky from it. light() adds the sun's gloss.
	SPECULAR = 0.0;
	AO = crown_ao * leaf_ambient;
	AO_LIGHT_AFFECT = 0.0;
#endif
}

void light() {
	bool is_sun = light_is_sun(LIGHT_IS_DIRECTIONAL, LIGHT, INV_VIEW_MATRIX);
	float far_shade = is_sun ? crown_ao : 1.0;
#ifdef BARK
	foliage_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION * far_shade, is_sun, sun_vis, 0.0, 0.0,
		ROUGHNESS, 0.04, DIFFUSE_LIGHT, SPECULAR_LIGHT);
#endif
#ifdef FOLIAGE
	foliage_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION * far_shade, is_sun, sun_vis,
		leaf_wrap, leaf_transmission, ROUGHNESS, 0.03, DIFFUSE_LIGHT, SPECULAR_LIGHT);
#endif
}
