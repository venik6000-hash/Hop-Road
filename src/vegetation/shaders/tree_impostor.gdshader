shader_type spatial;
// Distant trees: an upright quad turned toward the camera, textured with the
// two nearest of eight azimuthal views baked in Blender
// (tools/pipeline/vegetation/render_impostors.py, packed into arrays by
// tools/pipeline/vegetation/impostor_arrays.py). The views carry albedo *
// crown AO and the object-space normal, so the crowns light like the mesh
// LODs.
// INSTANCE_CUSTOM is (seed, species, crown widening, 0).
render_mode cull_disabled, depth_draw_opaque, world_vertex_coords;

#include "res://src/vegetation/shaders/vegetation.gdshaderinc"

const float VIEWS = 8.0;

uniform sampler2DArray impostor_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2DArray impostor_normal : filter_linear_mipmap_anisotropic, repeat_disable;
// Per species: frame width, frame height, frame bottom (m at scale 1), look
// group (TreePlacer.SPECIES_GROUP).
uniform vec4 frames[9];
// Fade-in start, fade-in end, fade-out start, fade-out end (m).
uniform vec4 lod_range;
// As the mesh foliage materials, per look group.
uniform float leaf_wrap[3];
uniform float leaf_transmission[3];
uniform vec3 leaf_tint[3];
uniform float leaf_ambient[3];

varying vec2 quad_uv;
varying flat float layer;
varying flat float group;
varying flat float view_a;
varying flat float view_b;
varying flat float view_t;
varying flat float yaw;
varying flat float tree_seed;
varying float lod_fade;
varying flat float fading_in;
varying float sun_vis;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	int species = clamp(int(INSTANCE_CUSTOM.y + 0.5), 0, 8);
	vec4 frame = frames[species];
	group = frame.w;
	float dist = distance(origin.xz, lod_camera.xz);
	lod_fade = lod_weight(dist, lod_range);
	fading_in = dist < lod_range.y ? 1.0 : 0.0;
	tree_seed = INSTANCE_CUSTOM.x;
	layer = float(species);
	// Model basis z column is (sin yaw, 0, cos yaw) * scale.
	yaw = atan(MODEL_MATRIX[2].x, MODEL_MATRIX[2].z);
	vec2 to_eye = CAMERA_POSITION_WORLD.xz - origin.xz;
	float along = length(to_eye);
	vec2 d = along > 1e-3 ? to_eye / along : vec2(0.0, 1.0);
	// View k was shot from azimuth k * 45 degrees in model space.
	float view = mod((atan(d.x, d.y) - yaw) / (TAU / VIEWS), VIEWS);
	view_a = floor(view);
	view_b = mod(view_a + 1.0, VIEWS);
	view_t = view - view_a;
	vec3 right = vec3(d.y, 0.0, -d.x);
	// world_vertex_coords: VERTEX arrives transformed; the quad corner is in UV.
	float across = (UV.x - 0.5) * frame.x * scale * INSTANCE_CUSTOM.z;
	float up = (frame.z + (1.0 - UV.y) * frame.y) * scale;
	VERTEX = lod_fade > 0.0 ? origin + right * across + vec3(0.0, up, 0.0) : origin;
	NORMAL = vec3(d.x, 0.0, d.y);
	quad_uv = UV;
	sun_vis = cloud_sun_visibility(origin + vec3(0.0, frame.y * scale * 0.5, 0.0));
}

void fragment() {
	vec2 frag = FRAGCOORD.xy + floor(fract(TIME * 7.31) * 64.0) * vec2(5.588238, 3.169421);
	if (lod_dither_discard(lod_fade, fading_in > 0.5, frag)) {
		discard;
	}
	vec3 uv_a = vec3((view_a + quad_uv.x) / VIEWS, quad_uv.y, layer);
	vec3 uv_b = vec3((view_b + quad_uv.x) / VIEWS, quad_uv.y, layer);
	vec4 albedo = mix(texture(impostor_albedo, uv_a), texture(impostor_albedo, uv_b), view_t);
	vec3 n_model = mix(texture(impostor_normal, uv_a).rgb, texture(impostor_normal, uv_b).rgb, view_t) * 2.0 - 1.0;
	float c = cos(yaw);
	float s = sin(yaw);
	vec3 n_world = normalize(vec3(c * n_model.x + s * n_model.z, n_model.y, -s * n_model.x + c * n_model.z));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float level = max(textureQueryLod(impostor_albedo, uv_a.xy).y, 0.0);
	ALPHA = albedo.a * (1.0 + 0.3 * level);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	int look = int(group + 0.5);
	ALBEDO = albedo.rgb * mix(vec3(0.9, 0.96, 1.0), vec3(1.08, 1.03, 0.9), tree_seed) * leaf_tint[look];
	ROUGHNESS = 0.75;
	// No reflection of the sky, as on the mesh LODs (see tree.gdshaderinc).
	SPECULAR = 0.0;
	AO = leaf_ambient[look];
}

void light() {
	bool is_sun = light_is_sun(LIGHT_IS_DIRECTIONAL, LIGHT, INV_VIEW_MATRIX);
	int look = int(group + 0.5);
	foliage_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, is_sun, sun_vis,
		leaf_wrap[look], leaf_transmission[look], ROUGHNESS, 0.03, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}
