shader_type spatial;
// Terrain: CDLOD vertex morphing over the tiles and the mid and far fields, 14 scanned material
// layers blended by height, triplanar rock, the colours of the meadow's
// sward, heightfield self-shadowing and cloud shadows in the light function,
// the shade of the trees' crowns. See terrain_system.gd.
render_mode cull_back, depth_draw_opaque;

#include "res://src/sky/atmosphere.gdshaderinc"
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/vegetation/shaders/canopy.gdshaderinc"
#include "res://src/water/underwater_light.gdshaderinc"
#include "res://src/terrain/terrain_fields.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"
uniform sampler2DArray layer_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_rah : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
// What the carving of the mountains knows and the slope does not (8 m,
// tools/pipeline/terrain/terrain.py): R sky seen from the ground, G slide
// debris under the walls, B hardness of the rock at the surface.
uniform sampler2D far_detail : filter_linear_mipmap, repeat_disable;
uniform vec3 terrain_camera;
// Ground that stands high is chosen and morphed as if it were nearer, by
// 1 + z above the height y and not at all below x (TerrainSystem.high_detail).
uniform vec3 high_detail = vec3(150.0, 700.0, 2.5);
// Far rock and scree: their grey, and how much of the scan's own colour stays.
uniform vec3 mountain_tone = vec3(0.77, 0.785, 0.82);
uniform float mountain_colour = 0.25;
// Far rock is broken finer than the far field's cells are wide. The height of
// a rock scan, laid over the mountains twice, is their crags: buttresses and
// ledges at x metres to a repeat standing y metres proud, and the breaks
// across them at z metres standing w proud.
uniform vec4 crags = vec4(520.0, 70.0, 170.0, 26.0);
// How far a crack darkens the rock in it, and how much of the sky's light a
// far wall is left with: it sees half the sky, and the ground for the rest.
uniform vec2 crag_shade = vec2(0.45, 0.5);
// On a far mountain snow holds on ledges and not on the walls between them:
// how much faster it gives way to the slope there than on ground close by.
uniform float snow_hold = 1.7;
uniform float layer_tile[15];
// Per-layer grade: rgb tint, a saturation. Scans come from different places
// and lights; this pulls them into one alpine palette.
uniform vec4 layer_grade[15];
uniform float normal_strength = 1.0;
// Ground under the grass near the camera (grass_field.gd): what is seen of it
// between the plants is their shaded feet, so its albedo takes this factor,
// darker and greener; and the distances over which that gives way to the
// unshaded ground that stands in for the meadow's lit top farther out.
uniform vec3 grass_shade = vec3(0.3, 0.48, 0.18);
uniform vec2 grass_shade_range = vec2(20.0, 55.0);
// Bare rock is laid wide, for a cliff to read as one: close by, its texels
// are broader than a pixel of the window. There the relief of the same scan,
// laid finer, keeps the face rough under the eye, as on the boulders
// (rock.gdshader). x: how strong (0 none); y: metres to a repeat; z, w: the
// eye's distances (m) over which it is gone.
uniform vec4 rock_grain = vec4(0.6, 1.5, 6.0, 10.0);
// The wear of a yard (GroundWear): how far a point is from the middle of the
// nearest cart track (r) and of the nearest footpath (g), metres; how much
// of its ruts the track has there (b: none where it runs out at its ends);
// and how much of the bare ground is trodden earth (a). wear_rect is the
// field's corner (x, z) and one over its size, zero while there is no field.
uniform sampler2D wear_field : filter_linear, repeat_disable;
uniform vec4 wear_rect = vec4(0.0);
// Where coal dust and cinders are trodden into a yard's earth (r), over the
// same rectangle: a smithy's. The bare ground there keeps its grain and
// loses its colour to cinder_tint of its own brightness.
uniform sampler2D cinder_field : hint_default_black, filter_linear, repeat_disable;
uniform vec3 cinder_tint = vec3(0.3, 0.29, 0.29);
// A cart's ruts: its gauge, half the width of a rut, its depth and how far
// it wanders from the track's line, metres.
uniform vec4 ruts = vec4(1.3, 0.1, 0.055, 0.08);
// The pressed, damp earth of a rut's bottom, as a tint of the ground's own.
uniform vec3 rut_tint = vec3(0.62, 0.6, 0.58);
// The road's stones show through a yard's earth in patches: where the noise
// is over x, most where it is over y, and then by z of the blend, which
// leaves earth between them; they are as dirty as w.
uniform vec4 yard_stones = vec4(0.6, 0.85, 0.65, 0.8);
// The earth of a yard lies damp in patches: how dark it is there.
uniform float yard_damp = 0.8;
// A footpath: how far the earth is trodden smooth (x) and how far it is pale
// with dust (y), the dust as a tint of the earth's own brightness.
uniform vec2 path_wear = vec2(0.5, 0.35);
uniform vec3 path_dust = vec3(1.1, 1.06, 0.98);
// The eye's distance at which the ruts' relief is gone (x) and at which the
// ruts themselves are (y), metres.
uniform vec2 wear_range = vec2(40.0, 90.0);
// Metres between the lookups that give a rut its direction.
const float WEAR_STEP = 0.25;
// How far from a rut's middle, in its half widths, the earth it squeezed out
// stands highest, and how high against the rut's depth.
const vec2 RUT_SHOULDER = vec2(1.8, 0.3);
// The prints of feet (GroundTracks). track_prints holds them, a column each:
// in row 0 where a foot fell (x, z) and which way it pointed (x, z), in row
// 1 when (seconds of track_clock.x) and which foot (-1 left, 1 right).
// track_cells names up to four prints for every cell of TRACK_GRID metres of
// ground, a byte each (0: none), and wraps: a print is drawn by its own
// place. track_clock is now and how long a print lasts (0: none are kept).
uniform sampler2D track_prints : filter_nearest, repeat_disable;
uniform sampler2D track_cells : filter_nearest, repeat_enable;
uniform vec2 track_clock = vec2(0.0);
// A print: how deep it is pressed (m), the tint of the pressed earth, how
// much of a print dry ground takes (wet ground takes all of it) and the
// eye's distance at which prints are gone (m).
uniform vec4 tracks = vec4(0.02, 0.3, 0.8, 22.0);
// Metres the grid of cells spans before it wraps, and the reach of a print
// from its middle (GroundTracks.CELL * CELLS, REACH).
const float TRACK_GRID = 32.0;
const float TRACK_REACH = 0.2;
// A print's sides: metres from its outline to its flat bottom, and how high
// the lip round it stands against its depth.
const float BOOT_SIDE = 0.025;
const float BOOT_LIP = 0.3;
// A stone in a print: the heights of the ground's scan (0..1) between which
// it stands proud of the earth, and how much of the print it refuses.
const vec3 BOOT_PROUD = vec3(0.55, 0.8, 0.8);
// The heights' normal is taken over a cell to each side: the flat at the brink
// of a drop and at its foot leans with the drop, and the drop's first cell
// with the flat. Rock laid along the world's axes by that normal is laid on
// the flat from the side and smears across it. So the axes are chosen by the
// face as it is drawn where the two differ in their lean by more than x,
// wholly from y; and the eye's distances (m) over which that is given up, the
// mesh being coarser than the heights from there.
const vec2 FACE_LEAN = vec2(0.12, 0.35);
const vec2 FACE_RANGE = vec2(50.0, 90.0);

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
// A yard's trodden earth: the scan of the wood's floor as it was shot, at a
// tile and a grade of its own.
const float L_EARTH = 14.0;

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
	float dist = distance(terrain_camera, vec3(xz.x, h, xz.y))
		/ (1.0 + high_detail.z * smoothstep(high_detail.x, high_detail.y, h));
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
	float scan = layer == L_EARTH ? L_FOREST : layer;
	Layer l;
	l.albedo = grade(texture(layer_albedo, vec3(uv, scan)).rgb, layer);
	vec3 rah = texture(layer_rah, vec3(uv, scan)).rgb;
	l.rough = rah.r;
	l.ao = rah.g;
	l.height = rah.b;
	vec3 n = tangent_normal(scan, uv);
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

