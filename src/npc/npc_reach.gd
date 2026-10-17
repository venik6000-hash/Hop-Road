class_name NpcReach
extends LimbPose
## The trunk and the arms of a villager who works with the hands at a thing
## of the world (docs/LIFE.md, «Работа руками»): the pelvis goes down and
## back with the feet kept where they stand, the trunk bends forward and
## turns, each hand goes to its place on the thing and lies there in its own
## turn, and the head looks at the work. A work (NpcBarWork, NpcWipe) sets the
## pose for each frame; NpcPoses sets the weight of each arm from NpcBody
## (the doers POUR and WIPE). It runs after the seat and the gestures, before
## the stumble and the joint limits.

## Where the middle of the palm's skin lies in the hand bone's own space, by
## model, for the right hand; the left mirrors x. Measured on the meshes (the
## hands have no finger bones): the palm faces the bone's +x on the right,
## -x on the left, and the hand runs along +y.
const PALM := {
	"innkeeper": Vector3(0.036, 0.082, -0.012),
	"maid": Vector3(0.026, 0.102, -0.018),
}
const PALM_DEFAULT := Vector3(0.03, 0.09, -0.015)
## How the trunk's bend and turn are shared among the spine bones, pelvis up.
const SPINE := ["Spine", "Spine1", "Spine2"]
const SHARE := [0.4, 0.35, 0.25]
## The farthest the trunk bends forward to bring a hand within reach, radians.
const MAX_LEAN := deg_to_rad(62.0)
## The pelvis goes back by this much of the bend's sine, metres: the weight
## stays over the feet.
const HIPS_BACK := 0.13
## The face keeps at least this far from every hand's place and from what it
## looks at, metres: the trunk bends no further, so the face never goes into
## the work.
const HEAD_CLEAR := 0.32
## The face lies this far ahead of the head's joint, metres.
const FACE_AHEAD := 0.1
## A hand reaches this share of the arm's full length before the trunk helps.
const EASY_REACH := 0.94
## The head's share of a look; the neck takes the rest.
const HEAD_SHARE := 0.6
## The widest the head turns to look at the work, radians.
const LOOK_REACH := deg_to_rad(55.0)

## Where one hand goes.
class Hand:
	## 0..1: how far the hand goes from the clip's place to its own.
	var weight := 0.0
	## Where the middle of the palm goes, world.
	var palm := Vector3.ZERO
	## Where the fingers point and the way the palm faces, world.
	var along := Vector3.FORWARD
	var facing := Vector3.DOWN
	## Which way the elbow goes, world; zero for out and down.
	var elbow := Vector3.ZERO

## Metres the pelvis goes down, the knees bending.
var drop := 0.0
## Radians the trunk bends forward at least; more when a hand needs it.
var lean := 0.0
## Radians the pelvis turns to the villager's left over the planted feet.
var turn := 0.0
## Radians the trunk turns to the villager's left over the pelvis.
var twist := 0.0
## Radians the trunk leans to the villager's left.
var tilt := 0.0
## Where the eyes go, world, and how far.
var look := Vector3.ZERO
var look_weight := 0.0
var left := Hand.new()
var right := Hand.new()
## How far the work drives each arm now, 0..1 (NpcBody): "L" and "R".
var arms := {"L": 0.0, "R": 0.0}
## The model's name (PALM).
var model := ""
## The bend the trunk took in the last frame, radians (for tests).
var bent := 0.0
## The trunk bends and straightens no faster than this, radians a second.
const BEND_RATE := deg_to_rad(90.0)
var _bend := -1.0
var _face := Vector3.ZERO
var _forearms := {"L": Vector3.ZERO, "R": Vector3.ZERO}

## The hand of `side`, "L" or "R".
func hand(side: String) -> Hand:
	return left if side == "L" else right

## The way the forearm of `side` pointed in the last frame the work drove it,
## elbow to wrist, world; zero before that.
func forearm(side: String) -> Vector3:
	return _forearms[side]

## Where the middle of the palm lies in the hand bone's space for `side`.
func palm_point(side: String) -> Vector3:
	var palm: Vector3 = PALM.get(model, PALM_DEFAULT)
	return palm if side == "R" else Vector3(-palm.x, palm.y, palm.z)

