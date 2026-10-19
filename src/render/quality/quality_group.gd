class_name QualityGroup
extends Resource
## One group of a QualityProfile, as the scalability groups of large engines:
## the shadows, the effects, the vegetation, the water or the post passes.
## A level of a group is a file (assets/quality/<group>/<level>.tres); a
## profile names one level of each group. The defaults of a group's fields
## are the authored picture; a level file sets only what it changes.

## The fields a system reads once, when the level is built: a profile that
## changes one of them shows it after a restart. The others take effect at
## once.
func read_at_start() -> Array[StringName]:
	return []

## Whether the game must restart before it shows this level, when it runs
## with `running` (the same group's level).
func needs_restart(running: QualityGroup) -> bool:
	for field: StringName in read_at_start():
		if get(field) != running.get(field):
			return true
	return false
