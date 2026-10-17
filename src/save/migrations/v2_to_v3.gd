extends RefCounted
## Save version 2 to 3 (SaveService.MIGRATIONS). Version 3 names the region
## the player is in ("region"); a save of version 2 knew the valley only, and
## lies in the first region of the game's list.

## `saved` (version 2) as version 3.
static func apply(saved: Dictionary, _path: String) -> Dictionary:
	saved["region"] = String(RegionDef.first_id())
	return saved
