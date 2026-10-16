class_name Acquaintance
extends RefCounted
## What has grown between the player and one villager: the warmth, the circle
## it has opened, and which of the person's stories were named and told.
##
## Warmth only grows, and by events, not by their number: each event counts
## once in a game day. A circle opens at its threshold, one circle a day.

## What each event is worth.
const EVENTS := {"walk": 1, "sit": 1, "toast": 1, "food": 1, "story": 1, "favorite_place": 1, "old_camp": 1, "catch": 1}
## What a treat of the person's favourite food is worth in place of "food".
const FAVORITE_FOOD := 2
## A story the person has spoken of, and one heard to the end.
const NAMED := "named"
const TOLD := "told"

## Warmth at which each circle opens (PersonSheet.circles).
var thresholds: Array[int] = [0, 3, 10, 20]
var warmth := 0
var circle := 0
## The day the circle last opened, 0 for never.
var risen_day := 0
## The person has told their name.
var introduced := false
## Event -> [day it last counted, what it was worth that day].
var marks: Dictionary = {}
## Story id -> {state (NAMED or TOLD), beat (the last one heard, -1 for none)}.
var stories: Dictionary = {}
## What happens once a day, by its key ("greet", "treat") -> the day it last
## did.
var notes: Dictionary = {}
## The day stories were last heard to the end, and how many that day.
var told_day := 0
var told_count := 0
## The story whose closing hook is still to be said, "" for none.
var owed := ""

## Counts `event` on `day`, worth `amount` (the event's own worth when left
## out). The same event later that day adds only what it is worth above the
## first. Returns the warmth added.
func note(event: String, day: int, amount := -1) -> int:
	if not EVENTS.has(event):
		return 0
	var worth: int = amount if amount > 0 else EVENTS[event]
	var mark: Array = marks.get(event, [0, 0])
	var had: int = mark[1] if mark[0] == day else 0
	if worth <= had:
		return 0
	marks[event] = [day, worth]
	warmth += worth - had
	return worth - had

## Whether `key` has not yet happened on `day`; asking makes it happen.
func once(key: String, day: int) -> bool:
	var last: int = notes.get(key, 0)
	if last == day:
		return false
	notes[key] = day
	return true

## What the player brought the person on `day`: "catch", else "food" for a
## treat, else "".
func gift(day: int) -> String:
	for event: String in PeopleIds.GIFTS:
		var mark: Array = marks.get(event, [0, 0])
		if mark[0] == day:
			return event
	return ""

## Opens the next circle if the warmth has reached it and none opened on
## `day`. Returns whether one opened.
func settle(day: int) -> bool:
	if circle >= thresholds.size() - 1 or risen_day == day or warmth < thresholds[circle + 1]:
		return false
	circle += 1
	risen_day = day
	return true

## "" for a story never spoken of, NAMED or TOLD.
func state(story_id: String) -> String:
	return stories[story_id].state if stories.has(story_id) else ""

## The last beat of the story the listener heard, -1 for none.
func heard(story_id: String) -> int:
	return stories[story_id].beat if stories.has(story_id) else -1

func name_story(story_id: String) -> void:
	if not stories.has(story_id):
		stories[story_id] = {"state": NAMED, "beat": -1}

## Beat `beat` of the story was said to the listener.
func hear(story_id: String, beat: int) -> void:
	name_story(story_id)
	if stories[story_id].state == NAMED:
		stories[story_id].beat = beat

## The story was heard to the end on `day`; `owes` leaves its closing hook to
## be said.
func finish(story_id: String, day: int, owes: bool) -> void:
	name_story(story_id)
	stories[story_id].state = TOLD
	told_count = told_on(day) + 1
	told_day = day
	note("story", day)
	if owes:
		owed = story_id

## Stories heard to the end on `day`.
func told_on(day: int) -> int:
	return told_count if told_day == day else 0

func to_dict() -> Dictionary:
	return {"warmth": warmth, "circle": circle, "risen_day": risen_day, "introduced": introduced, "marks": marks,
		"notes": notes, "stories": stories, "told_day": told_day, "told_count": told_count, "owed": owed}

## Takes what a save holds; what is missing or of the wrong kind starts anew.
func restore(data: Variant) -> void:
	if not data is Dictionary:
		return
	var saved: Dictionary = data
	warmth = maxi(0, _whole(saved.get("warmth")))
	circle = clampi(_whole(saved.get("circle")), 0, thresholds.size() - 1)
	while circle > 0 and warmth < thresholds[circle]:
		circle -= 1
	risen_day = _whole(saved.get("risen_day"))
	introduced = saved.get("introduced") is bool and saved.introduced
	told_day = _whole(saved.get("told_day"))
	told_count = maxi(0, _whole(saved.get("told_count")))
	owed = saved.owed if saved.get("owed") is String else ""
	marks = {}
	var saved_marks: Variant = saved.get("marks")
	if saved_marks is Dictionary:
		for event: Variant in saved_marks:
			var mark: Variant = saved_marks[event]
			if not event is String or not EVENTS.has(event) or not mark is Array:
				continue
			var pair: Array = mark
			if pair.size() == 2:
				marks[event] = [_whole(pair[0]), _whole(pair[1])]
	notes = {}
	var saved_notes: Variant = saved.get("notes")
	if saved_notes is Dictionary:
		for key: Variant in saved_notes:
			var noted: Variant = saved_notes[key]
			if key is String and (noted is float or noted is int) and is_finite(float(noted)) and float(noted) == floorf(float(noted)):
				notes[key] = int(noted)
	stories = {}
	var saved_stories: Variant = saved.get("stories")
	if saved_stories is Dictionary:
		for story_id: Variant in saved_stories:
			var entry: Variant = saved_stories[story_id]
			if not story_id is String or not entry is Dictionary:
				continue
			var row: Dictionary = entry
			var kept: Variant = row.get("state")
			if kept is String and (kept == NAMED or kept == TOLD):
				stories[story_id] = {"state": kept, "beat": maxi(-1, _whole(row.get("beat"), -1))}

static func _whole(value: Variant, fallback := 0) -> int:
	if (value is float or value is int) and is_finite(float(value)):
		return int(value)
	return fallback
