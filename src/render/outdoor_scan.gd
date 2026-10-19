extends RefCounted
## Materials of outdoor_scan.gdshaderinc for models that came with a plain
## one: the clouds' and the crowns' shadow and the rain reach them. Every
## mesh that stands outdoors goes through here (tests/test_world_start.gd
## checks the built level; what keeps a StandardMaterial3D, and why, is
## listed there).

const SHADER := preload("res://src/render/outdoor_scan.gdshader")
const CULLED := preload("res://src/render/outdoor_scan_culled.gdshader")
const CUTOUT := preload("res://src/render/outdoor_scan_cutout.gdshader")
## Every shader of these materials: none reads the object's origin, so a
## batch may draw them as instances (TavernBatching).
const SHADERS: Array[Shader] = [SHADER, CULLED, CUTOUT]
## The colours of an unlit scan hold the light it was shot in as much as its
## surface: its sunlit parts are several times brighter than anything of the
## valley's. This share of them (in linear light) is its albedo here.
const UNLIT_GRADE := 0.4
## How much of the rain's film shines on a prop of wood, stone or metal, and
## on one of cloth, straw or fur, which soaks.
const PROP_SHINE := 1.0
const SOAKED_SHINE := 0.0

static var _materials := {}

## The look of the scan `original` (its colour, relief and roughness) on the
## shader; the same material for every use of the same original. wet_shine:
## how much of the rain's film shines on it (0 for fur and feathers).
static func material(original: StandardMaterial3D, wet_shine := 1.0) -> ShaderMaterial:
	var key := [original, wet_shine]
	if not _materials.has(key):
		_materials[key] = _scan(original, wet_shine)
	return _materials[key]

## The whole look of the prop `original` (StandardMaterial3D as authored: its
## maps, metal, occlusion, texture scale, faces and cut-out) on the shader;
## the same material for every use of the same original. Only for a
## material that takes() says the shader draws.
static func prop(original: StandardMaterial3D, wet_shine := PROP_SHINE) -> ShaderMaterial:
	var key := [original, wet_shine, &"prop"]
	if not _materials.has(key):
		_materials[key] = unshared(original, wet_shine)
	return _materials[key]

## As prop(), a material of its own: for a piece made in code whose look
## changes while it stands (set its "tint"), so that no store keeps it.
static func unshared(original: StandardMaterial3D, wet_shine := PROP_SHINE) -> ShaderMaterial:
	var made := _scan(original, wet_shine)
	if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		made.shader = CUTOUT
		made.set_shader_parameter("alpha_scissor", original.alpha_scissor_threshold)
	elif original.cull_mode == BaseMaterial3D.CULL_BACK:
		made.shader = CULLED
	made.set_shader_parameter("specular_value", original.metallic_specular)
	made.set_shader_parameter("metallic_value", original.metallic)
	made.set_shader_parameter("uv_scale", original.uv1_scale)
	made.set_shader_parameter("uv_offset", original.uv1_offset)
	made.set_shader_parameter("roughness_channel", _mask(original.roughness_texture_channel))
	if original.metallic_texture != null:
		made.set_shader_parameter("metallic_map", original.metallic_texture)
		made.set_shader_parameter("metallic_channel", _mask(original.metallic_texture_channel))
	if original.ao_enabled and original.ao_texture != null:
		made.set_shader_parameter("ao_map", original.ao_texture)
		made.set_shader_parameter("ao_channel", _mask(original.ao_texture_channel))
	if not original.normal_enabled:
		made.set_shader_parameter("normal_map", null)
	return made

## Whether the shader draws `original` as the engine would: lit, opaque or
## cut out, with no glow, no vertex colours and none of the layers it does
## not know. A glass, a flame, a glowing ember or an unlit line keeps its own.
static func takes(original: StandardMaterial3D) -> bool:
	return original.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and not original.emission_enabled \
		and original.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] \
		and original.cull_mode != BaseMaterial3D.CULL_FRONT and not original.vertex_color_use_as_albedo \
		and not original.uv1_triplanar and not original.detail_enabled and not original.heightmap_enabled \
		and not original.rim_enabled and not original.clearcoat_enabled and not original.anisotropy_enabled \
		and not original.subsurf_scatter_enabled and not original.backlight_enabled and not original.refraction_enabled \
		and original.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and original.next_pass == null

## Every StandardMaterial3D of the meshes of `root` (it among them) that the
## shader takes goes onto it: the rain wets the piece, the clouds and the
## crowns shade it. `share`: the materials of a model loaded from a file are
## shared by every copy of it (prop()); a piece made in code gets its own
## (unshared()), so that no store keeps it after it is gone.
static func dress(root: Node, wet_shine := PROP_SHINE, share := true) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	meshes.append(root)
	for node: Node in meshes:
		var item := node as MeshInstance3D
		if item == null or item.mesh == null:
			continue
		var whole := item.material_override as StandardMaterial3D
		if whole != null:
			if takes(whole):
				item.material_override = prop(whole, wet_shine) if share else unshared(whole, wet_shine)
			continue
		for surface in item.mesh.get_surface_count():
			var original := item.get_active_material(surface) as StandardMaterial3D
			if original != null and takes(original):
				item.set_surface_override_material(surface, prop(original, wet_shine) if share else unshared(original, wet_shine))

static func _scan(original: StandardMaterial3D, wet_shine: float) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = SHADER
	made.set_shader_parameter("wet_shine", wet_shine)
	var tint := original.albedo_color
	if original.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		var graded := tint.srgb_to_linear()
		tint = Color(graded.r * UNLIT_GRADE, graded.g * UNLIT_GRADE, graded.b * UNLIT_GRADE, tint.a).linear_to_srgb()
	made.set_shader_parameter("tint", tint)
	made.set_shader_parameter("roughness_value", original.roughness)
	made.set_shader_parameter("normal_strength", original.normal_scale)
	# A map the original has not keeps the shader's default: white, flat.
	for pair: Array in [["albedo_map", original.albedo_texture], ["normal_map", original.normal_texture],
			["roughness_map", original.roughness_texture]]:
		if pair[1] != null:
			made.set_shader_parameter(StringName(str(pair[0])), pair[1])
	return made

## The mask of a BaseMaterial3D.TextureChannel, as the engine's materials
## read it.
static func _mask(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Vector4(1.0, 1.0, 1.0, 0.0) / 3.0
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0.0, 0.0, 0.0, 1.0)
	return Vector4(1.0, 0.0, 0.0, 0.0)
