extends RefCounted
## The tavern's materials, shared by the cottages: one ShaderMaterial per table
## entry, found by the name the glTF surfaces carry. tavern_surface.gdshader
## for the building, tavern_glass.gdshader for the windows,
## tavern_foliage.gdshader for the ivy and the flowers, tavern_flame.gdshader
## for the fires, tavern_cloth.gdshader for what is woven, tavern_fur.gdshader
## for the hides.
const SURFACE := preload("res://src/tavern/tavern_surface.gdshader")
const GLASS := preload("res://src/tavern/tavern_glass.gdshader")
const FLAME := preload("res://src/tavern/tavern_flame.gdshader")
const FOLIAGE := preload("res://src/tavern/tavern_foliage.gdshader")
const CLOTH := preload("res://src/tavern/tavern_cloth.gdshader")
const FUR := preload("res://src/tavern/tavern_fur.gdshader")
## The fine normal maps of a table entry's `detail` (tools/pipeline/tavern/detail_textures.py).
const DETAIL_MAPS := {
	"wood": "res://assets/generated/tavern/detail_wood_normal.png",
	"stone": "res://assets/generated/tavern/detail_stone_normal.png",
	"cloth": "res://assets/generated/tavern/detail_cloth_normal.png",
}
## Repeats of a detail map per metre of UV when the entry gives no `detail_scale`.
const DETAIL_SCALE := 2.5
## Adds a material to `materials` for each table entry it does not hold yet;
## ground_level is the floor height the surface shader puts the grime at.
## Without `detail` no material gets its detail, to compare the look with and
## without.
static func build(table: Dictionary, ground_level: float, materials: Dictionary, detail := true) -> void:
	var weather := load("res://assets/generated/sky/cloud_weather.png")
	var moss := load("res://assets/generated/terrain/terrain_albedo.jpg")
	var range_: float = table.get("color_range", 2.0)
	var specs: Dictionary = table.get("materials", {})
	for name: String in specs:
		if materials.has(name):
			continue
		var spec: Dictionary = specs[name]
		var material := ShaderMaterial.new()
		material.resource_name = name
		var tint: Array = spec.get("tint", [1.0, 1.0, 1.0])
		if spec.get("shader", "surface") == "flame":
			material.shader = FLAME
			var fc: Array = spec.get("color", [1.0, 0.62, 0.25])
			material.set_shader_parameter("flame_color", Color(fc[0], fc[1], fc[2]))
			material.set_shader_parameter("energy", spec.get("energy", 4.0))
			material.set_shader_parameter("wildness", spec.get("wildness", 0.2))
			material.set_shader_parameter("dusk_only", 1.0 if spec.get("dusk_only", false) else 0.0)
			if spec.has("core"):
				var core: Array = spec.core
				var hot := Color(core[0], core[1], core[2]).srgb_to_linear()
				material.set_shader_parameter("core_color", Vector3(hot.r, hot.g, hot.b))
			materials[name] = material
			continue
		if spec.get("shader", "surface") == "foliage":
			material.shader = FOLIAGE
			material.set_shader_parameter("albedo_map", load(spec.albedo))
			material.set_shader_parameter("normal_map", load(spec.normal))
			material.set_shader_parameter("tint", Vector3(tint[0], tint[1], tint[2]))
			material.set_shader_parameter("color_range", range_)
			material.set_shader_parameter("roughness_value", spec.get("roughness", 0.42))
			material.set_shader_parameter("normal_strength", spec.get("normal_strength", 0.7))
			material.set_shader_parameter("leaf_wrap", spec.get("wrap", 0.3))
			material.set_shader_parameter("leaf_transmission", spec.get("transmission", 0.55))
			material.set_shader_parameter("flutter", spec.get("flutter", 0.012))
			material.set_shader_parameter("cloud_weather", weather)
			materials[name] = material
			continue
		if spec.get("shader", "surface") == "fur":
			material.shader = FUR
			for key: String in ["albedo", "normal", "mask"]:
				material.set_shader_parameter(key + "_map", load(spec[key]))
			var tip: Array = spec.get("tip", [0.8, 0.7, 0.55])
			material.set_shader_parameter("tint", Vector3(tint[0], tint[1], tint[2]))
			material.set_shader_parameter("tip_color", Vector3(tip[0], tip[1], tip[2]))
			material.set_shader_parameter("roughness_value", spec.get("roughness", 0.8))
			for key: String in ["albedo_gain", "normal_strength", "tip_inside", "tip_edge", "fur_length", "fur_lean",
					"fur_droop", "strand_cell", "tuft_cell", "tuft_pull", "root_shade"]:
				if spec.has(key):
					material.set_shader_parameter(key, spec[key])
			material.set_shader_parameter("cloud_weather", weather)
			materials[name] = material
			continue
		if spec.get("shader", "surface") == "cloth":
			material.shader = CLOTH
			for key: String in ["albedo", "normal", "orm", "emblem"]:
				if spec.has(key):
					material.set_shader_parameter(key + "_map", load(spec[key]))
			material.set_shader_parameter("tint", Vector3(tint[0], tint[1], tint[2]))
			material.set_shader_parameter("roughness_scale", spec.get("roughness", 1.0))
			material.set_shader_parameter("color_range", range_)
			for key: String in ["desaturate", "albedo_gain", "uv_scale", "normal_strength", "cloth_wrap", "cloth_through",
					"cloth_sheen", "stain", "threads"]:
				if spec.has(key):
					material.set_shader_parameter(key, spec[key])
			for key: String in ["emblem_color"]:
				if spec.has(key):
					var c: Array = spec[key]
					material.set_shader_parameter(key, Color(c[0], c[1], c[2]))
			if spec.has("emblem_size"):
				var size: Array = spec.emblem_size
				material.set_shader_parameter("emblem_size", Vector2(size[0], size[1]))
			_lay_detail(material, name, spec, detail)
			material.set_shader_parameter("cloud_weather", weather)
			materials[name] = material
			continue
		if spec.get("shader", "surface") == "glass":
			material.shader = GLASS
			material.set_shader_parameter("glass_tint", Color(tint[0], tint[1], tint[2]))
			material.set_shader_parameter("clarity", spec.get("alpha", 0.1))
			material.set_shader_parameter("roughness_value", spec.get("roughness", 0.04))
			material.set_shader_parameter("wave", spec.get("wave", 0.05))
			material.set_shader_parameter("quarry_tilt", spec.get("quarry", 0.0))
			material.set_shader_parameter("pane", spec.get("pane", 1.0))
			materials[name] = material
			continue
		material.shader = SURFACE
		for key: String in ["albedo", "normal", "orm"]:
			if spec.has(key):
				material.set_shader_parameter(key + "_map", load(spec[key]))
		material.set_shader_parameter("tint", Vector3(tint[0], tint[1], tint[2]))
		material.set_shader_parameter("desaturate", spec.get("desaturate", 0.0))
		material.set_shader_parameter("albedo_gain", spec.get("albedo_gain", 1.0))
		material.set_shader_parameter("uv_scale", spec.get("uv_scale", 1.0))
		material.set_shader_parameter("normal_strength", spec.get("normal_strength", 1.0))
		material.set_shader_parameter("roughness_scale", spec.get("roughness", 1.0))
		material.set_shader_parameter("metallic_value", spec.get("metallic", 0.0))
		material.set_shader_parameter("grime", spec.get("grime", 0.0))
		material.set_shader_parameter("moss", spec.get("moss", 0.0))
		material.set_shader_parameter("lichen", spec.get("lichen", 0.0))
		_lay_detail(material, name, spec, detail)
		if spec.has("detail_turn"):
			material.set_shader_parameter("detail_turn", spec.detail_turn)
		material.set_shader_parameter("color_range", range_)
		material.set_shader_parameter("ground_level", ground_level)
		material.set_shader_parameter("cloud_weather", weather)
		material.set_shader_parameter("moss_albedo", moss)
		materials[name] = material

