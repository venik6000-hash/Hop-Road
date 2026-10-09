extends RefCounted
## Same texture channels and shaders as the tavern, with the cottage ground elevation.
const TAVERN_MATERIALS := preload("res://src/tavern/tavern_materials.gd")
const SURFACE := TAVERN_MATERIALS.SURFACE
const GLASS := TAVERN_MATERIALS.GLASS
const FLAME := TAVERN_MATERIALS.FLAME
const FOLIAGE := TAVERN_MATERIALS.FOLIAGE

static func build(table: Dictionary, ground_level: float) -> Dictionary:
	var result := {}
	TAVERN_MATERIALS.build(table, ground_level, result)
	return result

## A lantern draws its shadow map again in every frame a caster with an
## animated material is in it. So a swaying piece goes on the plants' render
## layer, which the lanterns leave out of their maps, and a flame casts none.
static func leave_out_of_lantern_shadows(item: MeshInstance3D) -> void:
	for surface in item.mesh.get_surface_count():
		var material := item.get_active_material(surface) as ShaderMaterial
		if material == null:
			continue
		if material.shader == FOLIAGE:
			item.layers = VegetationSystem.VISUAL_LAYER
		elif material.shader == FLAME:
			item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
