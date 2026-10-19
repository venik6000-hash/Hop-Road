extends RefCounted
## Save version 2 to 3 (SaveService.MIGRATIONS). Version 3 names the region
## the player is in ("region"); a save of version 2 knew the valley only.

## The region a save of version 2 was written in. A step keeps the facts of
## its own version: the first region of today's list may be another one.
const VALLEY := "valley"

## `saved` (version 2) as version 3.
static func apply(saved: Dictionary, _path: String) -> Dictionary:
	saved["region"] = VALLEY
	return saved
