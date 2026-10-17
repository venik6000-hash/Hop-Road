class_name TerrainBake
extends RefCounted
## The settled ground of a region (RegionDef) as the game reads it: the near
## heights of terrain.py with the region's rocks, buildings and water courses
## laid in, the masks of the near field with the beds, yards and worn ground
## painted in, and the manifest with the courses. The bake writes them
## (tools/pipeline/terrain/ground_bake.gd); the game lays and paints nothing
## in itself.
##
## The masks file (RegionDef.settled_masks) is compressed (zstd) and holds,
## one after the other: the path mask and the extra mask (RGBA8, the masks'
## size squared, as terrain.py's near_control.png and near_extra.png), then,
## if the manifest's `masks.wear.size` is not zero, the wear field (RGBAH)
## and, if `masks.cinder`, the cinder field (R8) of that size.

## Bump when the bake's files change their layout.
const FORMAT_VERSION := 2
## The numbers of a course row in the manifest, in order (step: 1 or 0).
const ROW := ["x", "y", "z", "half", "speed", "depth", "step"]

## The manifest at RegionDef.settled_ground, or null if it is missing.
static func read_manifest(region: RegionDef) -> Variant:
	if not FileAccess.file_exists(region.settled_ground):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(region.settled_ground))

## A course of the manifest: the numbers of ROW row by row, 64-bit, in base64.
static func decode_course(text: String) -> Array[Dictionary]:
	var numbers := Marshalls.base64_to_raw(text).to_float64_array()
	var course: Array[Dictionary] = []
	for k in range(0, numbers.size() - ROW.size() + 1, ROW.size()):
		course.append({"at": Vector3(numbers[k], numbers[k + 1], numbers[k + 2]), "half": numbers[k + 3],
			"speed": numbers[k + 4], "depth": numbers[k + 5], "step": numbers[k + 6] > 0.5})
	return course

## The courses of a manifest, by name.
static func courses_of(data: Dictionary) -> Dictionary:
	var result := {}
	var encoded: Dictionary = data.get("courses", {})
	for course_name: String in encoded:
		result[StringName(course_name)] = decode_course(str(encoded[course_name]))
	return result

## The masks of the bake of `region` whose manifest is `data`: `control` and
## `extra` (Image, RGBA8), and `wear`, `rect` and `cinder` when the region
## wears its ground. Empty if the file is missing or shorter than the manifest says.
static func read_masks(region: RegionDef, data: Dictionary) -> Dictionary:
	var layout: Dictionary = data.get("masks", {})
	if layout.is_empty() or not FileAccess.file_exists(region.settled_masks):
		return {}
	var file := FileAccess.open_compressed(region.settled_masks, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var size := Values.whole(layout.size)
	var masks := {}
	for mask: String in ["control", "extra"]:
		var image := _image(file, Vector2i(size, size), Image.FORMAT_RGBA8, 4)
		if image == null:
			return {}
		masks[mask] = image
	var wear: Dictionary = layout.wear
	var wear_size := Vector2i(Values.whole(wear.size[0]), Values.whole(wear.size[1]))
	if wear_size.x > 0 and wear_size.y > 0:
		var field := _image(file, wear_size, Image.FORMAT_RGBAH, 8)
		if field == null:
			return {}
		masks.wear = field
		masks.rect = Rect2(Values.real(wear.rect[0]), Values.real(wear.rect[1]), Values.real(wear.rect[2]), Values.real(wear.rect[3]))
		if layout.cinder:
			var cinder := _image(file, wear_size, Image.FORMAT_R8, 1)
			if cinder == null:
				return {}
			masks.cinder = cinder
	return masks

## The next image of `file`, `size` texels of `texel_bytes`; null if the file ends first.
static func _image(file: FileAccess, size: Vector2i, format: Image.Format, texel_bytes: int) -> Image:
	var bytes := file.get_buffer(size.x * size.y * texel_bytes)
	if bytes.size() != size.x * size.y * texel_bytes:
		return null
	return Image.create_from_data(size.x, size.y, false, format, bytes)
