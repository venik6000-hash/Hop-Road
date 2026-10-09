@tool
extends EditorScenePostImport
## Keep both authored models, but make their byte-identical imported maps shared.
## Runs only when wheel.glb is imported; exported scenes retain canonical refs.
const ROOT := "res://assets/models/village_pack/"
const MAPS := ["M_BucketAndWheel_baseColor.jpg", "M_BucketAndWheel_normal.png", "M_BucketAndWheel_metallicRoughness.png"]

func _post_import(scene: Node) -> Object:
	var replacements := {}
	for suffix: String in MAPS:
		var canonical := ROOT + "bucket_" + suffix
		var duplicate := ROOT + "wheel_" + suffix
		if FileAccess.get_sha256(canonical) != FileAccess.get_sha256(duplicate) or not _same_import(canonical, duplicate):
			push_error("Texture deduplication skipped: source or import settings differ for " + suffix)
			continue
		replacements[duplicate] = load(canonical)
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			# Packed maps may also be bound to AO or another texture slot. Match
			# every Texture2D property, preserving channel selectors and factors.
			for property: Dictionary in material.get_property_list():
				if int(property.type) != TYPE_OBJECT:
					continue
				var texture := material.get(property.name) as Texture2D
				if texture != null and replacements.has(texture.resource_path):
					material.set(property.name, replacements[texture.resource_path])
	return scene

func _same_import(first: String, second: String) -> bool:
	var a := ConfigFile.new()
	var b := ConfigFile.new()
	if a.load(first + ".import") != OK or b.load(second + ".import") != OK:
		return false
	if a.get_section_keys("params") != b.get_section_keys("params"):
		return false
	for key: String in a.get_section_keys("params"):
		if a.get_value("params", key) != b.get_value("params", key):
			return false
	return true
