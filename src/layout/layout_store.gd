extends RefCounted
## Files of the hand-placed objects, read by the game and written by the
## layout scene (scenes/alpine/layout.tscn, src/layout/map_layout.gd).
##
## Houses and cottages live in village_plan.json and the yard props in the
## village pack's layout.json, as before. The scanned stones and the forest's
## wood are lists too (rocks.json, forest_wood.json), written by the layout scene.
const PLAN := "res://assets/generated/layout/village_plan.json"
const PROPS := "res://assets/models/village_pack/layout.json"
const ROCKS := "res://assets/generated/layout/rocks.json"
const FOREST_WOOD := "res://assets/generated/layout/forest_wood.json"
## Pieces of the Blender map the loaded level still shows, for the layout scene.
const MAP_CONTEXT := "res://assets/generated/layout/map_context.json"

static func read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)

## A list as JSON with one record per line, so that a moved stone is one
## changed line.
static func rows_text(rows: Array) -> String:
	var lines := PackedStringArray()
	for row: Variant in rows:
		lines.append(JSON.stringify(row, "", false))
	return "[\n" + ",\n".join(lines) + "\n]\n"

## The list at `path`, or nothing if the file is missing.
static func placed(path: String) -> Array:
	var data: Variant = read(path)
	return data if data is Array else []

## A transform as twelve numbers: the basis columns, then the origin.
static func pack(xform: Transform3D) -> Array:
	var values := []
	for vector: Vector3 in [xform.basis.x, xform.basis.y, xform.basis.z, xform.origin]:
		for axis in 3:
			values.append(snappedf(vector[axis], 0.0001))
	return values

static func unpack(values: Array) -> Transform3D:
	return Transform3D(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]),
		Vector3(values[6], values[7], values[8]), Vector3(values[9], values[10], values[11]))
