class_name PeopleSchemas
extends RefCounted
## The schema of a sheet of assets/loop/people/<id>.json (PersonSheet; the
## fields are told in docs/LIFE.md).

const D := preload("res://src/data/data_schema.gd")

static func sheet() -> Dictionary:
	var hour := D.number(0.0, 24.0)
	var circle := D.whole(1, 3)
	var lines := D.checked(D.table(D.text()), func(value: Variant) -> String:
		for key: String in (value as Dictionary):
			var wrong := PeopleIds.line_problem(key)
			if not wrong.is_empty():
				return "'%s': %s" % [key, wrong]
		return "")
	var story := D.object({
		"id": D.id(&"story"),
		"title": D.text(),
		"circle": circle,
		"context": D.object({
			"zone": D.optional(D.list(D.ref(&"zone"), 1)),
			"part": D.optional(D.list(D.choice(DayClock.PARTS), 1)),
			"weather": D.optional(D.list(D.choice(WeatherSystem.KINDS), 1)),
			"activity": D.optional(D.list(D.choice(PeopleIds.ACTIVITIES), 1)),
			"gift": D.optional(D.list(D.choice(PeopleIds.GIFTS), 1)),
			"beer": D.optional(D.list(D.ref(&"sort"), 1)),
		}),
		"with": D.optional(D.ref(&"person")),
		"voices": D.optional(D.list(D.ref(&"person"), 2)),
		"hook_before": D.text(),
		"beats": D.list(D.text(), 1),
		"hook_after": D.text(),
		"echo": D.text(),
	})
	return D.object({
		"id": D.text(),
		"name": D.any_text(),
		"role": D.any_text(),
		# A note to the author; it never sounds in the game.
		"about": D.optional(D.text()),
		"circles": D.checked(D.list(D.whole(0), 4, 4), func(value: Variant) -> String:
			var steps: Array = value
			for index in range(1, steps.size()):
				if float(steps[index]) <= float(steps[index - 1]):
					return "the warmth of a circle must rise"
			return ""),
		"favorite_food": D.any_text(),
		"favorite_place": D.object({
			"zone": D.optional(D.ref(&"zone")),
			"path": D.optional(D.list(D.vector(2), 1)),
		}),
		"day": D.optional(D.list(D.object({"from": hour, "to": hour, "at": D.choice(VillagerDay.PLACES)}), 1)),
		"shelter": D.optional(D.choice(VillagerDay.SHELTERS)),
		"hall_seat": D.optional(D.ref(&"seat")),
		"yard_spot": D.optional(D.vector(2)),
		"lines": lines,
		"idle": D.list(D.text()),
		"idle_fire": D.list(D.text()),
		"idle_table": D.optional(D.list(D.text())),
		"stories": D.list(story),
	})
