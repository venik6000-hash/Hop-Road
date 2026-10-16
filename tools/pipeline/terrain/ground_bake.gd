extends RefCounted
## The bake of a region's settled ground (TerrainBake reads it): the near
## heights and masks of terrain.py, the region's ground recipe run over them,
## and the manifest with the courses and the key of the bake, the digest of
## every file the bake reads, code included. A bake whose key differs from
## the key of the files now is stale (problems()).

## The ground recipe of each region by RegionDef.id: a script whose static
## settle() lays the region's rocks, buildings and water courses into the
## near heights, whose static paint() paints its beds, yards and worn ground
## into the masks, and whose static inputs() names the files they read. A
## region without one is baked as terrain.py wrote it.
const RECIPES := {&"valley": "res://tools/pipeline/terrain/valley_ground.gd"}
## The code of the bake itself; the recipe names its own files.
const CODE := ["res://src/terrain/terrain_bake.gd", "res://tools/pipeline/terrain/ground_bake.gd",
	"res://tools/pipeline/terrain/bake_ground.gd"]
const SOURCE_HEIGHTS := "near_height.bin"
const SOURCE_META := "terrain.json"
const SOURCE_MASKS := ["near_control.png", "near_extra.png"]
## The files whose digest is of their text, with LF line ends; any other is
## digested by its bytes.
const TEXT := ["gd", "json", "tres", "tscn", "import", "py"]

## The recipe of `region`, or null.
static func recipe(region: RegionDef) -> Script:
	var path: String = RECIPES.get(region.id, "")
	return null if path.is_empty() else load(path) as Script

## Every file the bake of `region` reads.
static func inputs(region: RegionDef) -> PackedStringArray:
	var files := PackedStringArray(CODE)
	files.append(region.terrain_dir.path_join(SOURCE_HEIGHTS))
	files.append(region.terrain_dir.path_join(SOURCE_META))
	for mask: String in SOURCE_MASKS:
		files.append(region.terrain_dir.path_join(mask))
	var script := recipe(region)
	if script != null:
		var listed: PackedStringArray = script.call("inputs", region)
		files.append_array(listed)
	return files

## The digest of a file: of its text with LF line ends for a text (TEXT), of
## its bytes otherwise. Empty if it is missing.
static func file_digest(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	if not path.get_extension() in TEXT:
		return FileAccess.get_sha256(path)
	return FileAccess.get_file_as_string(path).replace("\r\n", "\n").sha256_text()

## The key of a bake of `region` from the files on disk. Empty if an input is missing.
static func key(region: RegionDef) -> String:
	var parts := PackedStringArray([str(TerrainBake.FORMAT_VERSION)])
	for path: String in inputs(region):
		var digest := file_digest(path)
		if digest.is_empty():
			return ""
		parts.append(path + ":" + digest)
	return "\n".join(parts).sha256_text()

## The near heights and masks of terrain.py and its terrain.json: {meta,
## image (FORMAT_RF), control, extra (RGBA8)}.
static func source(region: RegionDef) -> Dictionary:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(region.terrain_dir.path_join(SOURCE_META)))
	var size := int(meta.near.size)
	var bytes := FileAccess.get_file_as_bytes(region.terrain_dir.path_join(SOURCE_HEIGHTS))
	var loaded := {"meta": meta, "image": Image.create_from_data(size, size, false, Image.FORMAT_RF, bytes)}
	for mask: String in SOURCE_MASKS:
		var image := Image.load_from_file(ProjectSettings.globalize_path(region.terrain_dir.path_join(mask)))
		image.convert(Image.FORMAT_RGBA8)
		loaded[mask.get_basename().trim_prefix("near_")] = image
	return loaded

## Settles the ground of `region` by its recipe: {image, courses} for the
## heights, {control, extra} for the masks and, if the recipe wears the
## ground, {wear, cinder, rect} (GroundWear.bake).
static func settle(region: RegionDef) -> Dictionary:
	var settled := source(region)
	var image: Image = settled.image
	var meta: Dictionary = settled.meta
	settled.courses = {}
	var script := recipe(region)
	if script != null:
		settled.courses = script.call("settle", region, image, Vector2(meta.near.origin[0], meta.near.origin[1]),
			float(meta.near.cell), float(meta.water_level))
		var masks: Dictionary = meta.masks
		var fields: Dictionary = script.call("paint", region, settled, Vector2(masks.origin[0], masks.origin[1]),
			float(masks.cell))
		settled.merge(fields)
	return settled

