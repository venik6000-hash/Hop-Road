class_name CampVisit
extends RefCounted
## The player's visits to one villager who is at rest: at their work, in the
## hall, in the yard. A visit begins when the player comes near for the first
## time or after VISIT_GAP seconds away; the villager's talk starts anew with
## it (Storyteller.begin_outing). Within a visit a new halt begins when the
## player sits down or gets up beside the villager.

## Seconds the player stays away before coming back is a new visit.
const VISIT_GAP := 30.0
## How near the innkeeper the player stands to be at the bar.
const BAR_REACH := 3.5

## A number that changes with every new halt (Storyteller's moment).
var halt := 0
## The player was near in the last frame.
var near := false
## Seconds since the player was last near; endless before the first visit.
var away := INF
## The player was seated when last near.
var seated := false

## A frame: whether the player is near the villager now, and whether they
## sit. Returns whether a visit has begun with it.
func frame(delta: float, is_near: bool, is_seated: bool) -> bool:
	var began := false
	if is_near:
		if not near and away >= VISIT_GAP:
			began = true
			halt += 1
		elif is_seated != seated:
			halt += 1
		away = 0.0
		seated = is_seated
	else:
		away += delta
	near = is_near
	return began

## What the player is doing beside a villager at rest (Storyteller's moment):
## "bar" standing still within BAR_REACH of the innkeeper at work, "table" on
## a seat of the tavern, else "stand" or "walk". `distance` is to the villager.
static func activity(barkeeper: bool, at_table: bool, seated: bool, still: bool, distance: float) -> String:
	if barkeeper and not seated and still and distance <= BAR_REACH:
		return PeopleIds.ACTIVITY_BAR
	if at_table:
		return PeopleIds.ACTIVITY_TABLE
	return PeopleIds.ACTIVITY_STAND if still else PeopleIds.ACTIVITY_WALK
