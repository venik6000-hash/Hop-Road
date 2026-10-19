// The generated terrain fields and their sampling, shared by the terrain
// and everything that stands on it (stones, the lake's foam). TerrainSystem
// fills these uniforms on its material; other materials copy them from there
// with TerrainSystem.share_fields().
//
// The ground is tiles of 0.5 m heights and 1 m masks (TerrainTiles), one
// tile per layer of the arrays, over the 2 m mid field of the walkable land,
// over the 8 m far field. Sample [row z][column x] of a field sits at
// origin + (x, z) * cell. A tile fades into the mid field over 40 m toward a
// tile no layer holds, the mid field into the far one over 40 m at the
// land's edge. The map of the tiles is read first, outside every branch:
// tile_spot().

uniform sampler2DArray tile_heights : filter_linear, repeat_disable;
// R path, G beach, B the forest the trees were planted by (the wood's floor
// is drawn where they stand: canopy.gdshaderinc), A meadow flowers.
uniform sampler2DArray tile_control : filter_linear_mipmap, repeat_disable;
// R rock outcrop, G wet, B lake SDF (0.5 = shore), A occlusion.
uniform sampler2DArray tile_extra : filter_linear_mipmap, repeat_disable;
// Per tile from tile (-16, -16): R the layer + 1 (0: no layer holds it),
// G its neighbours no layer holds (TerrainTiles: bits west, east, north,
// south, then north-west, north-east, south-west, south-east).
uniform sampler2D tile_slots : filter_nearest, repeat_disable;
uniform vec4 tile_rect;    // corner of tile (0, 0) x, z, tile (m), map texels per side
uniform vec4 tile_cells;   // height cell (m), heights per side, mask cell (m), mask texels per side
uniform sampler2D mid_height : filter_linear, repeat_disable;
uniform vec4 mid_rect;     // origin x, origin z, cell (m), samples (0: no mid field)
uniform sampler2D far_height : filter_linear, repeat_disable;
// R snow, G bare rock and scree, B forest, A gully wetness (8 m).
uniform sampler2D far_masks : filter_linear_mipmap, repeat_disable;
uniform vec4 far_rect;
#include "res://src/water/lake_level.gdshaderinc"

// The tones of a sward and its colours.
#include "res://src/vegetation/shaders/sward.gdshaderinc"

const float TILE_FADE = 40.0;
const float TILE_MAP_FIRST = -16.0;

// The tile under a point: its layer, the metres into it, and how much of it
// the ground takes (0 where no layer holds it).
struct TileSpot {
	float layer;
	vec2 local;
	float weight;
};

TileSpot tile_spot(vec2 xz) {
	vec2 at = floor((xz - tile_rect.xy) / tile_rect.z);
	vec2 on = at - TILE_MAP_FIRST;
	vec4 slot = texelFetch(tile_slots, ivec2(clamp(on, vec2(0.0), vec2(tile_rect.w - 1.0))), 0);
	bool mapped = all(greaterThanEqual(on, vec2(0.0))) && all(lessThan(on, vec2(tile_rect.w)));
	int layer = mapped ? int(round(slot.r * 255.0)) - 1 : -1;
	int missing = int(round(slot.g * 255.0));
	TileSpot spot;
	spot.local = xz - (tile_rect.xy + at * tile_rect.z);
	vec2 l = spot.local;
	vec2 r = vec2(tile_rect.z) - l;
	float edge = 1e9;
	edge = (missing & 1) != 0 ? min(edge, l.x) : edge;
	edge = (missing & 2) != 0 ? min(edge, r.x) : edge;
	edge = (missing & 4) != 0 ? min(edge, l.y) : edge;
	edge = (missing & 8) != 0 ? min(edge, r.y) : edge;
	edge = (missing & 16) != 0 ? min(edge, max(l.x, l.y)) : edge;
	edge = (missing & 32) != 0 ? min(edge, max(r.x, l.y)) : edge;
	edge = (missing & 64) != 0 ? min(edge, max(l.x, r.y)) : edge;
	edge = (missing & 128) != 0 ? min(edge, max(r.x, r.y)) : edge;
	spot.layer = float(max(layer, 0));
	spot.weight = layer < 0 ? 0.0 : clamp(edge / TILE_FADE, 0.0, 1.0);
	return spot;
}

vec3 tile_uv(TileSpot spot) {
	return vec3((spot.local / tile_cells.x + 0.5) / tile_cells.y, spot.layer);
}

vec3 tile_mask_uv(TileSpot spot) {
	return vec3((spot.local / tile_cells.z + 0.5) / tile_cells.w, spot.layer);
}

vec2 mid_uv(vec2 xz) {
	return ((xz - mid_rect.xy) / mid_rect.z + 0.5) / mid_rect.w;
}

vec2 far_uv(vec2 xz) {
	return ((xz - far_rect.xy) / far_rect.z + 0.5) / far_rect.w;
}

// How much of the mid field the ground takes where no tile is.
float mid_weight(vec2 xz) {
	vec2 local = (xz - mid_rect.xy) / mid_rect.z;
	vec2 edge = min(local, vec2(mid_rect.w - 1.0) - local) * mid_rect.z;
	return clamp(min(edge.x, edge.y) / TILE_FADE, 0.0, 1.0);
}

float height_at(vec2 xz) {
	TileSpot spot = tile_spot(xz);
	if (spot.weight >= 1.0) {
		return textureLod(tile_heights, tile_uv(spot), 0.0).r;
	}
	float h = textureLod(far_height, far_uv(xz), 0.0).r;
	float wm = mid_weight(xz);
	if (wm > 0.0) {
		h = mix(h, textureLod(mid_height, mid_uv(xz), 0.0).r, wm);
	}
	if (spot.weight > 0.0) {
		h = mix(h, textureLod(tile_heights, tile_uv(spot), 0.0).r, spot.weight);
	}
	return h;
}

