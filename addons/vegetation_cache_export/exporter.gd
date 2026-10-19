@tool
extends EditorExportPlugin
## Puts the bakes of every region of the game (RegionDef.listed()) into the
## package, and stops the export when one of them is stale.
const CollisionCache = preload("res://src/village/prop_collision_cache.gd")
const Cache = preload("res://src/vegetation/vegetation_cache.gd")
const GroundBake = preload("res://tools/pipeline/terrain/ground_bake.gd")
## TerrainSystem reads these as raw bytes, so no importer puts them in the
## PCK: the region's fields and the world's tiles it starts with.
static func terrain_fields(region: RegionDef) -> PackedStringArray:
	var files := PackedStringArray([region.settled_heights, region.settled_masks, region.settled_ground,
		region.terrain_dir.path_join("far_height.bin"), region.terrain_dir.path_join("far_minmax.bin")])
	var world: PackedStringArray = TerrainTiles.start_files(region).files
	files.append_array(world)
	return files
func _get_name() -> String:
	return "VegetationPlacement"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	var regions := RegionDef.listed()
	if regions.is_empty():
		_fail("Regions", "No region in " + RegionDef.LIST + ".")
		return
	for region: RegionDef in regions:
		if not _add_region(region):
			return

## Adds the bakes of `region`; false, with the export's error, if one is stale or missing.
func _add_region(region: RegionDef) -> bool:
	var stale_ground := GroundBake.problems(region)
	if not stale_ground.is_empty():
		for message: String in stale_ground:
			_fail("Terrain", message)
		return false
	var stale_tiles: PackedStringArray = TerrainTiles.start_files(region).stale
	for folder: String in stale_tiles:
		_fail("Terrain", "The tile in %s is not cut from the ground bake; run tools/run/rebuild.sh --only world-ground-tiles." % folder)
	if not stale_tiles.is_empty():
		return false
	for path: String in terrain_fields(region):
		if not FileAccess.file_exists(path):
			_fail("Terrain", "Missing " + path + ".")
			return false
		add_file(path, FileAccess.get_file_as_bytes(path), false)
	var collision_errors := CollisionCache.validate_bakes(region)
	if not collision_errors.is_empty():
		for message: String in collision_errors:
			_fail("Collision bake", message)
		return false
	var stale := Cache.validate(region)
	if not stale.is_empty():
		for message: String in stale:
			_fail("Vegetation", message)
		return false
	# Non-resource .bin/.json files are not otherwise guaranteed to enter PCK.
	add_file(region.placement, FileAccess.get_file_as_bytes(region.placement), false)
	add_file(region.placement_manifest, FileAccess.get_file_as_bytes(region.placement_manifest), false)
	return true

func _fail(category: String, message: String) -> void:
	get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, category, message)
