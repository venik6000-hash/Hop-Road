class_name BrewArmIK
extends SkeletonModifier3D
## Two-bone IK of the brewer's arms (BrewArms): the shoulder and the elbow
## turn so the wrist lands where the hand must be, the elbow bent towards its
## pole (down and out) in the plane of its hinge (JointLimits) and no further
## than the hinge folds; the hand takes the target's turn, the forearm the
## hand's twist about its length. Closed form, in the skeleton's space.

## Bone names of a side ("R", "L").
const UPPER := "upper_arm.%s"
const FORE := "forearm.%s"
const HAND := "hand.%s"
const SIDES: Array[String] = ["R", "L"]
## Where each elbow bends towards, skeleton space (x right, y up, -z ahead).
const POLES: Array[Vector3] = [Vector3(0.6, -1.0, 0.25), Vector3(-0.6, -1.0, 0.25)]

## The hand's transform each side should reach, skeleton space, and how much
## (0 leaves the arm at rest).
var targets: Array[Transform3D] = [Transform3D(), Transform3D()]
var weights: Array[float] = [0.0, 0.0]
## Where each hand was put in the last pass, skeleton space. The skeleton
## gives its bones back their poses after the pass, and inside it the global
## poses read back stale, so the pass keeps them here.
var placed: Array[Transform3D] = [Transform3D(), Transform3D()]
## The elbows' limits (JointLimits, profile "player_arm"): forearm bone
## name -> JointLimits.Joint, its hinge axis in the upper arm's frame.
var _elbows: Dictionary = {}

## The elbow of an arm from `shoulder` with bones `upper` and `fore` long
## reaching for `wrist`, bent towards `pole`. A wrist out of reach is reached
## for along the straight arm.
static func elbow(shoulder: Vector3, wrist: Vector3, upper: float, fore: float, pole: Vector3) -> Vector3:
	var to := wrist - shoulder
	var along := to.normalized() if to.length() > 0.0001 else Vector3.FORWARD
	var reach := clampf(to.length(), absf(upper - fore) + 0.001, upper + fore - 0.0001)
	var cos_a := (upper * upper + reach * reach - fore * fore) / (2.0 * upper * reach)
	var side := pole - along * pole.dot(along)
	if side.length() < 0.0001:
		side = along.cross(Vector3.RIGHT)
	return shoulder + along * upper * cos_a + side.normalized() * upper * sqrt(maxf(1.0 - cos_a * cos_a, 0.0))

## Where the wrist ends up: `wrist`, or as near it as the arm reaches. A
## wrist nearer than `near` (the elbow folded as far as it goes) is held out
## to `near`.
static func reached(shoulder: Vector3, wrist: Vector3, upper: float, fore: float, near := 0.0) -> Vector3:
	var to := wrist - shoulder
	if to.length() < near:
		to = (to.normalized() if to.length() > 0.0001 else Vector3.FORWARD) * near
	return shoulder + to.limit_length(upper + fore - 0.0001)

## The turn about `axis` (unit) that `turn` makes, without its swing.
static func twist(turn: Quaternion, axis: Vector3) -> Quaternion:
	var spin := Vector3(turn.x, turn.y, turn.z)
	var along := axis * spin.dot(axis)
	var result := Quaternion(along.x, along.y, along.z, turn.w)
	return result.normalized() if result.length() > 0.0001 else Quaternion.IDENTITY

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for index in SIDES.size():
		if weights[index] > 0.0:
			placed[index] = _solve(skeleton, SIDES[index], targets[index], weights[index], POLES[index])

## Bends arm `side` to `target`; returns where the hand was put.
func _solve(skeleton: Skeleton3D, side: String, target: Transform3D, weight: float, pole: Vector3) -> Transform3D:
	var upper := skeleton.find_bone(UPPER % side)
	var fore := skeleton.find_bone(FORE % side)
	var hand := skeleton.find_bone(HAND % side)
	if upper < 0 or fore < 0 or hand < 0:
		return Transform3D()
	var upper_rest := skeleton.get_bone_global_rest(upper)
	var fore_rest := skeleton.get_bone_global_rest(fore)
	var hand_rest := skeleton.get_bone_global_rest(hand)
	var upper_length := upper_rest.origin.distance_to(fore_rest.origin)
	var fore_length := fore_rest.origin.distance_to(hand_rest.origin)
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	if _elbows.is_empty():
		for joint in JointLimits.bind(skeleton, "player_arm"):
			if joint.hinge and joint.name.begins_with("forearm."):
				_elbows[joint.name] = joint
	var hinge: JointLimits.Joint = _elbows.get(FORE % side)
	var folded := hinge.high if hinge != null else PI
	var near := JointLimits.near_reach(upper_length, fore_length, folded)
	var wrist := reached(shoulder, target.origin, upper_length, fore_length, near)
	var bend := elbow(shoulder, wrist, upper_length, fore_length, pole)
	var to_elbow := (bend - shoulder).normalized()
	var to_wrist := (wrist - bend).normalized()
	var upper_way := (fore_rest.origin - upper_rest.origin).normalized()
	var upper_basis := Basis(Quaternion(upper_way, to_elbow)) * upper_rest.basis
	var across := to_elbow.cross(to_wrist)
	if hinge != null and across.length() > 0.001:
		# The upper arm turns about its length until the elbow's hinge lies
		# across the bend: the elbow then bends in its own plane.
		var axis := upper_basis.orthonormalized() * hinge.axis
		axis = (axis - to_elbow * axis.dot(to_elbow)).normalized()
		upper_basis = Basis(to_elbow, axis.signed_angle_to(across.normalized(), to_elbow)) * upper_basis
	# The forearm is carried by the upper arm and bends to the wrist.
	var fore_way := (hand_rest.origin - fore_rest.origin).normalized()
	var length := (fore_rest.basis.inverse() * fore_way).normalized()
	var carried := upper_basis * (upper_rest.basis.inverse() * fore_rest.basis)
	var fore_basis := Basis(Quaternion((carried * length).normalized(), to_wrist)) * carried
	# The forearm turns about its length as far as the hand does against it.
	var hand_local := (fore_basis.inverse() * target.basis.orthonormalized()) * (fore_rest.basis.inverse() * hand_rest.basis).inverse()
	fore_basis = fore_basis * Basis(twist(hand_local.get_rotation_quaternion(), length))
	_place(skeleton, upper, Transform3D(upper_basis, shoulder), weight)
	_place(skeleton, fore, Transform3D(fore_basis, bend), weight)
	return _place(skeleton, hand, Transform3D(target.basis.orthonormalized(), wrist), weight)

func _place(skeleton: Skeleton3D, bone: int, pose: Transform3D, weight: float) -> Transform3D:
	var now := skeleton.get_bone_global_pose(bone)
	if weight < 1.0:
		var turn := now.basis.get_rotation_quaternion().slerp(pose.basis.get_rotation_quaternion(), weight)
		pose = Transform3D(Basis(turn), now.origin.lerp(pose.origin, weight))
	skeleton.set_bone_global_pose(bone, pose)
	return pose
