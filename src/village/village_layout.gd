extends RefCounted
## Placement only: the tavern precinct and original resource materials stay intact.
const ImageUtil = preload("res://src/common/image_util.gd")
const PLAN := "res://assets/generated/layout/village_plan.json"

static func plan() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PLAN))

static func cottage_pose(key: String) -> Transform3D:
	var spec: Dictionary = plan().cottages[key]
	var source := Vector3(spec.source[0], spec.source[1], spec.source[2])
	var target := Vector3(spec.position[0], spec.position[1], spec.position[2])
	var basis := Basis(Vector3.UP, deg_to_rad(spec.yaw))
	return Transform3D(basis, target - basis * source)

## How a cottage moved since tools/pipeline/village_layout/build.py wrote its
## placed scene: the layout scene keeps that pose in `built` when it moves one.
static func cottage_shift(key: String) -> Transform3D:
	var spec: Dictionary = plan().cottages[key]
	if not spec.has("built"):
		return Transform3D.IDENTITY
	var built: Dictionary = spec.built
	var was := Transform3D(Basis(Vector3.UP, deg_to_rad(built.yaw)), Vector3(built.position[0], built.position[1], built.position[2]))
	var now := Transform3D(Basis(Vector3.UP, deg_to_rad(spec.yaw)), Vector3(spec.position[0], spec.position[1], spec.position[2]))
	return now * was.affine_inverse()

## `lift` raises a house above the ground under its pivot (layout scene).
static func house_pose(spec: Dictionary, terrain: TerrainSystem) -> Transform3D:
	var source := Vector3(spec.source[0], terrain.height_at(spec.source[0], spec.source[1]), spec.source[1])
	var target := Vector3(spec.position[0], terrain.height_at(spec.position[0], spec.position[1]) + float(spec.get("lift", 0.0)), spec.position[1])
	var basis := Basis(Vector3.UP, deg_to_rad(spec.yaw))
	return Transform3D(basis, target - basis * source)

static func place_houses(map: Node3D, terrain: TerrainSystem) -> void:
	for spec: Dictionary in plan().houses:
		var pose := house_pose(spec, terrain)
		var prefix := "Village house %02d " % int(spec.id)
		for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
			if RockField.label_of(item).begins_with(prefix):
				item.global_transform = pose * item.global_transform

static func smoke_position(point: Vector3, terrain: TerrainSystem) -> Vector3:
	for spec: Dictionary in plan().houses:
		if Vector2(point.x - spec.source[0], point.z - spec.source[1]).length() < 3.0:
			return house_pose(spec, terrain) * point
	return point

## Shallow earthen house yards and the isolated inland depression. The original
## textures, lake, island, main street and tavern elevations are retained.
static func ground_height(x: float, z: float, original: float, cottages: Dictionary) -> float:
	var height := original
	if x > -8 and x < 5 and z > -81 and z < -68:
		var edge := minf(minf(x + 8, 5 - x), minf(z + 81, -68 - z))
		height += maxf(0.0, 1.7 - height) * smoothstep(0.0, 2.0, edge)
	if z > -18.0:
		return height
	for spec: Dictionary in cottages.values():
		var offset := Vector3(x - spec.position[0], 0, z - spec.position[2])
		var local := Basis(Vector3.UP, deg_to_rad(-spec.yaw)) * offset
		var edge := maxf(absf(local.x) - 3.9, absf(local.z - 0.5) - 4.7)
		var weight := 1.0 - smoothstep(0.0, 1.5, edge)
		# Preserve the already laid main road and the tavern approach.
		var y := -z
		var road_x := -3.5 + 3.5 * sin((y + 11.0) * 0.079) - 0.09 * maxf(0.0, y) - minf(10.0, maxf(0.0, (y - 20.0) * 0.5))
		weight *= smoothstep(2.8, 3.8, absf(x - road_x))
		height = lerpf(height, float(spec.position[1]) - 0.025, weight)
	return height