## The world turn of a hand bone of `side` whose fingers point `along` and
## whose palm faces `facing`.
static func hand_basis(side: String, along: Vector3, facing: Vector3) -> Basis:
	var length := along.normalized()
	var palm := (facing - length * facing.dot(length)).normalized()
	var x := palm if side == "R" else -palm
	return Basis(x, length, x.cross(length)).orthonormalized()

## Where the wrist goes so that the palm's middle of `side` lies at `palm`
## with the hand turned `turn` (world), for a skeleton of unit scale.
func wrist_for(side: String, palm: Vector3, turn: Basis) -> Vector3:
	return palm - turn * palm_point(side)

func _process_modification() -> void:
	bent = 0.0
	if influence <= 0.0 or not is_instance_valid(actor):
		_bend = -1.0
		return
	var skeleton := get_skeleton()
	_find(skeleton, ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "Arm_L", "ForeArm_L", "Hand_L",
		"Arm_R", "ForeArm_R", "Hand_R", "UpLeg_L", "Leg_L", "Foot_L", "UpLeg_R", "Leg_R", "Foot_R"])
	if _bones.Hips < 0 or _bones.Spine < 0:
		return
	var up := Vector3.UP
	var forward := -actor.global_basis.z.normalized()
	var right_side := actor.global_basis.x.normalized()
	var weight := influence
	# The trunk bends as far as the hands need, the pelvis going back.
	var wanted := _wrist_targets(skeleton)
	var bend := _bend_for(skeleton, wanted, forward, right_side, up)
	_bend = bend if _bend < 0.0 else move_toward(_bend, bend, BEND_RATE * get_process_delta_time())
	bend = _bend
	bent = bend * weight
	var shift := Vector3.DOWN * drop - forward * HIPS_BACK * sin(bend)
	if shift.length() * weight > 0.001 or absf(turn * weight) > 0.002:
		_lower_pelvis(skeleton, shift * weight, turn * weight, forward, right_side)
	forward = Basis(up, turn * weight) * forward
	right_side = Basis(up, turn * weight) * right_side
	# The trunk turns, leans aside and bends, shared from the pelvis up.
	var turned := 0.0
	for index in SPINE.size():
		var bone: int = _bones.get(SPINE[index], -1)
		if bone < 0:
			continue
		var share: float = SHARE[index] * weight
		turned += twist * share
		var across := Basis(up, turned) * right_side
		var ahead := Basis(up, turned) * forward
		var turn := Quaternion(across, -bend * share) * Quaternion(ahead, -tilt * share) * Quaternion(up, twist * share)
		_rotate_world(skeleton, bone, turn)
	# Each hand to its place, then turned as it lies there.
	for side: String in ["L", "R"]:
		var goal: Hand = hand(side)
		if goal.weight * Values.real(arms[side]) <= 0.0:
			continue
		var bone_hand: int = _bones["Hand_" + side]
		if bone_hand < 0:
			continue
		var turn := hand_basis(side, goal.along, goal.facing)
		var amount := goal.weight * Values.real(arms[side])
		var goal_at: Vector3 = wanted[side]
		var wrist := _world_origin(skeleton, bone_hand).lerp(goal_at, amount)
		var sign_side := 1.0 if side == "R" else -1.0
		var pole := goal.elbow if goal.elbow != Vector3.ZERO else right_side * sign_side * 0.7 + Vector3.DOWN * 0.6 - forward * 0.15
		_solve_chain(skeleton, Values.whole(_bones["Arm_" + side]), Values.whole(_bones["ForeArm_" + side]), bone_hand, wrist, pole.normalized())
		_forearms[side] = _world_origin(skeleton, Values.whole(bone_hand)) - _world_origin(skeleton, Values.whole(_bones["ForeArm_" + side]))
		var pose := skeleton.get_bone_global_pose(bone_hand)
		var now := (skeleton.global_basis.orthonormalized() * pose.basis.orthonormalized()).get_rotation_quaternion()
		var placed := now.slerp(turn.get_rotation_quaternion(), amount)
		pose.basis = skeleton.global_basis.orthonormalized().inverse() * Basis(placed)
		_set_global(skeleton, bone_hand, pose)
	if look_weight > 0.0:
		_look(skeleton, look_weight * weight)

