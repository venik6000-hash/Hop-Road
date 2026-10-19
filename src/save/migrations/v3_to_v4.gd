extends RefCounted
## Save version 3 to 4 (SaveService.MIGRATIONS). Version 4 keeps the sections
## that hold places in the world coordinates of one region under that
## region's id ("regions": {<id>: {camping, brewing}}). A save of version 3
## held one such section of each for the whole game: they go to the region it
## was written in, or to the valley when it names none.

## The sections that are a region's since version 4, and the key of the
## object that holds them (SaveService.REGIONS).
const MOVED: Array[String] = ["camping", "brewing"]
const REGIONS := "regions"
## The first region of the game's list at version 3. A step keeps the facts of
## its own version: the first region of today's list may be another one.
const VALLEY := "valley"

## `saved` (version 3) as version 4.
static func apply(saved: Dictionary, _path: String) -> Dictionary:
	var region_id := str(saved.get("region", "")) if saved.get("region") is String else ""
	if region_id.is_empty():
		region_id = VALLEY
	var held := {}
	for key in MOVED:
		if saved.has(key):
			held[key] = saved[key]
			saved.erase(key)
	if not held.is_empty():
		saved[REGIONS] = {region_id: held}
	return saved
