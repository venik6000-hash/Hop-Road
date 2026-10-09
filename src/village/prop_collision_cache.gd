extends RefCounted
## Exact trimesh faces, baked offline and shared by repeated instances.
const ROOT := "res://assets/generated/village_pack/collisions/"
const SOURCE := "res://assets/models/village_pack/"
const VERSION := 1
var _assets := {}

static func source_key(asset: String) -> String:
	var path := SOURCE + asset + ".glb"
	var settings := ConfigFile.new()
	settings.load(path + ".import")
	var importer: String = settings.get_value("params", "import_script/path", "")
	var importer_hash := "" if importer.is_empty() else FileAccess.get_sha256(importer)
	return (str(VERSION) + ":" + Engine.get_version_info().string + ":" + FileAccess.get_sha256(path) + ":" + FileAccess.get_sha256(path + ".import") + ":" + importer + ":" + importer_hash).sha256_text()

func shape(asset: String, mesh_path: String, mesh: Mesh) -> Shape3D:
	if not _assets.has(asset):
		_assets[asset] = _read(asset)
	var shapes: Dictionary = _assets[asset]
	if not shapes.has(mesh_path):
		# A missing/stale bake remains exact, and is still shared for this run.
		shapes[mesh_path] = mesh.create_trimesh_shape()
	return shapes[mesh_path]

func _read(asset: String) -> Dictionary:
	var path := ROOT + asset + ".res"
	if not ResourceLoader.exists(path):
		return {}
	var bundle := load(path)
	if int(bundle.get_meta("version", 0)) != VERSION:
		return {}
	# Source files can be converted/omitted in PCK. The build validates them;
	# development always checks content, including importer mesh settings.
	if OS.has_feature("editor") and bundle.get_meta("source_key", "") != source_key(asset):
		return {}
	return bundle.get_meta("shapes", {})

## Shared by the export gate and tests. Export must never trust a stale bake
## merely because the runtime cannot inspect transformed source GLBs in PCK.
static func bundle_is_valid(bundle: Resource, expected_key: String, mesh_paths: PackedStringArray) -> bool:
	if bundle == null or int(bundle.get_meta("version", 0)) != VERSION or bundle.get_meta("source_key", "") != expected_key:
		return false
	var shapes: Variant = bundle.get_meta("shapes", {})
	if not shapes is Dictionary or shapes.size() != mesh_paths.size():
		return false
	for path: String in mesh_paths:
		if not shapes.get(path) is ConcavePolygonShape3D:
			return false
	return true

static func validate_bakes() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var layout: Array = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "layout.json"))
	for entry: Dictionary in layout:
		if not entry.get("solid", true) or seen.has(entry.asset):
			continue
		seen[entry.asset] = true
		var path := ROOT + str(entry.asset) + ".res"
		if not ResourceLoader.exists(path):
			errors.append("Missing collision bake: " + path)
			continue
		var scene := load(SOURCE + str(entry.asset) + ".glb") as PackedScene
		var state := scene.get_state()
		var mesh_paths := PackedStringArray()
		for index in state.get_node_count():
			if state.get_node_type(index) == &"MeshInstance3D":
				mesh_paths.append(str(state.get_node_path(index)).trim_prefix("./"))
		if not bundle_is_valid(load(path), source_key(entry.asset), mesh_paths):
			errors.append("Stale or mismatched collision bake: " + path)
	return errors
