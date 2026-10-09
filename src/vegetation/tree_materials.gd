extends RefCounted
## The bark, foliage and impostor materials of VegetationSystem (static
## functions over the VegetationSystem `system`, which holds the materials).

const BARK_SHADER := preload("res://src/vegetation/shaders/tree_bark.gdshader")
const FOLIAGE_SHADER := preload("res://src/vegetation/shaders/tree_foliage.gdshader")
const IMPOSTOR_SHADER := preload("res://src/vegetation/shaders/tree_impostor.gdshader")
const TEXTURES := "res://assets/models/vegetation/textures/"
## Per look group (TreePlacer.SPECIES_GROUP): bark texture set and its file
## type, leaf atlas, broadleaf gloss.
const GROUPS := [
	["conifer_bark", ".jpg", "conifer_twig", false],
	["broadleaf_bark", ".png", "broadleaf_leaves", true],
	["pine_bark", ".jpg", "pine_twig", false],
]
## Foliage light per group: wrap, transmission, tint, sky light inside the
## crown. That light is all the shade of a crown gets: the leaves do not
## mirror the sky (see tree.gdshaderinc).
const FOLIAGE_LOOK := [
	[0.2, 0.25, Vector3(0.78, 0.84, 0.84), 0.75],
	[0.2, 0.25, Vector3(0.6, 0.68, 0.55), 0.75],
	[0.2, 0.25, Vector3(0.66, 0.86, 0.8), 0.75],
]

# --- materials ----------------------------------------------------------------

static func make(system: VegetationSystem) -> void:
	var wind_noise := load("res://assets/generated/sky/cloud_weather.png")
	for group: Array in GROUPS:
		system.bark_materials.append(bark_material(group[0], group[1]))
		var foliage := ShaderMaterial.new()
		foliage.shader = FOLIAGE_SHADER
		foliage.set_shader_parameter("albedo_texture", load(TEXTURES + str(group[2]) + "_albedo.png"))
		foliage.set_shader_parameter("broadleaf", group[3])
		system.foliage_materials.append(foliage)
	# A pine's trunk is a scan with its own unwrap: one material per tree.
	for kind in TreePlacer.SPECIES_NAMES.size():
		if TreePlacer.SPECIES_GROUP[kind] == TreePlacer.GROUP_PINE:
			var trunk := str(TreePlacer.SPECIES_NAMES[kind]).replace("pine_", "pine_trunk_")
			system.trunk_materials[kind] = bark_material(trunk, ".jpg")
	set_foliage_look(system, FOLIAGE_LOOK)
	system.impostor_material.shader = IMPOSTOR_SHADER
	system.impostor_material.set_shader_parameter("impostor_albedo", load("res://assets/generated/vegetation/impostor_albedo.png"))
	system.impostor_material.set_shader_parameter("impostor_normal", load("res://assets/generated/vegetation/impostor_normal.png"))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/vegetation/impostors.json"))
	for kind in meta.species.size():
		var frame: Dictionary = meta.species[kind]
		system.impostor_frames.append(Vector4(frame.width_m, frame.height_m, frame.bottom_m,
			TreePlacer.SPECIES_GROUP[kind]))
		system.crowns.append(Vector2(frame.crown_radius_m, VegetationSystem.CROWN_SHADE[TreePlacer.SPECIES_GROUP[kind]]))
	system.impostor_material.set_shader_parameter("frames", system.impostor_frames)
	system.impostor_material.set_shader_parameter("lod_range", VegetationSystem.IMPOSTOR_RANGE)
	for material in all_materials(system):
		material.set_shader_parameter("wind_noise", wind_noise)
		material.set_shader_parameter("cloud_weather", wind_noise)

static func bark_material(textures: String, extension: String) -> ShaderMaterial:
	var bark := ShaderMaterial.new()
	bark.shader = BARK_SHADER
	bark.set_shader_parameter("albedo_texture", load(TEXTURES + textures + "_diff" + extension))
	bark.set_shader_parameter("normal_texture", load(TEXTURES + textures + "_nor_gl" + extension))
	bark.set_shader_parameter("arm_texture", load(TEXTURES + textures + "_arm" + extension))
	return bark

## Applies [wrap, transmission, tint, ambient] per group to the mesh foliage
## and the impostors alike, so both LOD families light the same. Groups left
## out of `look` keep FOLIAGE_LOOK.
static func set_foliage_look(system: VegetationSystem, look: Array) -> void:
	var wrap := PackedFloat32Array()
	var transmission := PackedFloat32Array()
	var tint := PackedVector3Array()
	var ambient := PackedFloat32Array()
	for group in GROUPS.size():
		var values: Array = look[group] if group < look.size() else FOLIAGE_LOOK[group]
		system.foliage_materials[group].set_shader_parameter("leaf_wrap", values[0])
		system.foliage_materials[group].set_shader_parameter("leaf_transmission", values[1])
		system.foliage_materials[group].set_shader_parameter("leaf_tint", values[2])
		system.foliage_materials[group].set_shader_parameter("leaf_ambient", values[3])
		wrap.append(values[0])
		transmission.append(values[1])
		tint.append(values[2])
		ambient.append(values[3])
	system.impostor_material.set_shader_parameter("leaf_wrap", wrap)
	system.impostor_material.set_shader_parameter("leaf_transmission", transmission)
	system.impostor_material.set_shader_parameter("leaf_tint", tint)
	system.impostor_material.set_shader_parameter("leaf_ambient", ambient)

static func all_materials(system: VegetationSystem) -> Array[ShaderMaterial]:
	var all: Array[ShaderMaterial] = []
	all.append_array(system.bark_materials)
	for trunk: ShaderMaterial in system.trunk_materials.values():
		all.append(trunk)
	all.append_array(system.foliage_materials)
	all.append(system.impostor_material)
	return all
