shader_type spatial;
// Surfaces of the refined tavern (tools/pipeline/tavern/): Poly Haven scans on
// UVs laid out in metres, one material per entry of tavern.json.
//
// COLOR.rgb is the tint of the piece (each stone, beam or slate its own) over
// `color_range`; COLOR.a is how open to the weather the surface is (0 in the
// rooms), which gates the grime at the foot of the walls, moss and lichen.
// The sun is dimmed by cloud shadows like everything else outdoors.
render_mode cull_back, depth_draw_opaque;

global uniform vec3 sun_direction;
#include "res://src/sky/cloud_shadow.gdshaderinc"
#include "res://src/weather/wetness.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R ambient occlusion, G roughness, B metalness (Poly Haven "arm").
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float desaturate = 0.0;
uniform float albedo_gain = 1.0;
// Metres of surface one repeat of the texture covers.
uniform float uv_scale = 1.0;
uniform float normal_strength = 1.0;
uniform float roughness_scale = 1.0;
uniform float metallic_value = 0.0;
uniform float grime = 0.0;
uniform float moss = 0.0;
uniform float lichen = 0.0;
uniform float color_range = 2.0;
uniform float ground_level = 6.6;
// Moss is the terrain's mossy rock scan (a layer of its array).
uniform sampler2DArray moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_layer = 13.0;
uniform vec4 moss_grade = vec4(0.92, 1.03, 0.9, 1.05);

varying vec3 world_pos;
varying vec3 world_normal;
varying float sun_vis;
varying vec4 piece;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	sun_vis = cloud_sun_visibility(world_pos);
	piece = COLOR;
}

vec3 grade(vec3 c, vec4 g) {
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(luma), c, g.w) * g.rgb, vec3(0.0));
}

void fragment() {
	vec2 uv = UV / uv_scale;
	vec3 base = texture(albedo_map, uv).rgb;
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = mix(base, vec3(luma), desaturate) * tint * albedo_gain * piece.rgb * color_range;
	vec3 orm = texture(orm_map, uv).rgb;
	float rough = orm.g * roughness_scale;
	float open = piece.a;
	vec3 n = normalize(world_normal);

	// Weathering over metres: mottling from the sky's noise.
	vec4 weather = texture(cloud_weather, world_pos.xz * 0.045 + vec2(world_pos.y * 0.013));
	base *= mix(0.9, 1.08, weather.g);
	// Splashed dirt at the foot of the walls.
	float foot = smoothstep(ground_level + 1.3, ground_level + 0.05, world_pos.y) * (1.0 - max(n.y, 0.0) * 0.6);
	base *= 1.0 - grime * foot * mix(0.3, 0.55, weather.b) * open;

	if (moss > 0.0 && open > 0.01) {
		float patch = texture(cloud_weather, world_pos.xz / 3.1 + vec2(world_pos.y * 0.21)).g;
		float cover = smoothstep(0.55, 0.95, n.y + (patch - 0.5) * 1.1 + (0.8 - orm.r) * 0.8) * moss * open;
		if (cover > 0.01) {
			vec3 green = grade(texture(moss_albedo, vec3(world_pos.xz / 2.4, moss_layer)).rgb, moss_grade);
			base = mix(base, green, cover);
			rough = mix(rough, 0.92, cover);
		}
	}
	if (lichen > 0.0 && open > 0.01) {
		float spots = texture(cloud_weather, world_pos.xz * 0.9 + vec2(world_pos.y * 0.7)).r;
		float cover = smoothstep(0.6, 0.68, spots) * smoothstep(-0.2, 0.4, n.y) * lichen * open;
		base = mix(base, vec3(0.5, 0.46, 0.27) * (0.8 + 0.4 * spots), cover);
	}

	// Rain: the wet film, and puddles on level faces at the ground, in the
	// joints first.
	float flooded = 0.0;
	float rained = 0.0;
	if (rain_is_wet() && open > 0.01) {
		float reach = rain_reach(world_pos, n) * open;
		rained = rain_film(reach);
		wet_surface(rained, metallic_value, base, rough);
		float level = smoothstep(0.97, 0.995, n.y) * (1.0 - smoothstep(ground_level + 0.35, ground_level + 0.7, world_pos.y));
		if (level > 0.0) {
			float hollow = texture(cloud_weather, world_pos.xz / 6.3).g * 0.75 + (1.0 - orm.r) * 0.5;
			flooded = puddle_cover(level, hollow) * reach;
			puddle_surface(flooded, base, rough);
		}
	}

	ALBEDO = base;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metallic_value;
	SPECULAR = 0.4 * wet_specular(max(rained, flooded), reflect(normalize(world_pos - CAMERA_POSITION_WORLD), n).y);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = texture(normal_map, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - flooded);
}

void light() {
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Neither term contributes for a back-facing or fully shadowed light.
	if (n_dot_l > 0.0 && ATTENUATION > 0.0) {
		// Cloud shadows belong to the sun alone.
		vec3 shade = vec3(1.0);
		if (LIGHT_IS_DIRECTIONAL && dot((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz, sun_direction) > 0.999) {
			shade = vec3(sun_vis);
		}
		DIFFUSE_LIGHT += LIGHT_COLOR * shade * ATTENUATION * n_dot_l / PI;
		vec3 h = normalize(VIEW + LIGHT);
		float n_dot_h = clamp(dot(NORMAL, h), 0.0, 1.0);
		float n_dot_v = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
		float a = ROUGHNESS * ROUGHNESS;
		float a2 = a * a;
		float denominator = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
		float d = a2 / (PI * denominator * denominator);
		float k = a * 0.5;
		float vis = 0.25 / ((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k));
		vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
		float grazing = 1.0 - clamp(dot(VIEW, h), 0.0, 1.0);
		float grazing2 = grazing * grazing;
		vec3 fresnel = f0 + (1.0 - f0) * grazing2 * grazing2 * grazing;
		SPECULAR_LIGHT += LIGHT_COLOR * shade * ATTENUATION * n_dot_l * d * vis * fresnel;
	}
}
