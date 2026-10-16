class_name NpcArmPose
extends LimbPose
## One arm of a villager, bent to where the doers that drive it (NpcBody) want
## the hand, each by its weight: the seat to the lap, a gesture over where the
## hand is without it. With no doer the modifier leaves the clip's arm.
## Doer -> how a gesture lifts the hand over where it is without it: x up,
## y forward, metres.
const LIFT := {NpcBody.TOAST: Vector2(0.48, 0.03), NpcBody.MEAL: Vector2(0.24, 0.015)}

## "L" or "R".
var side := "R"
var part := NpcBody.RIGHT_ARM
## The seat's pose, for the lap.
var seat: CampPose

func _process_modification() -> void:
	if influence <= 0.0 or not is_instance_valid(actor):
		return
	var skeleton := get_skeleton()
	_find(skeleton, ["Arm_" + side, "ForeArm_" + side, "Hand_" + side])
	var hand: int = _bones["Hand_" + side]
	if hand < 0:
		return
	var forward := -actor.global_basis.z.normalized()
	var right := actor.global_basis.x.normalized()
	# A gesture lifts the hand from the lap while the villager sits, else from
	# where the clip has it.
	var base := _world_origin(skeleton, hand)
	if actor.body.has(NpcBody.SEAT):
		base = seat.lap(side)
	var target := Vector3.ZERO
	var sum := 0.0
	for doer in actor.body.drivers(part):
		# A doer with no place for the hand (the stumble) leaves the arm be.
		if doer != NpcBody.SEAT and not LIFT.has(doer):
			continue
		var weight := actor.body.weight(doer, part)
		var wanted := seat.lap(side) if doer == NpcBody.SEAT else base
		var lift: Vector2 = LIFT.get(doer, Vector2.ZERO)
		target += (wanted + Vector3.UP * lift.x + forward * lift.y) * weight
		sum += weight
	if sum <= 0.0:
		return
	var sign_side := 1.0 if side == "R" else -1.0
	var elbow_pole := right * sign_side * 0.6 + Vector3.DOWN * 0.8
	_solve_chain(skeleton, _bones["Arm_" + side], _bones["ForeArm_" + side], hand, target / sum, elbow_pole)
