class_name DataCheck
extends RefCounted
## One parsed file walked against a DataSchema: what is wrong with it, the ids
## it defines and the ids it points at.

## Problems past this many are counted, not listed: a file wrong in every row
## must not flood the log.
const MAX_PROBLEMS := 40

## "<where>: <what>", where being the field's path in the file ("stories[2].circle").
var problems := PackedStringArray()
## Kind -> {id: where it is defined}.
var defs: Dictionary = {}
## [kind, id, where] of every `ref`.
var refs: Array[Array] = []
## What the file held, as parsed.
var value: Variant = null

## Problems past MAX_PROBLEMS.
var dropped := 0

func ok() -> bool:
	return problems.is_empty()

func walk(schema: Dictionary, item: Variant, where: String) -> void:
	var before := problems.size() + dropped
	_walk_kind(schema, item, where)
	if schema.has("rule") and problems.size() + dropped == before:
		var rule: Callable = schema.rule
		var wrong: String = rule.call(item)
		if not wrong.is_empty():
			_add(where, wrong)

func _walk_kind(schema: Dictionary, item: Variant, where: String) -> void:
	var kind: StringName = schema.kind
	match kind:
		&"any":
			pass
		&"object":
			_object(schema, item, where)
		&"list":
			_list(schema, item, where)
		&"table":
			_table(schema, item, where)
		&"vector":
			_vector(schema, item, where)
		&"tagged":
			_tagged(schema, item, where)
		&"text":
			if not item is String:
				_add(where, "expected text, got %s" % _what(item))
			elif not bool(schema.empty) and (item as String).is_empty():
				_add(where, "the text is empty")
		&"number":
			_number(schema, item, where, false)
		&"whole":
			_number(schema, item, where, true)
		&"flag":
			if not item is bool:
				_add(where, "expected true or false, got %s" % _what(item))
		&"choice":
			var values: Array = schema.values
			if not values.has(item):
				_add(where, "%s is none of %s" % [_what(item), values])
		&"file":
			if not item is String:
				_add(where, "expected a path, got %s" % _what(item))
			elif not FileAccess.file_exists(item):
				_add(where, "the file %s does not exist" % item)
		&"either":
			_either(schema, item, where)
		&"stem":
			if not item is String or (item as String).is_empty():
				_add(where, "expected a file name, got %s" % _what(item))
			else:
				var path: String = "%s%s%s" % [schema.directory, item, schema.suffix]
				if not FileAccess.file_exists(path):
					_add(where, "the file %s does not exist" % path)
		&"id":
			_id(schema, item, where)
		&"ref":
			if not item is String or (item as String).is_empty():
				_add(where, "expected the id of a %s, got %s" % [schema.of, _what(item)])
			else:
				refs.append([schema.of, item, where])
		_:
			_add(where, "the schema has no kind %s" % kind)

## The refs to a kind this file defines itself that find no id; a kind the
## file does not define is left to DataLinks.
func local_problems() -> PackedStringArray:
	var result := problems.duplicate()
	if dropped > 0:
		result.append("... and %d more problems" % dropped)
	for ref: Array in refs:
		var kind: StringName = ref[0]
		if defs.has(kind) and not (defs[kind] as Dictionary).has(ref[1]):
			result.append("%s: %s is not a %s of this file" % [ref[2], ref[1], kind])
	return result

func _either(schema: Dictionary, item: Variant, where: String) -> void:
	var options: Array = schema.options
	for option: Dictionary in options:
		var trial := DataCheck.new()
		trial.walk(option, item, where)
		if trial.ok():
			for kind: StringName in trial.defs:
				for name: String in trial.defs[kind]:
					_define(kind, name, trial.defs[kind][name])
			refs.append_array(trial.refs)
			return
	_add(where, "%s fits none of the %d forms" % [_what(item), options.size()])

func _object(schema: Dictionary, item: Variant, where: String) -> void:
	if not item is Dictionary:
		_add(where, "expected an object, got %s" % _what(item))
		return
	var data: Dictionary = item
	var fields: Dictionary = schema.fields
	for key: String in fields:
		var field: Dictionary = fields[key]
		if not data.has(key):
			if not field.get("optional", false):
				_add(where, "the field '%s' is missing" % key)
			continue
		walk(field, data[key], _join(where, key))
	if not bool(schema.open):
		for key: Variant in data:
			if not fields.has(key):
				_add(where, "the field '%s' is not in the schema" % key)

