// Mesh LODs of the trees (tools/pipeline/vegetation/build_trees.py, build_scan_trees.py).
// Included by tree_bark.gdshader (BARK) and tree_foliage.gdshader (FOLIAGE).
//
// The bark is its scan; on trees close by its foot stands in earth and moss,
// moss climbs its damp side and lichen crusts it higher up. Rain darkens bark
// and leaves and lets them shine.
//
// COLOR carries the wind rig: R bend weight (0 at the root, 1 at branch tips),
// G flutter (0 at a card's stem, 1 at its free edge), B branch phase, A sky
// visibility through the crown (baked AO). INSTANCE_CUSTOM is (seed, species,
// crown widening, 0), see TreeLodGrid.instance_row().

#include "res://src/vegetation/shaders/vegetation.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"

// Fade-in start, fade-in end, fade-out start, fade-out end of this LOD (m).
instance uniform vec4 lod_range;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
#ifdef BARK
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_texture : filter_linear_mipmap_anisotropic, repeat_enable;
// Close by a trunk is more than its scan of bark. What stands at its foot and
// grows on it is laid on in world space, on trees within these distances of
// the eye (m: whole, gone); a tree farther off reads nothing for it.
uniform vec2 bark_range = vec2(22.0, 32.0);
// Metres to a repeat of the noise all of it is cut from.
uniform float bark_patch = 1.2;
// A trunk stands in the ground: earth is splashed on its foot and moss closes
// round it. x: how far the bark takes the colour of trunk_soil at the ground
// (0: no earth); y: how high the earth reaches (m); z: how closed the collar of
// moss is at the ground (0: no collar); w: how high it climbs (m).
uniform vec4 trunk_foot = vec4(0.7, 0.35, 0.9, 0.6);
uniform vec3 trunk_soil = vec3(0.55, 0.48, 0.4);
// Higher up moss keeps to the side of a trunk the midday sun does not reach,
// the more the closer the wood stands round it. x: how readily it grows there
// (0: none); y: how high it climbs (m); z, w: that side, as a direction on the
// ground (x, z): north.
uniform vec4 damp_moss = vec4(0.6, 2.5, 0.0, -1.0);
// Lichen crusts the bark above the foot, in the dry patches the moss leaves.
// x: how much of it there is (0: none); y, z: the heights (m) between which
// it comes in; w: the height above which the bark is its scan alone.
uniform vec4 bark_lichen = vec4(0.5, 0.4, 1.0, 6.0);
uniform vec3 lichen_pale = vec3(0.16, 0.175, 0.14);
// Moss is the growth of the terrain's mossy rock scan (its layer array), the
// bare stone of the scan left out.
uniform sampler2DArray moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_layer = 13.0;
uniform float moss_tile = 0.7;
uniform vec3 moss_tint = vec3(0.18, 0.32, 0.2);
// How far the rain soaks the bark, against open ground (0: it keeps dry). Bark
// is porous: it darkens as stone does and shines with the film on it.
uniform float rain_wets = 1.0;
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
// How far the rain wets the leaves, against open ground (0: they keep dry). A
// leaf or a needle takes no water in: it carries a film, a little darker and
// glossier to the sun. TreeMaterials.RAIN_ON_LEAVES, the impostors' as well.
uniform float rain_wets = 0.35;
#endif
// Beyond the reach of the sun's shadow map the baked crown AO darkens the
// sun as well, as the impostors do (their albedo carries it).
uniform vec2 shadow_fade = vec2(125.0, 158.0);

varying float lod_fade;
varying flat float fading_in;
varying float crown_ao;
varying float sun_vis;
// What the crowns of the wood round the tree leave it of the sky's light.
varying float sky_vis;
varying flat float tree_seed;
#ifdef BARK
// Where a point of the bark is (world, before the wind moves it) and, in w,
// how high it is above the tree's foot (m).
varying vec4 bark_place;
// 1 on a tree near enough for what is laid on its bark, 0 on one too far.
varying flat float bark_near;
// What the crowns over the trunk, its own first, leave of the sky to the
// mirror of wet bark.
varying float sky_open;
#endif

