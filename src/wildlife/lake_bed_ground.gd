extends RefCounted
## The ground of the lake bed for LakeBed: depth, slope and normal of the
## terrain as drawn, footprints of the laid pieces, and the resting pose of a
## scanned piece. Static functions over the LakeBed node `lake`, whose random
## numbers, caches and bodies they share.

## A point of the lake's search rectangle (only x and z count).
static func random_point(lake: LakeBed) -> Vector3:
	return Vector3(lake._rng.randf_range(LakeBed.LAKE.position.x, LakeBed.LAKE.end.x), 0, lake._rng.randf_range(LakeBed.LAKE.position.y, LakeBed.LAKE.end.y))

static func depth(lake: LakeBed, point: Vector3) -> float:
	return lake.habitat.terrain.water_level - lake.habitat.terrain.height_at(point.x, point.z)

static func slope(lake: LakeBed, point: Vector3) -> float:
	var y := lake.habitat.terrain.height_at(point.x, point.z)
	return Vector2(lake.habitat.terrain.height_at(point.x + 1.0, point.z) - y, lake.habitat.terrain.height_at(point.x, point.z + 1.0) - y).length()

static func normal(lake: LakeBed, point: Vector3) -> Vector3:
	var terrain := lake.habitat.terrain
	return Vector3(terrain.height_at(point.x - 0.25, point.z) - terrain.height_at(point.x + 0.25, point.z), 0.5,
		terrain.height_at(point.x, point.z - 0.25) - terrain.height_at(point.x, point.z + 0.25)).normalized()

## Lowest terrain under a disc of radius `reach` around `at`.
static func lowest_ground(lake: LakeBed, at: Vector3, reach: float) -> float:
	var low := lake.habitat.terrain.height_at(at.x, at.z)
	for k in 8:
		var angle := k * TAU / 8.0
		low = minf(low, lake.habitat.terrain.height_at(at.x + cos(angle) * reach, at.z + sin(angle) * reach))
	return low

static func free_of_others(point: Vector3, others: Array[Vector3], distance: float) -> bool:
	for other in others:
		if Vector2(point.x, point.z).distance_to(Vector2(other.x, other.z)) < distance:
			return false
	return true

## The rectangle a laid piece covers on the bed (its tilt left out).
static func footprint(lake: LakeBed, kind: String, transform: Transform3D) -> Dictionary:
	var u := Vector2(transform.basis.x.x, transform.basis.x.z)
	var v := Vector2(transform.basis.z.x, transform.basis.z.z)
	var half: Vector2 = shape_of(lake, kind).half
	return {"center": Vector2(transform.origin.x, transform.origin.z), "u": u.normalized(), "v": v.normalized(),
		"half": Vector2(half.x * u.length(), half.y * v.length())}

## Whether two footprints come closer than `margin` (separating axes).
static func overlap(a: Dictionary, b: Dictionary, margin: float) -> bool:
	var between: Vector2 = b.center - a.center
	for axis: Vector2 in [a.u, a.v, b.u, b.v]:
		var reach_a: float = a.half.x * absf(axis.dot(a.u)) + a.half.y * absf(axis.dot(a.v))
		var reach_b: float = b.half.x * absf(axis.dot(b.u)) + b.half.y * absf(axis.dot(b.v))
		if absf(between.dot(axis)) > reach_a + reach_b + margin:
			return false
	return true

static func under_wood(lake: LakeBed, point: Vector3, margin: float) -> bool:
	var flat := Vector2(point.x, point.z)
	for wood in lake._wood_footprints:
		var offset: Vector2 = flat - wood.center
		if absf(offset.dot(wood.u)) < wood.half.x + margin and absf(offset.dot(wood.v)) < wood.half.y + margin:
			return true
	return false

## Height of the bed under (x, z): the terrain as drawn, or a lake boulder
## lying on it when `boulders`; NAN where something else stands in the water
## there (a pier post, a shore stone, a cliff).
static func bed_at(lake: LakeBed, x: float, z: float, boulders: bool) -> float:
	var ground := lake.habitat.terrain.height_at(x, z)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, lake.habitat.terrain.water_level + 3.0, z), Vector3(x, ground + 0.15, z), 1 | LakeBed.BOULDER_LAYER)
	var hit := lake.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or String(hit.collider.name).begins_with("TerrainBody"):
		return ground
	if hit.collider == lake._solid:
		return maxf(ground, hit.position.y) if boulders else NAN
	return NAN

