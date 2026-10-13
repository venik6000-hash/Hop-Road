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
// A fine normal map (generated: tools/pipeline/tavern/detail_textures.py) laid
// over the scan's, for the grain the scan smooths away up close: wood's pores,
// stone's pits, cloth's weave. `detail_scale` is its repeats per metre of UV,
// `detail_strength` how much it tilts the surface (0: none, and no read at all,
// the default); it is full inside `DETAIL_NEAR` metres of the eye and gone by
// `DETAIL_FAR`, where it would only shimmer.
uniform sampler2D detail_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 2.5;
uniform float detail_strength = 0.0;
// 1 where the scan's grain runs along u: the detail is laid a quarter turn round.
uniform float detail_turn = 0.0;
const float DETAIL_NEAR = 2.5;
const float DETAIL_FAR = 7.0;
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
// The rooms (COLOR.a = 0), by what years of fires, boots and sleeves leave:
// smoke under each storey's ceiling and over the fires, a dark foot to the
// walls, floors polished where they are walked and dull with dust where they
// are not, furniture rubbed to a patchy shine. All off (0) for a building
// whose table does not ask for them.
uniform vec3 indoor_tint = vec3(1.0);
uniform float soot = 0.0;
uniform float indoor_grime = 0.0;
uniform float wear = 0.0;
uniform float handled = 0.0;
// Dirt and shadow deep in the joints and chips of old masonry (the scan's
// occlusion, pressed harder).
uniform float crevice = 0.0;
// Heights of the floors, lowest first, and of the ridge.
uniform vec4 storeys = vec4(-1000.0, 2000.0, 3000.0, 4000.0);
// The fires that smoke: where (xyz) and how much (w).
uniform vec4 fires[4];
// The ground floor from above: R how much a spot is walked, G how much dust
// lies there (tavern_wear.gd). `floor_wear_rect` is its corner (xz) and 1 / size.
uniform sampler2D floor_wear : hint_default_black, filter_linear, repeat_disable;
uniform vec4 floor_wear_rect = vec4(0.0, 0.0, 0.0, 0.0);
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
	// The detail's coordinates and their slopes are taken here, where every
	// pixel passes; its read below sits in a branch and takes them as given.
	vec2 detail_uv = (detail_turn > 0.5 ? UV.yx : UV) * detail_scale;
	vec2 detail_dx = dFdx(detail_uv);
	vec2 detail_dy = dFdy(detail_uv);
	float detail_fade = detail_strength * (1.0 - smoothstep(DETAIL_NEAR, DETAIL_FAR, length(VERTEX)));
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

	if (open < 0.5) {
		base *= indoor_tint;
		// A floor's boards belong to the storey above them, the boards of a
		// ceiling to the one below.
		float level = world_pos.y + n.y * 0.06;
		float low = storeys.x;
		float high = storeys.y;
		if (level > storeys.y) {
			low = storeys.y;
			high = storeys.z;
		}
		if (level > storeys.z) {
			low = storeys.z;
			high = storeys.w;
		}
		vec4 stain = texture(cloud_weather, world_pos.xz * 0.31 + world_pos.y * vec2(0.17, 0.11));
		base *= mix(1.0, smoothstep(0.2, 0.95, orm.r) * 0.85 + 0.15, crevice);
		if (soot > 0.0) {
			float up = clamp((level - low) / (high - low), 0.0, 1.0);
			float smoke = smoothstep(0.5, 1.0, up + (stain.g - 0.5) * 0.45) * (1.0 - max(n.y, 0.0));
			for (int i = 0; i < 4; i++) {
				vec3 over = world_pos - fires[i].xyz;
				float rise = max(over.y, 0.0);
				float reach = 0.5 + rise * 0.45;
				smoke += fires[i].w * smoothstep(-0.3, 0.5, over.y) * exp(-dot(over.xz, over.xz) / (reach * reach))
					/ (1.0 + rise * 0.6);
			}
			smoke = clamp(smoke * soot, 0.0, 0.92);
			base = mix(base, base * vec3(0.3, 0.28, 0.26), smoke);
			rough = mix(rough, 1.0, smoke * 0.6);
		}
		float kick = smoothstep(low + 0.75, low + 0.03, world_pos.y) * (1.0 - abs(n.y));
		base *= 1.0 - indoor_grime * kick * mix(0.3, 0.6, stain.b);
		if (handled > 0.0) {
			rough *= mix(1.0, 0.55, handled * smoothstep(0.35, 0.75, stain.r));
		}
		if (wear > 0.0 && n.y > 0.7) {
			vec2 at = (world_pos.xz - floor_wear_rect.xy) * floor_wear_rect.zw;
			// Only the ground floor has a map; the boards upstairs are walked thin and evenly.
			float mapped = step(level, storeys.y - 0.5) * step(0.0, at.x) * step(at.x, 1.0) * step(0.0, at.y)
				* step(at.y, 1.0);
			vec2 trod = mix(vec2(0.45, 0.25), texture(floor_wear, at).rg, mapped);
			float blot = texture(cloud_weather, world_pos.xz * 0.83).r;
			float fine = texture(cloud_weather, world_pos.xz * 3.1).g;
			// The hall's boards run with z: years of sweeping, dragged benches and
			// the grain itself left them streaked along their length.
			float streak = texture(cloud_weather, vec2(world_pos.x * 2.7, world_pos.z * 0.16)).g;
			float scratch = texture(cloud_weather, vec2(world_pos.x * 9.0 + 0.3, world_pos.z * 0.31)).r;
			base *= mix(1.0, mix(0.7, 1.16, streak), mapped * wear);
			float polish = wear * smoothstep(0.3, 0.85, trod.r + (blot - 0.5) * 0.5 + (streak - 0.5) * 0.25 * mapped);
			rough = mix(rough, rough * mix(0.5, 0.78, fine), polish);
			// Walked bare: paler and greyer than the boards that kept their oil and dirt.
			vec3 bare = mix(base, vec3(dot(base, vec3(0.3, 0.59, 0.11))), 0.4) * vec3(1.75, 1.66, 1.52);
			base = mix(base, bare, polish * 0.85);
			base *= 1.0 + 0.3 * mapped * polish * smoothstep(0.62, 0.74, scratch);
			float dust = wear * smoothstep(0.35, 0.9, trod.g + (fine - 0.5) * 0.5);
			base *= 1.0 - 0.5 * dust;
			rough = mix(rough, 1.0, dust * 0.7);
			// What was spilt and never quite came out of the grain: dark, and slick where feet still pass.
			float spill = smoothstep(0.7, 0.8, texture(cloud_weather, world_pos.xz * 0.21 + vec2(0.37)).b);
			base *= 1.0 - 0.42 * spill * wear;
			rough = mix(rough, 0.3, spill * polish * 0.5);
		}
	}

	// Moss and lichen are looked up by the place on the map; up a wall the
	// lookup also moves along the map's diagonal x = z, or a wall would be one
	// line of the noise. A wall that runs along that very diagonal would be
	// such a line again, drawn as slanting stripes, so it climbs the other.
	float turned = 1.0 - smoothstep(-0.15, -0.02, n.x * n.z);
	vec2 climb = world_pos.y * vec2(1.0, -1.0);
	if (moss > 0.0 && open > 0.01) {
		float patch = mix(texture(cloud_weather, world_pos.xz / 3.1 + vec2(world_pos.y * 0.21)).g,
				texture(cloud_weather, world_pos.xz / 3.1 + climb * 0.21).g, turned);
		float cover = smoothstep(0.55, 0.95, n.y + (patch - 0.5) * 1.1 + (0.8 - orm.r) * 0.8) * moss * open;
		if (cover > 0.01) {
			vec3 green = grade(texture(moss_albedo, vec3(world_pos.xz / 2.4, moss_layer)).rgb, moss_grade);
			base = mix(base, green, cover);
			rough = mix(rough, 0.92, cover);
		}
	}
	if (lichen > 0.0 && open > 0.01) {
		float spots = mix(texture(cloud_weather, world_pos.xz * 0.9 + vec2(world_pos.y * 0.7)).r,
				texture(cloud_weather, world_pos.xz * 0.9 + climb * 0.7).r, turned);
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
	vec3 scan = texture(normal_map, uv).rgb;
	if (detail_fade > 0.0) {
		// Whiteout blend of the two tangent-space normals (z rebuilt from x and y
		// as the engine does, the maps may hold no blue). The depth below scales
		// the sum, so the detail is divided by it to keep its own strength.
		vec2 tilt = textureGrad(detail_map, detail_uv, detail_dx, detail_dy).xy * 2.0 - 1.0;
		tilt = (detail_turn > 0.5 ? tilt.yx : tilt) * (detail_fade / clamp(normal_strength, 0.3, 2.0));
		vec2 under = scan.xy * 2.0 - 1.0;
		vec3 blended = normalize(vec3(under + tilt, sqrt(max(1.0 - dot(under, under), 0.0))
				* sqrt(max(1.0 - dot(tilt, tilt), 0.0))));
		scan = vec3(blended.xy * 0.5 + 0.5, blended.z);
	}
	NORMAL_MAP = scan;
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
