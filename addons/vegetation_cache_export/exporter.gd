@tool
extends EditorExportPlugin
const CollisionCache = preload("res://src/village/prop_collision_cache.gd")
const Cache = preload("res://src/vegetation/vegetation_cache.gd")
func _get_name() -> String:
	return "VegetationPlacement"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	var collision_errors := CollisionCache.validate_bakes()
	if not collision_errors.is_empty():
		for message: String in collision_errors:
			get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Collision bake", message)
		return
	var current := Cache.build_manifest()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Cache.MANIFEST)) if FileAccess.file_exists(Cache.MANIFEST) else null
	if not saved is Dictionary or saved.get("key", "") != current.get("key", "") or saved.get("placement_sha256", "") != FileAccess.get_sha256(Cache.PATH):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Vegetation", "Bake is missing or stale. Run tools/pipeline/vegetation/bake_placement.gd before export.")
		return
	# Non-resource .bin/.json files are not otherwise guaranteed to enter PCK.
	add_file(Cache.PATH, FileAccess.get_file_as_bytes(Cache.PATH), false)
	add_file(Cache.MANIFEST, FileAccess.get_file_as_bytes(Cache.MANIFEST), false)
