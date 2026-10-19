class_name PlayerState
extends RefCounted
## What the player has, apart from the systems of the world (docs/PLAYER.md,
## «Что есть у игрока»): the copper coins, the mug and the beer in it, the
## food in the left hand, and the place the player last stood on their feet.
## The player's body holds one (Player.state); the brewery's trade takes it
## by reference (BrewTrade.use_purse), the mug reads and writes its beer
## (BeerViewmodel.state), the fires put the potato in it (CampSystem). The
## save keeps it as the section SECTION (ValleyLoop adds it).

## The mug's beer or level was set from outside the mug: a save was read.
signal mug_filled

## The key of the player's section of the save.
const SECTION := "player"
## How full a poured mug is: the beer's level in the tankard (BeerViewmodel).
const MUG_FULL := 0.86
## The food the left hand holds: a baked potato (CampMeal), in halves.
const POTATO := &"potato"
const HELD_KINDS: Array[StringName] = [POTATO]
## The most halves the hand holds (CampMeal.take).
const MOST_PORTIONS := 2
## How far from the middle of the map, and how low and high, a saved place
## may lie to be taken for one.
const PLACE_REACH := 2000.0
const PLACE_HEIGHTS := Vector2(-50.0, 300.0)

## Copper coins; -1 while the game has given the player none (no brewery
## yet: the first one fills the purse with its start, BrewTrade.use_purse).
var coins := -1
## The beer in the mug (BrewTaste.profile), {} for the tavern's old beer.
var mug_beer: Dictionary = {}
## The beer's level in the mug, 0 (empty) to MUG_FULL.
var mug_fill := MUG_FULL
## The food in the left hand (HELD_KINDS), &"" for none.
var held := &""
## Halves of the food left in the hand.
var held_portions := 0
## Where the player last stood on their feet: {at: Vector3, yaw: degrees};
## {} until they have (ValleyLoop sets it).
var place: Dictionary = {}

## Puts `portions` halves of `kind` (HELD_KINDS) in the left hand.
func hold(kind: StringName, portions: int) -> void:
	held = kind if portions > 0 else &""
	held_portions = maxi(portions, 0) if held != &"" else 0

## One half of the food in the hand is gone (eaten or given). False when the
## hand holds none.
func use_held() -> bool:
	if held == &"" or held_portions <= 0:
		return false
	held_portions -= 1
	if held_portions == 0:
		held = &""
	return true

## The player's section of the save. Without `with_place`, the place is left
## out: it belongs to another region or to before a spawn (ValleyLoop).
func to_dict(with_place := true) -> Dictionary:
	var result := {"mug": {"beer": mug_beer.duplicate(true), "fill": mug_fill}}
	if coins >= 0:
		result["coins"] = coins
	if held != &"":
		result["held"] = {"kind": String(held), "portions": held_portions}
	if with_place and not place.is_empty():
		var at: Vector3 = place.at
		var yaw: float = place.yaw
		result["place"] = {"at": [at.x, at.y, at.z], "yaw": yaw}
	return result

## Takes back to_dict() from a save, checked (unpack). Coins and a mug the
## save does not hold stay as they are; food and a place it does not hold
## are none.
func restore(saved: Dictionary) -> void:
	var fields := unpack(saved)
	if Values.whole(fields.coins) >= 0:
		coins = fields.coins
	if saved.has("mug"):
		mug_beer = fields.mug_beer
		mug_fill = fields.mug_fill
		mug_filled.emit()
	place = fields.place
	var kind: StringName = fields.held
	var portions: int = fields.held_portions
	hold(kind, portions)

## The fields of a player's section (SaveService.part(save, SECTION)),
## checked: {coins (-1 when there are none), mug_beer ({} for the old beer),
## mug_fill, held (&"" for none), held_portions, place ({at: Vector3, yaw};
## {} when the section has none a player can stand at)}.
static func unpack(data: Variant) -> Dictionary:
	var saved: Dictionary = data if data is Dictionary else {}
	var mug := Values.table(saved.get("mug"))
	var held_food := Values.table(saved.get("held"))
	var kind := StringName(str(held_food.get("kind", "")))
	var portions := int(Values.number(held_food.get("portions"), 0.0, 0.0, MOST_PORTIONS))
	if not HELD_KINDS.has(kind) or portions <= 0:
		kind = &""
		portions = 0
	return {
		"coins": int(Values.number(saved.get("coins"), -1.0, 0.0, 1e9)),
		"mug_beer": Values.table(mug.get("beer")).duplicate(true),
		"mug_fill": Values.number(mug.get("fill"), MUG_FULL, 0.0, MUG_FULL),
		"held": kind,
		"held_portions": portions,
		"place": stood(saved.get("place")),
	}

## The place `saved` holds, {} when it holds none that a player can stand at.
static func stood(saved: Variant) -> Dictionary:
	if not saved is Dictionary:
		return {}
	var where: Dictionary = saved
	var at: Variant = where.get("at")
	if not at is Array:
		return {}
	var coords: Array = at
	if coords.size() != 3:
		return {}
	for value: Variant in coords:
		if not (value is float or value is int) or not is_finite(Values.real(value)):
			return {}
	var point := Values.vec3(coords)
	if absf(point.x) > PLACE_REACH or absf(point.z) > PLACE_REACH or point.y < PLACE_HEIGHTS.x or point.y > PLACE_HEIGHTS.y:
		return {}
	return {"at": point, "yaw": wrapf(Values.number(where.get("yaw"), 0.0, -360.0, 360.0), -180.0, 180.0)}
