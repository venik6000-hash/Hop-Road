class_name NpcStumble
extends LimbPose
## A villager's active ragdoll after the player runs into them (docs/LIFE.md,
## «Толчок»). The bones of RagdollJoints become rigid bodies on RAGDOLL,
## joined by the joint table. Each body is pulled towards the pose the
## skeleton has before this modifier (the clip, the seat, the gestures) by a
## spring with a damper. At the impact the springs go weak and come back; the
## pelvis keeps more of its strength and is also pulled to its place. The
## muscles carry the body's weight: the bodies have no gravity, and the
## stumble is the push against the weakened springs. The
## modifier writes the bodies' turns into the bones; its `influence`, the
## stumble's weight in NpcBody, blends them with the clip. The bodies are made
## at the bump and freed when the weight is back at zero.

## The slowest approach, m/s along the contact, that makes a villager
## stumble: between the player's walk (3) and run (5), so only a run does.
const BUMP_SPEED := 4.0
## Seconds the stumble holds the body (NpcBody.STUMBLE).
const SECONDS := 1.2
## The springs' stiffness at full strength, 1/s².
const STIFFNESS := 400.0
## The pelvis's springs are this many times stiffer.
const PELVIS_GAIN := 3.0
## The pull of the pelvis to its place at full strength, 1/s².
const PELVIS_PULL := 300.0
## The strength right after the impact; the pelvis keeps PELVIS_LOW.
const LOW := 0.25
const PELVIS_LOW := 0.5
## Seconds over which the strength comes back to full.
const RECOVER := 0.9
## How much of the push each body takes; the rest none.
const KICK := {"Hips": 0.3, "Spine": 0.45, "Spine1": 0.6, "Spine2": 0.6, "Head": 0.6}

## The budget the ragdoll is taken from and given back to (the villager's).
var ragdolls: RagdollBudget
## Bone name -> its body, while the ragdoll runs.
var bodies: Dictionary[String, RigidBody3D] = {}
## Seconds since the impact.
var age := 0.0
## Bone name -> where the pose before this modifier has it, world space.
var _targets: Dictionary[String, Transform3D] = {}
var _joints: Array[RID] = []
## The bones of RagdollJoints.BONES the rig has -> their indices, parents first.
var _indices: Dictionary[String, int] = {}

func _init() -> void:
	name = "Stumble"
	active = false

## The speed at which a body moving at `velocity` closes on a surface whose
## normal, towards the body, is `normal`; along the ground only.
static func bump_speed(velocity: Vector3, normal: Vector3) -> float:
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	return maxf(0.0, -Vector3(velocity.x, 0.0, velocity.z).dot(flat.normalized()))

## The springs' strength `seconds` after the impact, from `low` back to 1.
static func strength(seconds: float, low: float) -> float:
	return lerpf(low, 1.0, smoothstep(0.0, RECOVER, seconds))

## One step of a spring with a damper on `velocity` towards an `error`,
## implicit, so it holds at any stiffness: critically damped.
static func spring(velocity: Vector3, error: Vector3, stiffness: float, delta: float) -> Vector3:
	var damping := 2.0 * sqrt(stiffness)
	return (velocity + error * stiffness * delta) / (1.0 + damping * delta + stiffness * delta * delta)

## Whether the ragdoll's bodies exist.
func running() -> bool:
	return not bodies.is_empty()

## Where the pose under this modifier has `bone`, world space: the body of the
## bone is pulled to it.
func target_of(bone: String) -> Transform3D:
	return _targets[bone]

## Makes the bodies where the bones stand and pushes them at `push`, m/s.
## False when the ragdoll budget is spent (`distance`: metres to the player)
## or the skeleton lacks a bone.
func start(push: Vector3, distance: float) -> bool:
	var skeleton := get_skeleton()
	if running() or skeleton == null:
		return false
	_indices.clear()
	for bone: String in RagdollJoints.BONES:
		var index := skeleton.find_bone(bone)
		var joint: Dictionary = RagdollJoints.BONES[bone]
		if index >= 0:
			_indices[bone] = index
		elif not joint.get("optional", false):
			return false
	if not ragdolls.take(actor, distance):
		return false
	var limits := {}
	for joint in JointLimits.bind(skeleton, "villager"):
		limits[joint.name] = joint
	for bone: String in _indices:
		var frame := _world(skeleton, _indices[bone])
		var row: Dictionary = RagdollJoints.BONES[bone]
		var tip: Vector3 = frame.origin + frame.basis.y * Values.real(row.get("length", 0.0))
		for end: String in row.get("to", []):
			if skeleton.find_bone(end) >= 0:
				tip = _world_origin(skeleton, skeleton.find_bone(end))
				break
		var body := RagdollJoints.make_body(bone, frame, tip)
		add_child(body)
		body.linear_velocity = push * Values.real(KICK.get(bone, 0.0))
		bodies[bone] = body
		_targets[bone] = body.global_transform
		var parent := RagdollJoints.body_parent(skeleton, _indices[bone])
		if parent >= 0 and limits.has(bone):
			var above := _world(skeleton, skeleton.get_bone_parent(_indices[bone]))
			var limit: JointLimits.Joint = limits[bone]
			_joints.append(RagdollJoints.make(RagdollJoints.compile(limit),
				bodies[skeleton.get_bone_name(parent)], body, above.basis, frame.origin))
	age = 0.0
	active = true
	return true

## Frees the bodies and the joints and gives the budget back.
func stop() -> void:
	for joint in _joints:
		PhysicsServer3D.free_rid(joint)
	_joints.clear()
	for body: RigidBody3D in bodies.values():
		body.queue_free()
	bodies.clear()
	_targets.clear()
	active = false
	ragdolls.give_back(actor)

## Follows the stumble's weight in NpcBody; ends the ragdoll once the body is
## back at the clip.
func follow(weight: float, claimed: bool) -> void:
	influence = weight
	if running() and not claimed and weight <= 0.0:
		stop()

func _exit_tree() -> void:
	if running():
		stop()

func _physics_process(delta: float) -> void:
	if not running():
		return
	age += delta
	for bone: String in bodies:
		var body := bodies[bone]
		var target := _targets[bone]
		var pelvis := bone == "Hips"
		var power := strength(age, PELVIS_LOW if pelvis else LOW)
		var turn := (target.basis.get_rotation_quaternion() * body.global_basis.get_rotation_quaternion().inverse()).normalized()
		if turn.w < 0.0:
			turn = -turn
		var error := turn.get_axis() * turn.get_angle() if turn.w < 0.999999 else Vector3.ZERO
		body.angular_velocity = spring(body.angular_velocity, error, STIFFNESS * power * (PELVIS_GAIN if pelvis else 1.0), delta)
		if pelvis:
			body.linear_velocity = spring(body.linear_velocity, target.origin - body.global_position, PELVIS_PULL * power, delta)

func _process_modification() -> void:
	if not running():
		return
	var skeleton := get_skeleton()
	for bone: String in bodies:
		_targets[bone] = _world(skeleton, _indices[bone])
	for bone: String in bodies:
		var index := _indices[bone]
		var pose := skeleton.get_bone_global_pose(index)
		var body := bodies[bone].global_transform
		# The bone turns as its body; only the pelvis moves, the rest hang on it.
		var placed := skeleton.global_transform.affine_inverse() * Transform3D(body.basis, body.origin)
		pose.basis = placed.basis.orthonormalized()
		if bone == "Hips":
			pose.origin = placed.origin
		_set_global(skeleton, index, pose)

## The bone's frame in the world, scale removed.
func _world(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var frame := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	return Transform3D(frame.basis.orthonormalized(), frame.origin)
