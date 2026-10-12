class_name ValleyZones
extends RefCounted
## The named places of the valley, and which of them a point lies in. A zone
## is a few shapes on the map (assets/loop/zones.json): a box [x0, z0, x1, z1],
## a circle [x, z, radius], a band `reach` metres to each side of a path of
## [x, z] points, or a polygon of [x, z] corners for what has no simpler outline
## (the lake, the meadow, the forest); `floor` [y0, y1] keeps a shape to one
## storey. The first zone of the list that holds the point names it, so a place
## stands in the list before the land it lies on, and the lake, the meadow and
## the forest close it; among the village's houses and on the bare shore
## no zone does.

const PATH := "res://assets/loop/zones.json"

## {id, name, shapes} in the order of the file.
var zones: Array[Dictionary] = []

static func load_file(path := PATH) -> ValleyZones:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_list(data.get("zones", []) if data is Dictionary else [])

static func from_list(list: Variant) -> ValleyZones:
	var result := ValleyZones.new()
	if list is Array:
		for zone: Variant in list:
			if zone is Dictionary and zone.get("id") is String and zone.get("shapes") is Array:
				result.zones.append(zone)
	return result

## The id of the zone `point` lies in, "" for none.
func zone_at(point: Vector3) -> String:
	for zone: Dictionary in zones:
		for shape: Variant in zone.shapes:
			if shape is Dictionary and holds(shape, point):
				return zone.id
	return ""

func has_zone(id: String) -> bool:
	for zone: Dictionary in zones:
		if zone.id == id:
			return true
	return false

static func holds(shape: Dictionary, point: Vector3) -> bool:
	if shape.has("floor") and (point.y < float(shape.floor[0]) or point.y > float(shape.floor[1])):
		return false
	var at := Vector2(point.x, point.z)
	if shape.has("box"):
		var box: Array = shape.box
		return at.x >= float(box[0]) and at.x <= float(box[2]) and at.y >= float(box[1]) and at.y <= float(box[3])
	if shape.has("circle"):
		var circle: Array = shape.circle
		return at.distance_to(Vector2(circle[0], circle[1])) <= float(circle[2])
	if shape.has("path"):
		var path: Array = shape.path
		var reach := float(shape.get("reach", 3.0))
		for index in range(path.size() - 1):
			var from := Vector2(path[index][0], path[index][1])
			var to := Vector2(path[index + 1][0], path[index + 1][1])
			if Geometry2D.get_closest_point_to_segment(at, from, to).distance_to(at) <= reach:
				return true
	if shape.has("polygon"):
		var corners := PackedVector2Array()
		for corner: Variant in shape.polygon:
			corners.append(Vector2(corner[0], corner[1]))
		return Geometry2D.is_point_in_polygon(at, corners)
	return false
