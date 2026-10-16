extends RefCounted
## Save version 1 to 2 (SaveService.MIGRATIONS). Version 1 kept the fires and
## the catch in files of their own beside the save; version 2 holds them as
## the sections "camping" and "fishing". The old files are read once and left
## where they are.

## The files that held the fires and the catch, beside the save.
const CAMPING := "camping.json"
const FISHING := "lakeside-fishing.json"

## `saved` (version 1, read from `path`; "" when it lies nowhere) as version 2.
static func apply(saved: Dictionary, path: String) -> Dictionary:
	saved["camping"] = _old_file(path, CAMPING)
	saved["fishing"] = _old_file(path, FISHING)
	return saved

## The version-1 file `file_name` beside the save at `path`, without its
## version; {} when there is none that reads.
static func _old_file(path: String, file_name: String) -> Dictionary:
	if path.is_empty():
		return {}
	var file := path.get_base_dir().path_join(file_name)
	if not FileAccess.file_exists(file):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not data is Dictionary:
		return {}
	var old: Dictionary = data
	if old.get("version") != 1:
		return {}
	old.erase("version")
	return old