## The resting pose of a scanned piece laid at `at`, turned by `yaw` and
## scaled by `size`: tilted to the plane of the bed under its footprint,
## lowered until its underside touches the bed with no foot inside it, then
## pressed `sink` (m) into the silt. Null where it would not rest there: a
## slope steeper than `steepest` (degrees), its underside clear of the bed
## by more than `slack` (m) beyond its own shape, something in the way (a
## lake boulder too: wood propped on a stone reads as afloat from below), or
## the surface within CLEARANCE of its top.
static func settle(lake: LakeBed, kind: String, at: Vector3, yaw: float, size: float, sink: float, slack: float, steepest := LakeBed.STEEPEST) -> Variant:
	var shape := shape_of(lake, kind)
	var spin := Basis(Vector3.UP, yaw)
	# The plane of the bed from a 3 x 3 grid over the footprint (at least a
	# metre and a bit across, so a thin trunk still reads the slope across it).
	var half: Vector2 = (shape.half as Vector2) * size
	half = half.max(Vector2(0.6, 0.6))
	var b := 0.0
	var c := 0.0
	for i in 3:
		for j in 3:
			var p := at + spin * Vector3((i - 1) * half.x, 0.0, (j - 1) * half.y)
			var bed := bed_at(lake, p.x, p.z, false)
			if is_nan(bed):
				return null
			b += (i - 1) * half.x * bed
			c += (j - 1) * half.y * bed
	b /= 6.0 * half.x * half.x
	c /= 6.0 * half.y * half.y
	var up := spin * Vector3(-b, 1.0, -c).normalized()
	if up.y < cos(deg_to_rad(steepest)):
		return null
	var basis := Basis(Quaternion(Vector3.UP, up)) * spin * Basis.from_scale(Vector3.ONE * size)
	var feet: PackedVector3Array = shape.feet
	var beds := PackedFloat32Array()
	var rise := -INF
	for foot in feet:
		var w := basis * foot
		var bed := bed_at(lake, at.x + w.x, at.z + w.z, false)
		if is_nan(bed):
			return null
		beds.append(bed - w.y)
		rise = maxf(rise, bed - w.y)
	# How far the underside clears the bed, against how far it would on flat ground.
	var gaps := PackedFloat32Array()
	for k in feet.size():
		gaps.append(rise - beds[k])
	gaps.sort()
	if gaps[int(gaps.size() * 0.75)] > (shape.clear as float) * size + slack:
		return null
	var transform := Transform3D(basis, Vector3(at.x, rise - sink, at.z))
	var top := -INF
	for point in shape.points as PackedVector3Array:
		top = maxf(top, (transform * point).y)
	if top > lake.habitat.terrain.water_level - LakeBed.CLEARANCE:
		return null
	return transform

## The underside of a scanned model (its lowest point in each of about 12 x 12
## cells over its footprint), a sample of its vertices for its top, the half
## extents of its footprint and how far a quarter of its underside clears
## flat ground (all in its own space, scale 1).
static func shape_of(lake: LakeBed, kind: String) -> Dictionary:
	if lake._shapes.has(kind):
		return lake._shapes[kind]
	var scene: Node3D = (load(LakeBed.DIRECTORY + kind + ".glb") as PackedScene).instantiate()
	var all := PackedVector3Array()
	for source: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in source.mesh.get_surface_count():
			all.append_array(source.transform * (source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	scene.free()
	var box := AABB(all[0], Vector3.ZERO)
	for v in all:
		box = box.expand(v)
	var cell := maxf(box.size.x, box.size.z) / 12.0
	var lowest := {}
	for v in all:
		var key := Vector2i(floori((v.x - box.position.x) / cell), floori((v.z - box.position.z) / cell))
		if not lowest.has(key) or v.y < (lowest[key] as Vector3).y:
			lowest[key] = v
	var feet := PackedVector3Array(lowest.values())
	var heights := PackedFloat32Array()
	for foot in feet:
		heights.append(foot.y - box.position.y)
	heights.sort()
	var points := PackedVector3Array()
	for i in range(0, all.size(), maxi(1, all.size() / 700)):
		points.append(all[i])
	lake._shapes[kind] = {"feet": feet, "points": points, "clear": heights[int(heights.size() * 0.75)],
		"half": Vector2(maxf(-box.position.x, box.end.x), maxf(-box.position.z, box.end.z))}
	return lake._shapes[kind]