## The fine normal map a table entry asks for (`detail`), with its scale and strength.
static func _lay_detail(material: ShaderMaterial, name: String, spec: Dictionary, wanted: bool) -> void:
	var detail: String = spec.get("detail", "")
	if not wanted or detail.is_empty():
		return
	if not DETAIL_MAPS.has(detail):
		push_warning("tavern material %s: no detail map called %s" % [name, detail])
		return
	material.set_shader_parameter("detail_map", load(DETAIL_MAPS[detail]))
	material.set_shader_parameter("detail_scale", spec.get("detail_scale", DETAIL_SCALE))
	material.set_shader_parameter("detail_strength", spec.get("detail_strength", 1.0))

## How the rooms have aged (the table's `indoor`: the floors' heights with the
## ridge's, and per material what tavern_surface.gdshader's indoor uniforms
## take). The fires that smoke are the table's lights of a fire's colour;
## `place` carries the table's coordinates into the world's.
static func age_indoors(table: Dictionary, materials: Dictionary, place: Transform3D) -> void:
	var indoor: Dictionary = table.get("indoor", {})
	if indoor.is_empty():
		return
	var heights: Array = indoor.get("storeys", [])
	var storeys := Vector4(-1000.0, 2000.0, 3000.0, 4000.0)
	for index: int in mini(heights.size(), 4):
		storeys[index] = float(heights[index]) + place.origin.y
	var smoking: Array[Dictionary] = []
	for config: Dictionary in table.get("lights", []):
		var colour: Array = config.color
		if float(colour[1]) < 0.55:
			smoking.append(config)
	smoking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.energy) > float(b.energy))
	var fires := PackedVector4Array()
	for index: int in 4:
		if index < smoking.size():
			var p: Array = smoking[index].position
			var at: Vector3 = place * Vector3(p[0], p[1], p[2])
			fires.append(Vector4(at.x, at.y, at.z, clampf(float(smoking[index].energy) / 4.0, 0.2, 1.0)))
		else:
			fires.append(Vector4(0.0, -10000.0, 0.0, 0.0))
	var specs: Dictionary = indoor.get("materials", {})
	for name: String in specs:
		var material: ShaderMaterial = materials.get(name)
		if material == null or material.shader != SURFACE:
			continue
		var spec: Dictionary = specs[name]
		var tint: Array = spec.get("indoor_tint", [1.0, 1.0, 1.0])
		material.set_shader_parameter("indoor_tint", Vector3(tint[0], tint[1], tint[2]))
		for key: String in ["soot", "indoor_grime", "wear", "handled", "crevice"]:
			material.set_shader_parameter(key, spec.get(key, 0.0))
		material.set_shader_parameter("storeys", storeys)
		material.set_shader_parameter("fires", fires)
