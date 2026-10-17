@tool
class_name RegionExit
extends Resource
## A way out of a region (RegionDef.exits): the player who walks into `area`
## goes through the loading screen into the region `to` and comes in there
## at its spawn `spawn` (GameFlow.travel).

## The place of the way out (world coordinates).
@export var area := AABB()
## The id of the region it leads to (RegionDef.LIST names it).
@export var to: StringName
## The spawn of that region the player comes in at (RegionSpawn.id).
@export var spawn: StringName
