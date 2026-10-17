class_name LineTable
extends RefCounted
## What a system says by id: the `lines` of a data file (assets/brewing/lines.json,
## assets/camping/lines.json). A line is the Russian text, a key of the
## translation tables; the caller translates it where it shows it.
## tests/test_data_files.gd checks that every id the code says is in the file
## and every line of the file is said.

## The files of lines and who says them.
const BREWERY := "res://assets/brewing/lines.json"
const CAMP := "res://assets/camping/lines.json"

var path := ""
## Id -> text.
var lines: Dictionary = {}

static func read(from: String, schema: Dictionary) -> LineTable:
	var table := LineTable.new()
	table.path = from
	var data: Variant = DataFile.read(from, schema)
	if data is Dictionary and Values.table(data).get("lines") is Dictionary:
		table.lines = Values.table(data).lines
	return table

## The line `id`; the id itself, with an error, when the file lacks it.
func text(id: StringName) -> String:
	var key := String(id)
	if not lines.has(key):
		push_error("data file %s: no line '%s'" % [path, key])
		return key
	return str(lines[key])
