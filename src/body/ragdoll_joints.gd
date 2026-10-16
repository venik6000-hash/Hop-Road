class_name RagdollJoints
extends RefCounted
## The physical bones of a villager's active ragdoll and the joints between
## them, compiled from the joint table (JointLimits; docs/LIFE.md, «Толчок»).
##
## A joint is a frame in each of its two bodies and the limits between them;
## PhysicsServer3D joins the bodies by it. The frames are written so that the
## joint's angles count from the table's zero, not from the pose the bones had
## when they were made. A hinge's frame Z is its axis and its X the parent's
## line, so its limits are the table's `min` and `max`. A cone's frame X is the
## table's axis on the parent and the bone's length on the bone, so its swing
## span is the table's cone. Jolt counts a hinge's angle the other way round,
## so its limits are the table's turned over. The engine's hinge has no play
## and no twist and its cone one twist span both ways: JointLimitModifier3D
## clamps the rest.

## The bones, parents first: {to: the bones whose head ends this one, the
## first the rig has, or length: metres; radius: metres; mass: kg}. The neck
## and the shoulders are not physical: they keep their clip pose against the
## bone below. A rig without Spine2 (bartender, monk) has its chest in Spine1
## and 12 bones.
const BONES := {
	"Hips": {"to": ["Spine"], "radius": 0.12, "mass": 11.0},
	"Spine": {"to": ["Spine1"], "radius": 0.11, "mass": 7.0},
	"Spine1": {"to": ["Spine2", "Neck"], "radius": 0.12, "mass": 7.0},
	"Spine2": {"to": ["Neck"], "radius": 0.13, "mass": 9.0, "optional": true},
	"Head": {"length": 0.2, "radius": 0.1, "mass": 5.0},
	"Arm_L": {"to": ["ForeArm_L"], "radius": 0.05, "mass": 2.5},
	"ForeArm_L": {"to": ["Hand_L"], "radius": 0.045, "mass": 1.8},
	"Arm_R": {"to": ["ForeArm_R"], "radius": 0.05, "mass": 2.5},
	"ForeArm_R": {"to": ["Hand_R"], "radius": 0.045, "mass": 1.8},
	"UpLeg_L": {"to": ["Leg_L"], "radius": 0.07, "mass": 8.0},
	"Leg_L": {"to": ["Foot_L"], "radius": 0.055, "mass": 4.0},
	"UpLeg_R": {"to": ["Leg_R"], "radius": 0.07, "mass": 8.0},
	"Leg_R": {"to": ["Foot_R"], "radius": 0.055, "mass": 4.0},
}

## The joint of `joint` (one of JointLimits.bind) in two frames: `a` in the
## frame of the bone's parent in the skeleton, `b` in the bone's own frame.
## {hinge: bool, a: Basis, b: Basis, and low, high for a hinge, swing, twist
## for a cone; radians}.
static func compile(joint: JointLimits.Joint) -> Dictionary:
	var rest := Basis(joint.rest)
	var length := joint.rest * Vector3.UP
	if joint.hinge:
		var x := joint.straight.normalized()
		var z := joint.axis.normalized()
		var a := Basis(x, z.cross(x), z)
		var flat := length - z * length.dot(z)
		var bend := atan2(x.cross(flat).dot(z), x.dot(flat))
		# In the rest pose the hinge stands at the rest's bend.
		var b := rest.inverse() * Basis(Quaternion(z, bend)) * a
		return {"hinge": true, "a": a, "b": b, "low": joint.low, "high": joint.high}
	var axis := joint.axis.normalized()
	var across := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var a := Basis(axis, across, axis.cross(across))
	var b := rest.inverse() * Basis(JointLimits.arc(axis, length)) * a
	return {"hinge": false, "a": a, "b": b, "swing": joint.cone,
		"twist": minf(-joint.twist_low, joint.twist_high)}

## The nearest bone of BONES above `bone` in the skeleton, -1 for none.
static func body_parent(skeleton: Skeleton3D, bone: int) -> int:
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0 and not BONES.has(skeleton.get_bone_name(parent)):
		parent = skeleton.get_bone_parent(parent)
	return parent

## Makes the joint of `compiled` between two bodies on PhysicsServer3D.
## `parent_frame` is the world transform of the bone's parent in the skeleton,
## `head` the bone's head in the world; both bodies stand where their bones
## are. The caller frees the returned RID.
static func make(compiled: Dictionary, parent_body: RigidBody3D, body: RigidBody3D,
		parent_frame: Basis, head: Vector3) -> RID:
	var a := Transform3D(parent_frame.orthonormalized() * (compiled.a as Basis), head)
	var local_a := parent_body.global_transform.affine_inverse() * a
	local_a.basis = local_a.basis.orthonormalized()
	var local_b := Transform3D(compiled.b as Basis, Vector3.ZERO)
	var server := PhysicsServer3D
	var joint := server.joint_create()
	if compiled.hinge:
		server.joint_make_hinge(joint, parent_body.get_rid(), local_a, body.get_rid(), local_b)
		server.hinge_joint_set_flag(joint, PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT, true)
		# Jolt's hinge angle is the table's bend with its sign turned.
		server.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER, -float(compiled.high))
		server.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER, -float(compiled.low))
	else:
		server.joint_make_cone_twist(joint, parent_body.get_rid(), local_a, body.get_rid(), local_b)
		server.cone_twist_joint_set_param(joint, PhysicsServer3D.CONE_TWIST_JOINT_SWING_SPAN, float(compiled.swing))
		server.cone_twist_joint_set_param(joint, PhysicsServer3D.CONE_TWIST_JOINT_TWIST_SPAN, float(compiled.twist))
	server.joint_disable_collisions_between_bodies(joint, true)
	return joint

## A physical bone: a capsule from the bone's head to `tip` in the world, on
## RAGDOLL, with CCD and no gravity, standing at `frame` (the bone's world
## frame, scale removed).
static func make_body(bone: String, frame: Transform3D, tip: Vector3) -> RigidBody3D:
	var row: Dictionary = BONES[bone]
	var body := RigidBody3D.new()
	body.name = bone
	body.top_level = true
	body.collision_layer = PhysicsLayers.RAGDOLL
	body.collision_mask = PhysicsLayers.mask_of(PhysicsLayers.RAGDOLL)
	body.continuous_cd = true
	body.mass = float(row.mass)
	body.can_sleep = false
	# The springs of NpcStumble carry the weight, as the muscles do.
	body.gravity_scale = 0.0
	body.transform = Transform3D(frame.basis.orthonormalized(), frame.origin)
	var radius := float(row.radius)
	var along := body.transform.affine_inverse() * tip
	if along.length() < 0.01:
		along = Vector3.UP * 0.01
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = along.length() + 2.0 * radius
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.transform = Transform3D(Basis(JointLimits.arc(Vector3.UP, along.normalized())), along * 0.5)
	body.add_child(shape)
	return body
