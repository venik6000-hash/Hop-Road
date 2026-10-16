class_name JointLimitModifier3D
extends SkeletonModifier3D
## Keeps the bones of a skeleton inside the anatomical limits of its profile
## (JointLimits). It is the skeleton's last modifier, so whatever posed the
## bone before it (a clip, IK, a gesture, the seat) is clamped alike. It
## counts each bone's clamps: a bone clamped often has a wrong pose source.

## The profile of src/body/joint_limits.json.
var profile := ""
var _joints: Array[JointLimits.Joint] = []
## Clamps of each joint, in the order of `_joints`.
var _counts := PackedInt32Array()
## The largest overshoot of each joint so far, degrees.
var _worst := PackedFloat32Array()
var _bound := false

func _init(profile_name := "") -> void:
	profile = profile_name
	name = "JointLimits"

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if not _bound:
		_joints = JointLimits.bind(skeleton, profile)
		_counts.resize(_joints.size())
		_counts.fill(0)
		_worst.resize(_joints.size())
		_worst.fill(0.0)
		_bound = true
	for index in _joints.size():
		var joint := _joints[index]
		if JointLimits.hold(skeleton, joint):
			_counts[index] += 1
			_worst[index] = maxf(_worst[index], joint.excess)

## How many times `bone` was clamped; 0 for a bone without limits.
func clamp_count(bone: String) -> int:
	for index in _joints.size():
		if _joints[index].name == bone:
			return _counts[index]
	return 0

## Bone name -> [its clamps, its largest overshoot in degrees], for the
## bones clamped at least once.
func counts() -> Dictionary:
	var found := {}
	for index in _joints.size():
		if _counts[index] > 0:
			found[_joints[index].name] = [_counts[index], _worst[index]]
	return found
