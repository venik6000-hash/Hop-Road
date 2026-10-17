class_name JointLimits
extends RefCounted
## The anatomical limits of the joints (src/body/joint_limits.json) and the
## clamp that keeps a bone's turn from rest inside them (docs/LIFE.md,
## «Пределы суставов»). The table writes its vectors in the body's frame:
## [out, up, forward], where out is away from the body's middle, the right for
## a bone without a side. A "*" in a bone's name stands for "R" and "L"; the
## table is written for the right side and the left mirrors it.
##
## A turn from rest splits into a swing, which moves the bone's length (its
## own +Y), and a twist about that length. A hinge bends its bone from the
## parent's line towards `bends`, between `min` and `max`, and lets it lean
## out of that plane by `play`; a cone lets the length within `cone` of
## `axis`. Both limit the twist to `twist`. Angles are degrees in the table,
## radians here.

const TABLE := "res://src/body/joint_limits.json"
## A correction smaller than this is not counted as a clamp: half a degree.
const SLACK := 0.0087266
## How many times a bone's excess twist spills into its parent (hold).
const SPILL_ROUNDS := 3

## Profile name -> its joints, expanded: Array[Dictionary].
static var _profiles: Dictionary = {}

## One bone's limits, compiled in its parent's frame for one skeleton.
class Joint:
	var bone := -1
	var name := ""
	var hinge := false
	## The bone's rest turn against its parent.
	var rest := Quaternion.IDENTITY
	var _rest_inverse := Quaternion.IDENTITY
	## A cone's middle, or the hinge's axis (the bend is positive about it).
	var axis := Vector3.UP
	## The parent's line: where a hinge's bend is zero.
	var straight := Vector3.UP
	var cone := PI
	var low := 0.0
	var high := PI
	var play := 0.0
	var twist_low := -PI
	var twist_high := PI
	## Whether twist past the range goes to the parent bone (`"spill": true`
	## in the table): a forearm turns the hand, not the wrist.
	var spills := false
	## The twist the last `limit` cut off, signed, radians.
	var spill := 0.0
	## What the last `limit` found: whether it moved the bone by more than
	## SLACK, the largest overshoot in degrees, and which limit it was
	## (&"twist", &"bend", &"side", &"cone").
	var clamped := false
	var excess := 0.0
	var what := &""

	func set_rest(turn: Quaternion) -> void:
		rest = turn.normalized()
		_rest_inverse = rest.inverse()

	## `pose`, the bone's turn against its parent, kept inside the limits.
	func limit(pose: Quaternion) -> Quaternion:
		clamped = false
		excess = 0.0
		what = &""
		spill = 0.0
		var turn := _rest_inverse * pose
		var twist := Quaternion(0.0, turn.y, 0.0, turn.w)
		var size := twist.length()
		twist = twist / size if size > 0.000001 else Quaternion.IDENTITY
		var swing := turn * twist.inverse()
		var spun := JointLimits.twist_angle(twist)
		var kept_spin := JointLimits.clamp_angle(spun, twist_low, twist_high)
		var moved := false
		if kept_spin != spun:
			moved = true
			twist = Quaternion(Vector3.UP, kept_spin)
			spill = wrapf(spun - kept_spin, -PI, PI)
			_note(absf(wrapf(spun - kept_spin, -PI, PI)), &"twist")
		var length := rest * (swing * Vector3.UP)
		var wanted := length
		if hinge:
			var lean := clampf(length.dot(axis), -1.0, 1.0)
			var flat := length - axis * lean
			var bend := atan2(straight.cross(flat).dot(axis), straight.dot(flat))
			var side := asin(lean)
			var kept_bend := JointLimits.clamp_angle(bend, low, high)
			var kept_side := clampf(side, -play, play)
			if kept_bend != bend or kept_side != side:
				wanted = straight.rotated(axis, kept_bend) * cos(kept_side) + axis * sin(kept_side)
				_note(absf(wrapf(bend - kept_bend, -PI, PI)), &"bend")
				_note(absf(side - kept_side), &"side")
		else:
			var angle := length.angle_to(axis)
			if angle > cone:
				var across := length - axis * length.dot(axis)
				if across.length_squared() < 0.0000001:
					across = axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD)
				wanted = axis * cos(cone) + across.normalized() * sin(cone)
				_note(angle - cone, &"cone")
		if wanted != length:
			moved = true
			swing = JointLimits.arc(Vector3.UP, (_rest_inverse * wanted).normalized())
		if not moved:
			return pose
		clamped = excess > rad_to_deg(JointLimits.SLACK)
		return rest * swing * twist

	func _note(over: float, limit_name: StringName) -> void:
		var degrees := rad_to_deg(over)
		if degrees > excess:
			excess = degrees
			what = limit_name


