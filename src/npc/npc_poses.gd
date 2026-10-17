class_name NpcPoses
extends RefCounted
## The pose modifiers that bend a villager's clip (VillageNPC.poses,
## docs/LIFE.md, «Части тела»): the seat's hips and legs (CampPose), the arms
## (NpcArmPose), the trunk and the hands at work (NpcReach) and the ragdoll
## after a bump (NpcStumble). They are made at the first sit, gesture or bump;
## in each frame each bends the clip as far as the doers of VillageNPC.body
## drive its part. The feet keep to the ground (NpcFooting) where no doer
## holds the legs, near the camera.

var actor: VillageNPC
## The level's ragdolls at once (NpcPopulation sets it); without it the
## villager never stumbles.
var ragdolls: RagdollBudget
## The trunk and the hands at work (NpcReach): made with the seat's pose.
var reach: NpcReach
## The ragdoll after a bump (NpcStumble): made at the first bump.
var stumble: NpcStumble
var _seat_pose: CampPose
var _arm_poses: Array[NpcArmPose] = []

func _init(posed_actor: VillageNPC) -> void:
	actor = posed_actor

## Sits down on what is `height` m over the feet, eased over NpcBody.FADE.
func sit(height: float) -> void:
	if not prepare():
		return
	_seat_pose.seat_height = height
	actor.body.claim(NpcBody.SEAT)

## Gets up from the seat, eased as the sitting down.
func stand() -> void:
	actor.body.release(NpcBody.SEAT)

## Gives `doer` its parts (NpcBody.DOERS) for `seconds`. False when a doer
## of the same or a higher layer has one of them.
func gesture(doer: StringName, seconds: float) -> bool:
	return prepare() and actor.body.claim_for(doer, seconds)

## The player ran into the villager at `push`, m/s along the ground, from
## `from`: they stumble in an active ragdoll (NpcStumble) for
## NpcStumble.SECONDS. False when they sit, stumble already, or the ragdoll
## budget is spent or missing (`ragdolls`).
func bump(push: Vector3, from: Vector3) -> bool:
	if ragdolls == null or actor.seated or not prepare() or actor.body.blocker(NpcBody.STUMBLE) != &"":
		return false
	if stumble == null:
		stumble = NpcStumble.new()
		stumble.actor = actor
		stumble.ragdolls = ragdolls
		actor.skeleton.add_child(stumble)
		actor.skeleton.move_child(actor.limits, -1)
	if not stumble.start(push, actor.global_position.distance_to(from)):
		return false
	return actor.body.claim_for(NpcBody.STUMBLE, NpcStumble.SECONDS)

## Whether the villager stumbles, or is still finding their feet.
func stumbles() -> bool:
	return stumble != null and stumble.running()

## Whether the villager sits, or is still sitting down.
func sits() -> bool:
	return actor.body.has(NpcBody.SEAT)

## Makes the modifiers if they are not made yet. False for a model without a
## skeleton: it has none.
func prepare() -> bool:
	var skeleton := actor.skeleton
	if skeleton == null:
		return false
	if _seat_pose != null:
		return true
	# Modifiers run in the order of the skeleton's children: hips before arms.
	_seat_pose = CampPose.new()
	_seat_pose.actor = actor
	_seat_pose.influence = 0.0
	skeleton.add_child(_seat_pose)
	for side: String in ["L", "R"]:
		var arm := NpcArmPose.new()
		arm.actor = actor
		arm.side = side
		arm.part = NpcBody.LEFT_ARM if side == "L" else NpcBody.RIGHT_ARM
		arm.seat = _seat_pose
		arm.influence = 0.0
		skeleton.add_child(arm)
		_arm_poses.append(arm)
	reach = NpcReach.new()
	reach.actor = actor
	reach.model = NpcMotion.model_name(actor.model_path)
	reach.influence = 0.0
	skeleton.add_child(reach)
	# The limits stay last, and the hands are read once they have clamped.
	skeleton.move_child(actor.limits, -1)
	actor.limits.modification_processed.connect(actor.posed.emit)
	return true

## Each pose modifier bends the clip as far as its doers drive its part. The
## feet keep to the ground where no doer holds the legs, near the camera.
func update(delta: float) -> void:
	var body := actor.body
	if _seat_pose != null:
		body.step(delta)
		_seat_pose.influence = body.weight(NpcBody.SEAT, NpcBody.LEGS)
		for arm in _arm_poses:
			arm.influence = body.total(arm.part)
		# The work's share of each arm; the trunk bends as far as the more driven one.
		for side: String in ["L", "R"]:
			var part := NpcBody.LEFT_ARM if side == "L" else NpcBody.RIGHT_ARM
			var share := 0.0
			for doer in NpcBody.WORKERS:
				share += body.weight(doer, part)
			reach.arms[side] = minf(share, 1.0)
		reach.influence = maxf(Values.real(reach.arms.L), Values.real(reach.arms.R))
		if stumble != null:
			stumble.follow(body.weight(NpcBody.STUMBLE, NpcBody.LEGS), body.has(NpcBody.STUMBLE))
	var footing := actor.footing
	if footing != null:
		var camera := actor.get_viewport().get_camera_3d()
		var near := 1.0 if camera == null else NpcFooting.reach(camera.global_position.distance_to(actor.global_position))
		footing.influence = 0.0 if actor.seated else (1.0 - body.total(NpcBody.LEGS)) * near
