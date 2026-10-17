extends RefCounted
## The bark, foliage and impostor materials of VegetationSystem (static
## functions over the VegetationSystem `system`, which holds the materials).

const BARK_SHADER := preload("res://src/vegetation/shaders/tree_bark.gdshader")
const FOLIAGE_SHADER := preload("res://src/vegetation/shaders/tree_foliage.gdshader")
const IMPOSTOR_SHADER := preload("res://src/vegetation/shaders/tree_impostor.gdshader")
const TEXTURES := "res://assets/models/vegetation/textures/"
## The sizes of the impostors (WorldSchemas.impostors).
const IMPOSTORS := "res://assets/generated/vegetation/impostors.json"
## Per look group (TreePlacer.SPECIES_GROUP): bark texture set and its file
## type, leaf atlas, broadleaf gloss.
const GROUPS := [
	["conifer_bark", ".jpg", "conifer_twig", false],
	["broadleaf_bark", ".png", "broadleaf_leaves", true],
	["pine_bark", ".jpg", "pine_twig", false],
]
## Species whose trunk is a scan with its own unwrap, and that scan: the
## spruces and the fir are built on the same three trunks as the pines
## (tools/pipeline/vegetation/build_scan_trees.py).
const TRUNKS := {
	TreePlacer.SPRUCE_A: "pine_trunk_a", TreePlacer.SPRUCE_B: "pine_trunk_b", TreePlacer.SPRUCE_C: "pine_trunk_a",
	TreePlacer.FIR_YOUNG: "pine_trunk_b",
	TreePlacer.PINE_A: "pine_trunk_a", TreePlacer.PINE_B: "pine_trunk_b", TreePlacer.PINE_C: "pine_trunk_c",
}
## Foliage light per group: wrap, transmission, tint, sky light inside the
## crown. That light is all the shade of a crown gets: the leaves do not
## mirror the sky (see tree.gdshaderinc).
const FOLIAGE_LOOK := [
	[0.18, 0.2, Vector3(0.52, 0.57, 0.45), 0.56],
	[0.18, 0.2, Vector3(0.44, 0.49, 0.36), 0.58],
	[0.18, 0.2, Vector3(0.48, 0.58, 0.46), 0.56],
]

## How far the rain wets leaves and needles against open ground: the mesh
## foliage and the impostors take the same, so the wood darkens as one.
const RAIN_ON_LEAVES := 0.35

# --- materials ----------------------------------------------------------------

static func make(system: VegetationSystem) -> void:
	var wind_noise := load("res://assets/generated/sky/cloud_weather.png")
	for group: Array in GROUPS:
		system.bark_materials.append(bark_material(str(group[0]), str(group[1])))
		var foliage := ShaderMaterial.new()
		foliage.shader = FOLIAGE_SHADER
		foliage.set_shader_parameter("albedo_texture", load(TEXTURES + str(group[2]) + "_albedo.png"))
		foliage.set_shader_parameter("broadleaf", group[3])
		foliage.set_shader_parameter("rain_wets", RAIN_ON_LEAVES)
		system.foliage_materials.append(foliage)
	# A scanned trunk has its own unwrap: one material per scan.
	var scans := {}
	for kind: int in TRUNKS:
		if not scans.has(TRUNKS[kind]):
			scans[TRUNKS[kind]] = bark_material(str(TRUNKS[kind]), ".jpg")
		system.trunk_materials[kind] = scans[TRUNKS[kind]]
	set_foliage_look(system, FOLIAGE_LOOK)
	system.impostor_material.shader = IMPOSTOR_SHADER
	system.impostor_material.set_shader_parameter("impostor_albedo", load("res://assets/generated/vegetation/impostor_albedo.png"))
	system.impostor_material.set_shader_parameter("impostor_normal", load("res://assets/generated/vegetation/impostor_normal.png"))
	var meta: Dictionary = DataFile.read(IMPOSTORS, WorldSchemas.impostors())
	var species: Array = meta.species
	for kind: int in species.size():
		var frame: Dictionary = species[kind]
		system.impostor_frames.append(Vector4(Values.real(frame.width_m), Values.real(frame.height_m), Values.real(frame.bottom_m),
			Values.real(TreePlacer.SPECIES_GROUP[kind])))
		system.crowns.append(Vector2(Values.real(frame.crown_radius_m), Values.real(VegetationSystem.CROWN_SHADE[TreePlacer.SPECIES_GROUP[kind]])))
	system.impostor_material.set_shader_parameter("frames", system.impostor_frames)
	system.impostor_material.set_shader_parameter("lod_range", system.impostor_range())
	system.impostor_material.set_shader_parameter("rain_wets", RAIN_ON_LEAVES)
	# Beyond the canopy field an impostor takes the wood round it from the
	# terrain's forest mask.
	for param: String in ["far_masks", "far_rect"]:
		system.impostor_material.set_shader_parameter(param, system.terrain.material.get_shader_parameter(param))
	for material in all_materials(system):
		material.set_shader_parameter("wind_noise", wind_noise)
		material.set_shader_parameter("cloud_weather", wind_noise)

static func bark_material(textures: String, extension: String) -> ShaderMaterial:
	var bark := ShaderMaterial.new()
	bark.shader = BARK_SHADER
	bark.set_shader_parameter("albedo_texture", load(TEXTURES + textures + "_diff" + extension))
	bark.set_shader_parameter("normal_texture", load(TEXTURES + textures + "_nor_gl" + extension))
	bark.set_shader_parameter("arm_texture", load(TEXTURES + textures + "_arm" + extension))
	# Moss for the foot of the trunk: the terrain's layer array, as the rocks'.
	bark.set_shader_parameter("moss_albedo", load("res://assets/generated/terrain/terrain_albedo.jpg"))
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
		wrap.append(Values.real(values[0]))
		transmission.append(Values.real(values[1]))
		var leaf_tint: Vector3 = values[2]
		tint.append(leaf_tint)
		ambient.append(Values.real(values[3]))
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
