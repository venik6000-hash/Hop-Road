class_name NpcRounds
extends RefCounted
## A villager's round of their route (VillageNPC.rounds): from point to point
## and back, with a short stop at each. The one who keeps the hall finds her
## way between the furniture (TavernNavigation) and wipes the tops at her
## stops (`wipes`). A neighbour or the player in the way is waited for; one
## who waits too long turns back.

## The walking pace, m/s.
const SPEED := 0.85
## The farthest a hall walk leaves the navigation grid for its last steps to
## the place of work, metres.
const HALL_LAST_STEP := 0.6
## Seconds the one who keeps the hall wipes the bar when her round brings her
## to it: one pass of the recorded wiping.
const WIPE_SECONDS := 8.5

var actor: VillageNPC
var route: Array[Vector3] = []
var route_point := 0
var wait_time := 0.0
var blocked_time := 0.0
## The route point the hall path leads to; -1 to find the path anew.
var hall_target := -1
## The maid's stops where she wipes: route point -> {yaw: the way she faces
## there, across: how far her strip goes to either side (NpcWipe.across),
## rest: where her other hand rests (NpcWipe.rest)}.
var wipes: Dictionary[int, Dictionary] = {}
var _direction := 1
var _cleaning := false
var _hall_navigation: TavernNavigation
var _hall_path := PackedVector3Array()
var _hall_ready := false
var _route_probe: PhysicsShapeQueryParameters3D
## The way to face before the work at a stop begins, NAN for none.
var _face_to := NAN

func _init(walker: VillageNPC) -> void:
	actor = walker

## Builds the hall's navigation grid for the one who keeps the hall, once the
## physics of the level is in place. Her round waits for it.
func find_hall_paths() -> void:
	await actor.get_tree().physics_frame
	_hall_navigation = TavernNavigation.new()
	_hall_navigation.build(actor)
	_route_probe = PhysicsShapeQueryParameters3D.new()
	var probe := CapsuleShape3D.new()
	probe.radius = 0.25
	probe.height = 1.6
	_route_probe.shape = probe
	_route_probe.collision_mask = actor.collision_mask
	_route_probe.exclude = [actor.get_rid()]
	_hall_ready = true

## The round goes on from route point `point`: no wait, no hold-up, the hall
## path found anew.
func begin_at(point: int) -> void:
	route_point = point
	hall_target = -1
	wait_time = 0.0
	blocked_time = 0.0
	_cleaning = false

## The villager stands where they are for at least `seconds` and wipes
## nothing.
func pause(seconds: float) -> void:
	wait_time = maxf(wait_time, seconds)
	_cleaning = false

## Walks the round on by `delta` seconds: the stop, or the steps to the next
## point.
func walk(delta: float) -> void:
	if actor.job == "maid" and not _hall_ready:
		return
	wait_time = maxf(0.0, wait_time - delta)
	if wait_time > 0.0:
		# She turns to the top first, then wipes it.
		if _cleaning and not is_nan(_face_to) and absf(angle_difference(actor.rotation.y, _face_to)) > 0.04:
			actor.rotation.y = rotate_toward(actor.rotation.y, _face_to, delta * 2.5)
			actor.play("idle")
			return
		actor.play("wipe" if _cleaning else "idle")
		return
	var destination := route[route_point]
	if _hall_navigation != null:
		if hall_target != route_point:
			_hall_path = _hall_navigation.path(actor.global_position, destination)
			hall_target = route_point
		if _hall_path.is_empty():
			# No reachable path: wait and retry, never walk straight through furniture.
			hall_target = -1
			wait_time = 1.0
			actor.play("idle")
			return
		while _hall_path.size() > 1 and Vector2(actor.global_position.x - _hall_path[0].x,
				actor.global_position.z - _hall_path[0].z).length() < 0.1:
			_hall_path.remove_at(0)
		destination = _hall_path[0]
		# The grid keeps a wide berth of furniture; the last few steps go
		# straight to the place of work, which may stand nearer a top.
		if _hall_path.size() == 1 and Vector2(route[route_point].x - destination.x, route[route_point].z - destination.z).length() < HALL_LAST_STEP:
			destination = route[route_point]
	var offset := destination - actor.global_position
	offset.y = 0.0
	if offset.length() < (0.12 if _hall_navigation != null else 0.22) and (_hall_navigation == null or _hall_path.size() == 1):
		_cleaning = actor.job == "maid" and wipes.has(route_point)
		_face_to = Values.real(wipes[route_point].yaw) if _cleaning else NAN
		if _cleaning:
			actor.wipe.set_strip(wipes[route_point])
		wait_time = WIPE_SECONDS if _cleaning else 1.2 + float(route_point % 3) * 0.8
		_next_point()
		actor.play("idle")
		return
	var direction := offset.normalized()
	actor.rotation.y = lerp_angle(actor.rotation.y, atan2(-direction.x, -direction.z), minf(delta * 5.0, 1.0))
	# A moving neighbour or the player has priority. Avoid pushing them.
	if _obstructed(direction, offset.length()):
		blocked_time += delta
		actor.play("idle")
		if blocked_time > 3.0:
			_direction *= -1
			_next_point()
			hall_target = -1
			blocked_time = 0.0
		return
	blocked_time = 0.0
	var speed := SPEED if _hall_navigation == null else minf(SPEED, offset.length() / maxf(delta, 0.001))
	actor.velocity.x = direction.x * speed
	actor.velocity.z = direction.z * speed
	if actor.recorded:
		actor.stride(speed)
	else:
		actor.play("source_walk" if actor.animation.has_animation("source_walk") else "walk")

func _obstructed(direction: Vector3, distance: float) -> bool:
	var space := actor.get_world_3d().direct_space_state
	if _route_probe != null:
		_route_probe.transform.origin = actor.global_position + Vector3.UP * 0.85
		_route_probe.motion = direction * minf(0.42, distance)
		return space.cast_motion(_route_probe)[0] < 1.0
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 0.8,
		actor.global_position + Vector3.UP * 0.8 + direction * 0.65, actor.collision_mask)
	ray.exclude = [actor.get_rid()]
	return not space.intersect_ray(ray).is_empty()

func _next_point() -> void:
	var next := route_point + _direction
	if next < 0 or next >= route.size():
		_direction *= -1
		next = route_point + _direction
	route_point = clampi(next, 0, route.size() - 1)
