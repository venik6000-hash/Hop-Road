class_name NpcGaze
extends SkeletonModifier3D
## A villager looks at the one who comes up to them: the head turns to the
## camera over whatever clip the body plays, as far as a neck turns, and goes
## back to the clip when the camera is far, behind them, or they are busy with
## their hands in front of them.
## Metres within which the villager looks up.
const NOTICE := 4.5
## The widest the head turns from where the clip has it, radians.
const REACH := 0.9
## How far to the side of the body's front a face is still looked at, radians.
const FIELD := 1.75
## Seconds the head takes to turn.
const EASE := 0.45
## The share of the turn the neck takes; the head takes the rest.
const NECK_SHARE := 0.35
## Nobody stares: the look is held for LOOK seconds, then the work has the
## eyes for AWAY seconds.
const LOOK := 3.5
const AWAY := 5.0

var actor: VillageNPC
var _head := -1
var _neck := -1
var _weight := 0.0
var _turn := Quaternion.IDENTITY
## The way the face looks in the head bone's own frame.
var _face := Vector3.FORWARD
var _clock := 0
## Seconds into the round of looking and looking away.
var _round := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	_head = skeleton.find_bone("Head")
	_neck = skeleton.find_bone("Neck")
	if _head >= 0:
		# At rest the face looks where the body does.
		var rest := skeleton.get_bone_global_rest(_head).basis.orthonormalized()
		var ahead := (skeleton.global_basis.inverse() * (-actor.global_basis.z)).normalized()
		_face = rest.inverse() * ahead

func _process_modification() -> void:
	if _head < 0 or not is_instance_valid(actor):
		return
	var skeleton := get_skeleton()
	var now := Time.get_ticks_msec()
	var delta := clampf(float(now - _clock) * 0.001, 0.0, 0.1)
	_clock = now
	var wanted := Quaternion.IDENTITY
	var looks := false
	var camera := actor.get_viewport().get_camera_3d()
	if camera != null and not actor.seated and actor.outing == null:
		var pose := skeleton.get_bone_global_pose(_head)
		var eye := skeleton.global_transform * pose.origin
		var to_camera := camera.global_position - eye
		var level := Vector3(to_camera.x, 0.0, to_camera.z)
		var front := -actor.global_basis.z
		var near := to_camera.length() < NOTICE and level.length() > 0.2 and front.angle_to(level) < FIELD
		_round = fmod(_round + delta, LOOK + AWAY) if near else 0.0
		if near and _round < LOOK:
			var facing := (skeleton.global_basis * (pose.basis.orthonormalized() * _face)).normalized()
			var turn := Quaternion(facing, to_camera.normalized())
			var angle := turn.get_angle()
			if angle > REACH:
				turn = Quaternion(turn.get_axis().normalized(), REACH)
			wanted = turn
			looks = true
	_weight = move_toward(_weight, 1.0 if looks else 0.0, delta / EASE)
	if looks:
		_turn = _turn.slerp(wanted, minf(1.0, delta / EASE * 2.0))
	if _weight <= 0.001:
		_turn = Quaternion.IDENTITY
		return
	var eased := _weight * _weight * (3.0 - 2.0 * _weight)
	if _neck >= 0:
		_rotate_world(skeleton, _neck, Quaternion.IDENTITY.slerp(_turn, eased * NECK_SHARE))
	_rotate_world(skeleton, _head, Quaternion.IDENTITY.slerp(_turn, eased * (1.0 - NECK_SHARE)))

func _rotate_world(skeleton: Skeleton3D, bone: int, turn: Quaternion) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var basis := skeleton.global_basis.orthonormalized()
	pose.basis = basis.inverse() * Basis(turn) * basis * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
