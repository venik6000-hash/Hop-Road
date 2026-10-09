// The generated terrain fields (tools/pipeline/terrain/terrain.py) and their
// sampling, shared by the terrain and everything that stands on it (grass).
// TerrainSystem fills these uniforms on its material; other materials copy
// them from there with TerrainSystem.share_fields().
//
// Sample [row z][column x] sits at origin + (x, z) * cell; the 0.5 m near field
// fades into the 8 m far field over its outer 40 m.

uniform sampler2D near_height : filter_linear, repeat_disable;
uniform sampler2D far_height : filter_linear, repeat_disable;
// R path, G beach, B forest floor, A meadow flowers (1 m).
uniform sampler2D near_control : filter_linear_mipmap, repeat_disable;
// R rock outcrop, G wet, B lake SDF (0.5 = shore), A occlusion (1 m).
uniform sampler2D near_extra : filter_linear_mipmap, repeat_disable;
// R snow, G bare rock and scree, B forest, A gully wetness (8 m).
uniform sampler2D far_masks : filter_linear_mipmap, repeat_disable;
uniform vec4 near_rect;   // origin x, origin z, cell (m), samples
uniform vec4 far_rect;
uniform vec4 mask_rect;
uniform float water_level = 0.72;

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

// 0..1, how densely grass grows by the same weights (and control B forest
// floor, far R snow) and the height above the lake. The height-aware blend
// lets stones through at low weights, so grass gives way early. The grass
// shader grows its blades by it; the terrain shades the ground under them.
float grass_cover(vec4 control, vec4 extra, vec4 far, float slope, float above) {
	float bare = bare_ground(control, extra, far, slope);
	float d = 1.0 - smoothstep(0.02, 0.2, bare);
	d *= 1.0 - 0.75 * smoothstep(0.1, 0.8, control.b);
	d *= 1.0 - smoothstep(0.15, 0.5, far.r);
	return d * smoothstep(0.08, 0.45, above);
}
