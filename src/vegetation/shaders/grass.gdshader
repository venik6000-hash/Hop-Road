shader_type spatial;
// Grass and meadow plants as textured cards, one MultiMesh instance a clump
// (GrassClump builds the mesh and reads the atlas, GrassScatter fills the
// instances; GrassField streams them over the terrain, GrassGenerator grows
// them on any mesh).
//
// A clump is a few crossed cards that all show one cell of the atlas: a
// plant or a slice of turf with every blade drawn in the texture. vertex()
// gives the clump the size of its cell, turns it by a hash of where it
// stands, stands its foot on the slope, bends it in the wind and thins the
// meadow with distance. fragment() cuts the plant out of the card, light()
// lets the sun through it.
//
// What comes in:
//   mesh      VERTEX (a clump one card wide and one high, root at 0), NORMAL
//             (up, flaring outward toward the top), UV (across the card and
//             down it, v = 1 at the root), UV2 (x: place across the card,
//             -0.5 .. 0.5; y: the card's turn), COLOR (r: the card faces the
//             eye; g: the mat; b: flower)
//   instance  MODEL_MATRIX: origin = the clump's root on the ground, Y axis =
//             the ground's normal there
//             INSTANCE_CUSTOM: r size, g cell of the atlas and, in its
//             fraction, CROWD of how closely tall plants stand round the
//             clump, b tone, a rank (the order in which clumps drop out with
//             distance)
render_mode skip_vertex_transform, cull_disabled, depth_draw_opaque;

// Wind, the gust noise, cloud and ridge shadows, the foliage light model.
#include "res://src/vegetation/shaders/vegetation.gdshaderinc"

// GrassClump.MAX_CELLS.
const int CELLS = 32;
// GrassScatter.CROWD.
const float CROWD = 0.9;

// ---------------------------------------------------------------------------
// 1. Atlas
// ---------------------------------------------------------------------------
group_uniforms atlas_cells;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// x, y of the blade's surface in the card's frame (z is rebuilt).
uniform sampler2D atlas_normal : filter_linear_mipmap_anisotropic, repeat_disable;
// u, v of the cell's corner and its size in the atlas.
uniform vec4 cell_rect[CELLS];
// Width and height of the cell (m), share of the width the plant needs at
// its foot and half way up: the card is cut to them, to shade fewer holes.
uniform vec4 cell_shape[CELLS];
// The share of alpha_lift the cell's kind takes.
uniform float cell_lift[CELLS];
// How far the wind bends the cell's kind.
uniform float cell_flex[CELLS];

// ---------------------------------------------------------------------------
// 2. Distance fade
// ---------------------------------------------------------------------------
// The meadow thins with distance instead of ending at an edge. Every clump
// has a rank (0..1); it stands while its rank is under grass_keep(distance)
// and shrinks into the ground as the two meet. The clumps left grow, to
// cover for the ones that went.
group_uniforms distance_fade;
// Every clump stands out to here (m).
uniform float thin_start = 18.0;
// Beyond it the share left is (thin_start / distance) ^ thin_power.
uniform float thin_power : hint_range(0.0, 4.0) = 1.3;
// The last clumps go between these distances (m).
uniform float fade_start = 95.0;
uniform float fade_end = 115.0;
// The clumps left grow by this power of 1 / share.
uniform float thin_growth : hint_range(0.0, 1.0) = 0.3;
// Between these distances (m) a clump loses the shade at its foot and takes
// the ground's light: far off the eye no longer sees down between the
// plants, only the meadow's lit top, which is what the terrain shows beyond
// the last of them.
uniform float flat_start = 30.0;
uniform float flat_end = 80.0;
// The mat, the low growth under and between the taller plants, is what the
// eye sees of the ground when it looks down; it stands whole to mat_start
// and its last clumps go at mat_end (m), where the ground is seen too flatly
// to show between the plants.
uniform float mat_start = 10.0;
uniform float mat_end = 24.0;

// ---------------------------------------------------------------------------
// 3. Cut-out
// ---------------------------------------------------------------------------
group_uniforms cut_out;
// Mip averaging thins fine blades; the coverage is lifted by the mip level,
// up to lift_levels of it: farther than that a card thins out into the
// ground, which carries the meadow's colour on, instead of closing up into
// a flat rectangle.
uniform float alpha_lift : hint_range(0.0, 1.0) = 0.3;
uniform float lift_levels : hint_range(0.0, 8.0) = 3.0;
// Half width of the band of alpha in which the cut is dithered, for the
// temporal resolve to turn it into a soft edge.
uniform float alpha_soft : hint_range(0.0, 0.5) = 0.22;

