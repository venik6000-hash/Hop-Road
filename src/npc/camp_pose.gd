class_name CampPose
extends LimbPose
## The seat's hips and legs (NpcBody.SEAT): the pelvis over what is sat on,
## the feet on the ground in front. The hands on the lap are NpcArmPose's.
## The height of what is sat on over the actor's origin: a log by a fire, or a
## chair of the tavern.
var seat_height := 0.28

## Where the hand of `side` ("L", "R") rests on the lap, in world space.
func lap(side: String) -> Vector3:
	var sign_side := 1.0 if side == "R" else -1.0
	return actor.global_position + actor.global_basis.x.normalized() * sign_side * 0.22 \
		- actor.global_basis.z.normalized() * 0.32 + Vector3.UP * (seat_height + 0.26)

func _process_modification() -> void:
	if influence <= 0.0 or not is_instance_valid(actor):
		return
	var skeleton := get_skeleton()
	_find(skeleton, ["Hips", "Spine", "UpLeg_L", "UpLeg_R", "Leg_L", "Leg_R", "Foot_L", "Foot_R"])
	var forward := -actor.global_basis.z.normalized()
	var right := actor.global_basis.x.normalized()
	var origin := actor.global_position
	# The pelvis sits just above the seat's top, with the body over the seat.
	_set_origin(skeleton, _bones.Hips, origin + Vector3.UP * (seat_height + 0.12) - forward * 0.025)
	_rotate_world(skeleton, _bones.Spine, Quaternion(right, -0.08))
	for side: String in ["L", "R"]:
		var sign_side := 1.0 if side == "R" else -1.0
		var foot_target := origin + forward * 0.48 + right * sign_side * 0.14
		if actor.outing != null:
			var ground: Dictionary = actor.outing.camping.ground_at(foot_target, 0.8, 1.5)
			if not ground.is_empty():
				foot_target.y = ground.position.y
		foot_target.y += 0.075
		_solve_chain(skeleton, _bones["UpLeg_" + side], _bones["Leg_" + side], _bones["Foot_" + side], foot_target, Vector3.UP)
		# Preserve the standing boot orientation rather than inheriting knee rotation.
		var foot: int = _bones["Foot_" + side]
		if foot >= 0:
			var foot_pose := skeleton.get_bone_global_pose(foot)
			foot_pose.basis = (_rest["Foot_" + side] as Transform3D).basis
			_set_global(skeleton, foot, foot_pose)