## The names of the table's profiles.
static func profiles() -> PackedStringArray:
	_load()
	return PackedStringArray(_profiles.keys())

## The expanded joints of `profile`; none for an unknown one. Each is
## {bone, kind, twist: Vector2, and for a hinge bends: Vector3, min, max,
## play; for a cone axis_from ("rest", "straight", "body"), axis: Vector3,
## cone}; vectors in the skeleton's space, angles in radians.
static func joints(profile: String) -> Array[Dictionary]:
	_load()
	var found: Array[Dictionary] = []
	found.assign(Values.list(_profiles.get(profile, [])))
	return found

## The nearest a two-bone chain of `first` and `second` brings its tip to its
## root when its middle joint folds by `folded` radians from straight.
static func near_reach(first: float, second: float, folded: float) -> float:
	return sqrt(maxf(first * first + second * second + 2.0 * first * second * cos(folded), 0.0))

## Keeps the bone of `joint` inside its limits on `skeleton`; a joint that
## spills hands the cut-off twist to its parent first. True when the bone was
## clamped (by more than SLACK).
static func hold(skeleton: Skeleton3D, joint: Joint) -> bool:
	var pose := skeleton.get_bone_pose_rotation(joint.bone)
	var kept := joint.limit(pose)
	if joint.spills and joint.spill != 0.0:
		# The parent turns about its line to the bone, so the bone's joint
		# stays where it is; the bone keeps its turn in the world and is
		# clamped again. The line and the bone's length are not quite one
		# axis: what is left over spills again.
		var parent := skeleton.get_bone_parent(joint.bone)
		for round in SPILL_ROUNDS:
			var turn := Quaternion(joint.straight, joint.spill)
			skeleton.set_bone_pose_rotation(parent, skeleton.get_bone_pose_rotation(parent) * turn)
			pose = turn.inverse() * pose
			kept = joint.limit(pose)
			if joint.spill == 0.0:
				break
		skeleton.set_bone_pose_rotation(joint.bone, kept)
	elif kept != pose:
		skeleton.set_bone_pose_rotation(joint.bone, kept)
	return joint.clamped

## The joints of `profile` the skeleton has, compiled from its rest pose.
static func bind(skeleton: Skeleton3D, profile: String) -> Array[Joint]:
	var bound: Array[Joint] = []
	for entry in joints(profile):
		var bone := skeleton.find_bone(str(entry.bone))
		if bone < 0:
			continue
		var parent := skeleton.get_bone_parent(bone)
		var own := skeleton.get_bone_global_rest(bone)
		var parent_rest := Transform3D.IDENTITY if parent < 0 else skeleton.get_bone_global_rest(parent)
		var straight := own.origin - parent_rest.origin
		if parent < 0 or straight.length_squared() < 0.0000001:
			straight = own.basis.orthonormalized().y
		var joint := compile(entry, skeleton.get_bone_rest(bone).basis.orthonormalized().get_rotation_quaternion(),
			parent_rest.basis.orthonormalized(), straight.normalized())
		joint.bone = bone
		bound.append(joint)
	return bound

## One expanded `entry` compiled for a bone with this `rest` turn under a
## parent whose global rest basis is `parent`; `straight` is the parent's
## line to the bone, skeleton space.
static func compile(entry: Dictionary, rest: Quaternion, parent: Basis, straight: Vector3) -> Joint:
	var joint := Joint.new()
	joint.name = str(entry.bone)
	joint.set_rest(rest)
	var to_parent := parent.inverse()
	joint.straight = (to_parent * straight).normalized()
	var twist: Vector2 = entry.twist
	joint.twist_low = twist.x
	joint.twist_high = twist.y
	joint.spills = Values.flag(entry.get("spill", false))
	# The rest pose is reachable by definition: a rig whose rest lies past a
	# limit (a knee bound overstraight) gets that limit widened to its rest.
	var length := joint.rest * Vector3.UP
	if str(entry.kind) == "hinge":
		joint.hinge = true
		var bent: Vector3 = entry.bends
		var bends: Vector3 = to_parent * bent
		joint.axis = joint.straight.cross(bends).normalized()
		var lean := clampf(length.dot(joint.axis), -1.0, 1.0)
		var flat := length - joint.axis * lean
		var bend := atan2(joint.straight.cross(flat).dot(joint.axis), joint.straight.dot(flat))
		joint.low = minf(Values.real(entry.min), bend)
		joint.high = maxf(Values.real(entry.max), bend)
		joint.play = maxf(Values.real(entry.play), absf(asin(lean)))
	else:
		match str(entry.axis_from):
			"rest":
				joint.axis = joint.rest * Vector3.UP
			"straight":
				joint.axis = joint.straight
			_:
				var axis: Vector3 = entry.axis
				joint.axis = (to_parent * axis).normalized()
		joint.cone = maxf(Values.real(entry.cone), length.angle_to(joint.axis))
	return joint