// `facing` chooses the axes a layer is laid along (the face as it is drawn,
// see FACE_LEAN); its relief leans on `geo`, the normal the ground is lit by.
Layer triplanar(float layer, vec3 p, vec3 geo, vec3 facing, float scale) {
	vec3 w = pow(abs(facing), vec3(5.0));
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

// Height (0..1) of the rock scan that stands in for a far mountain's crags,
// at `tile` metres to a repeat, seen from the three axes by the weights w.
float crag_height(vec3 p, vec3 w, float tile) {
	float h = 0.0;
	if (w.x > 0.0) {
		h += texture(layer_rah, vec3(p.zy / tile, L_ROCK_DARK)).b * w.x;
	}
	if (w.y > 0.0) {
		h += texture(layer_rah, vec3(p.xz / tile, L_ROCK_DARK)).b * w.y;
	}
	if (w.z > 0.0) {
		h += texture(layer_rah, vec3(p.xy / tile, L_ROCK_DARK)).b * w.z;
	}
	return h;
}

// How the scan's height rises along the face and up it over `reach` metres,
// as the tilt it gives the slope.
vec3 crag_tilt(vec3 p, vec3 w, float tile, float relief, vec3 along, vec3 up, float reach, out float here) {
	here = crag_height(p, w, tile);
	vec2 rise = vec2(crag_height(p + along * reach, w, tile), crag_height(p + up * reach, w, tile)) - here;
	return (along * rise.x + up * rise.y) * (relief / reach);
}

// How the grain of bare rock tilts a face that looks along `geo`: the relief
// of the rock's scan, `tile` metres to a repeat, read along each axis the
// face is turned to.
vec3 grain_tilt(vec3 p, vec3 geo, float tile) {
	vec3 w = pow(abs(geo), vec3(4.0));
	w *= step(0.08 * (w.x + w.y + w.z), w);
	w /= w.x + w.y + w.z;
	vec3 tilt = vec3(0.0);
	if (w.x > 0.0) {
		vec2 t = texture(layer_normal, vec3(p.zy / tile, L_ROCK)).rg * 2.0 - 1.0;
		tilt += vec3(0.0, -t.y, t.x) * w.x;
	}
	if (w.y > 0.0) {
		vec2 t = texture(layer_normal, vec3(p.xz / tile, L_ROCK)).rg * 2.0 - 1.0;
		tilt += vec3(t.x, 0.0, -t.y) * w.y;
	}
	if (w.z > 0.0) {
		vec2 t = texture(layer_normal, vec3(p.xy / tile, L_ROCK)).rg * 2.0 - 1.0;
		tilt += vec3(t.x, -t.y, 0.0) * w.z;
	}
	return tilt;
}

// Stone seen from far off: the grey of a mountain, with a little of the
// scan's own colour left in it.
vec3 far_stone(vec3 albedo, float tone, float amount) {
	float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	return mix(albedo, mix(vec3(luma), albedo, mountain_colour) * mountain_tone * tone, amount);
}

// The whole layer stack at one texture scale.
// `facing` is triplanar()'s. `sward` is the meadow's (sward_at() of
// terrain_fields.gdshaderinc), `yard` the wear of a yard: how bare a
// cart's wheels keep the ground (x), how much of the bare ground is trodden
// earth (y) and how much of the road's stones shows through that (z).
Layer surface(vec3 p, vec3 geo, vec3 facing, float scale, vec4 control, vec4 extra, vec4 far, vec3 detail, vec4 macro,
		float stir, float wn, float dist, float cleft, float lie, vec2 sward, vec3 yard) {
	vec2 xz = p.xz;
	float slope = 1.0 - geo.y;
	float above = p.y - lake_level;
	float mountain = smoothstep(350.0, 1400.0, dist);
	float remote = mountain * (1.0 - wn);
	// Ground: meadow grass, drier grass up high and where the sward is poor,
	// forest floor, trodden earth.
	float alpine = smoothstep(600.0, 1100.0, p.y + (macro.g - 0.5) * 300.0);
	float dry = clamp(smoothstep(0.5, 0.82, macro.r) * 0.45 + alpine + 0.6 * sward.x, 0.0, 1.0);
	Layer ground = planar_untiled(L_GRASS, xz, geo, scale, stir);
	if (dry > 0.02) {
		ground = blend(ground, planar_untiled(L_SPARSE, xz, geo, scale, stir), dry);
	}
	// The grass's scans are a plain sward's: they take the green of this one's
	// tone, and its straw where it has dried.
	ground.albedo = dried_grass(ground.albedo * (sward_tint(sward.y) / sward_tint(SWARD_PLAIN)), sward_dried(sward.y));
	float forest = max(control.b, far.b * (1.0 - wn));
	if (forest > 0.02) {
		ground = blend(ground, planar_untiled(L_FOREST, xz, geo, scale, stir), forest);
	}
	// Far meadows read as the aerial scan: grass with rock breaking through.
	float far_meadow = smoothstep(220.0, 900.0, dist) * (1.0 - forest * 0.7);
	if (far_meadow > 0.02) {
		ground = blend(ground, planar(L_MOUNTAIN, xz, geo, 1.0), far_meadow);
	}
	float trail = clamp(max(control.r * 1.2, yard.x), 0.0, 1.0);
	if (trail > 0.02) {
		Layer bare = planar(L_TRAIL, xz, geo, scale);
		if (yard.y > 0.02) {
			bare.albedo *= mix(1.0, yard_stones.w, yard.y);
			bare = blend(bare, planar_untiled(L_EARTH, xz, geo, scale, stir), yard.y * (1.0 - yard.z));
		}
		ground = blend(ground, bare, trail);
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
	// On a far mountain not every steep slope is loose stone: there the scree
	// lies where the masks have it, in gullies and under walls.
	float scree = clamp(smoothstep(0.18, 0.38, slope) * 0.8 * (1.0 - 0.7 * remote) + far.a * 0.6 * (1.0 - wn) + far.g * 0.4
		+ detail.g * 0.7, 0.0, 1.0);
	scree *= 1.0 - under;
	if (scree > 0.02) {
		Layer talus = planar(L_SCREE, xz, geo, scale);
		talus.albedo = far_stone(talus.albedo, 1.08, remote);
		ground = blend(ground, talus, scree);
	}
	float rock = clamp(smoothstep(0.34, 0.55, slope) + extra.r * 0.9 + far.g * smoothstep(0.2, 0.4, slope) * (1.0 - wn), 0.0, 1.0);
	if (rock > 0.02) {
		Layer stone = triplanar(L_ROCK, p, geo, facing, scale);
		float dark = smoothstep(0.42, 0.62, macro.b);
		if (dark > 0.02) {
			stone = blend(stone, triplanar(L_ROCK_DARK, p, geo, facing, scale), dark);
		}
		if (mountain > 0.02) {
			stone = blend(stone, triplanar(L_ROCK, p, geo, facing, 9.0), mountain);
		}
		// The hard beds that stand as walls are the paler rock; cracks are dark.
		stone.albedo = far_stone(stone.albedo, mix(0.8, 1.12, detail.b) * cleft, remote);
		if (rock_grain.x > 0.0 && dist < rock_grain.w) {
			stone.normal = normalize(stone.normal
				+ grain_tilt(p, facing, rock_grain.y) * (rock_grain.x * (1.0 - smoothstep(rock_grain.z, rock_grain.w, dist))));
		}
		float mossy = smoothstep(0.4, 0.8, forest + extra.g * 0.5) * (1.0 - alpine);
		if (mossy > 0.02) {
			// The masks are laid from above and run down a wall in stripes:
			// there the moss keeps to the hollows of the rock.
			mossy *= mix(1.0, 1.0 - smoothstep(0.3, 0.65, stone.height), smoothstep(0.55, 0.85, slope));
			stone = blend(stone, triplanar(L_MOSS, p, geo, facing, scale), mossy * 0.7);
		}
		ground = blend(ground, stone, rock);
	}
	// Snow lies where the mask has it and the slope lets it: thresholded, the
	// 8 m mask ends at an edge that follows each ledge, not in a blur. `lie` is
	// the slope without its finest breaks: a snowfield covers those.
	float snow = smoothstep(-0.07, 0.07, far.r * 1.3 - 0.32 - lie * mix(1.1, snow_hold, remote)) * (1.0 - smoothstep(0.72, 0.92, lie));
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

// Metres from the outline of an oval of half-axes `r` to `p`, under zero
// inside it; near enough the truth round the outline, which is what a
// print's sides are cut by.
float oval(vec2 p, vec2 r) {
	float k = length(p / r);
	return k * (k - 1.0) / max(length(p / (r * r)), 0.001);
}

// A boot's print at `at` in its own frame (m): x along the foot from its
// middle, y across it toward the other foot. Returned are how deep the
// ground is pressed there (x, 0..1) and the earth squeezed up round the
// print (y, 0..1). A sole and a heel joined by a narrower waist: a pan with
// a flat bottom and steep sides, the heel struck a little deeper.
vec2 boot(vec2 at) {
	float heel = oval(at + vec2(0.1, 0.0), vec2(0.052, 0.042));
	float waist = length(vec2(max(abs(at.x + 0.03) - 0.05, 0.0), at.y - 0.004)) - 0.033;
	float outline = min(min(oval(at - vec2(0.055, -0.006), vec2(0.095, 0.05)), heel), waist);
	return vec2((1.0 - smoothstep(-BOOT_SIDE, 0.0, outline)) * mix(0.8, 1.0, 1.0 - smoothstep(-0.02, 0.03, heel)),
		smoothstep(-0.004, 0.01, outline) * (1.0 - smoothstep(0.01, 0.04, outline)));
}

void fragment() {
	// Private underwater capture camera; discard above-water fragments only there.
	if (CAMERA_VISIBLE_LAYERS == 262144u && world_pos.y > lake_level + 0.4) { discard; }
	vec3 p = world_pos;
	vec2 xz = p.xz;
	float dist = length(p - CAMERA_POSITION_WORLD);
	// The map of the tiles and the derivatives the masks are read with come
	// before any branch.
	TileSpot tile_here = tile_spot(xz);
	vec2 xz_dx = dFdx(xz);
	vec2 xz_dy = dFdy(xz);
	float wn = tile_here.weight;
	float fine_step = mix(mix(far_rect.z, mid_rect.z, mid_weight(xz)) * 1.5, tile_cells.x, wn);
	// The far field's relief is a few cells wide: its normal is taken over as
	// little as two pixels will bear.
	vec3 geo = height_normal(xz, max(fine_step, dist * mix(0.0018, 0.004, wn)));

	vec4 control = vec4(0.0);
	vec4 extra = vec4(0.0, 0.0, 1.0, 1.0);
	if (wn > 0.0) {
		vec4 tile_control_here;
		vec4 tile_extra_here;
		near_masks(tile_here, xz_dx, xz_dy, tile_control_here, tile_extra_here);
		control = tile_control_here * wn;
		extra = mix(extra, tile_extra_here, wn);
	}
	vec4 far = texture(far_masks, far_uv(xz));
	// The trees say where a wood is: the canopy field has their crowns. Far
	// off a pixel covers many of them, and the field is read blurred to
	// match; where it does not reach, the far forest mask stands for it. The
	// ground under a stand is the wood's floor, whatever the noise the trees
	// were planted by has there.
	float woods = far.b * (1.0 - wn) * CANOPY_STAND;
	float canopy_level = clamp(log2(max(dist * 0.02, 1.0)), 0.0, 5.0);
	float crowns = canopy_at(xz, canopy_level, woods);
	float wooded = canopy_level >= CANOPY_WIDE_LEVEL ? crowns : canopy_at(xz, CANOPY_WIDE_LEVEL, woods);
	control.b = canopy_floor(wooded) * wn;
	vec3 detail = vec3(1.0, 0.0, 0.0);
	if (wn < 1.0) {
		detail = mix(texture(far_detail, far_uv(xz)).rgb, detail, wn);
	}
	vec4 macro = texture(macro_noise, xz / 430.0);
	float stir = texture(macro_noise, xz / 61.0 + 0.37).r;
	float above = p.y - lake_level;
	// The meadow's sward: how poor it is and its tone, where the near field's
	// masks say what the ground is; beyond them it is a plain one.
	vec2 sward = vec2(0.0, SWARD_PLAIN);
	if (wn > 0.0) {
		sward = mix(sward, sward_at(texture(macro_noise, xz / 137.0 + 0.29).g, stir, texture(macro_noise, xz / 17.0 + 0.53).g,
			extra, far, geo, smoothstep(0.5, 0.82, macro.r) * 0.45, above, crowns), wn);
	}
	// Wear (GroundWear). `yard` is surface()'s, `damp` how damp its earth
	// lies and `trod` how far feet have pressed it; `rut` is the bottom of a
	// wheel's rut (x) and the earth squeezed up beside it (y), `lean` the
	// slope of the rut's sides along x and z. Both ruts of a track lie half
	// its gauge from its middle, so the distance to the middle draws them both.
	vec3 yard = vec3(0.0);
	float damp = 0.0;
	float trod = 0.0;
	float sooted = 0.0;
	vec2 rut = vec2(0.0);
	vec2 lean = vec2(0.0);
	if (wn > 0.0 && wear_rect.z > 0.0) {
		vec2 at = (xz - wear_rect.xy) * wear_rect.zw;
		if (at == clamp(at, vec2(0.0), vec2(1.0))) {
			vec4 away = texture(wear_field, at);
			sooted = texture(cinder_field, at).r * clamp(control.r * 1.2, 0.0, 1.0);
			vec3 mottle = texture(macro_noise, xz / 5.9 + 0.83).rgb;
			if (away.r < ruts.x && away.b > 0.0 && dist < wear_range.y) {
				float seen = 1.0 - smoothstep(wear_range.y * 0.6, wear_range.y, dist);
				vec2 reach = WEAR_STEP * wear_rect.zw;
				vec2 outward = vec2(
					texture(wear_field, at + vec2(reach.x, 0.0)).r - texture(wear_field, at - vec2(reach.x, 0.0)).r,
					texture(wear_field, at + vec2(0.0, reach.y)).r - texture(wear_field, at - vec2(0.0, reach.y)).r);
				outward /= max(length(outward), 1e-4);
				float sway = (texture(macro_noise, xz / 7.3 + 0.61).r - 0.5) * 2.0 * ruts.w;
				float across = (away.r + sway - ruts.x * 0.5) / ruts.y;
				// Soft ground takes a deep rut and hard ground hardly any.
				float soft = mix(0.35, 1.0, smoothstep(0.3, 0.65, texture(macro_noise, xz / 4.7 + 0.13).g)) * away.b * seen;
				float side = abs(across) - RUT_SHOULDER.x;
				rut = vec2(exp(-across * across), exp(-2.0 * side * side)) * soft;
				yard.x = exp(-across * across / 7.0) * away.b * seen;
				lean = outward * ((2.0 * across * rut.x - 4.0 * RUT_SHOULDER.y * side * sign(across) * rut.y) * ruts.z / ruts.y)
					* (1.0 - smoothstep(wear_range.x * 0.5, wear_range.x, dist));
			}
			trod = 1.0 - smoothstep(0.3, 1.0, away.g + (mottle.b - 0.5) * 0.5);
			yard.y = away.a;
			// Feet kick the stones off a path and a wheel presses them under.
			yard.z = smoothstep(yard_stones.x, yard_stones.y, texture(macro_noise, xz / 13.0 + 0.41).r) * yard_stones.z
				* (1.0 - max(trod, yard.x));
			damp = smoothstep(0.5, 0.75, mottle.g) * away.a;
		}
	}
	// Crags: the slope of a far mountain is tilted by the rock scan's height
	// along and up the face, which breaks it into walls and ledges that take
	// the light, the grass and the snow apart.
	float mountain = smoothstep(350.0, 1400.0, dist) * (1.0 - wn);
	float craggy = mountain * smoothstep(0.12, 0.3, 1.0 - geo.y);
	float cleft = 1.0;
	float crag_ao = 1.0;
	float lie = 1.0 - geo.y;
	if (craggy > 0.0) {
		vec3 w = pow(abs(geo), vec3(4.0));
		w *= step(0.04 * (w.x + w.y + w.z), w);
		w /= w.x + w.y + w.z;
		vec3 along = normalize(vec3(geo.y, -geo.x, 0.0));
		vec3 up = cross(along, geo);
		float reach = max(dist * 0.0025, crags.z / 400.0);
		float broad;
		float fine;
		vec3 tilt = crag_tilt(p, w, crags.x, crags.y, along, up, reach, broad) * craggy;
		vec3 ledges = normalize(geo - tilt);
		lie = 1.0 - max(ledges.y, 0.03);
		tilt += crag_tilt(p, w, crags.z, crags.w, along, up, reach, fine) * craggy;
		geo -= tilt;
		geo = normalize(vec3(geo.x, max(geo.y, 0.03), geo.z));
		float open = smoothstep(0.05, 0.6, mix(broad, fine, 0.4));
		cleft = mix(1.0, mix(1.0 - crag_shade.x, 1.0, open), craggy);
		crag_ao = mix(1.0, 0.5 + 0.5 * open, craggy);
	}
	crag_ao *= mix(1.0, mix(1.0, crag_shade.y, smoothstep(0.15, 0.65, 1.0 - geo.y)), mountain);

	// The face as it is drawn, where it leans otherwise than the heights'
	// normal says (FACE_LEAN): turned to the eye, whichever way the window's
	// rows run. Only where surface() lays rock near by: on the steep and where
	// the masks have it.
	vec3 facing = geo;
	if (wn > 0.0 && dist < FACE_RANGE.y && (1.0 - geo.y > 0.34 || extra.r > 0.02)) {
		vec3 drawn = cross(dFdx(p), dFdy(p));
		float area = length(drawn);
		if (area > 0.0) {
			drawn /= dot(drawn, CAMERA_POSITION_WORLD - p) < 0.0 ? -area : area;
			facing = normalize(mix(geo, drawn, smoothstep(FACE_LEAN.x, FACE_LEAN.y, abs(drawn.y - geo.y))
				* wn * (1.0 - smoothstep(FACE_RANGE.x, FACE_RANGE.y, dist))));
		}
	}

	// Texture repeat grows with distance in discrete steps, cross-faded, so
	// nothing slides while walking and far slopes do not show a grid.
	float mid = smoothstep(40.0, 110.0, dist);
	float remote = smoothstep(260.0, 650.0, dist);
	Layer ground;
	if (mid < 0.999) {
		ground = surface(p, geo, facing, 1.0, control, extra, far, detail, macro, stir, wn, dist, cleft, lie, sward, yard);
		if (mid > 0.001) {
			ground = mix_layers(ground,
				surface(p, geo, facing, 3.3, control, extra, far, detail, macro, stir, wn, dist, cleft, lie, sward, yard), mid);
		}
	} else {
		ground = surface(p, geo, facing, 3.3, control, extra, far, detail, macro, stir, wn, dist, cleft, lie, sward, yard);
		if (remote > 0.001) {
			ground = mix_layers(ground,
				surface(p, geo, facing, 11.0, control, extra, far, detail, macro, stir, wn, dist, cleft, lie, sward, yard), remote);
		}
	}
	if (rut.x + rut.y + trod + damp > 0.0) {
		// Feet press the earth smooth and leave it pale with dust. A wheel
		// presses a rut whose bottom is smooth, dark and damp, and squeezes
		// up beside it earth that dries pale.
		ground.normal = normalize(mix(ground.normal, geo, max(rut.x * 0.6, trod * path_wear.x)) - vec3(lean.x, 0.0, lean.y));
		float luma = dot(ground.albedo, vec3(0.2126, 0.7152, 0.0722));
		ground.albedo = mix(ground.albedo, luma * path_dust, trod * path_wear.y * (1.0 - rut.x));
		ground.albedo *= mix(vec3(1.0), rut_tint, rut.x) * (1.0 + 0.12 * rut.y) * mix(1.0, yard_damp, damp);
		ground.rough = mix(ground.rough, 0.7, max(rut.x, damp) * 0.5);
		ground.ao *= 1.0 - 0.35 * rut.x;
	}
	if (sooted > 0.0) {
		ground.albedo = mix(ground.albedo, dot(ground.albedo, vec3(0.2126, 0.7152, 0.0722)) * cinder_tint, sooted);
	}
	// A foot leaves a print in bare earth, in sand and in a wood's litter,
	// deeper when the ground is wet; turf and rock take none, and a stone that
	// stands proud of the earth keeps its place in one. The sole presses the
	// earth smooth and dark, the lip round it dries pale, and a low sun lays
	// the shadow of the print's side across its bottom.
	float pressed = 0.0;
	float tread_shade = 0.0;
	if (track_clock.y > 0.0 && wn > 0.0 && dist < tracks.w) {
		float sodden = max(weather_wet.x, extra.g);
		float takes = clamp(max(max(control.r * 1.2, control.g), control.b * 0.4), 0.0, 1.0)
			* (1.0 - clamp(extra.r * 0.9 + smoothstep(0.3, 0.5, 1.0 - geo.y), 0.0, 1.0))
			* (1.0 - BOOT_PROUD.z * smoothstep(BOOT_PROUD.x, BOOT_PROUD.y, ground.height))
			* mix(tracks.z, 1.0, sodden);
		vec4 cell = takes > 0.02 ? textureLod(track_cells, xz / TRACK_GRID, 0.0) : vec4(0.0);
		// The newest of the prints that lie here: how deep it is pressed (x),
		// the slope of its sides along x and z (yz) and its lip (w).
		vec4 tread = vec4(0.0);
		float newest = -1.0;
		for (int k = 0; k < 4; k++) {
			int slot = int(cell[k] * 255.0 + 0.5);
			if (slot == 0) {
				continue;
			}
			vec4 spot = texelFetch(track_prints, ivec2(slot, 0), 0);
			vec2 off = xz - spot.xy;
			vec4 born = texelFetch(track_prints, ivec2(slot, 1), 0);
			if (dot(off, off) > TRACK_REACH * TRACK_REACH || born.x < newest) {
				continue;
			}
			vec2 across = vec2(-spot.w, spot.z) * born.y;
			vec2 foot = vec2(dot(off, spot.zw), dot(off, across));
			vec2 mark = boot(foot);
			if (mark.x + mark.y > 0.0) {
				const float STEP = 0.004;
				vec2 along = boot(foot + vec2(STEP, 0.0)) - boot(foot - vec2(STEP, 0.0));
				vec2 aside = boot(foot + vec2(0.0, STEP)) - boot(foot - vec2(0.0, STEP));
				vec2 slant = vec2(along.x - BOOT_LIP * along.y, aside.x - BOOT_LIP * aside.y) / (2.0 * STEP);
				float fresh = (1.0 - smoothstep(0.6, 1.0, (track_clock.x - born.x) / track_clock.y))
					* (1.0 - smoothstep(tracks.w * 0.6, tracks.w, dist));
				tread = vec4(mark.x, spot.zw * slant.x + across * slant.y, mark.y) * fresh;
				newest = born.x;
				// The bottom is in shadow as far from the side toward the sun
				// as the side is high against the sun's height.
				vec2 sunward = sun_direction.xz * (tracks.x * takes * (1.0 + BOOT_LIP) / max(sun_direction.y, 0.05));
				sunward *= min(1.0, 0.1 / max(length(sunward), 0.001));
				tread_shade = sun_direction.y > 0.02 ? fresh * clamp(
					mark.x - boot(foot + vec2(dot(sunward, spot.zw), dot(sunward, across))).x, 0.0, 1.0) : 0.0;
			}
		}
		pressed = tread.x * takes;
		ground.normal = normalize(mix(ground.normal, geo, pressed * 0.8) + vec3(tread.y, 0.0, tread.z) * (takes * tracks.x));
		ground.albedo *= mix(1.0, tracks.y, pressed) * (1.0 + 0.12 * tread.w * takes * (1.0 - sodden));
		ground.rough = mix(ground.rough, 0.6, pressed * 0.4);
		ground.ao *= 1.0 - 0.45 * pressed;
	}

	// Wet margin: darker and glossier just above the waterline.
	float wet = clamp(extra.g * smoothstep(0.35, 1.3, above) + smoothstep(0.04, -0.08, above), 0.0, 1.0);
	vec4 shore_memory = lake_shore_at(world_pos.xz);
	wet = max(wet, shore_memory.g * (1.0 - smoothstep(0.3, 0.7, above)));
	float grass = grass_cover(control, extra, far, 1.0 - geo.y, above, wooded, crowns) * smoothstep(0.0, 0.6, wn);
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
			// Water stands in a rut and in a print before it stands anywhere else.
			float hollow = max(texture(macro_noise, xz / 11.0).b * 0.55 + texture(macro_noise, xz / 2.9).g * 0.45, max(rut.x, pressed));
			puddle = puddle_cover(smoothstep(0.988, 0.998, geo.y), hollow) * reach * (1.0 - turf)
				* (1.0 - smoothstep(45.0, 70.0, dist));
		}
	}
	vec3 albedo = ground.albedo;
	albedo *= mix(1.0, 0.62, wet);
	// Thin ground holds its grass in patches (the gate of GrassSurvey.run),
	// and so does a poor sward: only under a patch is the ground the
	// plants' shaded feet, which are dry where the plants are.
	float shaded = 1.0 - smoothstep(grass_shade_range.x, grass_shade_range.y, dist);
	if (shaded > 0.0 && grass > 0.0) {
		float poor = sward.x;
		float patchy = clamp(0.5 + (texture(macro_noise, xz / 19.0 + 0.47).g - 0.5) * 1.8, 0.0, 1.0);
		float stand = clamp((grass * mix(1.0, 0.45, poor) * 1.2 - patchy) * 5.0, 0.0, 1.0);
		albedo *= mix(vec3(1.0), dried_grass(grass_shade, sward_dried(sward.y)), stand * shaded);
	}
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
	float depth = lake_level - p.y;
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
	SPECULAR = 0.4 * wet_specular_under(max(rained * (1.0 - turf), puddle),
		reflect(normalize(p - CAMERA_POSITION_WORLD), ground.normal).y, 1.0 - crowns);
	// Under the trees little of the sky comes down, and beyond the sun's
	// shadow map their shadow lies where the canopy field has their crowns.
	AO = ground.ao * mix(1.0, extra.a, 0.85) * mix(1.0, detail.r, 0.9) * crag_ao * (1.0 - canopy_light.x * crowns);
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(ground.normal, 0.0)).xyz);
	cloud_shadow = cloud_cover_visibility(p) * ground_sun_visibility(xz)
		* (1.0 - canopy_sun_shade(xz, CANOPY_HEIGHT, -VERTEX.z, woods)) * (1.0 - tread_shade);
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
