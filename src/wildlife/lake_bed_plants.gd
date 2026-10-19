extends RefCounted
## The freshwater plants of LakeBed (static functions over the LakeBed node
## `lake`, drawing from its random numbers).
const Ground = preload("res://src/wildlife/lake_bed_ground.gd")
const Batches = preload("res://src/wildlife/lake_bed_batches.gd")

## Patches of one plant kind in its depth band, each tuft rooted in the silt
## (not on a boulder, a pier post or a shore stone).
static func place(lake: LakeBed, kind: String) -> void:
	var config: Dictionary = LakeBed.PLANTS[kind]
	var centers: Array[Vector3] = []
	# The shore band is a strip a metre or two wide, so reed stands are drawn
	# from a survey of the whole shore instead of random throws.
	var candidates: Array[Vector3] = []
	if kind == "reed":
		candidates = _shore_survey(lake)
	for attempt: int in config.patches * 12:
		if centers.size() >= config.patches or (kind == "reed" and candidates.is_empty()):
			break
		var center: Vector3 = candidates.pop_at(lake.rng.randi_range(0, candidates.size() - 1)) if kind == "reed" else Ground.random_point(lake)
		var depth := Ground.depth(lake, center)
		if depth < config.depth.x or depth > config.depth.y or Ground.slope(lake, center) > config.slope:
			continue
		if not Ground.free_of_others(center, centers, Values.real(config.radius.x * (1.2 if kind == "reed" else 2.0))):
			continue
		centers.append(center)
		_grow(lake, kind, center, lake.rng.randf_range(Values.real(config.radius.x), Values.real(config.radius.y)))
	if kind == "reed":
		# After every other stand, and the lake's random numbers go on from
		# where those left them: what the lake places stays where it was.
		var state := lake.rng.state
		for stand: Vector3 in lake.plan.marsh_stands:
			var center := Vector3(stand.x, 0.0, stand.y)
			centers.append(center)
			_grow(lake, kind, center, stand.z)
		lake.rng.state = state
	if kind == "eelgrass":
		lake.meadow_centers = centers
	elif kind == "reed":
		lake.reed_centers = centers

## One patch of `kind` round `center`, `radius` metres: its tufts where the
## depth and the slope let them root.
static func _grow(lake: LakeBed, kind: String, center: Vector3, radius: float) -> void:
	var config: Dictionary = LakeBed.PLANTS[kind]
	var spacing: float = config.spacing
	var cells := int(radius * 2.0 / spacing)
	for i in cells:
		for j in cells:
			var offset := Vector3((i + lake.rng.randf()) * spacing - radius, 0, (j + lake.rng.randf()) * spacing - radius)
			var falloff := offset.length() / radius
			if falloff > 1.0 or lake.rng.randf() < falloff * falloff * 0.9:
				continue
			var point := center + offset
			var depth_here := Ground.depth(lake, point)
			if depth_here < config.depth.x or depth_here > config.depth.y or Ground.slope(lake, point) > config.slope:
				continue
			if is_nan(Ground.bed_at(lake, point.x, point.z, false)) or Ground.under_wood(lake, point, 0.15):
				continue
			var ground := lake.habitat.terrain.height_at(point.x, point.z)
			var normal := Ground.normal(lake, point)
			if normal.y < 0.55:
				continue
			var position := Vector3(point.x, ground, point.z)
			var size: float = lake.rng.randf_range(Values.real(config.size.x), Values.real(config.size.y))
			if kind != "reed":
				# Submerged plants stop short of the surface.
				size = minf(size, Values.real((lake.habitat.terrain.water_level - position.y - 0.4) / config.height))
				if size < config.size.x * 0.6:
					continue
			var basis := Basis(Quaternion(Vector3.UP, normal.lerp(Vector3.UP, 0.5).normalized())) * Basis(Vector3.UP, lake.rng.randf_range(0, TAU))
			Batches.add(lake, kind, lake.rng.randi_range(0, Values.whole(config.variants - 1)), Transform3D(basis.scaled(Vector3.ONE * size), position - normal * 0.03))
			lake.plant_count += 1

## Every 3 m cell of the lake's shore where reeds could stand.
static func _shore_survey(lake: LakeBed) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var config: Dictionary = LakeBed.PLANTS.reed
	var search := lake.plan.search
	var x := search.position.x
	while x < search.end.x:
		var z := search.position.y
		while z < search.end.y:
			var point := Vector3(x + lake.rng.randf_range(-1.0, 1.0), 0, z + lake.rng.randf_range(-1.0, 1.0))
			var depth := Ground.depth(lake, point)
			if depth >= config.depth.x and depth <= config.depth.y and Ground.slope(lake, point) <= config.slope and reed_shore(lake, point):
				found.append(point)
			z += 3.0
		x += 3.0
	return found

static func reed_shore(lake: LakeBed, point: Vector3) -> bool:
	if lake.plan.keeps_reeds_off(Vector2(point.x, point.z)):
		return false
	# Not at the foot of a cliff: reeds take root where the shore keeps
	# shelving gently inland, not where the valley wall drops into the lake.
	for angle in 8:
		var sample := point + Vector3(cos(angle * TAU / 8.0), 0, sin(angle * TAU / 8.0)) * 6.0
		if lake.habitat.terrain.height_at(sample.x, sample.z) > lake.habitat.terrain.water_level + 2.5:
			return false
	# Nothing built within a stand's reach: houses, piers and walls have
	# their own bodies; only the terrain and the lake's boulders may answer.
	for index in 5:
		var offset := Vector3.ZERO if index == 0 else Vector3(cos(index * TAU / 4.0), 0, sin(index * TAU / 4.0)) * LakeBed.PLANTS.reed.radius.y
		var sample := point + offset
		var ray := PhysicsRayQueryParameters3D.create(Vector3(sample.x, lake.habitat.terrain.water_level + 30.0, sample.z),
			Vector3(sample.x, lake.habitat.terrain.water_level - 3.0, sample.z), PhysicsLayers.GROUND)
		var hit := lake.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and not PhysicsLayers.hit_terrain(hit) and hit.collider != lake.solid:
			return false
	return true