static func settle_ground(image: Image, origin: Vector2, cell: float) -> void:
	var cottages: Dictionary = plan().cottages
	for iz in range(int((-82.0 - origin.y) / cell), int((-18.0 - origin.y) / cell) + 1):
		for ix in range(int((-18.0 - origin.x) / cell), int((12.0 - origin.x) / cell) + 1):
			var x := origin.x + ix * cell
			var z := origin.y + iz * cell
			var height := ground_height(x, z, image.get_pixel(ix, iz).r, cottages)
			image.set_pixel(ix, iz, Color(height, 0, 0))

static func settle_bridge(map: Node3D, terrain: TerrainSystem) -> void:
	var deck: MeshInstance3D
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var label := RockField.label_of(item)
		if label in ["Arched village footbridge", "Bridge stone walkway"]:
			item.position.y -= 0.42
		if label == "Bridge stone walkway": deck = item
	if deck == null: return
	var rows := {}
	var box := deck.global_transform * deck.get_aabb()
	var centre_z := box.get_center().z
	for stone: AABB in RockField.stones_of(deck):
		var x := snappedf(stone.get_center().x, 0.01)
		rows[x] = maxf(rows.get(x, -INF), stone.end.y + 0.015)
	var keys := rows.keys()
	keys.sort()
	var profile: Array[Vector2] = []
	profile.append(Vector2(box.position.x - 1.8, terrain.height_at(box.position.x - 1.8, centre_z)))
	profile.append(Vector2(box.position.x, rows[keys[0]]))
	for x: float in keys: profile.append(Vector2(x, rows[x]))
	profile.append(Vector2(box.end.x, rows[keys[-1]]))
	profile.append(Vector2(box.end.x + 1.8, terrain.height_at(box.end.x + 1.8, centre_z)))
	var body := StaticBody3D.new()
	body.name = "VillageBridgeWalkway"
	map.add_child(body)
	for i in range(profile.size() - 1):
		var points := PackedVector3Array()
		for point: Vector2 in [profile[i], profile[i + 1]]:
			for z in [centre_z - 1.08, centre_z + 1.08]:
				points.append(Vector3(point.x, point.y, z))
				points.append(Vector3(point.x, point.y - 0.18, z))
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var holder := CollisionShape3D.new()
		holder.shape = shape
		body.add_child(holder)

static func rock_pose(pose: Transform3D, radius: float, terrain: TerrainSystem, paths: Array) -> Transform3D:
	# Keep every scanned stone, moving obstructions onto the lane shoulders.
	if pose.origin.z + radius > -18.0 or pose.origin.z < -87.0 or pose.origin.x < -33.0 or pose.origin.x > 28.0:
		return pose
	var original := Vector2(pose.origin.x, pose.origin.z)
	var point := original
	var clearance := radius + 1.05
	for attempt in 12:
		var moved := false
		for path: Dictionary in paths:
			for i in range(path.points.size() - 1):
				var a := Vector2(path.points[i][0], path.points[i][1])
				var b := Vector2(path.points[i + 1][0], path.points[i + 1][1])
				var near := Geometry2D.get_closest_point_to_segment(point, a, b)
				var offset := point - near
				if offset.length() >= clearance:
					continue
				if offset.length_squared() < 0.0001:
					offset = (b - a).orthogonal()
				point = near + offset.normalized() * clearance
				point.y = minf(point.y, -18.0 - radius)
				moved = true
		if not moved: break
	if point != original:
		pose.origin.y += terrain.height_at(point.x, point.y) - terrain.height_at(original.x, original.y)
		pose.origin.x = point.x
		pose.origin.z = point.y
	return pose

## Trodden earth around each house: the grass thins toward the walls.
static func paint_aprons(map: Node3D, terrain: TerrainSystem) -> void:
	var config: Dictionary = terrain.meta.masks
	var origin := Vector2(config.origin[0], config.origin[1])
	var cell: float = config.cell
	var image := ImageUtil.rgba8(terrain.material.get_shader_parameter("near_control"))
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		if not RockField.label_of(item).ends_with("limewashed rooms"):
			continue
		var inverse := item.global_transform.affine_inverse()
		var box := item.get_aabb()
		var centre := item.global_transform * box.get_center()
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
	terrain.material.set_shader_parameter("near_control", ImageTexture.create_from_image(image))
