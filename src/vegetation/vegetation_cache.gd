class_name VegetationCache
extends RefCounted
## Content-addressed placement: baked package data is read-only; runtime
## rebuilds go to user:// and never try to overwrite an exported PCK.
##
## The placement is a function of what the placer is given, so that is what
## the key hashes, not the files that made it: the placer's own code and the
## region's two tree lists (the static part), and the world as the placer sees it, the
## terrain arrays of VegetationTerrain and the obstacle grid of ObstacleMap
## (the world part). An edit that leaves both unchanged, a tavern shader, a
## house texture, a moved lamp, leaves the key and the baked trees alone.
## The world part is known only once the level has built the terrain and the
## colliders, so every load builds both (prepare(): the part of compute that
## is cheap, about the cost of the obstacle scan) and places the trees only
## when no stored placement carries the key. A region names its tree lists
## and its baked placement (RegionDef.woodland, village_trees, placement,
## placement_manifest).
## Where runtime rebuilds are kept: the player's cache; a test sets its own.
static var runtime_root := "user://cache/vegetation/"
## Bump when the layout of the file or the way the key is made changes.
## TreePlacer.VERSION is the other knob, for a change of the placement that
## no byte of the placer's code shows (the engine's RNG or float behaviour).
const FORMAT_VERSION := 3
## First string of every placement file. The key lives in the manifest and in
## the name of a runtime file, never in the bytes: the same trees are the same
## file however often the key changes.
const MAGIC := "VEG3"
## The code that places trees: with the region's tree lists, the static part
## of the key (static_files()). LF-normalised text, so a checkout with CRLF
## gives the same key.
const CODE := [
	"res://src/vegetation/tree_placer.gd",
	"res://src/vegetation/tree_pass_composed.gd",
	"res://src/vegetation/tree_pass_detail.gd",
	"res://src/vegetation/tree_pass_far.gd",
	"res://src/vegetation/tree_set.gd",
	"res://src/vegetation/vegetation_terrain.gd",
	"res://src/vegetation/obstacle_map.gd",
]

var trees: TreeSet
var obstacles: ObstacleMap
## The key of this placement; empty when it cannot be made (no static part).
var key := ""
## From prepare(): the terrain arrays, the lists to place, and what making
## them and hashing them took (ms).
var fields: VegetationTerrain
var tree_list: Array = []
var scan_msec := 0.0
var digest_msec := 0.0

## The digest of a text file with LF line ends; empty if it is missing.
static func text_digest(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).replace("\r\n", "\n").sha256_text()

## The files of the static part of the key of `region`: the code, then the
## lists of trees the placer is given.
static func static_files(region: RegionDef) -> PackedStringArray:
	var files := PackedStringArray(CODE)
	files.append_array([region.woodland, region.village_trees])
	return files

## The static part of the key of `region`, from the files on disk (the editor
## only: an exported script cannot be read back). Empty if one of them is missing.
static func static_digest(region: RegionDef) -> String:
	var parts := PackedStringArray()
	for path: String in static_files(region):
		var digest := text_digest(path)
		if digest.is_empty():
			return ""
		parts.append(path + ":" + digest)
	return "\n".join(parts).sha256_text()

## The static part this process runs with: from the files in the editor, from
## the manifest of the bake in an export (checked by the export gate).
static func _static_part(region: RegionDef) -> String:
	if OS.has_feature("editor"):
		return static_digest(region)
	var saved: Variant = _load_manifest(region.placement_manifest)
	if not saved is Dictionary:
		return ""
	var manifest: Dictionary = saved
	return str(manifest.get("static_digest", ""))

## The world part of the key: every array and number of the terrain fields the placer
## reads, and the obstacle grid.
static func world_digest(terrain_fields: VegetationTerrain, grid: ObstacleMap) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes([terrain_fields.water_level, terrain_fields.near_origin, terrain_fields.near_cell, terrain_fields.near_size,
		terrain_fields.far_origin, terrain_fields.far_cell, terrain_fields.far_size, terrain_fields.mask_origin, terrain_fields.mask_cell, terrain_fields.mask_size,
		terrain_fields.far_block_count, grid.origin, grid.cell, grid.size,
		terrain_fields.near_h.size(), terrain_fields.far_h.size(), terrain_fields.control.size(), terrain_fields.extra.size(),
		terrain_fields.far_masks.size(), terrain_fields.far_forest_blocks.size(), grid.cover.size()]))
	for values: PackedFloat32Array in [terrain_fields.near_h, terrain_fields.far_h]:
		if not values.is_empty():
			context.update(values.to_byte_array())
	for bytes: PackedByteArray in [terrain_fields.control, terrain_fields.extra, terrain_fields.far_masks, terrain_fields.far_forest_blocks, grid.cover]:
		if not bytes.is_empty():
			context.update(bytes)
	return context.finish().hex_encode()