vec3 height_normal(vec2 xz, float step) {
	float hl = height_at(xz - vec2(step, 0.0));
	float hr = height_at(xz + vec2(step, 0.0));
	float hd = height_at(xz - vec2(0.0, step));
	float hu = height_at(xz + vec2(0.0, step));
	return normalize(vec3(hl - hr, 2.0 * step, hd - hu));
}

// The masks of the tile at `spot`, unweighted. `dx`, `dy` are the screen
// derivatives of the world position (x, z), taken before any branch: the
// mask's coordinates jump at a tile's edge, so their own derivatives there
// would pick its smallest copy.
void near_masks(TileSpot spot, vec2 dx, vec2 dy, out vec4 control, out vec4 extra) {
	vec2 scale = vec2(1.0 / (tile_cells.z * tile_cells.w));
	vec3 uv = tile_mask_uv(spot);
	control = textureGrad(tile_control, uv, dx * scale, dy * scale);
	extra = textureGrad(tile_extra, uv, dx * scale, dy * scale);
}

// 0..1, how much of the ground is path, beach, scree or rock by the weights
// the terrain blends its layers with (see surface() in terrain.gdshader):
// control (R path, G beach), extra (R rock outcrop), far (G bare rock) and the
// slope (1 - normal.y).
float bare_ground(vec4 control, vec4 extra, vec4 far, float slope) {
	float trail = clamp(control.r * 1.2, 0.0, 1.0);
	float scree = clamp(smoothstep(0.18, 0.38, slope) * 0.8 + far.g * 0.4, 0.0, 1.0);
	float rock = clamp(smoothstep(0.34, 0.55, slope) + extra.r * 0.9, 0.0, 1.0);
	return max(max(trail, control.g), max(scree, rock));
}

// 0..1, how densely grass grows by the same weights (and far R snow), the
// height above the lake and the trees over it: `wooded`, how closed the
// stand round it is, and `shade`, the crowns right over it (the canopy field
// at CANOPY_WIDE_LEVEL and at its finest, canopy.gdshaderinc). The
// height-aware blend lets stones through at low weights, so grass gives way
// early. The grass's jobs scatter the plants by it (GrassSurvey.run); the
// terrain shades the ground under them.
float grass_cover(vec4 control, vec4 extra, vec4 far, float slope, float above, float wooded, float shade) {
	float bare = bare_ground(control, extra, far, slope);
	float d = 1.0 - smoothstep(0.02, 0.2, bare);
	d *= (1.0 - 0.75 * smoothstep(0.3, 0.85, wooded)) * (1.0 - 0.92 * shade);
	d *= 1.0 - smoothstep(0.15, 0.5, far.r);
	return d * smoothstep(0.08, 0.45, above);
}

// The sward at a place: x, how poor it is (0..1), and y, its tone
// (sward.gdshaderinc). A meadow is no even carpet: swathes of rank grass tens
// of metres across stand beside swathes of short turf broken into tussocks,
// with ragged edges between them (`swathe` and `ragged`: the macro noise's G
// at 137 m to a repeat and its R at 61 m). Wet ground and the foot of a rock
// feed the sward; thin dry soil on a sunward slope (`normal`, `parched`: the
// dry patches of the macro noise) and the cold of the heights starve it. On a
// poor sward the grass's jobs leave bare ground between the tussocks, which
// the terrain must not shade as the feet of a closed meadow. Nor is a meadow
// of one colour: a rank sward is the deep green, wet ground and the crowns
// over it (`shade`) keep the growth dark, a poor sward and dry or cold ground
// dry the grass on the stalk, and `fine` (the macro noise's G at 17 m)
// mottles all of it. This is GrassSurvey.run again, which knows a little
// more: how far the wet soaks into a bank and what stands beside.
vec2 sward_at(float swathe, float ragged, float fine, vec4 extra, vec4 far, vec3 normal, float parched, float above,
		float shade) {
	float lakeside = (1.0 - smoothstep(2.0, 14.0, extra.b * 255.0 - 128.0)) * (1.0 - smoothstep(1.5, 4.0, above));
	float hollow = clamp((0.72 - extra.a) * 4.0, 0.0, 1.0);
	float moist = clamp(max(extra.g, lakeside) + 0.7 * far.a + 0.5 * hollow, 0.0, 1.0);
	float lean = smoothstep(0.04, 0.2, 1.0 - normal.y) * (0.45 + 0.55 * clamp(normal.z * 3.0 + 0.5, 0.0, 1.0));
	float dry = clamp(lean + 0.6 * far.g + parched, 0.0, 1.0) * (1.0 - moist);
	float cold = max(smoothstep(70.0, 150.0, above), smoothstep(0.02, 0.15, far.r));
	float vigour = 0.5 + (swathe - 0.5) * 1.3 + (ragged - 0.5) * 0.5 + 0.45 * moist + 0.3 * smoothstep(0.01, 0.08, extra.r)
		- 0.55 * dry - 0.35 * cold;
	float poor = 1.0 - smoothstep(0.22, 0.40, vigour);
	float tone = SWARD_PLAIN + (ragged - 0.5) * 0.5 + (fine - 0.5) * 0.4 + 0.4 * poor + 0.3 * dry + 0.1 * cold
		- 0.15 * moist - 0.15 * shade - 0.15 * smoothstep(0.58, 0.72, vigour);
	return vec2(poor, clamp(tone, 0.0, 1.0));
}