## A table entry made into one joint per side; `frame` gives the skeleton's
## right, up and forward.
static func expand(entry: Dictionary, frame: Dictionary) -> Array[Dictionary]:
	var sides: Array[String] = [""]
	if str(entry.bone).contains("*"):
		sides = ["R", "L"]
	var made: Array[Dictionary] = []
	for side in sides:
		var right := Values.vec3(frame.right) * (-1.0 if side == "L" else 1.0)
		var up := Values.vec3(frame.up)
		var forward := Values.vec3(frame.forward)
		var twist: Array = entry.get("twist", [-180, 180])
		var low := deg_to_rad(Values.real(twist[0]))
		var high := deg_to_rad(Values.real(twist[1]))
		var joint := {
			"bone": str(entry.bone).replace("*", side),
			"kind": str(entry.kind),
			"twist": Vector2(-high, -low) if side == "L" else Vector2(low, high),
			"spill": Values.flag(entry.get("spill", false)),
		}
		if joint.kind == "hinge":
			joint.bends = _body(entry.bends, right, up, forward)
			joint.min = deg_to_rad(Values.real(entry.min))
			joint.max = deg_to_rad(Values.real(entry.max))
			joint.play = deg_to_rad(Values.real(entry.get("play", 0.0)))
		else:
			var axis: Variant = entry.get("axis", "rest")
			joint.axis_from = str(axis) if axis is String else "body"
			joint.axis = _body(axis, right, up, forward) if axis is Array else Vector3.ZERO
			joint.cone = deg_to_rad(Values.real(entry.cone))
		made.append(joint)
	return made

## The twist of `turn` about +Y, radians in (-PI, PI].
static func twist_angle(turn: Quaternion) -> float:
	return wrapf(2.0 * atan2(turn.y, turn.w), -PI, PI)

## `angle` inside [low, high], or the bound nearer to it round the circle.
static func clamp_angle(angle: float, low: float, high: float) -> float:
	if angle >= low and angle <= high:
		return angle
	var below := absf(wrapf(angle - low, -PI, PI))
	var above := absf(wrapf(angle - high, -PI, PI))
	return low if below <= above else high

## The shortest turn from unit `from` to unit `to`, a half turn included.
static func arc(from: Vector3, to: Vector3) -> Quaternion:
	var along := from.dot(to)
	if along < -0.999999:
		var side := from.cross(Vector3.RIGHT)
		if side.length_squared() < 0.000001:
			side = from.cross(Vector3.FORWARD)
		return Quaternion(side.normalized(), PI)
	var cross := from.cross(to)
	return Quaternion(cross.x, cross.y, cross.z, 1.0 + along).normalized()

static func _load() -> void:
	if not _profiles.is_empty():
		return
	var table: Variant = DataFile.read(TABLE, BodySchemas.joint_limits())
	if not table is Dictionary:
		push_error("JointLimits: %s is not a table" % TABLE)
		return
	var listed: Dictionary = Values.table(table).get("profiles", {})
	for profile: String in listed:
		var described: Dictionary = listed[profile]
		var expanded: Array[Dictionary] = []
		for entry: Dictionary in described.joints:
			expanded.append_array(expand(entry, Values.table(described.frame)))
		_profiles[profile] = expanded

static func _body(values: Variant, right: Vector3, up: Vector3, forward: Vector3) -> Vector3:
	var listed: Array = values
	return right * Values.real(listed[0]) + up * Values.real(listed[1]) + forward * Values.real(listed[2])
