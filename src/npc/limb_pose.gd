class_name LimbPose
extends SkeletonModifier3D
## What the villager's pose modifiers share: two-bone chains solved in world
## space, since the imported rigs have different axes and scales. How far the
## modifier bends the clip is its `influence`, set by VillageNPC from NpcBody.
var actor: VillageNPC
var _bones: Dictionary = {}
var _rest: Dictionary = {}
## Middle bone -> its hinge (JointLimits, profile "villager"): how far it
## folds and the plane it bends in.
var _hinges: Dictionary = {}

## The bone indices and global rests of `labels`, found once.
func _find(skeleton: Skeleton3D, labels: Array[String]) -> void:
	if not _bones.is_empty():
		return
	for joint in JointLimits.bind(skeleton, "villager"):
		if joint.hinge:
			_hinges[joint.bone] = joint
	for label in labels:
		_bones[label] = skeleton.find_bone(label)
		if _bones[label] >= 0:
			_rest[label] = _global_rest(skeleton, _bones[label])

## Where a chain of two bones `first` and `second` long from `start` puts its
## middle joint and its tip for `target`, the joint bent towards `pole` and
## folded no more than `fold` radians: [joint, tip]. A target nearer than the
## fold allows is reached along the same line.
static func chain(start: Vector3, target: Vector3, first: float, second: float, fold: float, pole: Vector3) -> PackedVector3Array:
	var offset := target - start
	var near := JointLimits.near_reach(first, second, fold)
	var distance := clampf(offset.length(), near + 0.001, first + second - 0.001)
	var direction := offset.normalized()
	var along := (first * first - second * second + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, first * first - along * along))
	var bend := (pole - direction * pole.dot(direction)).normalized()
	return PackedVector3Array([start + direction * along + bend * height, start + direction * distance])

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
	var hinge: JointLimits.Joint = _hinges.get(middle)
	var points := chain(start, target, first_length, second_length, hinge.high if hinge != null else PI, pole)
	var desired_joint := points[0]
	var reach := points[1]
	_aim_child(skeleton, upper, middle, desired_joint)
	var across := (desired_joint - start).cross(reach - desired_joint)
	if hinge != null and across.length_squared() > 0.000001:
		# The upper bone turns about its length until the hinge lies across
		# the bend: the knee or the elbow then bends in its own plane.
		var length := (desired_joint - start).normalized()
		var basis := skeleton.global_basis.orthonormalized() * skeleton.get_bone_global_pose(upper).basis.orthonormalized()
		var axis := basis * hinge.axis
		axis = (axis - length * axis.dot(length)).normalized()
		_rotate_world(skeleton, upper, Quaternion(length, axis.signed_angle_to(across.normalized(), length)))
	_aim_child(skeleton, middle, tip, reach)

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