## The key of a static part and a world part, with the versions of the format
## and of the placer.
static func combine(static_part: String, world_part: String) -> String:
	return ("%d;%d;%s;%s" % [FORMAT_VERSION, TreePlacer.VERSION, static_part, world_part]).sha256_text()

static func _load_manifest(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return DataFile.read(path, WorldSchemas.placement_manifest())

## Whether `saved` (a manifest) describes a bake of this format and placer
## made for `expected`; the file's own checksum is checked apart.
static func baked_for(saved: Variant, expected: String) -> bool:
	if not saved is Dictionary or expected.is_empty():
		return false
	var manifest: Dictionary = saved
	return manifest.get("key", "") == expected and int(manifest.get("format_version", 0)) == FORMAT_VERSION \
		and int(manifest.get("tree_placer_version", -1)) == TreePlacer.VERSION

## Whether the baked package of `region` on disk is for `expected`, checksum included.
static func is_current(region: RegionDef, expected: String) -> bool:
	var saved: Variant = _load_manifest(region.placement_manifest)
	if not baked_for(saved, expected):
		return false
	var manifest: Dictionary = saved
	return str(manifest.get("placement_sha256", "")) == FileAccess.get_sha256(region.placement)

## Why a baked package cannot be shipped: `saved` is its manifest,
## `static_part` the static part of the sources now, `binary_sha256` the
## checksum of the baked file. The world part needs a loaded level, so
## whether the terrain and the colliders still give the baked trees is for
## the runtime to find out (the key it makes differs, and it places the
## trees once again, slower but never wrong).
static func problems(saved: Variant, static_part: String, binary_sha256: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not saved is Dictionary:
		found.append("Missing vegetation manifest; run bake_placement.gd")
		return found
	var manifest: Dictionary = saved
	if int(manifest.get("format_version", 0)) != FORMAT_VERSION or int(manifest.get("tree_placer_version", -1)) != TreePlacer.VERSION:
		found.append("Vegetation bake is of another format or placer version; run bake_placement.gd")
	if static_part.is_empty():
		found.append("A placer source file is missing; the content key cannot be computed")
	elif manifest.get("static_digest", "") != static_part:
		found.append("The placer or the tree lists changed since the bake; run bake_placement.gd")
	if manifest.get("placement_sha256", "") != binary_sha256:
		found.append("Vegetation binary checksum differs from manifest")
	return found

## The shared gate of the export plugin and the preflight: `problems()` for
## the files of `region` on disk (another manifest at `manifest_path`), and
## the binary must read back.
static func validate(region: RegionDef, manifest_path := "") -> PackedStringArray:
	var manifest := region.placement_manifest if manifest_path.is_empty() else manifest_path
	var found := problems(_load_manifest(manifest), static_digest(region), FileAccess.get_sha256(region.placement))
	if found.is_empty() and _read_file(region.placement) == null:
		found.append("Vegetation binary cannot be read; run bake_placement.gd")
	return found

static func runtime_path(source_key: String) -> String:
	return runtime_root + source_key + ".bin"

## Builds the terrain arrays and scans the buildings from above (the part of
## the placement that needs the world), and makes the key; the trees are
## those of the terrain's region. `exclude` holds the
## bodies the obstacle rays must pass (the player, the rocks); the terrain's
## own bodies are added here.
static func prepare(terrain: TerrainSystem, map: Node3D, exclude: Array[RID]) -> VegetationCache:
	var start := Time.get_ticks_usec()
	var cache := VegetationCache.new()
	cache.fields = VegetationTerrain.from_terrain(terrain)
	var space := terrain.get_world_3d().direct_space_state
	var skip := exclude.duplicate()
	for body: StaticBody3D in terrain.find_children("*", "StaticBody3D", true, false):
		skip.append(body.get_rid())
	var bounds := ObstacleMap.collider_bounds(map)
	# The village's buildings stand beside the map, the lighthouse beyond its edge.
	for building: Node in terrain.get_tree().get_nodes_in_group(VillageBuilding.GROUP):
		bounds = bounds.merge(ObstacleMap.collider_bounds(building))
	cache.obstacles = ObstacleMap.scan(space, bounds, cache.fields, skip)
	cache.obstacles.apply_to(cache.fields)
	var region := terrain.region
	var woodland: Dictionary = DataFile.read(region.woodland, WorldSchemas.woodland())
	# The village's own trees: by the brook and between the yards.
	cache.tree_list = woodland.trees
	cache.tree_list.append_array(DataFile.read(region.village_trees, WorldSchemas.trees()))
	var scanned := Time.get_ticks_usec()
	var static_part := _static_part(region)
	if not static_part.is_empty():
		cache.key = combine(static_part, world_digest(cache.fields, cache.obstacles))
	cache.scan_msec = (scanned - start) / 1000.0
	cache.digest_msec = (Time.get_ticks_usec() - scanned) / 1000.0
	return cache

## The slow part: places every tree of the lists over the prepared terrain.
func place() -> void:
	trees = TreePlacer.new(fields).place_all(tree_list)

## The stored placement made for `expected`: the baked package of `region`
## if it carries that key and checksum, else the runtime cache of that key,
## else null; null too when the trees are to be placed `anew`
## (WorldContext.place_trees_anew).
static func stored(region: RegionDef, expected: String, anew := false) -> VegetationCache:
	if expected.is_empty() or anew:
		return null
	var saved: Variant = _load_manifest(region.placement_manifest)
	if baked_for(saved, expected):
		var manifest: Dictionary = saved
		var baked := _read_file(region.placement, str(manifest.get("placement_sha256", "")))
		if baked != null:
			return baked
	return _read_file(runtime_path(expected))

## A placement file as it is, whatever key it was made for.
static func read(path: String) -> VegetationCache:
	return _read_file(path)

## `binary_sha256`, if given, is the checksum the file must have.
static func _read_file(path: String, binary_sha256 := "") -> VegetationCache:
	if not FileAccess.file_exists(path):
		return null
	if not binary_sha256.is_empty() and FileAccess.get_sha256(path) != binary_sha256:
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_pascal_string() != MAGIC:
		return null
	var cache := VegetationCache.new()
	cache.obstacles = ObstacleMap.read(file)
	if cache.obstacles == null:
		return null
	cache.trees = TreeSet.read(file)
	return cache if cache.trees != null else null

## Writes the runtime cache of `key` (or the file at `path`). A runtime cache
## of another key is of no use any more and is removed.
func write(path := "") -> Error:
	var target := path
	if path.is_empty():
		if key.is_empty():
			return ERR_INVALID_DATA
		target = runtime_path(key)
	var error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error != OK:
		return error
	var temporary := target + ".tmp"
	error = _store(temporary)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary, target)
	if error == OK and path.is_empty():
		var folder := DirAccess.open(runtime_root)
		if folder != null:
			for file_name: String in folder.get_files():
				if file_name != target.get_file():
					folder.remove(file_name)
	return error

func _store(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_pascal_string(MAGIC)
	obstacles.store(file)
	trees.store(file)
	file.close()
	return OK

## Offline build only: the baked package of `region`. The caller must compute
## placement against the complete world first; never bless an old cache by
## merely replacing its header. The baked file is replaced only when its bytes
## change, and the manifest only when its text does: a new key over the same
## trees touches the manifest.
func write_baked(region: RegionDef) -> Error:
	var static_part := static_digest(region)
	if key.is_empty() or static_part.is_empty():
		return ERR_INVALID_DATA
	var temporary := region.placement + ".tmp"
	var error := _store(temporary)
	if error != OK:
		return error
	var digest := FileAccess.get_sha256(temporary)
	if digest == FileAccess.get_sha256(region.placement):
		DirAccess.remove_absolute(temporary)
	else:
		error = DirAccess.rename_absolute(temporary, region.placement)
		if error != OK:
			return error
	var text := JSON.stringify({"format_version": FORMAT_VERSION, "tree_placer_version": TreePlacer.VERSION,
		"static_digest": static_part, "key": key, "placement_sha256": digest}, "\t") + "\n"
	if FileAccess.file_exists(region.placement_manifest) and FileAccess.get_file_as_string(region.placement_manifest) == text:
		return OK
	var file := FileAccess.open(region.placement_manifest, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return OK
