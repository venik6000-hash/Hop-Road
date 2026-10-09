extends RefCounted
## How LakeBed draws its plants and scans: one MultiMesh per model mesh and
## 24 m tile, and one underwater material per plant kind or scan material
## (static functions over the LakeBed node `lake`).
const REED := preload("res://src/wildlife/reed.gdshader")

static func add(lake: LakeBed, kind: String, variant: int, transform: Transform3D) -> void:
	var tile := Vector2i(floori(transform.origin.x / LakeBed.TILE), floori(transform.origin.z / LakeBed.TILE))
	var key := "%s/%d/%d/%d" % [kind, variant, tile.x, tile.y]
	if not lake._groups.has(key):
		lake._groups[key] = {"kind": kind, "variant": variant, "transforms": []}
	lake._groups[key].transforms.append(transform)

static func _model_name(kind: String, variant: int) -> String:
	return kind + "_" + str(variant) if LakeBed.PLANTS.has(kind) else kind

static func build(lake: LakeBed) -> void:
	var models: Dictionary = {}
	var prepared: Dictionary = {}
	for key: String in lake._groups:
		var group: Dictionary = lake._groups[key]
		var model_name := _model_name(group.kind, group.variant)
		if not models.has(model_name):
			models[model_name] = (load(LakeBed.DIRECTORY + model_name + ".glb") as PackedScene).instantiate()
		var scene: Node3D = models[model_name]
		for source: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh_key := model_name + "/" + source.name
			if not prepared.has(mesh_key):
				var mesh := source.mesh.duplicate() as ArrayMesh
				for surface in mesh.get_surface_count():
					mesh.surface_set_material(surface, _material(lake, group.kind, WildlifeModel.material_for(source, surface) as StandardMaterial3D))
				prepared[mesh_key] = mesh
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = prepared[mesh_key]
			multi.instance_count = group.transforms.size()
			for i in multi.instance_count:
				multi.set_instance_transform(i, group.transforms[i] * source.transform)
			var instance := MultiMeshInstance3D.new()
			instance.name = key.replace("/", "_")
			instance.multimesh = multi
			var range_end: float = LakeBed.PLANTS[group.kind].range if LakeBed.PLANTS.has(group.kind) else 130.0
			instance.visibility_range_end = range_end
			instance.visibility_range_end_margin = range_end * 0.12
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			lake.add_child(instance)
	for scene: Node in models.values():
		scene.free()

## One material per kind (plants) or per source material (scans).
static func _material(lake: LakeBed, kind: String, original: StandardMaterial3D) -> ShaderMaterial:
	var key := kind if LakeBed.PLANTS.has(kind) else str(original.get_instance_id())
	if lake._materials.has(key):
		return lake._materials[key]
	var material := ShaderMaterial.new()
	if kind == "reed":
		material.shader = REED
		material.set_shader_parameter("plant_height", LakeBed.PLANTS[kind].height)
		material.set_shader_parameter("wind_noise", load("res://assets/generated/sky/cloud_weather.png"))
		material.set_shader_parameter("cloud_weather", load("res://assets/generated/sky/cloud_weather.png"))
		lake.reed_material = material
	else:
		material.shader = WildlifeModel.UNDERWATER
		if LakeBed.PLANTS.has(kind):
			material.set_shader_parameter("vertex_color", true)
			material.set_shader_parameter("motion", 1)
			material.set_shader_parameter("plant_height", LakeBed.PLANTS[kind].height)
			material.set_shader_parameter("translucency", 0.55 if kind != "chara" else 0.2)
			material.set_shader_parameter("roughness", 0.45)
		else:
			WildlifeModel.copy_scan_look(material, original)
			material.set_shader_parameter("biofilm", 1.0)
	material.set_shader_parameter("water_level", lake.habitat.terrain.water_level)
	material.set_shader_parameter("water_absorption", WaterSystem.ABSORPTION)
	material.set_shader_parameter("water_scattering", WaterSystem.SCATTERING)
	lake._materials[key] = material
	return material
