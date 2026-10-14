class_name ObstacleMap
extends RefCounted
## Top-down cover of the ground by everything solid that is not terrain:
## houses, walls, cobbles, fences, boulders, cliffs, bridges.
##
## The Blender buildings carry collision, so a grid of vertical rays against
## the physics world (terrain body excluded) finds their exact footprints,
## eaves included, without knowing anything about the scene's structure.
## Rays run right after the map enters the tree (no physics step is needed),
## about 1.4 us each, so the ~100k rays over the village take ~150 ms.
## A hit also marks its four neighbours: grass and trunks then keep half a
## cell away from walls instead of growing through their base.

const CELL := 0.5

var origin := Vector2.ZERO
var cell := CELL
var size := Vector2i.ZERO
var cover := PackedByteArray()

## Union of the world XZ bounds of all collision shapes under `root`.
static func collider_bounds(root: Node) -> Rect2:
	var result := Rect2()
	var first := true
	for holder: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
		if holder.shape == null:
			continue
		var box := holder.global_transform * _shape_aabb(holder.shape)
		var flat := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		result = flat if first else result.merge(flat)
		first = false
	return result

static func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is ConcavePolygonShape3D:
		var faces := (shape as ConcavePolygonShape3D).get_faces()
		var box := AABB(faces[0], Vector3.ZERO) if faces.size() > 0 else AABB()
		for point in faces:
			box = box.expand(point)
		return box
	var mesh := shape.get_debug_mesh()
	return mesh.get_aabb() if mesh != null else AABB()

## Casts one ray per cell over `bounds`, from `top` metres above the ground
## down to just under it. `exclude` holds the terrain and player bodies.
static func scan(space: PhysicsDirectSpaceState3D, bounds: Rect2, ground: VegetationTerrain, exclude: Array[RID],
		top := 60.0) -> ObstacleMap:
	var map := ObstacleMap.new()
	map.origin = (bounds.position / CELL).floor() * CELL
	map.size = Vector2i(int(ceil((bounds.end.x - map.origin.x) / CELL)) + 1,
		int(ceil((bounds.end.y - map.origin.y) / CELL)) + 1)
	map.cover.resize(map.size.x * map.size.y)
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = exclude
	query.hit_back_faces = false
	for iz in map.size.y:
		for ix in map.size.x:
			var x := map.origin.x + ix * CELL
			var z := map.origin.y + iz * CELL
			var floor_y := ground.height(x, z)
			query.from = Vector3(x, floor_y + top, z)
			query.to = Vector3(x, floor_y - 1.0, z)
			if space.intersect_ray(query).is_empty():
				continue
			map._mark(ix, iz)
			map._mark(ix - 1, iz)
			map._mark(ix + 1, iz)
			map._mark(ix, iz - 1)
			map._mark(ix, iz + 1)
	return map

func _mark(ix: int, iz: int) -> void:
	if ix >= 0 and iz >= 0 and ix < size.x and iz < size.y:
		cover[iz * size.x + ix] = 255

func covered_fraction() -> float:
	var count := 0
	for value in cover:
		if value > 0:
			count += 1
	return float(count) / maxf(cover.size(), 1.0)

## Hands the grid to the placement fields.
func apply_to(ground: VegetationTerrain) -> void:
	ground.obstacles = cover
	ground.obstacle_origin = origin
	ground.obstacle_cell = cell
	ground.obstacle_size = size

## L8 texture for the grass shader (1 = covered), bilinear filtered.
func make_texture() -> ImageTexture:
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, cover)
	return ImageTexture.create_from_image(image)

func store(file: FileAccess) -> void:
	file.store_float(origin.x)
	file.store_float(origin.y)
	file.store_float(cell)
	file.store_32(size.x)
	file.store_32(size.y)
	file.store_buffer(cover)

static func read(file: FileAccess) -> ObstacleMap:
	var map := ObstacleMap.new()
	map.origin = Vector2(file.get_float(), file.get_float())
	map.cell = file.get_float()
	map.size = Vector2i(file.get_32(), file.get_32())
	map.cover = file.get_buffer(map.size.x * map.size.y)
	return map if map.cover.size() == map.size.x * map.size.y else null
