class_name NpcFooting
extends LimbPose
## Sets a villager's feet on what is under them (docs/LIFE.md, «Опора»). The
## clip draws the feet on a flat floor at the body's origin. A ray under each
## foot finds the floor, a step or the terrain (PhysicsLayers.GROUND); the
## pelvis goes down by the larger drop, each leg reaches its own ground, and
## the foot lies along the ground's slope. The knee bends inside its hinge of
## the joint table (LimbPose). It runs before the seat, the arms and the
## stumble: VillageNPC sets its `influence`, none while the seat holds the
## legs, less with distance.

## How far the pelvis goes down at most, metres.
const MAX_DROP := 0.25
## How far the ray starts over the foot and reaches under the body's origin.
const RISE := 0.45
const REACH := 0.5
## How far a foot tilts along the ground at most.
const MAX_TILT := deg_to_rad(30.0)
## A foot this high over the body's origin, metres, is off the ground: it
## does not tilt. Between SOLE and LIFTED it tilts in part.
const SOLE := 0.12
const LIFTED := 0.25
## Less than this, metres, is not worth a solve.
const STILL := 0.004
## The camera nearer than NEAR metres gives full footing, farther than FAR none.
const NEAR := 12.0
const FAR := 20.0

var _ray: PhysicsRayQueryParameters3D

## How far the pelvis goes down when the ground under the left and the right
## foot lies `left` and `right` metres over the body's origin: the lower foot
## must reach its ground; a pelvis never rises.
static func pelvis_drop(left: float, right: float) -> float:
	return clampf(-minf(minf(left, right), 0.0), 0.0, MAX_DROP)

## The turn that lays a flat foot on ground of `normal`, no more than `limit`.
static func foot_turn(normal: Vector3, limit := MAX_TILT) -> Quaternion:
	var turn := JointLimits.arc(Vector3.UP, normal.normalized())
	var angle := turn.get_angle()
	if angle <= limit:
		return turn
	return Quaternion.IDENTITY.slerp(turn, limit / angle)

## How far footing applies at `distance` metres from the camera, 0..1.
static func reach(distance: float) -> float:
	return 1.0 - smoothstep(NEAR, FAR, distance)

func _process_modification() -> void:
	if influence <= 0.0 or not is_instance_valid(actor):
		return
	var skeleton := get_skeleton()
	_find(skeleton, ["Hips", "UpLeg_L", "Leg_L", "Foot_L", "UpLeg_R", "Leg_R", "Foot_R"])
	if _bones.Hips < 0:
		return
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = PhysicsLayers.GROUND
		_ray.exclude = [actor.get_rid()]
	var space := actor.get_world_3d().direct_space_state
	var floor_y := actor.global_position.y
	var heights := {}
	var normals := {}
	var feet := {}
	var frames := {}
	for side: String in ["L", "R"]:
		var foot: int = _bones["Foot_" + side]
		if foot < 0:
			return
		feet[side] = _world_origin(skeleton, foot)
		frames[side] = skeleton.global_transform * skeleton.get_bone_global_pose(foot)
		var at: Vector3 = feet[side]
		_ray.from = Vector3(at.x, maxf(at.y, floor_y) + RISE, at.z)
		_ray.to = Vector3(at.x, floor_y - REACH, at.z)
		var hit := space.intersect_ray(_ray)
		heights[side] = 0.0
		normals[side] = Vector3.UP
		if not hit.is_empty():
			var ground: Vector3 = hit.position
			heights[side] = ground.y - floor_y
			normals[side] = hit.normal
	var drop := pelvis_drop(heights.L, heights.R)
	if drop > STILL:
		_set_origin(skeleton, _bones.Hips, _world_origin(skeleton, _bones.Hips) + Vector3.DOWN * drop)
	var forward := -actor.global_basis.z.normalized()
	for side: String in ["L", "R"]:
		var upper: int = _bones["UpLeg_" + side]
		var middle: int = _bones["Leg_" + side]
		var foot: int = _bones["Foot_" + side]
		var height: float = heights[side]
		var at: Vector3 = feet[side]
		var solved := absf(height) > STILL or drop > STILL
		if solved:
			var hip := _world_origin(skeleton, upper)
			var knee := _world_origin(skeleton, middle)
			var target := at + Vector3.UP * height
			var pole := knee - (hip + target) * 0.5
			if pole.length_squared() < 0.0001:
				pole = forward
			_solve_chain(skeleton, upper, middle, foot, target, pole.normalized())
		# The clip's foot, turned to the slope as far as it stands on it.
		var planted := 1.0 - smoothstep(SOLE, LIFTED, at.y - floor_y - maxf(height, 0.0))
		var turn := Quaternion.IDENTITY.slerp(foot_turn(normals[side]), planted)
		if not solved and turn.get_angle() < 0.002:
			continue
		var frame: Transform3D = frames[side]
		var placed := Transform3D(Basis(turn) * frame.basis, _world_origin(skeleton, foot))
		_set_global(skeleton, foot, skeleton.global_transform.affine_inverse() * placed)