// Model height (m) at scale 1 per species (TreePlacer.SPECIES_HEIGHT).
float species_height(float species) {
	float heights[9] = float[9](24.5, 17.5, 20.0, 4.5, 17.3, 14.1, 20.3, 14.8, 17.5);
	return heights[clamp(int(species + 0.5), 0, 8)];
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float dist = distance(origin.xz, lod_camera.xz);
	lod_fade = lod_weight(dist, lod_range);
	fading_in = dist < lod_range.y ? 1.0 : 0.0;
	crown_ao = mix(1.0, COLOR.a, smoothstep(shadow_fade.x, shadow_fade.y, dist));
	tree_seed = INSTANCE_CUSTOM.x;
#ifdef BARK
	bark_place = vec4((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, VERTEX.y * length(MODEL_MATRIX[1].xyz));
	bark_near = 1.0 - smoothstep(bark_range.x, bark_range.y, dist);
#endif
	sun_vis = 1.0;
	sky_vis = 1.0;
#ifdef BARK
	sky_open = 1.0;
#endif
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
		// In a wood the foot of a tree stands under its neighbours' crowns and
		// its top clear of them: the foot gets less of the sky, and beyond the
		// shadow map less of the sun, by how closed the canopy is round the
		// trunk. The casters of the shadow map (a lod_range that never ends,
		// VegetationSystem.NO_FADE) are never lit and skip this.
		float under = 1.0 - smoothstep(0.25, 0.85, VERTEX.y / height);
		if (under > 0.0 && lod_range.w < 1000000.0) {
			sky_vis = 1.0 - under * canopy_sky_shade(origin.xz, 3.0, 0.0);
#ifdef BARK
			sky_open = 1.0 - under * canopy_at(origin.xz, 1.0, 0.0);
#endif
			// The ray to the sun is shaded until it clears the neighbours' tops.
			float rise = max(0.8 * height - VERTEX.y, 0.0) * scale * 0.5;
			float depth = -(VIEW_MATRIX * vec4(origin, 1.0)).z;
			sun_vis *= 1.0 - under * canopy_sun_shade(origin.xz, rise, depth, 0.0);
		}
	}
}

// Screen position with a per-frame offset, so TAA turns the dither into a blend.
vec2 dither_position(vec2 frag, float time) {
	return frag + floor(fract(time * 7.31) * 64.0) * vec2(5.588238, 3.169421);
}

#ifdef BARK
// What is laid on a trunk in world space is read on the world's two upright
// planes: how far bark that faces `face` takes the one across x (0..1).
float bark_turn(vec3 face) {
	return smoothstep(0.3, 0.7, face.x * face.x / (dot(face.xz, face.xz) + 1e-6));
}

// The weather noise on bark at `p`, `tile` metres to a repeat.
vec3 bark_noise(vec3 p, float turned, float tile, float seed) {
	vec3 noise = vec3(0.0);
	if (turned > 0.0) {
		noise += texture(cloud_weather, p.zy / tile + seed).rgb * turned;
	}
	if (turned < 1.0) {
		noise += texture(cloud_weather, p.xy / tile + seed + 0.41).rgb * (1.0 - turned);
	}
	return noise;
}

// The moss scan on bark at `p`.
vec3 bark_moss(vec3 p, float turned) {
	vec3 scan = vec3(0.0);
	if (turned > 0.0) {
		scan += texture(moss_albedo, vec3(p.zy / moss_tile, moss_layer)).rgb * turned;
	}
	if (turned < 1.0) {
		scan += texture(moss_albedo, vec3(p.xy / moss_tile, moss_layer)).rgb * (1.0 - turned);
	}
	return scan;
}
#endif

