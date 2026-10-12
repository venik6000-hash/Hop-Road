extends RefCounted
## Materials of outdoor_scan.gdshader for models that came with a plain one.

const SHADER := preload("res://src/render/outdoor_scan.gdshader")
## The colours of an unlit scan hold the light it was shot in as much as its
## surface: its sunlit parts are several times brighter than anything of the
## valley's. This share of them (in linear light) is its albedo here.
const UNLIT_GRADE := 0.4

static var _materials := {}

## The look of `original` (its colour, relief and roughness) on the shader;
## the same material for every use of the same original. wet_shine: how much
## of the rain's film shines on it (0 for fur and feathers).
static func material(original: StandardMaterial3D, wet_shine := 1.0) -> ShaderMaterial:
	var key := [original, wet_shine]
	if not _materials.has(key):
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
				made.set_shader_parameter(pair[0], pair[1])
		made.set_shader_parameter("cloud_weather", load("res://assets/generated/sky/cloud_weather.png"))
		_materials[key] = made
	return _materials[key]
