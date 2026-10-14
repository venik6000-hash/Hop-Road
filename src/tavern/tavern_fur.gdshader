shader_type spatial;
// The hair of the hides on the tavern's floor (tools/pipeline/tavern/
// props_dressing.fur_rug). The hide is one light mesh; TavernDressing draws
// it again and again as shells, each a step further out along the hair
// (INSTANCE_CUSTOM.x: 0 the skin, 1 the tips), and every shell keeps only
// the pixels a strand passes through at its height.
//
// COLOR.rg is the way the hair lies over the floor (the table's x and y,
// about 0.5; shorter where neighbours disagree and the hair stands), COLOR.b
// how long it is of `fur_length`, COLOR.a how near the hide's edge, where
// the tips are palest. Strands are told apart by where they root, so they
// stay put whatever shell shows them; toward its tip each leans to the
// middle of its tuft and thins.
render_mode cull_back, depth_draw_opaque, world_vertex_coords;

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
// R the hide's outline, G how deep a spot lies among its folds.
uniform sampler2D mask_map : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float albedo_gain = 1.0;
uniform float normal_strength = 0.6;
uniform float roughness_value = 0.8;
// The tips' colour, and how much of it they take in the middle of the hide and at its edge.
uniform vec3 tip_color = vec3(0.8, 0.7, 0.55);
uniform float tip_inside = 0.25;
uniform float tip_edge = 0.9;
// Metres of hair; how far it leans off the skin at the root and how much further by the tip (radians).
uniform float fur_length = 0.06;
uniform float fur_lean = 0.9;
uniform float fur_droop = 0.45;
// Metres between strands, and between the tufts they gather into; how far a tip is drawn to its tuft.
uniform float strand_cell = 0.0035;
uniform float tuft_cell = 0.03;
uniform float tuft_pull = 0.55;
// How dark it is down among the roots.
uniform float root_shade = 0.3;
uniform float fur_wrap = 0.45;
// How many shells the hide is drawn in (TavernDressing sets it).
uniform float shells = 20.0;
uniform float tip_sheen = 0.5;
// How many strands (strand_cell) a pixel spans where the hair begins to close into a mat, and where it has.
uniform float mat_from = 0.5;
uniform float mat_to = 1.4;

varying vec3 root;
varying float shell;
varying float rim_side;
varying float sun_vis;
varying float tips;
// Metres over the floor a strand moves from one shell to the next.
varying vec2 drift;

void vertex() {
	root = VERTEX;
	shell = INSTANCE_CUSTOM.x;
	rim_side = COLOR.a;
	sun_vis = cloud_sun_visibility(root);
	vec2 lie = COLOR.rg * 2.0 - 1.0;
	vec3 skin = normalize(NORMAL);
	vec3 way = (MODEL_MATRIX * vec4(lie.x, 0.0, -lie.y, 0.0)).xyz;
	way -= skin * dot(way, skin);
	float lying = min(length(way), 1.0);
	way = lying > 0.001 ? way / length(way) : vec3(0.0);
	float off = (fur_lean + fur_droop * shell) * lying;
	drift = way.xz * sin((fur_lean + fur_droop * 0.5) * lying) * fur_length * COLOR.b / shells;
	VERTEX += (skin * cos(off) + way * sin(off)) * fur_length * COLOR.b * shell;
}

vec3 dice(vec2 cell) {
	uvec2 q = uvec2(ivec2(cell)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return vec3(float(n >> 8u), float((n * 16807u) >> 8u), float((n * 48271u) >> 8u)) / 16777216.0;
}

void fragment() {
	vec3 hide = texture(mask_map, UV).rgb;
	if (hide.r < 0.5) {
		discard;
	}
	vec3 own = vec3(0.5);
	float along = 0.0;
	if (shell > 0.001) {
		vec2 at = root.xz;
		vec2 tuft = floor(at / tuft_cell);
		vec3 lot = dice(tuft);
		vec2 middle = (tuft + 0.25 + 0.5 * lot.xy) * tuft_cell;
		float drawn = tuft_pull * shell * shell;
		vec2 q = (at - middle * drawn) / (1.0 - drawn) / strand_cell;
		own = dice(floor(q));
		along = shell / (mix(0.45, 1.0, own.x) * mix(0.75, 1.0, lot.z));
		vec2 from_axis = fract(q) - 0.5 - (own.yz - 0.5) * 0.4;
		float wide = 0.5 * sqrt(max(1.0 - along, 0.0)) + 0.08;
		// A lying strand crosses a shell aslant: its cut is drawn out along the lie
		// by the step to the next shell, so the cuts join into a hair.
		float step_cells = length(drift) / strand_cell;
		vec2 lie = step_cells > 0.001 ? drift / (step_cells * strand_cell) : vec2(1.0, 0.0);
		float fore = dot(from_axis, lie);
		vec2 aside = from_axis - lie * fore;
		float cut = fore * fore / ((wide + 0.6 * step_cells) * (wide + 0.6 * step_cells)) + dot(aside, aside) / (wide * wide);
		float near = step(cut, 1.0) * step(along, 1.0);
		// Strands finer than a pixel would only sparkle: far off, the lower
		// shells close into a mat and the upper ones are left out. The cells
		// are a lattice, and one a pixel wide beats against the pixels in dots.
		float cells = sqrt(length(dFdx(at)) * length(dFdy(at))) / strand_cell;
		float coarse = smoothstep(mat_from, mat_to, cells);
		if (mix(near, step(shell, 0.55), coarse) < 0.5) {
			discard;
		}
		// What is left must not speckle either: by the middle of that range
		// each strand's length and tone give way to the mean of the strands
		// (0.63 of the hair's length, a tone of 0.5).
		float even = smoothstep(mat_from, 0.5 * (mat_from + mat_to), cells);
		own = mix(own, vec3(0.5), even);
		along = mix(along, shell / 0.63, even);
	}
	float up = clamp(along, 0.0, 1.0);
	tips = shell;
	vec3 base = texture(albedo_map, UV).rgb * tint * albedo_gain;
	base = mix(base, tip_color * mix(0.8, 1.2, own.z), smoothstep(0.35, 1.0, up) * mix(tip_inside, tip_edge, rim_side * rim_side));
	base *= mix(0.8, 1.2, own.y) * mix(root_shade, 1.0, pow(shell, 0.7)) * mix(0.7, 1.0, hide.g);
	ALBEDO = base;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}

void light() {
	// Hair scatters: the light comes round the pile, and tips looked at
	// along the hide catch it.
	float lit = clamp((dot(NORMAL, LIGHT) + fur_wrap) / (1.0 + fur_wrap), 0.0, 1.0);
	vec3 shade = vec3(1.0);
	if (LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999) {
		shade = vec3(sun_vis);
	}
	vec3 come = LIGHT_COLOR * shade * ATTENUATION * lit;
	DIFFUSE_LIGHT += come / PI;
	float glance = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	SPECULAR_LIGHT += come * ALBEDO * tip_sheen * tips * glance * glance * glance;
}
