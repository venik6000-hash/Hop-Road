extends RefCounted
## The sunken wood and the litter of LakeBed (static functions over the
## LakeBed node `lake`, drawing from its random numbers).
const Ground = preload("res://src/wildlife/lake_bed_ground.gd")
const Batches = preload("res://src/wildlife/lake_bed_batches.gd")

## Drowned trunks and snags lie on the slope they slid down.
static func place(lake: LakeBed) -> void:
	for config: Dictionary in LakeBed.WOOD:
		var placed := 0
		for attempt: int in config.count * 60:
			if placed >= config.count:
				break
			var point := Ground.random_point(lake)
			var depth := Ground.depth(lake, point)
			if depth < config.depth.x or depth > config.depth.y or not Ground.free_of_others(point, lake.wood_places, 7.0):
				continue
			if not Ground.free_of_others(point, lake.boulder_places, 4.0):
				continue
			var size: float = lake.rng.randf_range(Values.real(config.size.x), Values.real(config.size.y))
			var resting: Variant = Ground.settle(lake, str(config.kind), point, lake.rng.randf_range(0, TAU), size, Values.real(config.sink * size), 0.3, Values.real(config.steepest))
			if resting == null:
				continue
			var rest: Transform3D = resting
			# Two trunks do not lie through each other.
			var footprint := Ground.footprint(lake, str(config.kind), rest)
			var crossing := false
			for other in lake.wood_footprints:
				crossing = crossing or Ground.overlap(footprint, other, 0.25)
			if crossing:
				continue
			lake.wood_footprints.append(footprint)
			_lay(lake, str(config.kind), rest)
			lake.wood_places.append(Vector3(point.x, lake.habitat.terrain.height_at(point.x, point.z), point.z))
			placed += 1
			lake.wood_count += 1

static func litter(lake: LakeBed) -> void:
	for config: Dictionary in LakeBed.LITTER:
		for anchor in lake.wood_places:
			for index: int in config.per_wood:
				_scatter(lake, config, anchor)
		for anchor in lake.boulder_places:
			if lake.rng.randf() < config.per_boulder:
				_scatter(lake, config, anchor)
		var placed := 0
		for attempt: int in config.loose * 30:
			if placed >= config.loose:
				break
			if _drop(lake, config, Ground.random_point(lake)):
				placed += 1

## A piece of litter a little way from `anchor`, tried a few times around it.
static func _scatter(lake: LakeBed, config: Dictionary, anchor: Vector3) -> void:
	for attempt in 6:
		var angle := lake.rng.randf_range(0, TAU)
		if _drop(lake, config, anchor + Vector3(cos(angle), 0, sin(angle)) * lake.rng.randf_range(1.2, Values.real(config.radius))):
			return

static func _drop(lake: LakeBed, config: Dictionary, point: Vector3) -> bool:
	var depth := Ground.depth(lake, point)
	if depth < config.depth.x or depth > config.depth.y:
		return false
	var size: float = lake.rng.randf_range(Values.real(config.size.x), Values.real(config.size.y))
	var resting: Variant = Ground.settle(lake, str(config.kind), point, lake.rng.randf_range(0, TAU), size, Values.real(config.sink * size), 0.12)
	if resting == null:
		return false
	var rest: Transform3D = resting
	var footprint := Ground.footprint(lake, str(config.kind), rest)
	for other in lake.wood_footprints:
		if Ground.overlap(footprint, other, 0.1):
			return false
	_lay(lake, str(config.kind), rest)
	return true

static func _lay(lake: LakeBed, kind: String, transform: Transform3D) -> void:
	Batches.add(lake, kind, 0, transform)
	lake.pieces.append({"kind": kind, "transform": transform})
