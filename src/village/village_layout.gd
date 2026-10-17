extends RefCounted
## Placement only: the tavern precinct and original resource materials stay intact.
const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")

## The x of the village's main road at `y` (m south of the tavern's yard, that
## is -z): the line the Blender road was drawn on, with the shoulder it keeps
## for the tavern's approach. The ground bake keeps the cottages' yards off it
## (ground_height). tools/pipeline/buildings/ground.py has the same line in
## Python; the road the villagers walk is the region's (PeopleSchemas.villagers).
static func road_x(y: float) -> float:
	return -3.5 + 3.5 * sin((y + 11.0) * 0.079) - 0.09 * maxf(0.0, y) + 0.63 * maxf(0.0, -y - 3.0) \
		- minf(10.0, maxf(0.0, (y - 20.0) * 0.5))

## The village plan at `path` (RegionDef.village_plan): houses, cottages,
## paths and the main road.
static func read_plan(path: String) -> Dictionary:
	return DataFile.read(path, WorldSchemas.village_plan())

static func cottage_pose(village_plan: Dictionary, key: String) -> Transform3D:
	var spec: Dictionary = village_plan.cottages[key]
	var source := Values.vec3(spec.source)
	var target := Values.vec3(spec.position)
	var basis := Basis(Vector3.UP, deg_to_rad(Values.real(spec.yaw)))
	return Transform3D(basis, target - basis * source)

## How a cottage moved since tools/pipeline/village_layout/build.py wrote its
## placed scene: the layout scene keeps that pose in `built` when it moves one.
static func cottage_shift(village_plan: Dictionary, key: String) -> Transform3D:
	var spec: Dictionary = village_plan.cottages[key]
	if not spec.has("built"):
		return Transform3D.IDENTITY
	var built: Dictionary = spec.built
	var was := Transform3D(Basis(Vector3.UP, deg_to_rad(Values.real(built.yaw))), Values.vec3(built.position))
	var now := Transform3D(Basis(Vector3.UP, deg_to_rad(Values.real(spec.yaw))), Values.vec3(spec.position))
	return now * was.affine_inverse()

## The ground a house was built on at its place in the Blender map. The plan
## keeps it (`ground`): the terrain there has since been shaped anew.
static func source_ground(spec: Dictionary, terrain: TerrainSystem) -> float:
	if spec.has("ground"):
		return Values.real(spec.ground)
	return terrain.height_at(Values.real(spec.source[0]), Values.real(spec.source[1]))

## `lift` raises a house above the ground under its pivot (layout scene).
static func house_pose(spec: Dictionary, terrain: TerrainSystem) -> Transform3D:
	var source := Vector3(Values.real(spec.source[0]), source_ground(spec, terrain), Values.real(spec.source[1]))
	var target := Vector3(Values.real(spec.position[0]), terrain.height_at(Values.real(spec.position[0]), Values.real(spec.position[1])) + Values.real(spec.get("lift", 0.0)), Values.real(spec.position[1]))
	var basis := Basis(Vector3.UP, deg_to_rad(Values.real(spec.yaw)))
	return Transform3D(basis, target - basis * source)

static func place_houses(map: Node3D, terrain: TerrainSystem, village_plan: Dictionary) -> void:
	for spec: Dictionary in village_plan.houses:
		var pose := house_pose(spec, terrain)
		var prefix := "Village house %02d " % Values.whole(spec.id)
		for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
			if RockField.label_of(item).begins_with(prefix):
				item.global_transform = pose * item.global_transform

static func smoke_position(point: Vector3, terrain: TerrainSystem, village_plan: Dictionary) -> Vector3:
	for spec: Dictionary in village_plan.houses:
		if Vector2(Values.real(point.x - spec.source[0]), Values.real(point.z - spec.source[1])).length() < 3.0:
			return house_pose(spec, terrain) * point
	return point

