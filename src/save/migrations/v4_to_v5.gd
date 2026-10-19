extends RefCounted
## Save version 4 to 5 (SaveService.MIGRATIONS). Version 5 keys the villagers'
## memories of the fires and of the treats ("memories" of each region's
## "camping") by the villager's sheet (VillageNPC.person_id). Version 4 keyed
## them by the name of the villager's node: the job and the place in the order
## the level made them ("Wander6"). That order follows villagers.json as it
## stood when the save was written, so an old key cannot be told for sure:
## the memories go. What the player has with each villager is kept: it lies in
## the section "people", keyed by the sheet.

const REGIONS := "regions"
const CAMPING := "camping"
const MEMORIES := "memories"

## `saved` (version 4) as version 5.
static func apply(saved: Dictionary, _path: String) -> Dictionary:
	var regions: Variant = saved.get(REGIONS)
	if not regions is Dictionary:
		return saved
	var held: Dictionary = regions
	for region_id: Variant in held:
		var sections: Variant = held[region_id]
		if not sections is Dictionary:
			continue
		var table: Dictionary = sections
		var camping: Variant = table.get(CAMPING)
		if camping is Dictionary:
			var camp: Dictionary = camping
			camp.erase(MEMORIES)
	return saved
