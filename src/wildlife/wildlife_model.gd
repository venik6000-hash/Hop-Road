class_name WildlifeModel
extends RefCounted
## Shared downloaded scenes; each actor keeps its own skeleton and clip clock.
const DIRECTORY := "res://assets/models/wildlife/"
## Birds that read as birds up close.
const BIRDS := ["bird", "raven", "seagull"]
## Fish of a cold mountain lake: rudd, perch, trout and pike.
const FISH := ["fish", "perch", "trout", "pike"]
const UNDERWATER := preload("res://src/wildlife/underwater_life.gdshader")
const OutdoorScan = preload("res://src/render/outdoor_scan.gd")
static var scenes: Dictionary = {}
static var materials: Dictionary = {}
static var bird_materials: Dictionary = {}

static func instantiate(kind: String, distance: float) -> Node3D:
	if not scenes.has(kind):
		scenes[kind] = load(DIRECTORY + kind + ".glb") as PackedScene
	var scene: PackedScene = scenes[kind]
	var model: Node3D = scene.instantiate()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = distance
		mesh.visibility_range_end_margin = distance * 0.15
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if kind in FISH or kind in BIRDS or kind == "butterfly":
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind in BIRDS or kind == "butterfly":
			for surface in mesh.mesh.get_surface_count():
				var original := material_for(mesh, surface) as StandardMaterial3D
				if original != null:
					mesh.set_surface_override_material(surface, bird_material(original))
		elif kind in FISH:
			for surface in mesh.mesh.get_surface_count():
				var original := material_for(mesh, surface) as StandardMaterial3D
				mesh.set_surface_override_material(surface, underwater_material(original, kind))
		else:
			# The animals of the land stand in its weather: the sun behind the
			# clouds and the crowns, the rain darkening their backs.
			for surface in mesh.mesh.get_surface_count():
				var original := material_for(mesh, surface) as StandardMaterial3D
				if original != null:
					mesh.set_surface_override_material(surface, OutdoorScan.material(original, 0.0))
	return model

## Actors animate skeletons, never these material values. Keeping the original
## resource as key prevents resource ID reuse and shares identical GPU state.
static func bird_material(original: StandardMaterial3D) -> StandardMaterial3D:
	if not bird_materials.has(original):
		var material := original.duplicate() as StandardMaterial3D
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.35
		bird_materials[original] = material
	return bird_materials[original]

static func underwater_material(original: StandardMaterial3D, kind: String) -> ShaderMaterial:
	var key := str(original.get_instance_id()) + kind
	if materials.has(key):
		return materials[key]
	var material := ShaderMaterial.new()
	material.shader = UNDERWATER
	copy_scan_look(material, original)
	if kind in ["perch", "trout"]:
		material.set_shader_parameter("motion", 2)
		material.set_shader_parameter("fish_length", {"perch": 0.42, "trout": 0.48}[kind])
	material.set_shader_parameter("water_absorption", WaterSystem.ABSORPTION)
	material.set_shader_parameter("water_scattering", WaterSystem.SCATTERING)
	materials[key] = material
	return material

## The scan's colour, roughness, normal strength and maps, from its imported
## material, on an underwater_life.gdshader `material` (LakeBed uses it too).
static func copy_scan_look(material: ShaderMaterial, original: StandardMaterial3D) -> void:
	material.set_shader_parameter("base_color", original.albedo_color)
	material.set_shader_parameter("roughness", original.roughness)
	material.set_shader_parameter("normal_strength", original.normal_scale)
	material.set_shader_parameter("roughness_channel", original.roughness_texture_channel)
	for pair: Array in [["albedo", original.albedo_texture], ["normal", original.normal_texture], ["roughness", original.roughness_texture]]:
		material.set_shader_parameter(StringName(str("has_" + pair[0])), pair[1] != null)
		if pair[1] != null:
			material.set_shader_parameter(StringName(str(pair[0] + "_map")), pair[1])

static func play(animation: AnimationPlayer, clip: String, speed := 1.0) -> void:
	if animation == null or not animation.has_animation(clip):
		return
	if animation.current_animation != clip or not animation.is_playing():
		animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		animation.play(clip, 0.2)
	animation.speed_scale = speed

static func material_for(mesh: MeshInstance3D, surface: int) -> Material:
	if mesh.material_override != null:
		return mesh.material_override
	var override := mesh.get_surface_override_material(surface)
	return override if override != null else mesh.mesh.surface_get_material(surface)