## Shallow earthen yards of the two cottages. The original textures, lake,
## main street and tavern elevations are retained.
static func ground_height(x: float, z: float, original: float, cottages: Dictionary) -> float:
	var height := original
	if z > -18.0:
		return height
	for spec: Dictionary in cottages.values():
		var offset := Vector3(Values.real(x - spec.position[0]), 0, Values.real(z - spec.position[2]))
		var local := Basis(Vector3.UP, deg_to_rad(Values.real(-spec.yaw))) * offset
		var edge := maxf(absf(local.x) - 3.9, absf(local.z - 0.5) - 4.7)
		var weight := 1.0 - smoothstep(0.0, 1.5, edge)
		# Preserve the already laid main road and the tavern approach.
		weight *= smoothstep(2.8, 3.8, absf(x - road_x(-z)))
		height = lerpf(height, Values.real(spec.position[1]) - 0.025, weight)
	return height

static func settle_ground(image: Image, origin: Vector2, cell: float, village_plan: Dictionary) -> void:
	var cottages: Dictionary = village_plan.cottages
	for iz in range(int((-56.0 - origin.y) / cell), int((-18.0 - origin.y) / cell) + 1):
		for ix in range(int((-18.0 - origin.x) / cell), int((12.0 - origin.x) / cell) + 1):
			var x := origin.x + ix * cell
			var z := origin.y + iz * cell
			var height := ground_height(x, z, image.get_pixel(ix, iz).r, cottages)
			image.set_pixel(ix, iz, Color(height, 0, 0))

## Trodden earth around each house: the grass thins toward the walls. Paints
## the path mask `image` (texel (0, 0) at `origin`, `cell` metres apart) round
## the houses of `map` as the level stands them (MapEdits drops those a
## building replaces, place_houses moves the rest by `plan`). The ground
## bake does it on a map of its own, outside the tree: a mesh's place in the
## map is the chain of its transforms (in_map()).
static func paint_aprons(image: Image, origin: Vector2, cell: float, map: Node3D, terrain: TerrainSystem,
		plan: Dictionary) -> void:
	var replaced := VILLAGE_BUILDINGS.replaced(terrain.region)
	var poses := {}
	for spec: Dictionary in plan.houses:
		poses["Village house %02d " % Values.whole(spec.id)] = house_pose(spec, terrain)
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var label := RockField.label_of(item)
		if not label.ends_with("limewashed rooms") or VILLAGE_BUILDINGS.begins(label, replaced):
			continue
		var holder := item.get_parent() as Node3D
		if holder is MeshInstance3D and RockField.label_of(holder).begins_with("Village house "):
			push_error("VillageLayout: house mesh %s stands in another one; its apron would be off" % label)
		var parent := in_map(map, holder)
		var xform := parent * item.transform
		for prefix: String in poses:
			if label.begins_with(prefix):
				# As place_houses sets it, and the node gives it back.
				var pose: Transform3D = poses[prefix]
				xform = parent * (parent.affine_inverse() * (pose * xform))
		var inverse := xform.affine_inverse()
		var box := item.get_aabb()
		var centre := xform * box.get_center()
		var reach := box.size.length() * 0.5 + 2.5
		for iz in range(int((centre.z - reach - origin.y) / cell), int((centre.z + reach - origin.y) / cell) + 2):
			for ix in range(int((centre.x - reach - origin.x) / cell), int((centre.x + reach - origin.x) / cell) + 2):
				var point := origin + Vector2(ix, iz) * cell
				var local := inverse * Vector3(point.x, centre.y, point.y)
				var outside := maxf(maxf(box.position.x - local.x, local.x - box.end.x), maxf(box.position.z - local.z, local.z - box.end.z))
				outside += sin(point.x * 1.9) * cos(point.y * 1.6) * 0.35
				var wear := 0.34 * (1.0 - smoothstep(0.1, 1.9, outside))
				if wear <= 0.0:
					continue
				var color := image.get_pixel(ix, iz)
				color.r = maxf(color.r, wear)
				color.a *= 1.0 - wear
				image.set_pixel(ix, iz, color)

## Where `node` stands in the map, as the node itself would tell in the
## tree: the transforms from the map's root down to it, multiplied in the
## engine's order (the level stands the map at the origin).
static func in_map(map: Node3D, node: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var at := node
	while at != map and at != null:
		chain.push_front(at)
		at = at.get_parent() as Node3D
	var xform := map.transform
	for link: Node3D in chain:
		xform = xform * link.transform
	return xform
