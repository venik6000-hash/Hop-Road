extends RefCounted
## The village's buildings that tools/pipeline/buildings/kit.py makes: their
## tables, and the ground under them. A table (assets/models/<name>/<name>.json)
## stands its building by `origin` and `yaw`; docs/village-buildings/README.md
## tells what else it holds.

const TABLES: Array[String] = [
	"res://assets/models/brewery/brewery.json",
	"res://assets/models/lighthouse/lighthouse.json",
	"res://assets/models/smithy/smithy.json",
	"res://assets/models/mill/mill.json",
	"res://assets/models/lamplighter/lamplighter.json",
	"res://assets/models/hop_kiln/hop_kiln.json",
	"res://assets/models/marsh_walk/marsh_walk.json",
	"res://assets/models/wash_stage/wash_stage.json",
	"res://assets/models/quay/quay.json",
	"res://assets/models/road_lanterns/road_lanterns.json",
	"res://assets/models/cooperage/cooperage.json",
	"res://assets/models/hop_garden/hop_garden.json",
]

static func tables() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for path: String in TABLES:
		result.append(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return result

## Where a building stands in the map.
static func pose(table: Dictionary) -> Transform3D:
	var origin: Array = table.origin
	return Transform3D(Basis(Vector3.UP, deg_to_rad(table.get("yaw", 0.0))), Vector3(origin[0], origin[1], origin[2]))

## How the labels begin of the Blender map's pieces a building stands in
## place of (a table's `replaces`): the old house on the smithy's lot.
static func replaced() -> PackedStringArray:
	var beginnings := PackedStringArray()
	for table: Dictionary in tables():
		for beginning: String in table.get("replaces", []):
			beginnings.append(beginning)
	return beginnings

## Whether `label` begins as one of `beginnings` does.
static func begins(label: String, beginnings: PackedStringArray) -> bool:
	for beginning: String in beginnings:
		if label.begins_with(beginning):
			return true
	return false

## Shapes the heights `image` (texel (0, 0) at `origin`, `cell` metres apart)
## under every building, as its table's `terrain` asks.
static func settle_ground(image: Image, origin: Vector2, cell: float) -> void:
	for table: Dictionary in tables():
		shape_ground(image, origin, cell, pose(table), table.get("terrain", {}))

## What a table's `terrain` asks of the ground, in the building's own frame
## (x and z from its origin, heights from its floor):
## - `seat` {at, radius, skirt, to}: level at `to` within `radius` of `at`,
##   running out over `skirt` metres more into the ground as it was;
## - `ramp` {from, to, height, half, shoulder}: a way from `from` at `height`
##   straight to `to` at the ground's own height there, `half` metres to
##   either side of the line and running out over `shoulder`;
## - `level` {rect, to, skirt}: level at `to` inside the rectangle (two
##   opposite corners), coming back to the ground as it was over `skirt`
##   metres round it;
## - `lower` {rect, to}: taken down to `to` at most inside the rectangle. It
##   is cut last: a floor keeps the ground a yard beside it raised out.
static func shape_ground(image: Image, origin: Vector2, cell: float, place: Transform3D, terrain: Dictionary) -> void:
	var to_local := place.affine_inverse()
	var floor_height := place.origin.y
	for seat: Dictionary in terrain.get("seat", []):
		var centre := Vector2(seat.at[0], seat.at[1])
		var radius: float = seat.radius
		var reach: float = radius + float(seat.skirt)
		var level: float = floor_height + float(seat.to)
		var span := _span(image, origin, cell, place, Rect2(centre - Vector2.ONE * reach, Vector2.ONE * reach * 2.0))
		for iz in range(span.position.y, span.end.y + 1):
			for ix in range(span.position.x, span.end.x + 1):
				var blend: float = smoothstep(radius, reach, _local(to_local, origin, cell, ix, iz).distance_to(centre))
				if blend < 1.0:
					image.set_pixel(ix, iz, Color(lerpf(level, image.get_pixel(ix, iz).r, blend), 0.0, 0.0))
	for ramp: Dictionary in terrain.get("ramp", []):
		var from := Vector2(ramp.from[0], ramp.from[1])
		var along := Vector2(ramp.to[0], ramp.to[1]) - from
		var half: float = ramp.half
		var shoulder: float = ramp.shoulder
		var head: float = floor_height + float(ramp.height)
		var end := place * Vector3(from.x + along.x, 0.0, from.y + along.y)
		var foot := image.get_pixel(roundi((end.x - origin.x) / cell), roundi((end.z - origin.y) / cell)).r
		var span := _span(image, origin, cell, place, Rect2(from, Vector2.ZERO).expand(from + along).grow(half + shoulder))
		for iz in range(span.position.y, span.end.y + 1):
			for ix in range(span.position.x, span.end.x + 1):
				var at := _local(to_local, origin, cell, ix, iz) - from
				var way := at.dot(along) / along.length_squared()
				if way < 0.0 or way > 1.0:
					continue
				var blend: float = smoothstep(half, half + shoulder, absf(at.cross(along)) / along.length())
				if blend < 1.0:
					image.set_pixel(ix, iz, Color(lerpf(lerpf(head, foot, way), image.get_pixel(ix, iz).r, blend), 0.0, 0.0))
	for flat: Dictionary in terrain.get("level", []):
		var rect := _rect(flat.rect)
		var skirt: float = flat.skirt
		var level: float = floor_height + float(flat.to)
		var span := _span(image, origin, cell, place, rect.grow(skirt))
		for iz in range(span.position.y, span.end.y + 1):
			for ix in range(span.position.x, span.end.x + 1):
				var at := _local(to_local, origin, cell, ix, iz)
				var blend: float = smoothstep(0.0, skirt, at.distance_to(at.clamp(rect.position, rect.end)))
				if blend < 1.0:
					image.set_pixel(ix, iz, Color(lerpf(level, image.get_pixel(ix, iz).r, blend), 0.0, 0.0))
	for cut: Dictionary in terrain.get("lower", []):
		var rect := _rect(cut.rect)
		var level: float = floor_height + float(cut.to)
		# The ground between two heights is a straight line: every height
		# whose cells reach under the rectangle goes down.
		var under := rect.grow(cell - 0.001)
		var span := _span(image, origin, cell, place, under)
		for iz in range(span.position.y, span.end.y + 1):
			for ix in range(span.position.x, span.end.x + 1):
				if under.has_point(_local(to_local, origin, cell, ix, iz)) and image.get_pixel(ix, iz).r > level:
					image.set_pixel(ix, iz, Color(level, 0.0, 0.0))

## A rectangle of a table: two opposite corners (x, z).
static func _rect(corners: Array) -> Rect2:
	return Rect2(Vector2(corners[0][0], corners[0][1]), Vector2.ZERO).expand(Vector2(corners[1][0], corners[1][1]))

## The texels whose places may lie in `rect` of the building's frame.
static func _span(image: Image, origin: Vector2, cell: float, place: Transform3D, rect: Rect2) -> Rect2i:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var world := place * Vector3(corner.x, 0.0, corner.y)
		low = low.min(Vector2(world.x, world.z))
		high = high.max(Vector2(world.x, world.z))
	var first := Vector2i(((low - origin) / cell).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((high - origin) / cell).ceil()).min(image.get_size() - Vector2i.ONE)
	return Rect2i(first, last - first)

## Where the texel (ix, iz) lies in the building's frame (x, z).
static func _local(to_local: Transform3D, origin: Vector2, cell: float, ix: int, iz: int) -> Vector2:
	var point := to_local * Vector3(origin.x + ix * cell, 0.0, origin.y + iz * cell)
	return Vector2(point.x, point.z)
