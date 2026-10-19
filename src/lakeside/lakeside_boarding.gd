extends RefCounted
## The rowing boat: where it moors, and getting in and out of it.

## The boat moors where the water is from SHALLOWEST to DEEPEST metres deep,
## every MOORING_STEP metres of the lake's search (LakePlan.mooring_search),
## nearest its point.
const SHALLOWEST := 1.2
const DEEPEST := 3.0
const MOORING_STEP := 2

static func find_mooring(lake: LakesideSystem) -> Vector3:
	var best := INF
	var plan := lake.plan
	var result := Vector3(plan.mooring_fallback.x, lake.water.water_level, plan.mooring_fallback.y)
	for x in range(int(plan.mooring_search.position.x), int(plan.mooring_search.end.x), MOORING_STEP):
		for z in range(int(plan.mooring_search.position.y), int(plan.mooring_search.end.y), MOORING_STEP):
			var depth := lake.water.water_level - lake.terrain.height_at(x, z)
			if depth < SHALLOWEST or depth > DEEPEST or not lake.boat.can_navigate(Vector3(x, lake.water.water_level, z)):
				continue
			var distance := (Vector2(x, z) - plan.mooring_near).length()
			if distance < best:
				best = distance
				result = Vector3(x, lake.water.water_level, z)
	return result

## The boat is boarded from this far, m (from the eye to its middle).
const REACH := 3.5

## How far the eye is from the boat (m) when the player can board it now;
## -1 when they cannot: they are in a mode other than Player.WALK or lay a
## fire, or the boat is not before their eyes within REACH.
static func board_distance(lake: LakesideSystem) -> float:
	if lake.player.mode != Player.WALK or lake.camping.placing:
		return -1.0
	var point := lake.boat.global_position + Vector3.UP * 0.3
	var offset := point - lake.interactions.camera.global_position
	if offset.length() > REACH or offset.normalized().dot(-lake.interactions.camera.global_basis.z) < 0.65:
		return -1.0
	var ray := PhysicsRayQueryParameters3D.create(lake.interactions.camera.global_position, point)
	ray.exclude = [lake.player.get_rid()]
	var hit := lake.get_world_3d().direct_space_state.intersect_ray(ray)
	return offset.length() if hit.is_empty() or hit.collider == lake.boat else -1.0

## The player into the boat: the boat owns their mode (Player.BOAT), which
## stops the body and takes away its capsule.
static func board(lake: LakesideSystem) -> void:
	if not lake.player.enter(Player.BOAT, lake):
		return
	lake.cancel_fishing()
	lake.camping.fast_travel()
	lake.aboard = true
	lake.boarded_eye = lake.player.rig.position.y
	lake.player.rig.position.y = 1.05
	lake.player.swimming = false
	lake.player.global_position = lake.boat.to_global(Vector3(0, 0.20, 0.65))
	lake.play("step_wood", lake.boat.position)

static func leave_boat(lake: LakesideSystem) -> bool:
	for radius: float in [2.2, 2.8]:
		for i in range(12):
			var at := lake.boat.global_position + Vector3(cos(i * TAU / 12), 0, sin(i * TAU / 12)) * radius
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 1.0)
			ray.exclude = [lake.player.get_rid(), lake.boat.get_rid()]
			var hit := lake.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty():
				continue
			var stand: Vector3 = hit.position
			if hit.normal.y > 0.7 and stand.y > lake.water.water_level + 0.05 and lake.interactions.can_stand(stand):
				unboard(lake, stand + Vector3.UP * 0.03)
				return true
	# Swimming is already a safe, supported mode in this game. Test the capsule first.
	var at := lake.boat.to_global(Vector3(2.0, 0.1, 0.0))
	var query := PhysicsShapeQueryParameters3D.new()
	var collision := lake.player.collision
	query.shape = collision.shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
	query.exclude = [lake.player.get_rid()]
	if lake.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		unboard(lake, at)
		return true
	lake.notify("Борт закрыт препятствием. Отплыви немного дальше.")
	return false

static func unboard(lake: LakesideSystem, at: Vector3) -> void:
	lake.aboard = false
	lake.boat.rowing = false
	lake.boat.throttle = 0
	lake.player.rig.position.y = lake.boarded_eye
	lake.player.global_position = at
	lake.player.leave(lake)