func _list(schema: Dictionary, item: Variant, where: String) -> void:
	if not item is Array:
		_add(where, "expected a list, got %s" % _what(item))
		return
	var data: Array = item
	if data.size() < int(schema.min) or (int(schema.max) >= 0 and data.size() > int(schema.max)):
		_add(where, "%d items, expected %s" % [data.size(), _span(int(schema.min), int(schema.max))])
	var each: Dictionary = schema.item
	for index in data.size():
		walk(each, data[index], "%s[%d]" % [where, index])

func _table(schema: Dictionary, item: Variant, where: String) -> void:
	if not item is Dictionary:
		_add(where, "expected a table, got %s" % _what(item))
		return
	var data: Dictionary = item
	var each: Dictionary = schema.value
	var key_kind: StringName = schema.key_kind
	var key_ref: StringName = schema.key_ref
	for key: Variant in data:
		if not key is String:
			_add(where, "the key %s is not text" % _what(key))
			continue
		if key_kind != &"":
			_define(key_kind, key, _join(where, key))
		if key_ref != &"":
			refs.append([key_ref, key, _join(where, key)])
		walk(each, data[key], _join(where, key))

func _vector(schema: Dictionary, item: Variant, where: String) -> void:
	if not item is Array:
		_add(where, "expected %d numbers, got %s" % [schema.size, _what(item)])
		return
	var data: Array = item
	if data.size() != int(schema.size):
		_add(where, "%d numbers, expected %d" % [data.size(), schema.size])
		return
	for index in data.size():
		_number(schema, data[index], "%s[%d]" % [where, index], false)

func _tagged(schema: Dictionary, item: Variant, where: String) -> void:
	if not item is Array or (item as Array).is_empty() or not (item as Array)[0] is String:
		_add(where, "expected a list that begins with a name, got %s" % _what(item))
		return
	var data: Array = item
	var forms: Dictionary = schema.forms
	var tag: String = data[0]
	if not forms.has(tag):
		_add(where, "'%s' is none of %s" % [tag, forms.keys()])
		return
	var rest: Array = forms[tag]
	if data.size() != rest.size() + 1:
		_add(where, "'%s' takes %d more items, got %d" % [tag, rest.size(), data.size() - 1])
		return
	for index in rest.size():
		walk(rest[index], data[index + 1], "%s[%d]" % [where, index + 1])

func _number(schema: Dictionary, item: Variant, where: String, whole: bool) -> void:
	if not (item is float or item is int) or not is_finite(float(item)):
		_add(where, "expected %s, got %s" % ["a whole number" if whole else "a number", _what(item)])
		return
	var number: float = float(item)
	if whole and number != floorf(number):
		_add(where, "expected a whole number, got %s" % _what(item))
	elif number < float(schema.low) or number > float(schema.high):
		_add(where, "%s is outside %s..%s" % [_what(item), schema.low, schema.high])

func _id(schema: Dictionary, item: Variant, where: String) -> void:
	if not item is String or (item as String).is_empty():
		_add(where, "expected an id, got %s" % _what(item))
		return
	_define(schema.of, item, where)

func _define(kind: StringName, name: String, where: String) -> void:
	if not defs.has(kind):
		defs[kind] = {}
	var known: Dictionary = defs[kind]
	if known.has(name):
		_add(where, "the %s '%s' is also defined at %s" % [kind, name, known[name]])
	else:
		known[name] = where

func _add(where: String, what: String) -> void:
	if problems.size() >= MAX_PROBLEMS:
		dropped += 1
		return
	problems.append("%s: %s" % [where if not where.is_empty() else "(file)", what])

static func _join(where: String, key: String) -> String:
	return key if where.is_empty() else "%s.%s" % [where, key]

static func _span(low: int, high: int) -> String:
	if high < 0:
		return "at least %d" % low
	return "%d" % low if low == high else "%d to %d" % [low, high]

static func _what(item: Variant) -> String:
	if item is String or item is float or item is int or item is bool:
		return "'%s'" % item if item is String else str(item)
	return type_string(typeof(item)).to_lower()
