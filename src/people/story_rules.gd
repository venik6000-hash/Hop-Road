class_name StoryRules
extends RefCounted
## Which of a person's stories may sound at a moment, and which of them does.
## A moment is {zone, part, weather, activity, gift, company, ...}
## (Storyteller); a story's context maps some of these keys to the values it
## may sound at. A shared story (PersonSheet) also needs its other teller in
## the moment's company.

## How seldom each weather comes: a story kept for a storm outweighs one for
## a fair day.
const WEATHER_RARITY := {"clear": 1, "fair": 1, "overcast": 2, "mist": 3, "rain": 3, "storm": 5}
## What a shared story adds to the rarity of its context: the two are seldom
## found together.
const SHARED_RARITY := 2

## Whether the moment has, for every key of the context, one of its values.
static func matches(context: Dictionary, moment: Dictionary) -> bool:
	for key: String in context:
		var allowed: Array = context[key]
		var now: Variant = moment.get(key)
		if not now is String or not allowed.has(now):
			return false
	return true

## Whether the story may sound at the moment: its context matches and, for a
## shared story, the one it is told with is in the company.
static func fits(story: Dictionary, moment: Dictionary) -> bool:
	if not matches(story.context, moment):
		return false
	var partner: String = story.get("with", "")
	if partner.is_empty():
		return true
	var company: Variant = moment.get("company", [])
	if not company is Array:
		return false
	var present: Array = company
	return present.has(partner)

## How seldom a context comes together. A place, an activity or a gift counts
## 1; the part of the day the more, the fewer parts it allows; the weather as
## the commonest of the kinds it allows.
static func rarity(context: Dictionary) -> int:
	var total := 0
	for key: String in context:
		var allowed: Array = context[key]
		if key == "part":
			total += maxi(1, DayClock.PARTS.size() - allowed.size())
		elif key == "weather":
			var commonest := 0
			for kind: String in allowed:
				var worth: int = WEATHER_RARITY.get(kind, 1)
				commonest = worth if commonest == 0 else mini(commonest, worth)
			total += maxi(1, commonest)
		else:
			total += 1
	return total

## The story to tell at `moment`, out of `stories` in the order of the sheet:
## of those the circle has opened, not yet told and fitting the moment, the
## one broken off before, then the one with the rarer context, then the one of
## the higher circle, then the earlier. A shared story ranks as one with a
## context rarer by SHARED_RARITY. {} when none fits.
static func choose(stories: Array[Dictionary], bond: Acquaintance, moment: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_rank := -1
	for story: Dictionary in stories:
		if story.circle > bond.circle or bond.state(story.id) == Acquaintance.TOLD or not fits(story, moment):
			continue
		var partner: String = story.get("with", "")
		var seldom: int = rarity(story.context) + (0 if partner.is_empty() else SHARED_RARITY)
		var rank: int = (10000 if bond.heard(story.id) >= 0 else 0) + seldom * 100 + story.circle
		if rank > best_rank:
			best_rank = rank
			best = story
	return best
