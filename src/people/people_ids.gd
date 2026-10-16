class_name PeopleIds
extends RefCounted
## The names the people's code and data share: the seven villagers, the foods
## they love, the gifts the player brings, what a moment of the day is doing,
## and the keys of the lines a sheet may hold (assets/loop/people/*.json).

const BORR := &"borr"
const KUL := &"kul"
const TOMAS := &"tomas"
const IVAR := &"ivar"
const MARTA := &"marta"
const LINA := &"lina"
const SAVVA := &"savva"
const VILLAGERS: Array[StringName] = [BORR, KUL, TOMAS, IVAR, MARTA, LINA, SAVVA]
## The sheet a passer-by speaks by, and a villager where their own has no line.
const COMMON := &"passerby"

const FOOD_POTATO := &"potato"
const FOOD_FISH := &"fish"
const FOODS: Array[StringName] = [FOOD_POTATO, FOOD_FISH]

## What the player brought a person today (Acquaintance.gift).
const GIFT_CATCH := &"catch"
const GIFT_FOOD := &"food"
const GIFTS: Array[StringName] = [GIFT_CATCH, GIFT_FOOD]

## What a villager is doing at a moment (CampSystem.moment).
const ACTIVITY_FIRE := &"fire"
const ACTIVITY_TABLE := &"table"
const ACTIVITY_BAR := &"bar"
const ACTIVITY_STAND := &"stand"
const ACTIVITY_WALK := &"walk"
const ACTIVITIES: Array[StringName] = [ACTIVITY_FIRE, ACTIVITY_TABLE, ACTIVITY_BAR, ACTIVITY_STAND, ACTIVITY_WALK]

## The keys of a sheet's `lines`. A key may end in a circle ("greet_2",
## PersonSheet.line_at). Besides these there are "food_<food>", "beer_<sort>"
## and "beer_flaw_<flaw>".
const LINES: Array[StringName] = [&"accept", &"accept_again", &"blocked", &"catch", &"company_full", &"farewell",
	&"favorite", &"fire_new", &"fire_old", &"greet", &"guide", &"guide_lost", &"guide_none", &"introduce", &"join_fire",
	&"later_day", &"later_halt", &"offer_guide", &"toast", &"treat", &"usual", &"warm_by_fire"]

## Why `key` is no key of a line, "" when it is.
static func line_problem(key: String) -> String:
	var base := key
	var tail := key.rsplit("_", true, 1)
	if tail.size() == 2 and tail[1].is_valid_int():
		base = tail[0]
	if LINES.has(StringName(base)):
		return ""
	if base.begins_with("beer_flaw_"):
		return "" if BrewIds.FLAWS.has(StringName(base.trim_prefix("beer_flaw_"))) else "no flaw '%s'" % base.trim_prefix("beer_flaw_")
	if base.begins_with("beer_"):
		return "" if BrewIds.SORTS.has(StringName(base.trim_prefix("beer_"))) else "no sort '%s'" % base.trim_prefix("beer_")
	if base.begins_with("food_"):
		return "" if FOODS.has(StringName(base.trim_prefix("food_"))) else "no food '%s'" % base.trim_prefix("food_")
	return "no line is called '%s'" % key