void fragment() {
	if (lod_dither_discard(lod_fade, fading_in > 0.5, dither_position(FRAGCOORD.xy, TIME))) {
		discard;
	}
	// A little per-tree variety in tone.
	vec3 tint = mix(vec3(0.9, 0.96, 1.0), vec3(1.08, 1.03, 0.9), tree_seed);
#ifdef BARK
	vec3 arm = texture(arm_texture, UV).rgb;
	vec3 bark = texture(albedo_texture, UV).rgb * mix(vec3(1.0), tint, 0.5);
	float rough = arm.g;
	float open = arm.r;
	float relief = 1.0;
	// What is laid on the bark reaches no higher than this (m).
	float top = max(max(trunk_foot.y * 1.5, trunk_foot.w), damp_moss.x > 0.0 ? damp_moss.y : 0.0);
	top = max(top, bark_lichen.x > 0.0 ? bark_lichen.w : 0.0);
	if (bark_near > 0.0 && bark_place.w < top && trunk_foot.x + trunk_foot.z + damp_moss.x + bark_lichen.x > 0.0) {
		vec3 face = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float turned = bark_turn(face);
		vec3 speck = bark_noise(bark_place.xyz, turned, bark_patch, tree_seed * 5.0);
		// Moss grows in patches: whole where it grows best, specks where
		// hardly; the fine grain of the noise frays their edges.
		float patchy = speck.g * 0.4 + speck.r * 0.25 + (speck.b - 0.17) * 0.35;
		float damp = smoothstep(-0.2, 0.9, dot(face.xz, damp_moss.zw));
		// The collar round the foot: closed on the damp side and open on the
		// other, and one tree has more of it than the next.
		float grow = trunk_foot.z * (1.0 - smoothstep(0.0, trunk_foot.w, bark_place.w))
			* mix(0.6, 1.0, damp) * mix(0.5, 1.0, fract(tree_seed * 7.31));
		// The damp side, thinning out upward; sky_vis is low in a close wood.
		grow = max(grow, damp_moss.x * damp
			* (1.0 - smoothstep(damp_moss.y * 0.3, damp_moss.y, bark_place.w))
			* mix(0.5, 1.0, clamp((1.0 - sky_vis) * 1.7, 0.0, 1.0)));
		float mossed = smoothstep(0.0, 0.2, grow + patchy - 1.0) * bark_near;
		if (mossed > 0.01) {
			vec3 scan = bark_moss(bark_place.xyz, turned);
			// The scan is of mossy rock: its growth has colour, its stone has
			// none, and where the stone shows the bark does.
			float high = max(scan.r, max(scan.g, scan.b));
			mossed *= mix(0.25, 1.0, smoothstep(0.2, 0.45, (high - min(scan.r, min(scan.g, scan.b))) / max(high, 1e-4)));
			bark = mix(bark, scan * moss_tint, mossed);
			rough = mix(rough, 0.95, mossed);
			relief = 1.0 - 0.5 * mossed;
		}
		// Lichen: crusts a few centimetres wide, close together where the
		// noise has the bark dry and few elsewhere.
		float crusted = smoothstep(0.0, 0.14, speck.b * 0.7 + speck.r * 0.3 - mix(0.86, 0.66, 1.0 - smoothstep(0.3, 0.5, speck.g)))
			* smoothstep(bark_lichen.y, bark_lichen.z, bark_place.w)
			* (1.0 - smoothstep(bark_lichen.w * 0.7, bark_lichen.w, bark_place.w))
			* (1.0 - mossed) * bark_lichen.x * bark_near;
		bark = mix(bark, lichen_pale, crusted);
		rough = mix(rough, 0.92, crusted);
		// Earth splashed up by the rain, over bark and moss alike.
		float stain = trunk_foot.x * (1.0 - smoothstep(0.0, trunk_foot.y * (0.5 + speck.g), bark_place.w)) * bark_near;
		bark *= mix(vec3(1.0), trunk_soil, stain);
		open *= 1.0 - 0.4 * stain;
	}
	// Rain runs down a trunk: most of it on what faces up, least under a bough.
	// The film mirrors the sky only where its mirror looks up at it past the crowns.
	if (rain_is_wet() && rain_wets > 0.0) {
		float rained = rain_film(rain_wets * mix(0.3, 1.0, smoothstep(-0.6, 0.6, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y)));
		wet_surface(rained, 0.0, bark, rough);
		SPECULAR = 0.5 * wet_specular_under(rained, (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).y, sky_open);
	}
	ALBEDO = bark;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = relief;
	ROUGHNESS = rough;
	AO = open * crown_ao * sky_vis;
	AO_LIGHT_AFFECT = 0.0;
#endif
#ifdef FOLIAGE
	vec4 leaf = texture(albedo_texture, UV);
	// Mip averaging thins alpha-tested foliage with distance; lift the
	// coverage by the mip level so far crowns stay closed.
	float level = max(textureQueryLod(albedo_texture, UV).y, 0.0);
	ALPHA = leaf.a * (1.0 + 0.3 * level);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 green = leaf.rgb * tint * leaf_tint;
	float gloss = broadleaf ? 0.62 : 0.78;
	if (rain_is_wet() && rain_wets > 0.0) {
		wet_surface(rain_film(rain_wets), 0.0, green, gloss);
	}
	ALBEDO = green;
	// Culling is off: undo the flip of back faces, the crown normal points out
	// of the crown on both sides of a card.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = gloss;
	// No reflection of the sky: mirrored about the crown normal, which may
	// face away from the eye, it paints whole cards flat grey, and nothing
	// in the crown hides the sky from it. light() adds the sun's gloss.
	SPECULAR = 0.0;
	AO = crown_ao * leaf_ambient * sky_vis;
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