// ---------------------------------------------------------------------------
// 4. Colour
// ---------------------------------------------------------------------------
group_uniforms colour;
// A clump's tone lies between these two tints: older, bluer growth and
// young, sunlit growth. Flowers keep the atlas's colours.
uniform vec3 tone_deep = vec3(0.84, 0.94, 0.86);
uniform vec3 tone_fresh = vec3(1.1, 1.06, 0.9);
// The foot of a clump stands in the shade of its neighbours: its colour and
// the sun on it at the ground, both back to 1 at root_height (m) or at
// root_share of the plant's own height, whichever is higher. That is in the
// thick of the meadow; a lone tuft, or one among low turf, keeps lone_shade
// of the shade and only over its own height.
uniform float root_shade : hint_range(0.0, 1.0) = 0.65;
uniform float root_sun : hint_range(0.0, 1.0) = 0.55;
uniform float root_height = 0.5;
uniform float root_share : hint_range(0.0, 1.0) = 0.6;
uniform float lone_shade : hint_range(0.0, 1.0) = 0.35;

// ---------------------------------------------------------------------------
// 5. Wind
// ---------------------------------------------------------------------------
// The direction and strength are `wind`, the gusts `wind_noise` (a tileable
// 2D noise texture scrolled downwind), both from vegetation.gdshaderinc.
group_uniforms wind_response;
// How far the wind lays a clump's top over, as a share of its height.
uniform float wind_bend : hint_range(0.0, 1.0) = 0.24;
// The sideways shiver.
uniform float wind_flutter : hint_range(0.0, 0.3) = 0.06;
// Whoever walks the meadow parts the plants round their feet: how far the
// tops lean away (m), within part_reach (m) of the eye's foot point.
uniform float part_lean = 0.45;
uniform float part_reach = 1.1;

// ---------------------------------------------------------------------------
// 6. Light
// ---------------------------------------------------------------------------
group_uniforms lighting;
// Share of the blade's own surface direction in the lighting normal; the
// rest is the clump's smooth one, which leans on the ground's.
uniform float normal_detail : hint_range(0.0, 1.0) = 0.2;
// Diffuse light wraps round the blades this far.
uniform float leaf_wrap : hint_range(0.0, 1.0) = 0.8;
// How much of the sun comes through a blade, and its colour on the way out.
uniform float leaf_transmission : hint_range(0.0, 2.0) = 0.5;
uniform vec3 through_tint = vec3(1.2, 1.1, 0.5);
uniform float blade_roughness : hint_range(0.0, 1.0) = 0.6;
// Share of the gloss a smooth leaf of this roughness would show: the blades
// of a card face every way, and toward the sun a full gloss burns white.
uniform float blade_gloss : hint_range(0.0, 1.0) = 0.2;
group_uniforms;

// Clumps shrink away over the last FADE_SOFTNESS of the ranks still standing
// (GrassScatter.SOFTNESS; share() there counts the clumps a tile must hold).
const float FADE_SOFTNESS = 0.25;
// Roots stand this far in the ground (m), so none hangs over a hollow.
const float ROOT_SINK = 0.03;

varying vec3 tint;
varying float lift;
// Height above the root (m), and the height at which the foot's shade ends.
varying float height;
varying float lit_height;
// The shade at the clump's foot at this distance: of its colour, of the sun;
// and the share of the blades' own directions left in its light.
varying vec3 foot_shade;
// How much of the sun the clouds and the ridges let through.
varying float sun_seen;
varying vec3 card_axis;
varying vec3 card_up;

