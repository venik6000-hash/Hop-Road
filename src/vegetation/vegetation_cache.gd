class_name VegetationCache
extends RefCounted
## Content-addressed placement: baked package data is read-only; runtime
## rebuilds go to user:// and never try to overwrite an exported PCK.
const PATH := "res://assets/generated/vegetation/placement.bin"
const MANIFEST := "res://assets/generated/vegetation/placement-manifest.json"
const RUNTIME_ROOT := "user://cache/vegetation/"
const FORMAT_VERSION := 2
const INPUTS := [
	"res://src/alpine/level.gd",
	"res://src/vegetation/vegetation_system.gd",
	"res://src/vegetation/vegetation_cache.gd",
	"res://src/vegetation/tree_placer.gd",
	"res://src/vegetation/tree_pass_composed.gd",
	"res://src/vegetation/tree_pass_detail.gd",
	"res://src/vegetation/tree_pass_far.gd",
	"res://src/vegetation/vegetation_terrain.gd",
	"res://src/vegetation/obstacle_map.gd",
	"res://src/vegetation/tree_set.gd",
	"res://src/village/village_layout.gd",
	"res://assets/generated/layout/village_plan.json",
	"res://assets/generated/layout/herbalist_placed.glb",
	"res://assets/generated/layout/potter_placed.glb",
	"res://src/village/village_brook.gd",
	"res://assets/generated/layout/village_trees.json",
	"res://src/village/village_pack.gd",
	"res://assets/models/village_pack/layout.json",
	"res://assets/generated/terrain/terrain.json",
	"res://assets/generated/terrain/near_height.bin",
	"res://assets/generated/terrain/far_height.bin",
	"res://assets/generated/terrain/near_control.png",
	"res://assets/generated/terrain/near_extra.png",
	"res://assets/generated/terrain/far_masks.png",
	"res://assets/models/alpine/alpine_map.glb",
	"res://assets/models/alpine/woodland.json",
	"res://scenes/alpine/main.tscn",
	# The unique cottage changes the porch and wood-store footprint.
	"res://assets/models/cottage/herbalist.glb",
	"res://src/village/herbalist_cottage.gd",
	# The rocks replace the Blender stones and cliff as obstacles.
	"res://src/rocks/rock_field.gd",
	"res://assets/models/rocks/rock_shapes.glb",
	# Stones moved by hand in the layout scene are other obstacles.
	"res://assets/generated/layout/rocks.json",
]

var trees: TreeSet
var obstacles: ObstacleMap

static func source_paths() -> Array:
	var paths: Array = INPUTS.duplicate()
	paths.append_array([
		"res://src/terrain/terrain_heights.gd", "res://src/terrain/terrain_collision.gd",
		"res://src/terrain/terrain_system.gd", "res://src/terrain/terrain_material.gd",
		"res://src/village/prop_collision_cache.gd", "res://src/village/potter_cottage.gd",
		"res://assets/models/cottage/herbalist.json", "res://assets/models/potter/potter.json",
		"res://src/tavern/tavern_collision.gd", "res://src/tavern/tavern_system.gd",
		"res://assets/models/tavern/tavern.json", "res://assets/models/tavern/tavern_interior.json",
	])
	var layout: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/village_pack/layout.json"))
	for entry: Dictionary in layout:
		var source := "res://assets/models/village_pack/" + str(entry.asset) + ".glb"
		if entry.get("solid", true) and not paths.has(source):
			paths.append(source)
	# Import settings may alter the collision mesh without changing GLB bytes.
	for path: String in paths.duplicate():
		if path.ends_with(".glb"):
			paths.append(path + ".import")
			var settings := ConfigFile.new()
			settings.load(path + ".import")
			var importer: String = settings.get_value("params", "import_script/path", "")
			if not importer.is_empty() and not paths.has(importer):
				paths.append(importer)
	paths.sort()
	return paths

static func build_manifest(paths: Array = []) -> Dictionary:
	if paths.is_empty():
		paths = source_paths()
	var inputs := {}
	var parts := PackedStringArray(["format=%d;trees=%d;engine=%s" % [FORMAT_VERSION, TreePlacer.VERSION, Engine.get_version_info().string]])
	for path: String in paths:
		var digest := FileAccess.get_sha256(path)
		if digest.is_empty():
			return {}
		inputs[path] = digest
		parts.append(path + ":" + digest)
	return {"format_version": FORMAT_VERSION, "tree_placer_version": TreePlacer.VERSION, "engine_version": Engine.get_version_info().string,
		"key": "\n".join(parts).sha256_text(), "inputs": inputs}

static func key() -> String:
	if OS.has_feature("editor"):
		return str(build_manifest().get("key", ""))
	# Exported scripts/GLBs are transformed, so source mtime/hash cannot be read
	# back reliably. The validated build manifest identifies this exact package.
	if not FileAccess.file_exists(MANIFEST):
		return ""
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or int(manifest.get("format_version", 0)) != FORMAT_VERSION:
		return ""
	if manifest.get("engine_version", "") != Engine.get_version_info().string:
		return ""
	if int(manifest.get("tree_placer_version", -1)) != TreePlacer.VERSION:
		return ""
	return str(manifest.get("key", ""))

static func runtime_path(source_key: String) -> String:
	return RUNTIME_ROOT + source_key + ".bin"

## Prefer the baked package. A missing/stale package falls back to a cache for
## exactly this content version in the writable user directory.
static func read(path := "") -> VegetationCache:
	var expected := key()
	if expected.is_empty():
		return null
	if not path.is_empty():
		return _read_file(path, expected)
	var baked := _read_file(PATH, expected)
	return baked if baked != null else _read_file(runtime_path(expected), expected)

static func _read_file(path: String, expected: String) -> VegetationCache:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_pascal_string() != expected:
		return null
	var cache := VegetationCache.new()
	cache.obstacles = ObstacleMap.read(file)
	if cache.obstacles == null:
		return null
	cache.trees = TreeSet.read(file)
	return cache if cache.trees != null else null

func write(path := "") -> Error:
	var source_key := key()
	if source_key.is_empty():
		return ERR_INVALID_DATA
	return _write_file(runtime_path(source_key) if path.is_empty() else path, source_key)

func _write_file(path: String, source_key: String) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_pascal_string(source_key)
	obstacles.store(file)
	trees.store(file)
	file.close()
	return DirAccess.rename_absolute(temporary, path)

## Offline build only. The caller must compute placement against the complete
## world first; never bless an old cache by merely replacing its header.
func write_baked() -> Error:
	var manifest := build_manifest()
	if manifest.is_empty():
		return ERR_FILE_NOT_FOUND
	var error := _write_file(PATH, manifest.key)
	if error != OK:
		return error
	manifest["placement_sha256"] = FileAccess.get_sha256(PATH)
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	return OK

## The slow path: scans the buildings from above and places every tree.
## `exclude` holds the bodies the obstacle rays must pass (terrain, player).
static func compute(terrain: TerrainSystem, map: Node3D, exclude: Array[RID]) -> VegetationCache:
	var fields := VegetationTerrain.from_terrain(terrain)
	var cache := VegetationCache.new()
	var space := terrain.get_world_3d().direct_space_state
	cache.obstacles = ObstacleMap.scan(space, ObstacleMap.collider_bounds(map), fields, exclude)
	cache.obstacles.apply_to(fields)
	var woodland: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/alpine/woodland.json"))
	# The village's own trees: by the brook and between the yards.
	var trees: Array = woodland.trees
	trees.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/layout/village_trees.json")))
	cache.trees = TreePlacer.new(fields).place_all(trees)
	return cache
