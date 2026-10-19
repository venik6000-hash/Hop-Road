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
##
## The physics server takes a moved body's new place only on the next physics
## frame. settle() writes every fixed body's place into it first, so the grid
## is the same however many frames the build waited (docs/LEVEL.md, «Части
## уровня»).
##
## A cell is SOLID, LAWN or free. A lawn is the ground of a yard the region's
## yard rule keeps short (lay_lawn()): no card grass grows on it, but a tree
## may stand there, and it is no wall's foot to the grass round it.

const CELL := 0.5
## The values of a cell of `cover`: something solid stands there; a yard's
## lawn. A tree reads a cell above half of 255 as solid (VegetationTerrain).
const SOLID := 255
const LAWN := 64

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

## Writes the place of every fixed body under `scope` (a StaticBody3D, not an
## AnimatableBody3D) into the physics server now, as the next physics frame
## would. Returns the bodies that move: doors, the boat, characters, ragdoll
## bones. Their place depends on the frames that ran, so the scan passes them.
static func settle(scope: Node) -> Array[RID]:
	var moving: Array[RID] = []
	for found: Node in scope.find_children("*", "CollisionObject3D", true, false):
		if found is StaticBody3D and not found is AnimatableBody3D:
			var body := found as StaticBody3D
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
		elif found is PhysicsBody3D:
			moving.append((found as PhysicsBody3D).get_rid())
	return moving

## Casts one ray per cell over `bounds`, from `top` metres above the ground
## down to just under it. `exclude` holds the terrain and player bodies.
static func scan(space: PhysicsDirectSpaceState3D, bounds: Rect2, ground: VegetationTerrain, exclude: Array[RID],
		top := 60.0) -> ObstacleMap:
	var map := ObstacleMap.new()
	map.origin = (bounds.position / CELL).floor() * CELL
	map.size = Vector2i(ceili((bounds.end.x - map.origin.x) / CELL) + 1,
		ceili((bounds.end.y - map.origin.y) / CELL) + 1)
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
		cover[iz * size.x + ix] = SOLID

## Lays the lawns of a region's yard rule into the free cells and returns how
## many cells it laid. `plan` is the region's worn plan (GroundWear.plan_of):
## its `lawn` (x: metres round a cottage's yard, y: round a door, z: how near
## a wall a route's end makes a door) and its routes. `yards` are the
## cottages' levelled yards (VillageLayout.yards()). A route's end at a wall
## is a door, a step or a porch; along the route and at an end in the open
## the path keeps its wayside.
func lay_lawn(plan: Dictionary, yards: Array[Dictionary]) -> int:
	var rule: Vector3 = plan.lawn
	var lawn := PackedByteArray()
	lawn.resize(cover.size())
	if rule.x > 0.0:
		for yard: Dictionary in yards:
			_lay_yard(lawn, yard, rule.x)
	if rule.y > 0.0:
		var cart: Array = plan.cart
		var foot: Array = plan.foot
		for line: PackedVector2Array in cart + foot:
			for end: Vector2 in [line[0], line[line.size() - 1]]:
				var at := Vector2i(((end - origin) / cell).round())
				if _near_solid(at.x, at.y, rule.z):
					_lay_disc(lawn, end, rule.y)
	var laid := 0
	for index in cover.size():
		if lawn[index] > 0 and cover[index] == 0:
			cover[index] = LAWN
			laid += 1
	return laid

## Marks in `lawn` the cells of `yard`'s box grown by `margin` metres, the box
## turned as VillageLayout.yard_weight() turns it.
func _lay_yard(lawn: PackedByteArray, yard: Dictionary, margin: float) -> void:
	var half: Array = yard.half
	var half_x := Values.real(half[0]) + margin
	var half_z := Values.real(half[1]) + margin
	var middle := Values.real(yard.middle)
	var centre := Vector2(Values.real(yard.x), Values.real(yard.z))
	var turn := Basis(Vector3.UP, deg_to_rad(-Values.real(yard.yaw)))
	var reach := Vector2(half_x, absf(middle) + half_z).length()
	var lo := _cell_below(centre - Vector2.ONE * reach)
	var hi := _cell_below(centre + Vector2.ONE * reach) + Vector2i.ONE
	for iz in range(maxi(lo.y, 0), mini(hi.y + 1, size.y)):
		for ix in range(maxi(lo.x, 0), mini(hi.x + 1, size.x)):
			var offset := origin + Vector2(ix, iz) * cell - centre
			var local := turn * Vector3(offset.x, 0.0, offset.y)
			if absf(local.x) <= half_x and absf(local.z - middle) <= half_z:
				lawn[iz * size.x + ix] = 1

## Marks in `lawn` the cells within `reach` metres of `centre`.
func _lay_disc(lawn: PackedByteArray, centre: Vector2, reach: float) -> void:
	var lo := _cell_below(centre - Vector2.ONE * reach)
	var hi := _cell_below(centre + Vector2.ONE * reach) + Vector2i.ONE
	for iz in range(maxi(lo.y, 0), mini(hi.y + 1, size.y)):
		for ix in range(maxi(lo.x, 0), mini(hi.x + 1, size.x)):
			if (origin + Vector2(ix, iz) * cell).distance_to(centre) <= reach:
				lawn[iz * size.x + ix] = 1

## Whether a solid cell lies within `reach` metres of cell (ix, iz): the cell
## itself, then eight ways out, a cell at a time.
func _near_solid(ix: int, iz: int, reach: float) -> bool:
	if ix >= 0 and iz >= 0 and ix < size.x and iz < size.y and cover[iz * size.x + ix] == SOLID:
		return true
	var steps := maxi(ceili(reach / cell), 1)
	for ring in range(1, steps + 1):
		for k in 8:
			var angle := k * TAU / 8.0
			var jx := ix + roundi(cos(angle) * ring)
			var jz := iz + roundi(sin(angle) * ring)
			if jx >= 0 and jz >= 0 and jx < size.x and jz < size.y and cover[jz * size.x + jx] == SOLID:
				return true
	return false

## The cell at or below `point` on both axes (cells centre on origin + i * cell).
func _cell_below(point: Vector2) -> Vector2i:
	return Vector2i(((point - origin) / cell).floor())

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
