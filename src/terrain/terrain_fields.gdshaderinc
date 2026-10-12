// The generated terrain fields (tools/pipeline/terrain/terrain.py) and their
// sampling, shared by the terrain and everything that stands on it (grass).
// TerrainSystem fills these uniforms on its material; other materials copy
// them from there with TerrainSystem.share_fields().
//
// Sample [row z][column x] sits at origin + (x, z) * cell; the 0.5 m near field
// fades into the 8 m far field over its outer 40 m.

uniform sampler2D near_height : filter_linear, repeat_disable;
uniform sampler2D far_height : filter_linear, repeat_disable;
// R path, G beach, B the forest the trees were planted by (the wood's floor
// is drawn where they stand: canopy.gdshaderinc), A meadow flowers (1 m).
uniform sampler2D near_control : filter_linear_mipmap, repeat_disable;
// R rock outcrop, G wet, B lake SDF (0.5 = shore), A occlusion (1 m).
uniform sampler2D near_extra : filter_linear_mipmap, repeat_disable;
// R snow, G bare rock and scree, B forest, A gully wetness (8 m).
uniform sampler2D far_masks : filter_linear_mipmap, repeat_disable;
uniform vec4 near_rect;   // origin x, origin z, cell (m), samples
uniform vec4 far_rect;
uniform vec4 mask_rect;
uniform float water_level = 0.72;

// The tones of a sward and its colours.
#include "res://src/vegetation/shaders/sward.gdshaderinc"

vec2 near_uv(vec2 xz) {
	return ((xz - near_rect.xy) / near_rect.z + 0.5) / near_rect.w;
}

vec2 far_uv(vec2 xz) {
	return ((xz - far_rect.xy) / far_rect.z + 0.5) / far_rect.w;
}

vec2 mask_uv(vec2 xz) {
	return ((xz - mask_rect.xy) / mask_rect.z + 0.5) / mask_rect.w;
}

float near_weight(vec2 xz) {
	vec2 local = (xz - near_rect.xy) / near_rect.z;
	vec2 edge = min(local, vec2(near_rect.w - 1.0) - local) * near_rect.z;
	return clamp(min(edge.x, edge.y) / 40.0, 0.0, 1.0);
}

float height_at(vec2 xz) {
	float w = near_weight(xz);
	if (w >= 1.0) {
		return textureLod(near_height, near_uv(xz), 0.0).r;
	}
	float h = textureLod(far_height, far_uv(xz), 0.0).r;
	if (w > 0.0) {
		h = mix(h, textureLod(near_height, near_uv(xz), 0.0).r, w);
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
// early. The grass's jobs scatter the plants by it (_survey() of
// grass_tile_job.gd); the terrain shades the ground under them.
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
// mottles all of it. This is _survey() of grass_tile_job.gd again, which
// knows a little more: how far the wet soaks into a bank and what stands
// beside.
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
