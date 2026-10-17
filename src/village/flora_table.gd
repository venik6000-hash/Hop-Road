class_name FloraTable
extends RefCounted
## The village's ground plants as data (assets/village/flora.json;
## WorldSchemas.flora): each plant's scanned model, the triangles of its
## variants, its scale range, sway, shadow and view, and what grows where, by
## relative odds. VillageFlora grows them.

const PATH := "res://assets/village/flora.json"
## The scanned models: <DIRECTORY><model>/<model>_1k.gltf.
const DIRECTORY := "res://assets/models/flora/"

## Plant -> {model, tris, least, scale, sway, shadow, view}.
var plants: Dictionary = {}
## Mix -> {plant: odds}.
var mixes: Dictionary = {}

static func read() -> FloraTable:
	var table := FloraTable.new()
	var data: Variant = DataFile.read(PATH, WorldSchemas.flora())
	if data is Dictionary:
		var found: Dictionary = data
		table.plants = found.get("plants", {})
		table.mixes = found.get("mixes", {})
	return table

static func model_path(model: String) -> String:
	return "%s%s/%s_1k.gltf" % [DIRECTORY, model, model]
