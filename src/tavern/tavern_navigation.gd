class_name TavernNavigation
extends RefCounted
## A capsule-clearance grid for hall staff. Built once from the imported
## furniture colliders, on the grid of the tavern's table (`hall`, in its
## frame); paths cannot cut diagonally between chair legs.
var grid := AStarGrid2D.new()
## Where the tavern stands; the grid lies in its frame.
var place := Transform3D.IDENTITY
var origin := Vector2.ZERO
var cell := 0.25
var floor_y := 0.0

## Builds the grid of the hall of the tavern nearest to `actor`; without a
## tavern the grid stays empty and finds no path.
func build(actor: CharacterBody3D) -> void:
	var tavern := TavernSystem.nearest(actor)
	if tavern == null or tavern.hall_grid.is_empty():
		return
	place = tavern.global_transform
	var hall := tavern.hall_grid
	var cells := Values.vec2(hall.cells)
	origin = Values.vec2(hall.origin)
	cell = Values.real(hall.cell)
	floor_y = Values.real(hall.floor)
	grid.region = Rect2i(0, 0, int(cells.x), int(cells.y))
	grid.cell_size = Vector2.ONE * cell
	grid.offset = origin
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	# People stand on PhysicsLayers.PLAYER and VILLAGERS, which GROUND does
	# not meet: moving people never become permanent obstacles in the map.
	query.collision_mask = PhysicsLayers.GROUND
	query.exclude = [actor.get_rid()]
	var space := actor.get_world_3d().direct_space_state
	for x in grid.region.size.x:
		for y in grid.region.size.y:
			var id := Vector2i(x, y)
			var point := grid.get_point_position(id)
			query.transform.origin = place * Vector3(point.x, floor_y + 0.85, point.y)
			grid.set_point_solid(id, not space.intersect_shape(query, 1).is_empty())

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var into := place.affine_inverse()
	var local_from := into * from
	var local_to := into * to
	var start := nearest_free(Vector2(local_from.x, local_from.z))
	var end := nearest_free(Vector2(local_to.x, local_to.z))
	var points := PackedVector3Array()
	if start.x < 0 or end.x < 0:
		return points
	for point: Vector2 in grid.get_point_path(start, end):
		points.append(place * Vector3(point.x, floor_y, point.y))
	return points

## The free cell nearest to `point` of the tavern's frame (x, z), within two
## cells; (-1, -1) for none.
func nearest_free(point: Vector2) -> Vector2i:
	var center := Vector2i(((point - origin) / cell).round())
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
