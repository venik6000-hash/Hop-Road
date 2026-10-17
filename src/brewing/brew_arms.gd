class_name BrewArms
extends Node3D
## The brewer's arms (assets/models/brewery/brew_hands.glb, modelled by
## tools/pipeline/brewery/hands.py) on the brewery's works: each hand on the
## bar BrewHands gives it, the arm bent there by IK (BrewArmIK), the fingers
## closed by the hand's clip. A hand with nothing to take hangs at the side.
## The node stands in the eye's frame, turned with the look but kept upright.
## The player owns one (Player.arms); the doer that has the hands
## (BodyChannels) puts them on what it holds.

const MODEL := preload("res://assets/models/brewery/brew_hands.glb")
## The beer mug's hand: the same skin, its maps already imported.
const SKIN := preload("res://assets/models/beer/right_hand_grip.glb")
const CLIPS: Array[String] = ["grip", "hold", "rest", "open"]
## The bar bone each clip's fingers close on.
const BARS := {"grip": "grip", "hold": "hold", "rest": "grip", "open": "grip"}
const SIDES: Array[String] = ["R", "L"]
## Seconds the fingers take from one clip to the next.
const CLOSE := 0.15
## Where an idle hand hangs, from its shoulder (the eye's frame).
const HANG := Vector3(0.05, -0.53, -0.06)

var skeleton: Skeleton3D
var ik: BrewArmIK
## The arms' anatomical limits, after the IK.
var limits: JointLimitModifier3D
## The hands now: BrewHands' {side, at, clip}.
var hands: Array[Dictionary] = []
## Metres from the shoulder to the wrist with the arm straight: the farthest
## the IK puts a wrist (BrewArmIK.reached).
var span := 0.0

## clip -> bone index -> its rotation.
var _poses := {}
## side -> the finger bones.
var _fingers: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _clip: Array[String] = ["rest", "rest"]
## side -> bone -> the rotation the fingers left from.
var _from: Array[Dictionary] = [{}, {}]
var _blend: Array[float] = [1.0, 1.0]
## "R:grip" -> the hand's transform from the bar's frame (BrewHands' `at`).
var _offsets := {}
var _mesh: MeshInstance3D

func _ready() -> void:
	var model := MODEL.instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	ik = BrewArmIK.new()
	ik.name = "ArmIK"
	skeleton.add_child(ik)
	limits = JointLimitModifier3D.new("player_arm")
	skeleton.add_child(limits)
	_mesh = skeleton.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	# The arms move with every look: a lamp would draw its shadow map again in
	# each frame (docs/PERFORMANCE.md).
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.layers = LightLayers.ROOMS
	var beer := SKIN.instantiate()
	var skin := (beer.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.surface_get_material(0)
	beer.free()
	_mesh.set_surface_override_material(0, skin)
	_mesh.set_surface_override_material(1, MugPresentation.sleeve_cloth())
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in CLIPS:
		_poses[clip] = _read_clip(player.get_animation(clip))
	player.queue_free()
	for side in SIDES.size():
		for bone: int in _poses.grip:
			if skeleton.get_bone_name(bone).ends_with("." + SIDES[side]):
				_fingers[side].append(bone)
		for bar: String in ["grip", "hold"]:
			_offsets["%s:%s" % [SIDES[side], bar]] = rest_bar(side, bar).affine_inverse() * \
				skeleton.get_bone_global_rest(skeleton.find_bone("hand." + SIDES[side]))
	var upper := skeleton.get_bone_global_rest(skeleton.find_bone("upper_arm." + SIDES[0])).origin
	var fore := skeleton.get_bone_global_rest(skeleton.find_bone("forearm." + SIDES[0])).origin
	span = upper.distance_to(fore) + fore.distance_to(skeleton.get_bone_global_rest(skeleton.find_bone("hand." + SIDES[0])).origin)
	visible = false

## The bar's frame of a hand at rest, skeleton space, in BrewHands' terms: x
## from the index finger to the little one, y to the back of the hand.
func rest_bar(side: int, bar: String) -> Transform3D:
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_1." + SIDES[side])).origin
	var little := skeleton.get_bone_global_rest(skeleton.find_bone("little_1." + SIDES[side])).origin
	var x := little - index
	x.y = 0.0
	x = x.normalized()
	var y := Vector3.UP
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("%s.%s" % [bar, SIDES[side]])).origin
	return Transform3D(Basis(x, y, x.cross(y)), middle)