## Where each weighted hand's wrist must go, world.
func _wrist_targets(skeleton: Skeleton3D) -> Dictionary:
	var found := {}
	for side: String in ["L", "R"]:
		var goal: Hand = hand(side)
		var bone_hand: int = _bones["Hand_" + side]
		found[side] = _world_origin(skeleton, bone_hand) if bone_hand >= 0 else Vector3.ZERO
		if goal.weight > 0.0 and bone_hand >= 0:
			found[side] = wrist_for(side, goal.palm, hand_basis(side, goal.along, goal.facing))
	return found

## The bend, no less than `lean`, that brings every wrist driven at least
## half way within EASY_REACH of its shoulder, found from the last frame's
## bend: it stays while it serves, eases down while a smaller one serves, and
## grows only when the hands need more. The reach is not steady in the bend
## (a high hand first goes away as the shoulders go down), so a search from
## the upright would jump between far bends. No bend brings the head nearer
## than HEAD_CLEAR to a hand's place: where the hands need more, they fall
## short. The shoulders and the head are moved as the pose moves them: the
## pelvis goes down, back and round, then each spine bone turns its share
## about its own joint.
func _bend_for(skeleton: Skeleton3D, wanted: Dictionary, forward: Vector3, right_side: Vector3, up: Vector3) -> float:
	var hips := _world_origin(skeleton, Values.whole(_bones.Hips))
	var joints: Array[Vector3] = []
	for name: String in SPINE:
		var bone: int = _bones.get(name, -1)
		if bone >= 0:
			joints.append(_world_origin(skeleton, bone))
	var step := deg_to_rad(2.0)
	var most := MAX_LEAN
	while most > lean and not _head_clear(skeleton, hips, joints, most, forward, right_side, up):
		most -= step
	var bend := clampf(_bend, lean, most) if _bend >= 0.0 else lean
	if _reaches(skeleton, wanted, hips, joints, bend, forward, right_side, up):
		while bend - step >= lean and _reaches(skeleton, wanted, hips, joints, bend - step, forward, right_side, up):
			bend -= step
		return bend
	var from := bend
	while bend < most:
		bend = minf(bend + step, most)
		if _reaches(skeleton, wanted, hips, joints, bend, forward, right_side, up):
			return bend
	bend = from
	while bend - step >= lean:
		bend -= step
		if _reaches(skeleton, wanted, hips, joints, bend, forward, right_side, up):
			return bend
	return most

## Whether the head at `bend` keeps HEAD_CLEAR from what it looks at and
## from the place of every hand driven at least half way.
func _head_clear(skeleton: Skeleton3D, hips: Vector3, joints: Array[Vector3], bend: float, forward: Vector3,
		right_side: Vector3, up: Vector3) -> bool:
	if _bones.Head < 0:
		return true
	var face := _world_origin(skeleton, Values.whole(_bones.Head)) + forward * FACE_AHEAD
	var head := _swung(face, hips, joints, bend, forward, right_side, up)
	if look_weight > 0.0 and head.distance_to(look) < HEAD_CLEAR:
		return false
	for side: String in ["L", "R"]:
		var goal: Hand = hand(side)
		if goal.weight * Values.real(arms[side]) >= 0.5 and head.distance_to(goal.palm) < HEAD_CLEAR:
			return false
	return true

## Whether every wrist driven at least half way is within EASY_REACH of its
## shoulder at `bend`.
func _reaches(skeleton: Skeleton3D, wanted: Dictionary, hips: Vector3, joints: Array[Vector3], bend: float,
		forward: Vector3, right_side: Vector3, up: Vector3) -> bool:
	for side: String in ["L", "R"]:
		var goal: Hand = hand(side)
		if goal.weight * Values.real(arms[side]) < 0.5 or _bones["Arm_" + side] < 0:
			continue
		var shoulder := _world_origin(skeleton, Values.whole(_bones["Arm_" + side]))
		var elbow := _world_origin(skeleton, Values.whole(_bones["ForeArm_" + side]))
		var wrist := _world_origin(skeleton, Values.whole(_bones["Hand_" + side]))
		var length := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
		var moved := _swung(shoulder, hips, joints, bend, forward, right_side, up)
		var goal_at: Vector3 = wanted[side]
		if moved.distance_to(goal_at) > EASY_REACH * length:
			return false
	return true

