extends RefCounted
## Where a campfire may stand: ground rays and the site check, with the seats
## around the fire.
const SITE_RADIUS := 2.15
const MAX_SLOPE := 0.95
const SEAT_RADIUS := 1.65

static func _prepare_ground(camp: CampSystem) -> void:
	var excluded: Array[RID] = [camp.player.get_rid()]
	for actor in camp.population.actors:
		excluded.append(actor.get_rid())
	camp.site_ground_query.exclude = excluded
	camp.site_ground_query.collision_mask = PhysicsLayers.GROUND

static func ground_at(camp: CampSystem, point: Vector3, above := 2.0, below := 5.0, prepare := true) -> Dictionary:
	if prepare:
		_prepare_ground(camp)
	var query := camp.site_ground_query
	query.from = point + Vector3.UP * above
	query.to = point - Vector3.UP * below
	return camp.get_world_3d().direct_space_state.intersect_ray(query)

static func check_site(camp: CampSystem, point: Vector3, restoring := false) -> Dictionary:
	var hit := ground_at(camp, point)
	if hit.is_empty():
		return {"reason": "Наведи взгляд на землю неподалёку"}
	var floor_point: Vector3 = hit.position
	if not PhysicsLayers.hit_terrain(hit):
		return {"reason": "Костёр можно поставить на земле, вне построек"}
	if floor_point.y <= camp.water_level + 0.30:
		return {"reason": "Здесь вода или слишком мокрый берег"}
	if hit.normal.y < MAX_SLOPE:
		return {"reason": "Найди более ровное место"}
	for fire in camp.fires:
		if fire.global_position.distance_to(floor_point) < SITE_RADIUS * 2.0:
			return {"reason": "Рядом уже есть костёр"}
	var seats: Array[Dictionary] = []
	for index in range(8):
		var angle := TAU * index / 8.0
		var offset := Vector3(cos(angle), 0, sin(angle))
		var sample := ground_at(camp, floor_point + offset * SITE_RADIUS, 1.0, 2.0, false)
		if sample.is_empty() or sample.collider != hit.collider or sample.normal.y < MAX_SLOPE or absf(Values.real(sample.position.y - floor_point.y)) > 0.35:
			return {"reason": "Здесь мало ровной земли для огня и привала"}
		if index % 2 == 0:
			var seat_floor := ground_at(camp, floor_point + offset * SEAT_RADIUS, 1.0, 2.0, false)
			if seat_floor.is_empty():
				return {"reason": "Нет места, чтобы сесть"}
			var at: Vector3 = seat_floor.position
			var exit_point: Vector3 = sample.position
			seats.append({"name": "полено у костра", "position": [at.x, at.y, at.z],
				"height": 0.28, "facing": [-offset.x, 0, -offset.z],
				"exits": [[exit_point.x, exit_point.y, exit_point.z]], "camp": true})
	var clearance := camp.site_clearance_query
	if clearance.shape == null:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = SITE_RADIUS
		cylinder.height = 1.8
		clearance.shape = cylinder
	clearance.transform.origin = floor_point + Vector3.UP * 1.22
	clearance.collision_mask = PhysicsLayers.GROUND | PhysicsLayers.PLAYER | PhysicsLayers.VILLAGERS
	# Restoration may ignore actors; normal placement must reset those excludes.
	clearance.exclude = camp.site_ground_query.exclude if restoring else []
	if not camp.get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty():
		return {"reason": "Оставь вокруг костра место для людей"}
	# An overhang can be above the clearance cylinder; don't camp indoors.
	var roof := camp.site_roof_query
	roof.from = floor_point + Vector3.UP * 0.4
	roof.to = floor_point + Vector3.UP * 12.0
	roof.collision_mask = PhysicsLayers.GROUND
	if not camp.get_world_3d().direct_space_state.intersect_ray(roof).is_empty():
		return {"reason": "Выбери место под открытым небом"}
	return {"position": floor_point, "seats": seats, "reason": ""}
