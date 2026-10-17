extends RefCounted
## Scanned surfaces for the Blender map's village in place of its flat
## colours: the tavern's stone, plaster, oak and slate on the houses, the
## bridge and the paving. The tavern's own pieces are left as they are.
const SURFACE := preload("res://src/village/village_surface.gdshader")
const TEXTURES := "res://assets/generated/tavern/"
## Blender collections of the tavern (alpine_group).
const TAVERN_GROUPS := ["20", "21", "30"]
## Kinds of surface: scan, tint, metres per repeat, grime, moss, lichen.
const KINDS := {
	"masonry": {"scan": "worn_rock_natural_01", "size": "2k", "tint": Vector3(0.84, 0.82, 0.78), "uv_scale": 1.6,
		"desaturate": 0.7, "gain": 1.12, "grime": 0.55, "moss": 0.3, "lichen": 0.15},
	"paving": {"scan": "worn_rock_natural_01", "size": "2k", "tint": Vector3(0.74, 0.69, 0.61), "uv_scale": 1.1,
		"desaturate": 0.75, "gain": 1.2, "grime": 0.0, "moss": 0.07, "lichen": 0.0},
	"bridge": {"scan": "worn_rock_natural_01", "size": "2k", "tint": Vector3(0.7, 0.68, 0.64), "uv_scale": 1.4,
		"desaturate": 0.7, "gain": 1.1, "grime": 0.5, "moss": 0.42, "lichen": 0.3},
	"slate": {"scan": "worn_rock_natural_01", "size": "2k", "tint": Vector3(0.6, 0.68, 0.86), "uv_scale": 0.9,
		"desaturate": 1.0, "gain": 1.25, "grime": 0.0, "moss": 0.22, "lichen": 0.3},
	"tile": {"scan": "rough_plaster_03", "size": "1k", "tint": Vector3(0.74, 0.36, 0.22), "uv_scale": 0.5,
		"desaturate": 0.8, "gain": 1.6, "grime": 0.0, "moss": 0.15, "lichen": 0.25},
	"plaster": {"scan": "grey_plaster_03", "size": "2k", "tint": Vector3(1.0, 0.94, 0.82), "uv_scale": 2.4,
		"desaturate": 0.85, "gain": 2.9, "grime": 0.5, "moss": 0.0, "lichen": 0.0},
	"oak": {"scan": "rough_wood", "size": "2k", "tint": Vector3(0.5, 0.35, 0.22), "uv_scale": 1.4,
		"desaturate": 0.85, "gain": 1.0, "grime": 0.25, "moss": 0.0, "lichen": 0.0},
	"golden_oak": {"scan": "rough_wood", "size": "2k", "tint": Vector3(0.66, 0.5, 0.34), "uv_scale": 1.2,
		"desaturate": 0.85, "gain": 1.0, "grime": 0.2, "moss": 0.0, "lichen": 0.0},
	"dark_oak": {"scan": "rough_wood", "size": "2k", "tint": Vector3(0.3, 0.21, 0.14), "uv_scale": 0.9,
		"desaturate": 0.85, "gain": 1.0, "grime": 0.2, "moss": 0.0, "lichen": 0.0},
	"mortar": {"scan": "rough_plaster_03", "size": "1k", "tint": Vector3(0.36, 0.34, 0.31), "uv_scale": 1.2,
		"desaturate": 0.6, "gain": 1.0, "grime": 0.6, "moss": 0.2, "lichen": 0.0},
	"iron": {"scan": "rust_coarse_01", "size": "1k", "tint": Vector3(0.34, 0.31, 0.29), "uv_scale": 0.6,
		"desaturate": 0.0, "gain": 1.0, "grime": 0.0, "moss": 0.0, "lichen": 0.0},
	"earth": {"scan": "worn_rock_natural_01", "size": "2k", "tint": Vector3(0.46, 0.38, 0.29), "uv_scale": 0.5,
		"desaturate": 0.5, "gain": 1.0, "grime": 0.0, "moss": 0.0, "lichen": 0.0},
}
## The map's materials ("Alpine / <name>", by the start of the name).
const FAMILIES := {
	"Limestone": "masonry", "Blue slate": "slate", "Terracotta": "tile", "Bell tower terracotta": "tile",
	"Warm lime plaster": "plaster", "Old oak": "oak", "Cut golden oak": "golden_oak", "Recessed timber": "dark_oak",
	"Shadow in masonry": "mortar", "Forged iron": "iron", "Meadow earth": "earth", "Ochre soil": "earth",
}

