class_name TavernLadder
extends RefCounted
## The ladder to the attic, from a table's `ladder` (tools/pipeline/tavern/
## furnish.py, LADDER), in the tavern's frame: where the climb starts at its
## foot, the rim of the hatch it goes through, and where it steps off in the
## attic and back in the corridor.

var foot := Vector3.ZERO
var hatch := Vector3.ZERO
var attic := Vector3.ZERO
var corridor := Vector3.ZERO

static func from_table(row: Dictionary) -> TavernLadder:
	var ladder := TavernLadder.new()
	ladder.foot = Values.vec3(row.foot)
	ladder.hatch = Values.vec3(row.hatch)
	ladder.attic = Values.vec3(row.attic)
	ladder.corridor = Values.vec3(row.corridor)
	return ladder

## Whether `point` of the tavern's frame is below the attic: lower than half
## the way from the ladder's foot up to its hatch.
func below(point: Vector3) -> bool:
	return point.y < (foot.y + hatch.y) * 0.5
