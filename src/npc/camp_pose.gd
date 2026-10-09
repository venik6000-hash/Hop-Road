class_name CampPose
extends SkeletonModifier3D
## Solve limbs in world space: the three imported rigs have different axes/scales.
var actor: VillageNPC
var seated := false
var toast_weight := 0.0
var food_weight := 0.0
var _bones: Dictionary = {}
var _rest: Dictionary = {}

func _process_modification() -> void:
	if not seated or not is_instance_valid(actor):
		return
	var skeleton := get_skeleton()
	if _bones.is_empty():
		for label in ["Hips", "Spine", "UpLeg_L", "UpLeg_R", "Leg_L", "Leg_R", "Foot_L", "Foot_R", "Arm_L", "Arm_R", "ForeArm_L", "ForeArm_R", "Hand_L", "Hand_R"]:
			_bones[label] = skeleton.find_bone(label)
			if _bones[label] >= 0:
				_rest[label] = _global_rest(skeleton, _bones[label])
	var forward := -actor.global_basis.z.normalized()
	var right := actor.global_basis.x.normalized()
	var origin := actor.global_position
	# Seat top is 0.28 m: pelvis sits just above it, with the body over the log.
	_set_origin(skeleton, _bones.Hips, origin + Vector3.UP * 0.40 - forward * 0.025)
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
		var hand_target := origin + right * sign_side * 0.22 + forward * 0.32 + Vector3.UP * 0.54
		var lift := toast_weight if side == "R" else food_weight
		hand_target += Vector3.UP * lift * 0.48 + forward * lift * 0.03
		var elbow_pole := right * sign_side * 0.6 + Vector3.DOWN * 0.8
		_solve_chain(skeleton, _bones["Arm_" + side], _bones["ForeArm_" + side], _bones["Hand_" + side], hand_target, elbow_pole)

func _solve_chain(skeleton: Skeleton3D, upper: int, middle: int, tip: int, target: Vector3, pole: Vector3) -> void:
	if upper < 0 or middle < 0 or tip < 0:
		return
	var start := _world_origin(skeleton, upper)
	var joint := _world_origin(skeleton, middle)
	var end := _world_origin(skeleton, tip)
	var first_length := start.distance_to(joint)
	var second_length := joint.distance_to(end)
	if first_length < 0.001 or second_length < 0.001:
		return
	var offset := target - start
	var distance := clampf(offset.length(), absf(first_length - second_length) + 0.001, first_length + second_length - 0.001)
	var direction := offset.normalized()
	var along := (first_length * first_length - second_length * second_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, first_length * first_length - along * along))
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var desired_joint := start + direction * along + bend * height
	_aim_child(skeleton, upper, middle, desired_joint)
	_aim_child(skeleton, middle, tip, start + direction * distance)

func _aim_child(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var origin := _world_origin(skeleton, bone)
	var current := _world_origin(skeleton, child) - origin
	var desired := target - origin
	if current.length_squared() > 0.000001 and desired.length_squared() > 0.000001:
		_rotate_world(skeleton, bone, Quaternion(current.normalized(), desired.normalized()))

func _rotate_world(skeleton: Skeleton3D, bone: int, rotation: Quaternion) -> void:
	if bone < 0:
		return
	var bone_pose := skeleton.get_bone_global_pose(bone)
	var basis := skeleton.global_basis
	bone_pose.basis = basis.inverse() * Basis(rotation) * basis * bone_pose.basis
	_set_global(skeleton, bone, bone_pose)

func _set_origin(skeleton: Skeleton3D, bone: int, origin: Vector3) -> void:
	if bone < 0:
		return
	var bone_pose := skeleton.get_bone_global_pose(bone)
	bone_pose.origin = skeleton.global_transform.affine_inverse() * origin
	_set_global(skeleton, bone, bone_pose)

func _set_global(skeleton: Skeleton3D, bone: int, bone_pose: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_pose := Transform3D.IDENTITY if parent < 0 else skeleton.get_bone_global_pose(parent)
	# Godot bone poses are absolute local transforms, not deltas from bone rest.
	var local_pose := parent_pose.affine_inverse() * bone_pose
	skeleton.set_bone_pose_position(bone, local_pose.origin)
	skeleton.set_bone_pose_rotation(bone, local_pose.basis.orthonormalized().get_rotation_quaternion())

func _world_origin(skeleton: Skeleton3D, bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin

func _global_rest(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var result := skeleton.get_bone_rest(bone)
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		result = skeleton.get_bone_rest(parent) * result
		parent = skeleton.get_bone_parent(parent)
	return result