uint grass_hash(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

float hash_unit(uint h) {
	return float(h >> 8u) / 16777216.0;
}

// The gust field at a ground position: wind_gust()'s broad octave alone, one
// lookup for a vertex instead of two. The gusts still cross the meadow with
// those in the trees.
float grass_gust(vec2 xz) {
	float broad = textureLod(wind_noise, (xz - wind.xy * wind.w * TIME) / GUST_SCALE, 0.0).r;
	return clamp((broad - 0.35) * 2.2, 0.0, 1.0);
}

// Share of the clumps standing `dist` metres from the eye (GrassScatter.keep()).
float grass_keep(float dist) {
	float thin = pow(clamp(thin_start / max(dist, 1e-3), 0.0, 1.0), thin_power);
	return thin * (1.0 - smoothstep(fade_start, fade_end, dist));
}

void vertex() {
	// -- The instance: where the clump stands and what the scatter says of it.
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 ground = normalize(MODEL_MATRIX[1].xyz);
	int cell = int(INSTANCE_CUSTOM.g);
	float crowd = fract(INSTANCE_CUSTOM.g) / CROWD;
	float rank = INSTANCE_CUSTOM.a;
	bool facing = COLOR.r > 0.5;
	bool mat = COLOR.g > 0.5;
	bool flower = COLOR.b > 0.5;
	float t = 1.0 - UV.y;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	float dist = distance(root, eye);

	// -- Distance fade. The rank is squeezed so that every clump is whole
	// while keep is 1; past that the last of them are on their way into the
	// ground. Flowers thin out more slowly: a few bright heads carry far.
	float keep = mat ? 1.0 - smoothstep(mat_start, mat_end, dist) : grass_keep(dist);
	keep = flower ? sqrt(keep) : keep;
	float grow = clamp((keep - rank * (1.0 - FADE_SOFTNESS)) / (keep * FADE_SOFTNESS + 1e-4), 0.0, 1.0);

	// A clump that does not stand goes behind the camera, where it is clipped,
	// before anything costly is worked out for it.
	vec3 view_position = vec3(0.0, 0.0, 1.0);
	vec3 normal = vec3(0.0, 1.0, 0.0);
	vec2 uv = vec2(0.0);
	tint = vec3(0.0);
	lift = 0.0;
	height = 0.0;
	lit_height = 1.0;
	foot_shade = vec3(1.0);
	sun_seen = 1.0;
	card_axis = vec3(1.0, 0.0, 0.0);
	card_up = vec3(0.0, 1.0, 0.0);
	if (grow > 0.0) {
		// -- Variation: a hash of the world position gives every clump its own
		// turn, shade and phase in the wind, the same in every frame.
		ivec2 place = ivec2(floor(root.xz * 128.0)) + ivec2(4194304);
		uint h = grass_hash(uint(place.x) ^ grass_hash(uint(place.y)));
		float turn_by = hash_unit(h) * TAU;
		float phase = hash_unit(grass_hash(h + 1u));
		float shade_by = hash_unit(grass_hash(h ^ 2654435769u));

		// -- Shape: the cell's size, the clumps left standing grown to cover
		// the ground of those gone, the card cut to the plant's outline.
		vec4 shape = cell_shape[cell];
		vec4 rect = cell_rect[cell];
		float cover = mat ? 1.0 : min(pow(1.0 / max(keep, 0.02), thin_growth), 2.2);
		float wide = shape.x * INSTANCE_CUSTOM.r * cover * grow;
		float tall = shape.y * INSTANCE_CUSTOM.r * sqrt(cover) * grow;
		float hull = t < 0.5 ? mix(shape.z, shape.w, t * 2.0) : mix(shape.w, 1.0, t * 2.0 - 1.0);
		float angle = UV2.y + turn_by;
		vec2 axis = vec2(cos(angle), sin(angle));
		vec2 to_eye = normalize(eye.xz - root.xz + vec2(1e-4, 0.0));
		// Where the vertex stands off the root, on level ground (m).
		vec2 spot;
		if (facing) {
			axis = vec2(-to_eye.y, to_eye.x);
			spot = axis * (UV2.x * hull * wide);
			normal = normalize(ground + vec3(to_eye.x, 0.0, to_eye.y) * 0.35);
		} else {
			mat2 turn = mat2(vec2(cos(turn_by), sin(turn_by)), vec2(-sin(turn_by), cos(turn_by)));
			spot = (turn * VERTEX.xz - axis * (UV2.x * (1.0 - hull))) * wide;
			// The mesh's normal flares out of "up"; here "up" is the ground's
			// normal, so a meadow on a slope is lit as the slope is.
			vec2 flare = turn * (NORMAL.xz / max(NORMAL.y, 0.2));
			normal = normalize(ground + vec3(flare.x, 0.0, flare.y));
		}
		float flat_by = smoothstep(flat_start, flat_end, dist);
		normal = normalize(mix(normal, ground, flat_by));
		float shaded = (1.0 - flat_by) * mix(lone_shade, 1.0, crowd);
		foot_shade = vec3(mix(1.0, root_shade, shaded), mix(1.0, root_sun, shaded), 1.0 - flat_by);
		// Plants grow upright whatever the slope; the card's foot follows it.
		float foot = -dot(ground.xz, spot) / max(ground.y, 0.3) - ROOT_SINK * grow;
		vec3 world = root + vec3(spot.x, VERTEX.y * tall + foot, spot.y);
		height = t * tall;
		lit_height = max(root_height * crowd, root_share * tall);

		// -- Wind: the root stands, the top travels farthest. A gust field
		// sweeps across the meadow, every clump sways on its own phase.
		float strength = wind.z * (0.45 + 0.9 * grass_gust(root.xz));
		float sway = sin(TIME * (1.5 + phase) + phase * 37.0 - dot(root.xz, wind.xy) * 0.5);
		float reach = t * t * cell_flex[cell] * tall;
		vec2 push = wind.xy * strength * (wind_bend + 0.1 * sway) * reach;
		push += vec2(-wind.y, wind.x) * strength * wind_flutter * reach * sin(TIME * 2.7 + phase * 91.0);
		// The player parts the plants round their feet; the mat is too low to
		// be pushed aside.
		vec2 away = world.xz - eye.xz;
		float parted = (1.0 - smoothstep(0.3, part_reach, length(away))) * (1.0 - smoothstep(1.3, 2.6, eye.y - root.y));
		push += away / max(length(away), 1e-3) * part_lean * parted * t * (mat ? 0.25 : 1.0);
		world.xz += push;
		// What leans over does not grow longer.
		world.y -= dot(push, push) / max(2.0 * tall, 0.2);
		view_position = (VIEW_MATRIX * vec4(world, 1.0)).xyz;

		// -- What fragment() and light() need. The texture's x runs along the
		// card's axis, or against it on the cards that show the cell mirrored.
		float along = (UV.x - 0.5) * UV2.x > 0.0 ? 1.0 : -1.0;
		card_axis = (VIEW_MATRIX * vec4(axis.x * along, 0.0, axis.y * along, 0.0)).xyz;
		card_up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		uv = rect.xy + vec2(0.5 + (UV.x - 0.5) * hull, UV.y) * rect.zw;
		tint = vec3(mix(0.88, 1.1, shade_by));
		if (!flower) {
			tint *= mix(tone_deep, tone_fresh, INSTANCE_CUSTOM.b);
		}
		lift = alpha_lift * cell_lift[cell];
		// Cloud and ridge shadow where the clump stands: one answer for all
		// of its pixels.
		sun_seen = cloud_sun_visibility(root);
	}
	VERTEX = view_position;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
	UV = uv;
}

void fragment() {
	vec4 plant = texture(atlas, UV);
	float level = max(textureQueryLod(atlas, UV).y, 0.0);
	// The dither moves every frame, so the temporal resolve blends it.
	vec2 at = FRAGCOORD.xy + floor(fract(TIME * 7.31) * 64.0) * vec2(5.588238, 3.169421);
	ALPHA = plant.a * (1.0 + lift * min(level, lift_levels));
	ALPHA_SCISSOR_THRESHOLD = 0.5 + alpha_soft * (dither_noise(at) * 2.0 - 1.0);

	float foot = smoothstep(0.0, lit_height, height);
	ALBEDO = plant.rgb * tint * mix(foot_shade.x, 1.0, foot);

	// The blade's own direction, mirrored to the side of the card that is seen.
	vec2 slope = texture(atlas_normal, UV).rg * 2.0 - 1.0;
	vec3 axis = normalize(card_axis);
	vec3 up = normalize(card_up);
	vec3 face = normalize(cross(axis, up));
	if (dot(face, VIEW) < 0.0) {
		face = -face;
	}
	vec3 detail = axis * slope.x + up * slope.y + face * sqrt(max(1.0 - dot(slope, slope), 0.0));
	NORMAL = normalize(mix(normalize(NORMAL), detail, normal_detail * foot_shade.z));
	ROUGHNESS = blade_roughness;
	// No mirror of the sky on a card: light() adds the gloss.
	SPECULAR = 0.0;
	// The sky reaches the roots less than the tops.
	AO = mix(foot_shade.x, 1.0, foot);
	AO_LIGHT_AFFECT = 0.0;
}

void light() {
	bool is_sun = light_is_sun(LIGHT_IS_DIRECTIONAL, LIGHT, INV_VIEW_MATRIX);
	// Toward the ground the plants shade each other.
	float within = is_sun ? mix(foot_shade.y, 1.0, smoothstep(0.0, lit_height, height)) : 1.0;
	vec3 gloss = vec3(0.0);
	foliage_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION * within, is_sun, sun_seen,
		leaf_wrap, 0.0, ROUGHNESS, 0.03, DIFFUSE_LIGHT, gloss);
	SPECULAR_LIGHT += min(gloss, LIGHT_COLOR) * blade_gloss;
	// Light through the blades: strongest looking toward the sun.
	float shade = ATTENUATION * within * (is_sun ? sun_seen : 1.0);
	float toward = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0);
	float behind = clamp(-dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * shade * leaf_transmission * (0.25 * behind + 0.75 * toward) * through_tint / PI;
}
