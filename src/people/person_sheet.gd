class_name PersonSheet
extends RefCounted
## A villager as the data has them (assets/loop/people/<id>.json): the name,
## the role they go by until they tell it, the warmth each circle opens at,
## the food and the place they love, their lines and their stories.
##
## `lines` are looked up by a key ("accept", "farewell", ...); where a sheet
## has none, the common sheet's is said (PeopleBook.line). A key may have a
## variant for a circle, "greet_2": line_at takes the one of the highest
## circle opened. `idle` are the remarks of a stranger, `idle_fire` those kept
## for a fire, `idle_table` those for a table and the bar.
##
## A story is {id, title, circle, context, with, voices, hook_before, beats,
## hook_after, echo}. `context` maps "zone", "part", "weather", "activity",
## "gift" and "beer" (the sort of the player's own beer, ValleyLoop.beer_words)
## to the values the story may sound at; a key left out allows any
## (StoryRules). `with` is the villager a shared story is told together with,
## "" for a story of one; `voices` names who says each beat, and is empty
## when the owner says them all.

var id := ""
var name := ""
var role := ""
## Warmth at which circles 0, 1, 2 and 3 open.
var circles: Array[int] = [0, 3, 10, 20]
## "potato", "fish" or "".
var favorite_food := ""
## The zone (ValleyZones) of the place they love, and the way to it from their
## road as [x, z] points; the last is the place itself.
var favorite_zone := ""
var favorite_path: Array[Vector2] = []
var lines: Dictionary = {}
var idle: Array[String] = []
var idle_fire: Array[String] = []
var idle_table: Array[String] = []
## Where they are through the day (VillagerDay.entries); empty for one who
## keeps to the road or to their work.
var day: Array[Dictionary] = []
## Where rain sends them from an open place: one of VillagerDay.SHELTERS or "".
var shelter := ""
## The seat of the tavern's hall they take, "" for none.
var hall_seat := ""
## Where they stand in the yard, as (x, z); Vector2.INF for nowhere.
var yard_spot := Vector2.INF
var stories: Array[Dictionary] = []

static func load_file(path: String, of_id: String) -> PersonSheet:
	return from_dict(of_id, DataFile.read(path, PeopleSchemas.sheet()))

## A sheet from parsed JSON; what is missing or of the wrong kind stays empty.
static func from_dict(of_id: String, data: Variant) -> PersonSheet:
	var sheet := PersonSheet.new()
	sheet.id = of_id
	if not data is Dictionary:
		return sheet
	var saved: Dictionary = data
	sheet.name = _text(saved.get("name"))
	sheet.role = _text(saved.get("role"))
	sheet.favorite_food = _text(saved.get("favorite_food"))
	var steps: Variant = saved.get("circles")
	if steps is Array:
		var values: Array = steps
		if values.size() == sheet.circles.size():
			for index: int in values.size():
				if values[index] is float or values[index] is int:
					sheet.circles[index] = int(values[index])
	var place: Variant = saved.get("favorite_place")
	if place is Dictionary:
		var favorite: Dictionary = place
		sheet.favorite_zone = _text(favorite.get("zone"))
		var path: Variant = favorite.get("path")
		if path is Array:
			for point: Variant in path:
				if not point is Array:
					continue
				var pair: Array = point
				if pair.size() == 2:
					sheet.favorite_path.append(Vector2(float(pair[0]), float(pair[1])))
	sheet.day = VillagerDay.entries(saved.get("day"))
	var cover := _text(saved.get("shelter"))
	if VillagerDay.SHELTERS.has(cover):
		sheet.shelter = cover
	sheet.hall_seat = _text(saved.get("hall_seat"))
	var spot: Variant = saved.get("yard_spot")
	if spot is Array:
		var yard: Array = spot
		if yard.size() == 2 and _is_number(yard[0]) and _is_number(yard[1]):
			sheet.yard_spot = Vector2(float(yard[0]), float(yard[1]))
	var said: Variant = saved.get("lines")
	if said is Dictionary:
		for key: Variant in said:
			if key is String and said[key] is String:
				sheet.lines[key] = said[key]
	sheet.idle = _texts(saved.get("idle"))
	sheet.idle_fire = _texts(saved.get("idle_fire"))
	sheet.idle_table = _texts(saved.get("idle_table"))
	var told: Variant = saved.get("stories")
	if told is Array:
		for entry: Variant in told:
			var story := _story(entry, of_id)
			if not story.is_empty():
				sheet.stories.append(story)
	return sheet

## The person's own line for `key`, "" when the sheet has none.
func line(key: String) -> String:
	return lines.get(key, "")

## The person's line for `key` at a circle: the variant of the highest circle
## from `circle` down ("key_3", "key_2", "key_1"), then the plain one; "" when
## the sheet has none.
func line_at(key: String, circle: int) -> String:
	for level in range(circle, 0, -1):
		var said := line("%s_%d" % [key, level])
		if not said.is_empty():
			return said
	return line(key)

func has_yard_spot() -> bool:
	return yard_spot.is_finite()

## The story with this id, {} when the sheet has none.
func story(story_id: String) -> Dictionary:
	for entry: Dictionary in stories:
		if entry.id == story_id:
			return entry
	return {}

static func _story(entry: Variant, of_id: String) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var row: Dictionary = entry
	var beats := _texts(row.get("beats"))
	if _text(row.get("id")).is_empty() or beats.is_empty():
		return {}
	var context: Dictionary = {}
	var conditions: Variant = row.get("context")
	if conditions is Dictionary:
		for key: Variant in conditions:
			var allowed := _texts(conditions[key])
			if key is String and not allowed.is_empty():
				context[key] = allowed
	var circle: Variant = row.get("circle")
	var partner := _text(row.get("with"))
	return {
		"id": _text(row.get("id")),
		"title": _text(row.get("title")),
		"circle": int(circle) if circle is float or circle is int else 1,
		"context": context,
		"with": partner,
		"voices": _voices(row.get("voices"), beats.size(), of_id, partner),
		"hook_before": _text(row.get("hook_before")),
		"beats": beats,
		"hook_after": _text(row.get("hook_after")),
		"echo": _text(row.get("echo")),
	}

## Who says each beat of a shared story: one of the two for every beat, else
## nothing.
static func _voices(value: Variant, beats: int, of_id: String, partner: String) -> Array[String]:
	var result: Array[String] = []
	var nobody: Array[String] = []
	if partner.is_empty() or not value is Array:
		return nobody
	var list: Array = value
	if list.size() != beats:
		return nobody
	for voice: Variant in list:
		if not voice is String or (voice != of_id and voice != partner):
			return nobody
		result.append(voice)
	return result

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _text(value: Variant) -> String:
	return value if value is String else ""

static func _texts(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			if item is String:
				var text: String = item
				if not text.is_empty():
					result.append(text)
	return result
