extends RefCounted
## Save version 6 to 7 (SaveService.MIGRATIONS). Version 7 keeps what the
## player has in the section "player" (PlayerState): the copper coins
## ("coins"), the place they stood ("place"), the mug and the food in the
## hand. Version 6 kept the coins and the place ("player": {at, yaw}) at the
## top of the file and did not keep the mug or the food: the mug of a carried
## save is full of the tavern's old beer, the hand is empty.

const PLAYER := "player"
const COINS := "coins"
const PLACE := "place"

## `saved` (version 6) as version 7.
static func apply(saved: Dictionary, _path: String) -> Dictionary:
	var section := {}
	var place: Variant = saved.get(PLAYER)
	if place is Dictionary:
		section[PLACE] = place
	if saved.has(COINS):
		section[COINS] = saved[COINS]
	saved.erase(COINS)
	saved[PLAYER] = section
	return saved
