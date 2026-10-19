extends RefCounted
## Placement only: the tavern precinct and original resource materials stay intact.
const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")

## The village plan at `path` (RegionDef.village_plan): houses, cottages,
## paths, the main road (VillageRoad) and the green. A region without a
## village names none: an empty plan.
static func read_plan(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	return Values.table(DataFile.read(path, WorldSchemas.village_plan()))

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
	for spec: Dictionary in Values.list(village_plan.get("houses", [])):
		var pose := house_pose(spec, terrain)
		var prefix := "Village house %02d " % Values.whole(spec.id)
		for item: MeshInstance3D in MapIndex.of(map).starting(prefix):
			item.global_transform = pose * item.global_transform

static func smoke_position(point: Vector3, terrain: TerrainSystem, village_plan: Dictionary) -> Vector3:
	for spec: Dictionary in Values.list(village_plan.get("houses", [])):
		if Vector2(Values.real(point.x - spec.source[0]), Values.real(point.z - spec.source[1])).length() < 3.0:
			return house_pose(spec, terrain) * point
	return point

## The levelled yards of the cottages of `cottages` (RegionDef.cottages:
## each one's `yard`, the rules of all of them in `yards`) at their places in
## `village_plan`: {x, z, level, yaw, half, middle, rim, sink, road, north}
## (BuildingSchemas.cottages); `half` and `road` are pairs of numbers.
## tools/lib/village_ground.py reads the same.
static func yards(village_plan: Dictionary, cottages: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if cottages.is_empty():
		return found
	var data := Values.table(DataFile.read(cottages, BuildingSchemas.cottages()))
	for entry: Dictionary in Values.list(data.get("cottages", [])):
		if not entry.has("yard"):
			continue
		var rules: Dictionary = data.yards
		var place: Dictionary = village_plan.cottages[entry.key]
		var yard: Dictionary = entry.yard
		var position: Array = place.position
		found.append({"x": Values.real(position[0]), "level": Values.real(position[1]), "z": Values.real(position[2]),
			"yaw": Values.real(place.yaw), "half": Values.list(yard.half), "middle": Values.real(yard.middle),
			"rim": Values.real(rules.rim), "sink": Values.real(rules.sink), "road": Values.list(rules.road),
			"north": Values.real(rules.north)})
	return found

## 0..1: how much of the level of `yard` (yards()) the ground takes at (x, z):
## its box with a soft rim, kept off the main road of `village_plan`. The
## original textures, lake, main street and tavern elevations are retained.
static func yard_weight(yard: Dictionary, x: float, z: float, village_plan: Dictionary) -> float:
	if z > Values.real(yard.north):
		return 0.0
	var offset := Vector3(x - Values.real(yard.x), 0, z - Values.real(yard.z))
	var local := Basis(Vector3.UP, deg_to_rad(-Values.real(yard.yaw))) * offset
	# The numbers stay in double precision: a Vector2 would round them.
	var half: Array = yard.half
	var road: Array = yard.road
	var edge := maxf(absf(local.x) - Values.real(half[0]), absf(local.z - Values.real(yard.middle)) - Values.real(half[1]))
	var weight := 1.0 - smoothstep(0.0, Values.real(yard.rim), edge)
	# Preserve the already laid main road and the tavern approach.
	weight *= smoothstep(Values.real(road[0]), Values.real(road[1]), absf(x - VillageRoad.centre(village_plan, z)))
	return weight

## Where `yard` can reach (x, z): its box with the rim, cut at its north edge.
static func yard_window(yard: Dictionary) -> Rect2:
	var half: Array = yard.half
	var rim := Values.real(yard.rim)
	var basis := Basis(Vector3.UP, deg_to_rad(Values.real(yard.yaw)))
	var window := Rect2()
	for corner in 4:
		var local := Vector3((Values.real(half[0]) + rim) * (1.0 if corner & 1 else -1.0), 0.0,
			Values.real(yard.middle) + (Values.real(half[1]) + rim) * (1.0 if corner & 2 else -1.0))
		var at := basis * local
		var point := Vector2(Values.real(yard.x) + at.x, Values.real(yard.z) + at.z)
		window = Rect2(point, Vector2.ZERO) if corner == 0 else window.expand(point)
	window.size.y = minf(window.end.y, Values.real(yard.north)) - window.position.y
	return window

## Lays the shallow earthen yards of the region's cottages into `image`
## (FORMAT_RF, texel (0, 0) at `origin`, `cell` metres apart).
static func settle_ground(image: Image, origin: Vector2, cell: float, village_plan: Dictionary,
		cottages: String) -> void:
	for yard: Dictionary in yards(village_plan, cottages):
		var window := yard_window(yard)
		var level := Values.real(yard.level) - Values.real(yard.sink)
		for iz in range(maxi(0, floori((window.position.y - origin.y) / cell)),
				mini(image.get_height(), ceili((window.end.y - origin.y) / cell) + 1)):
			for ix in range(maxi(0, floori((window.position.x - origin.x) / cell)),
					mini(image.get_width(), ceili((window.end.x - origin.x) / cell) + 1)):
				var weight := yard_weight(yard, origin.x + ix * cell, origin.y + iz * cell, village_plan)
				if weight > 0.0:
					image.set_pixel(ix, iz, Color(lerpf(image.get_pixel(ix, iz).r, level, weight), 0, 0))

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
	for item: MeshInstance3D in MapIndex.of(map).ending("limewashed rooms"):
		var label := RockField.label_of(item)
		if VILLAGE_BUILDINGS.begins(label, replaced):
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
