class_name DataSchema
extends RefCounted
## What a data file may hold. A schema is a Dictionary built by the functions
## below; DataCheck walks a parsed file against it and lists what is wrong,
## field by field. The schemas of the game's files stand in src/data/schemas/,
## and DataFiles names the file each one describes (docs/LEVEL.md, «Данные содержимого»).
##
## - `object` has the fields it names, all required unless wrapped in
##   `optional`; a field it does not name is a problem unless it is `open`;
## - `list`, `table` (any keys, one kind of value), `vector` (a point of n
##   numbers) and `tagged` (a list whose first item names the form of the rest)
##   hold other schemas;
## - `text` is a string that is not empty, `any_text` may be empty; `number`
##   is finite, `whole` has no fraction, `flag` is true or false, `choice` is
##   one of the values;
## - `either` fits one of several schemas;
## - `file` is a text that names a file of the project, `stem` one by its
##   name in a folder;
## - `checked` adds a rule in code to another schema;
## - `id` names a thing of a kind and `ref` points at one; DataLinks checks
##   that every `ref` finds its `id`, across files.

static func object(fields: Dictionary, open := false) -> Dictionary:
	return {"kind": &"object", "fields": fields, "open": open}

## The field may be missing.
static func optional(schema: Dictionary) -> Dictionary:
	var copy := schema.duplicate()
	copy["optional"] = true
	return copy

static func list(item: Dictionary, min_size := 0, max_size := -1) -> Dictionary:
	return {"kind": &"list", "item": item, "min": min_size, "max": max_size}

## A dictionary with any keys and one schema for the values. A non-empty
## `key_kind` makes each key the id of a thing of that kind; a non-empty
## `key_ref` makes each key point at one.
static func table(value: Dictionary, key_kind := &"", key_ref := &"") -> Dictionary:
	return {"kind": &"table", "value": value, "key_kind": key_kind, "key_ref": key_ref}

## A list of `size` numbers: a point, a size, a colour.
static func vector(size: int, low := -INF, high := INF) -> Dictionary:
	return {"kind": &"vector", "size": size, "low": low, "high": high}

## A list whose first item is one of the keys of `forms`; the items after it
## follow the schemas `forms` holds for that key.
static func tagged(forms: Dictionary) -> Dictionary:
	return {"kind": &"tagged", "forms": forms}

static func text() -> Dictionary:
	return {"kind": &"text", "empty": false}

static func any_text() -> Dictionary:
	return {"kind": &"text", "empty": true}

static func number(low := -INF, high := INF) -> Dictionary:
	return {"kind": &"number", "low": low, "high": high}

static func whole(low := -INF, high := INF) -> Dictionary:
	return {"kind": &"whole", "low": low, "high": high}

static func flag() -> Dictionary:
	return {"kind": &"flag"}

static func choice(values: Array) -> Dictionary:
	return {"kind": &"choice", "values": values}

## The value fits one of the `options`.
static func either(options: Array) -> Dictionary:
	return {"kind": &"either", "options": options}

## A path of the project (res://...) that names a file.
static func file() -> Dictionary:
	return {"kind": &"file"}

## A text that names a file by its stem: `directory + text + suffix` exists.
static func stem(directory: String, suffix: String) -> Dictionary:
	return {"kind": &"stem", "directory": directory, "suffix": suffix}

## A text that is the id of a thing of `of_kind`: it must be new among the
## ids of the kind in the file.
static func id(of_kind: StringName) -> Dictionary:
	return {"kind": &"id", "of": of_kind}

## A text that must be the id of a thing of `of_kind`, in this file or another.
static func ref(of_kind: StringName) -> Dictionary:
	return {"kind": &"ref", "of": of_kind}

## `inner`, and then a rule that a schema cannot say: `rule` takes the value
## and returns "" when it holds, else what is wrong.
static func checked(inner: Dictionary, rule: Callable) -> Dictionary:
	var copy := inner.duplicate()
	copy["rule"] = rule
	return copy

## Whatever the value is. Only for what the game passes on without reading.
static func any() -> Dictionary:
	return {"kind": &"any"}
