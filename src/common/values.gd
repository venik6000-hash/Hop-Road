class_name Values
extends RefCounted
## Plain values read out of parsed data files, saves and untyped tables. The
## project's compiler turns an untyped value given where a type is asked for
## into an error (project.godot, [debug]); these say what the value is meant
## to be and check it, as float() and int() do.

## The first three numbers of a list of a data file, as a point.
static func vec3(values: Variant) -> Vector3:
	var listed: Array = values
	return Vector3(real(listed[0]), real(listed[1]), real(listed[2]))

## The first two numbers of a list, as a point of a plane.
static func vec2(values: Variant) -> Vector2:
	var listed: Array = values
	return Vector2(real(listed[0]), real(listed[1]))

## `value` within [low, high] when it is a finite number, else `fallback`:
## what a save holds is checked before the game takes it.
static func number(value: Variant, fallback: float, low: float, high: float) -> float:
	if value is float or value is int:
		var found := real(value)
		if is_finite(found):
			return clampf(found, low, high)
	return fallback

## `value` as a float, as float() makes it: a number as it is, true as 1, a
## text by its digits; 0 for anything else.
static func real(value: Variant) -> float:
	if value is float:
		return value
	if value is int:
		var whole_number: int = value
		return whole_number
	if value is bool:
		return 1.0 if value else 0.0
	if value is String or value is StringName:
		return str(value).to_float()
	return 0.0

## `value` as an int, as int() makes it: a float cut towards zero, true as 1,
## a text by its digits; 0 for anything else.
static func whole(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var fraction: float = value
		return int(fraction)
	if value is bool:
		return 1 if value else 0
	if value is String or value is StringName:
		return str(value).to_int()
	return 0

## `value` as a truth: false, 0, null and the empty ones are false.
static func flag(value: Variant) -> bool:
	return true if value else false

## `value` when it is a list, else an empty one.
static func list(value: Variant) -> Array:
	return value if value is Array else []

## `value` when it is a table, else an empty one.
static func table(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
