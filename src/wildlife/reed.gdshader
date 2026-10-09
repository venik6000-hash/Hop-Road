shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Reed stands at the lake shore (tools/pipeline/lakebed): stems with vertex
// colours, alpha the height fraction. They stand with their feet in the
// water, so the lower stems take the lake's underwater light while the stand
// above bends in the same wind as the trees and grass.
#include "res://src/vegetation/shaders/vegetation.gdshaderinc"
#include "res://src/water/underwater_light.gdshaderinc"

uniform float water_level = 0.72;
uniform float plant_height = 2.2;
varying vec3 world_pos;
varying vec3 sun_under;
varying float sun_vis;
varying vec3 tint;

void vertex() {
	vec3 anchor = MODEL_MATRIX[3].xyz;
	float phase = anchor.x * 0.37 + anchor.z * 0.29;
	float tip = COLOR.a;
	float bend = tip * tip;
	float gust = wind_strength(anchor.xz, TIME);
	// Steady lean downwind, plus the stems whipping back as gusts pass.
	float sway = 0.04 + 0.22 * gust + 0.05 * sin(TIME * 1.9 + phase) * (0.4 + gust);
	float flutter = sin(TIME * 3.4 + phase + tip * 4.0) * 0.012 * (0.3 + gust);
	vec3 along = vec3(wind.x, 0.0, wind.y);
	VERTEX.xz += (along.xz * sway + vec2(-wind.y, wind.x) * flutter) * bend * plant_height;
	VERTEX.y -= sway * sway * bend * plant_height * 0.5;
	tint = COLOR.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sun_vis = cloud_sun_visibility(world_pos);
}

void fragment() {
	// Private underwater capture camera; discard above-water fragments only there.
	if (CAMERA_VISIBLE_LAYERS == 262144u && world_pos.y > water_level + 0.4) { discard; }
	ALBEDO = tint;
	sun_under = vec3(1.0);
	float depth = water_level - world_pos.y;
	// The drowned stems mirror nothing (see underwater_life.gdshader).
	float submerged = smoothstep(-0.05, 0.3, depth);
	ROUGHNESS = mix(0.6, 1.0, submerged);
	SPECULAR = 0.2 * (1.0 - submerged);
	if (depth > 0.0) ALBEDO *= underwater_light(world_pos.xz, depth, length(world_pos - CAMERA_POSITION_WORLD), 1.0, sun_under);
}

void light() {
	vec3 color = LIGHT_COLOR * (LIGHT_IS_DIRECTIONAL ? sun_under : vec3(1.0));
	foliage_light(NORMAL, LIGHT, VIEW, color, ATTENUATION, LIGHT_IS_DIRECTIONAL, sun_vis, 0.3, 0.45, ROUGHNESS, 0.04,
		DIFFUSE_LIGHT, SPECULAR_LIGHT);
}