## Where `point` on the upper body goes when the pelvis at `hips` moves and
## turns and the spine bones at `joints` bend `bend` and twist, as
## _process_modification does it.
func _swung(point: Vector3, hips: Vector3, joints: Array[Vector3], bend: float, forward: Vector3,
		right_side: Vector3, up: Vector3) -> Vector3:
	var shift := Vector3.DOWN * drop - forward * HIPS_BACK * sin(bend)
	var yaw := Quaternion(up, turn)
	var pivots: Array[Vector3] = []
	for joint in joints:
		pivots.append(hips + shift + yaw * (joint - hips))
	var moved := hips + shift + yaw * (point - hips)
	var across := yaw * right_side
	var turned := 0.0
	for index in pivots.size():
		var share: float = SHARE[index]
		turned += twist * share
		var swing := Quaternion(Basis(up, turned) * across, -bend * share) * Quaternion(up, twist * share)
		var pivot := pivots[index]
		moved = pivot + swing * (moved - pivot)
		for later in range(index + 1, pivots.size()):
			pivots[later] = pivot + swing * (pivots[later] - pivot)
	return moved

## Moves the pelvis by `shift`, turns it `yaw` about the vertical and bends
## each leg back to its foot, the foot keeping its place and its turn.
func _lower_pelvis(skeleton: Skeleton3D, shift: Vector3, yaw: float, forward: Vector3, right_side: Vector3) -> void:
	var feet := {}
	for side: String in ["L", "R"]:
		var foot: int = _bones["Foot_" + side]
		if foot < 0:
			return
		feet[side] = skeleton.global_transform * skeleton.get_bone_global_pose(foot)
	_set_origin(skeleton, Values.whole(_bones.Hips), _world_origin(skeleton, Values.whole(_bones.Hips)) + shift)
	if absf(yaw) > 0.0001:
		_rotate_world(skeleton, Values.whole(_bones.Hips), Quaternion(Vector3.UP, yaw))
	for side: String in ["L", "R"]:
		var sign_side := 1.0 if side == "R" else -1.0
		var placed: Transform3D = feet[side]
		# The knee goes ahead and a little out, over the toes (the standing
		# clips turn the toes out a little): a nearly straight leg of the clip
		# gives no steady way of its own.
		var pole := (forward + right_side * sign_side * 0.15).normalized()
		_solve_chain(skeleton, Values.whole(_bones["UpLeg_" + side]), Values.whole(_bones["Leg_" + side]), Values.whole(_bones["Foot_" + side]), placed.origin, pole)
		var foot: int = _bones["Foot_" + side]
		var pose := skeleton.get_bone_global_pose(foot)
		pose.basis = skeleton.global_basis.orthonormalized().inverse() * placed.basis.orthonormalized()
		_set_global(skeleton, foot, pose)

## Turns the neck and the head toward `look`, `amount` of the way and no
## more than LOOK_REACH.
func _look(skeleton: Skeleton3D, amount: float) -> void:
	var head: int = _bones.Head
	if head < 0:
		return
	if _face == Vector3.ZERO:
		var rest := skeleton.get_bone_global_rest(head).basis.orthonormalized()
		var ahead := (skeleton.global_basis.orthonormalized().inverse() * (-actor.global_basis.z)).normalized()
		_face = rest.inverse() * ahead
	var pose := skeleton.get_bone_global_pose(head)
	var eye := skeleton.global_transform * pose.origin
	var facing := (skeleton.global_basis.orthonormalized() * (pose.basis.orthonormalized() * _face)).normalized()
	var toward := look - eye
	if toward.length_squared() < 0.0001:
		return
	var turn := Quaternion(facing, toward.normalized())
	var angle := turn.get_angle()
	if angle < 0.001:
		return
	var axis := turn.get_axis().normalized()
	angle = minf(angle, LOOK_REACH) * amount
	if _bones.Neck >= 0:
		_rotate_world(skeleton, Values.whole(_bones.Neck), Quaternion(axis, angle * (1.0 - HEAD_SHARE)))
	_rotate_world(skeleton, head, Quaternion(axis, angle * HEAD_SHARE))
