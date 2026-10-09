class_name TavernNavigation
extends RefCounted
## A capsule-clearance grid for hall staff. Built once from the imported
## furniture colliders; paths cannot cut diagonally between chair legs.
const ORIGIN := Vector2(4.7, -13.25)
const CELL := 0.25
const FLOOR_Y := 6.96
var grid := AStarGrid2D.new()

func build(actor: CharacterBody3D) -> void:
	grid.region = Rect2i(0, 0, 51, 50)
	grid.cell_size = Vector2.ONE * CELL
	grid.offset = ORIGIN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	var exclude: Array[RID] = []
	# Moving people must never become permanent obstacles in the cached map.
	for person in actor.get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if person is CharacterBody3D:
			exclude.append(person.get_rid())
	query.exclude = exclude
	var space := actor.get_world_3d().direct_space_state
	for x in grid.region.size.x:
		for y in grid.region.size.y:
			var id := Vector2i(x, y)
			var point := grid.get_point_position(id)
			query.transform.origin = Vector3(point.x, FLOOR_Y + 0.85, point.y)
			grid.set_point_solid(id, not space.intersect_shape(query, 1).is_empty())

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := nearest_free(Vector2(from.x, from.z))
	var end := nearest_free(Vector2(to.x, to.z))
	var points := PackedVector3Array()
	if start.x < 0 or end.x < 0:
		return points
	for point: Vector2 in grid.get_point_path(start, end):
		points.append(Vector3(point.x, FLOOR_Y, point.y))
	return points

func nearest_free(point: Vector2) -> Vector2i:
	var center := Vector2i(((point - ORIGIN) / CELL).round())
	var best := Vector2i(-1, -1)
	var distance := INF
	for x in range(center.x - 2, center.x + 3):
		for y in range(center.y - 2, center.y + 3):
			var id := Vector2i(x, y)
			if not grid.region.has_point(id) or grid.is_point_solid(id):
				continue
			var d := grid.get_point_position(id).distance_squared_to(point)
			if d < distance:
				distance = d
				best = id
	return best