## Writes `settled` (from settle()) as the bake of `region`, with the key of
## the files now. Each file goes through a temporary one, so a failed bake
## leaves the old one whole.
static func write(region: RegionDef, settled: Dictionary) -> Error:
	var image: Image = settled.image
	var heights := image.get_data()
	var error := _write(region.settled_heights, heights)
	if error == OK:
		error = _write_masks(region.settled_masks, settled)
	if error == OK:
		var data := manifest(key(region), heights, FileAccess.get_sha256(region.settled_masks), settled)
		error = _write(region.settled_ground, (JSON.stringify(data, " ", false, true) + "\n").to_utf8_buffer())
	return error

static func _write(path: String, bytes: PackedByteArray) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

## The masks of `settled` as TerrainBake.read_masks() reads them.
static func _write_masks(path: String, settled: Dictionary) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open_compressed(temporary, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return FileAccess.get_open_error()
	for mask: String in ["control", "extra", "wear", "cinder"]:
		var image: Image = settled.get(mask)
		if image != null:
			file.store_buffer(image.get_data())
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

## The manifest of a bake: the key, the checksums of the heights and of the
## masks file, the courses, and the layout of the masks file (TerrainBake).
static func manifest(bake_key: String, heights: PackedByteArray, masks_sha256: String, settled: Dictionary) -> Dictionary:
	var encoded := {}
	var courses: Dictionary = settled.get("courses", {})
	for course_name: Variant in courses:
		encoded[str(course_name)] = encode_course(courses[course_name])
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(heights)
	var control: Image = settled.get("control")
	var wear: Image = settled.get("wear")
	var rect: Rect2 = settled.get("rect", Rect2())
	var layout := {
		"size": control.get_width() if control != null else 0,
		"wear": {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"size": [wear.get_width(), wear.get_height()] if wear != null else [0, 0]},
		"cinder": settled.get("cinder") != null,
	}
	return {"format_version": TerrainBake.FORMAT_VERSION, "key": bake_key, "heights_sha256": context.finish().hex_encode(),
		"masks_sha256": masks_sha256, "courses": encoded, "masks": layout}

## A course (rows {at, half, speed, depth, step}) as the numbers of
## TerrainBake.ROW row by row, 64-bit, in base64: JSON text would round them.
static func encode_course(course: Array[Dictionary]) -> String:
	var numbers := PackedFloat64Array()
	for row: Dictionary in course:
		var at: Vector3 = row.at
		numbers.append_array([at.x, at.y, at.z, row.half, row.speed, row.depth, 1.0 if row.step else 0.0])
	return Marshalls.raw_to_base64(numbers.to_byte_array())

## Why the bake of `region` on disk cannot be used. A stale key is checked
## when `with_key`.
static func problems(region: RegionDef, with_key := true) -> PackedStringArray:
	var found := PackedStringArray()
	var saved: Variant = TerrainBake.read_manifest(region)
	if not saved is Dictionary:
		found.append("No settled ground for %s; run tools/run/rebuild.sh --only terrain-ground" % region.id)
		return found
	var data: Dictionary = saved
	if int(data.get("format_version", 0)) != TerrainBake.FORMAT_VERSION:
		found.append("The settled ground of %s is of another format; bake it again" % region.id)
	if str(data.get("heights_sha256", "")) != FileAccess.get_sha256(region.settled_heights):
		found.append("The settled heights of %s differ from their manifest; bake them again" % region.id)
	if str(data.get("masks_sha256", "")) != FileAccess.get_sha256(region.settled_masks):
		found.append("The settled masks of %s differ from their manifest; bake them again" % region.id)
	if with_key:
		var expected := key(region)
		if expected.is_empty():
			found.append("An input of the ground bake of %s is missing" % region.id)
		elif str(data.get("key", "")) != expected:
			found.append("The ground of %s changed since the bake; run tools/run/rebuild.sh --only terrain-ground"
				% region.id)
	return found