static func apply(map: Node3D, terrain: TerrainSystem) -> int:
	var weather := load("res://assets/generated/sky/cloud_weather.png") as Texture2D
	var moss := load("res://assets/generated/terrain/terrain_albedo.jpg") as Texture
	var made := {}
	var changed := 0
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = item.get_meta("extras", {})
		var label := str(extras.get("alpine_label", item.name))
		if str(extras.get("alpine_group", "")) in TAVERN_GROUPS:
			continue
		var touched := false
		for surface in item.mesh.get_surface_count():
			var old := item.mesh.surface_get_material(surface) as ShaderMaterial
			if old == null or not old.resource_name.begins_with("Alpine / "):
				continue
			var kind := _kind(old.resource_name.trim_prefix("Alpine / "), label)
			if kind.is_empty():
				continue
			# The map's own shade of the family stays, as a tint of the scan.
			var shade: Color = old.get_shader_parameter("base_color")
			var key := "%s/%s" % [kind, old.resource_name]
			if not made.has(key):
				made[key] = _material(Values.table(KINDS[kind]), shade, kind, weather, moss)
			var dressed: Material = made[key]
			item.set_surface_override_material(surface, dressed)
			touched = true
		if touched:
			var box := item.global_transform * item.get_aabb()
			var centre := box.get_center()
			var wide := maxf(box.size.x, box.size.z) > 16.0
			item.set_instance_shader_parameter("ground_level", -100.0 if wide else terrain.height_at(centre.x, centre.z))
			changed += 1
	print("VILLAGE_MATERIALS meshes=%d materials=%d" % [changed, made.size()])
	return changed

static func _kind(material: String, label: String) -> String:
	for family: String in FAMILIES:
		if material.begins_with(family):
			var kind: String = FAMILIES[family]
			if kind == "masonry":
				if "cobble" in label.to_lower() or "walkway" in label or "paving" in label.to_lower():
					return "paving"
				if "footbridge" in label:
					return "bridge"
			return kind
	return ""

static func _material(spec: Dictionary, shade: Color, kind: String, weather: Texture2D, moss: Texture) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	var base := "%s%s_" % [TEXTURES, spec.scan]
	material.set_shader_parameter("albedo_map", load(base + "diff_%s.jpg" % spec.size))
	material.set_shader_parameter("normal_map", load(base + "nor_gl_%s.jpg" % spec.size))
	material.set_shader_parameter("orm_map", load(base + "arm_%s.jpg" % spec.size))
	var tint: Vector3 = spec.tint
	if kind in ["slate", "tile"]:
		# Each roof keeps the map's own hue, muted toward the scan.
		var hue := Vector3(shade.r, shade.g, shade.b) / maxf(shade.get_luminance(), 0.05)
		tint *= Vector3.ONE.lerp(hue / maxf(hue.x, maxf(hue.y, hue.z)), 0.35) * clampf(shade.get_luminance() / 0.3, 0.8, 1.2)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("desaturate", spec.desaturate)
	material.set_shader_parameter("albedo_gain", spec.gain)
	material.set_shader_parameter("uv_scale", spec.uv_scale)
	material.set_shader_parameter("grime", spec.grime)
	material.set_shader_parameter("moss", spec.moss)
	material.set_shader_parameter("lichen", spec.lichen)
	material.set_shader_parameter("color_range", 1.0)
	material.set_shader_parameter("cloud_weather", weather)
	material.set_shader_parameter("moss_albedo", moss)
	return material