## The hands to take (BrewHands' list); none hides the arms.
func reach(taken: Array[Dictionary]) -> void:
	hands = taken
	visible = not taken.is_empty()
	for side in SIDES.size():
		var clip := "rest"
		for hand: Dictionary in taken:
			if Values.whole(hand.side) == side:
				clip = str(hand.clip)
		if clip != _clip[side]:
			for bone in _fingers[side]:
				_from[side][bone] = skeleton.get_bone_pose_rotation(bone)
			_clip[side] = clip
			_blend[side] = 0.0

## Takes the hands away: the arms hide.
func drop() -> void:
	var none: Array[Dictionary] = []
	reach(none)

## Opens the fingers that held something (a log let fly), keeping the hands where they are.
func let_go() -> void:
	var opened: Array[Dictionary] = []
	for hand: Dictionary in hands:
		var open := hand.duplicate()
		open.clip = "open"
		opened.append(open)
	reach(opened)

## Poses the arms for this frame: the fingers on the way to their clips, the
## arms reaching for the hands' bars.
func pose(delta: float) -> void:
	if not visible:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for side in SIDES.size():
		_blend[side] = minf(_blend[side] + delta / CLOSE, 1.0)
		var t := smoothstep(0.0, 1.0, _blend[side])
		var target: Dictionary = _poses[_clip[side]]
		for bone in _fingers[side]:
			var from: Quaternion = _from[side].get(bone, target[bone])
			var to: Quaternion = target[bone]
			skeleton.set_bone_pose_rotation(bone, from.slerp(to, t))
		ik.targets[side] = _hang(side)
		ik.weights[side] = 1.0
	for hand: Dictionary in hands:
		var side := Values.whole(hand.side)
		var bar := str(BARS[str(hand.clip)])
		var at: Transform3D = hand.at
		var offset: Transform3D = _offsets["%s:%s" % [SIDES[side], bar]]
		ik.targets[side] = to_skeleton * at * offset
	skeleton.advance(delta)

## The clip hand `side`'s fingers go to now (CLIPS).
func clip_of(side: int) -> String:
	return _clip[side]

## Whether hand `side`'s fingers stand in `clip`, each bone within
## `tolerance` radians.
func fingers_in(side: int, clip: String, tolerance: float) -> bool:
	var want: Dictionary = _poses[clip]
	for bone in _fingers[side]:
		var rotation: Quaternion = want[bone]
		if skeleton.get_bone_pose_rotation(bone).angle_to(rotation) > tolerance:
			return false
	return true

## Where the wrist of `hand` (BrewHands' {side, at, clip}) must stand for
## the hand to close on its bar, world space. The wrist lies off the bar by
## the hand's own size, and the bar's turn sets the way: reach is the wrist's.
func wrist_for(hand: Dictionary) -> Vector3:
	var at: Transform3D = hand.at
	var offset: Transform3D = _offsets["%s:%s" % [SIDES[Values.whole(hand.side)], str(BARS[str(hand.clip)])]]
	return (at * offset).origin

## Shoulder `side`'s joint, world space.
func shoulder(side: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("upper_arm." + SIDES[side])).origin

## Where hand `side` would be on its bar now, world space (to check the reach).
func bar_now(side: int, bar: String) -> Transform3D:
	var offset: Transform3D = _offsets["%s:%s" % [SIDES[side], bar]]
	return skeleton.global_transform * ik.placed[side] * offset.affine_inverse()

## An idle hand hanging by its side, fingers down, skeleton space.
func _hang(side: int) -> Transform3D:
	var shoulder := skeleton.get_bone_global_rest(skeleton.find_bone("upper_arm." + SIDES[side])).origin
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone("hand." + SIDES[side]))
	var out := HANG * Vector3(1.0 if side == 0 else -1.0, 1.0, 1.0)
	return Transform3D(Basis(Quaternion(Vector3.FORWARD, Vector3.DOWN)) * hand.basis, shoulder + out)

## A clip's finger rotations: bone index -> Quaternion.
func _read_clip(animation: Animation) -> Dictionary:
	var pose := {}
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := skeleton.find_bone(str(animation.track_get_path(track).get_concatenated_subnames()))
		if bone >= 0:
			pose[bone] = animation.rotation_track_interpolate(track, 0.0)
	return pose
