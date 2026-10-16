class_name DataLinks
extends RefCounted
## The ids that files point at in each other and in the code: a recipe names
## a beer, a villager a zone, a guide step a note of the profile. Files are
## added with the DataCheck of each, ids that the code owns with `provide`;
## problems() lists every `ref` that finds no `id`, every id two files define,
## and every kind that the code and the data both name with different ids.

## Kind -> {id: where a file defines it}.
var defs: Dictionary = {}
## Kind -> {id: true} for the ids the code names.
var code: Dictionary = {}
## [kind, id, where, file] of every ref.
var refs: Array[Array] = []

var _doubles := PackedStringArray()
var _exact: Dictionary = {}

func add(path: String, check: DataCheck) -> void:
	for kind: StringName in check.defs:
		var known := _known(defs, kind)
		var found: Dictionary = check.defs[kind]
		for name: String in found:
			if known.has(name):
				_doubles.append("%s: %s: the %s '%s' is also defined at %s" % [path, found[name], kind, name, known[name]])
			else:
				known[name] = "%s: %s" % [path, found[name]]
	for ref: Array in check.refs:
		refs.append([ref[0], ref[1], ref[2], path])

## Ids of `kind` that the code names (constants). With `exact` the data must
## define the same ids; without it the code names only some of them.
func provide(kind: StringName, ids: Array, exact := true) -> void:
	var known := _known(code, kind)
	for name: Variant in ids:
		known[str(name)] = true
	if exact:
		_exact[kind] = true

func problems() -> PackedStringArray:
	var result := _doubles.duplicate()
	for kind: StringName in code:
		if not defs.has(kind) or not _exact.has(kind):
			continue
		var in_code: Dictionary = code[kind]
		var in_data: Dictionary = defs[kind]
		for name: String in in_data:
			if not in_code.has(name):
				result.append("%s: the %s '%s' is in the data and not in the code" % [in_data[name], kind, name])
		for name: String in in_code:
			if not in_data.has(name):
				result.append("the %s '%s' is in the code and not in the data" % [kind, name])
	for ref: Array in refs:
		var kind: StringName = ref[0]
		var name: String = ref[1]
		if not defs.has(kind) and not code.has(kind):
			result.append("%s: %s: nothing defines the kind '%s'" % [ref[3], ref[2], kind])
		elif not (defs.has(kind) and (defs[kind] as Dictionary).has(name)) and not (code.has(kind) and (code[kind] as Dictionary).has(name)):
			result.append("%s: %s: '%s' is not a %s" % [ref[3], ref[2], name, kind])
	return result

func _known(of: Dictionary, kind: StringName) -> Dictionary:
	if not of.has(kind):
		of[kind] = {}
	return of[kind]
