class_name DataFile
extends RefCounted
## Reading a data file the way the systems do: parse it, check it against its
## schema and say aloud what is wrong. The file's content comes back in any
## case, so that a system keeps going with what it can use; a file that cannot
## be parsed comes back as null.

## The file walked against `schema`; `check.value` is what it held.
static func inspect(path: String, schema: Dictionary) -> DataCheck:
	var check := DataCheck.new()
	if not FileAccess.file_exists(path):
		check.problems.append("(file): the file does not exist")
		return check
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		check.problems.append("line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return check
	check.value = parser.data
	check.walk(schema, check.value, "")
	return check

## The problems of the file, the refs to kinds it defines itself included.
static func problems(path: String, schema: Dictionary) -> PackedStringArray:
	return inspect(path, schema).local_problems()

## What the file holds. Every problem goes to the error log with the path and
## the field.
static func read(path: String, schema: Dictionary) -> Variant:
	var check := inspect(path, schema)
	for problem: String in check.local_problems():
		push_error("data file %s: %s" % [path, problem])
	return check.value
