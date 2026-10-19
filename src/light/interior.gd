class_name Interior
extends RefCounted
## The rooms and the openings of one building or cave, in its own frame
## (docs/LEVEL.md, «Свет помещений»). A room is its air as boxes, how far its
## probe reaches through its walls, its floor and its profile. An opening is
## a rectangle on the line of a wall (a window, a door) or a hole in a floor
## (the stairs, a hatch) between two rooms, or between a room and the
## outdoors (OUT). Interiors holds every one of a level and answers for all of
## them how far an eye is indoors.

## What an opening of a wall or of a floor is.
const WALL_KINDS: Array[String] = ["window", "door"]
const FLOOR_KINDS: Array[String] = ["stair", "hatch"]
## The outdoors, as the other side of an opening.
const OUT := "out"
## How far a room a table gives by its probe alone (`probes`) reaches past
## the probe's box, m. A wall of a village building may be a board, and a
## probe that reached through it would give the wall's weather side the
## room's darkness. The tavern's `rooms` say their walls (half a metre of stone).
const PROBE_WALL := 0.12

class Room:
	var name := ""
	## Its air: boxes in the building's frame.
	var boxes: Array[AABB] = []
	## How far the room reaches past its air on each side, m: through its
	## walls, under its floor and over its ceiling. The probe's box is the
	## room's so grown, and so is the room as every system asks after it.
	var wall := Vector3.ZERO
	## The height of its floor in the building's frame, m.
	var floor_height := 0.0
	var profile: LightProfile
	## The ambient light its probe holds (linear).
	var ambient := Color.BLACK
	## The boxes grown by the walls.
	var reach: Array[AABB] = []

	func _init(title: String, air: Array[AABB], walls: Vector3, floor_at: float, light: LightProfile,
			ambient_light: Color) -> void:
		name = title
		boxes = air
		wall = walls
		floor_height = floor_at
		profile = light
		ambient = ambient_light
		for box: AABB in boxes:
			var half := box.size * 0.5 + wall
			reach.append(AABB(box.get_center() - half, half * 2.0))

	## The middle of the probe's box and its size, in the building's frame.
	func probe_centre() -> Vector3:
		return _air().get_center()

	func probe_size() -> Vector3:
		return (_air().size * 0.5 + wall) * 2.0

	func _air() -> AABB:
		var whole := boxes[0]
		for box: AABB in boxes:
			whole = whole.merge(box)
		return whole

class Opening:
	var name := ""
	var kind := ""
	## The two sides: room names, or OUT.
	var rooms := PackedStringArray()
	## A wall's: the middle of the opening on the wall's line, the wall's
	## normal into the room, the clear width, the sill, the top and the
	## springing of its arch, the way from the wall's line to the room's face
	## of the wall, the floor under it, and whether the day comes in by it.
	var centre := Vector3.ZERO
	var inward := Vector3.ZERO
	var width := 0.0
	var sill := 0.0
	var top := 0.0
	var spring := 0.0
	var reveal := 0.0
	var floor_height := 0.0
	var daylight := false
	## A floor's: the height of its boards and the hole (x and z).
	var height := 0.0
	var hole := Rect2()

	func in_floor() -> bool:
		return kind in FLOOR_KINDS

	func to_outdoors() -> bool:
		return OUT in rooms

var title := ""
## The building's frame in the world.
var transform := Transform3D.IDENTITY
## What the building takes up, in world space.
var bounds := AABB()
var rooms: Array[Room] = []
var openings: Array[Opening] = []
## Its lamps and probes; null for one that has none.
var lamps: InteriorLamps
## The rooms' contact shadows are drawn (ContactShadows) while the eye is here.
var contact := false

var _to_local := Transform3D.IDENTITY

func _init(name: String, frame: Transform3D, building: AABB) -> void:
	title = name
	transform = frame
	_to_local = frame.affine_inverse()
	bounds = building

## The rooms of a table's `rooms` (BuildingSchemas.room()).
static func rooms_of(rows: Array) -> Array[Room]:
	var found: Array[Room] = []
	for row: Dictionary in rows:
		var boxes: Array[AABB] = []
		for values: Array in row.boxes:
			var half := Vector3(Values.real(values[3]), Values.real(values[4]), Values.real(values[5]))
			boxes.append(AABB(Vector3(Values.real(values[0]), Values.real(values[1]), Values.real(values[2])) - half, half * 2.0))
		var a: Array = row.ambient
		found.append(Room.new(str(row.name), boxes, Values.vec3(row.wall), Values.real(row.floor),
			LightProfile.named(str(row.profile)), Color(Values.real(a[0]), Values.real(a[1]), Values.real(a[2]))))
	return found

## The room under a row of a table's `probes` (BuildingSchemas.probe()): its
## air, PROBE_WALL past it on every side, with the row's profile or the one
## for such rooms (LightProfile.of_probe_rooms).
static func room_of_probe(row: Dictionary) -> Room:
	var half := Values.vec3(row.extents)
	var air: Array[AABB] = [AABB(Values.vec3(row.position) - half, half * 2.0)]
	var a: Array = row.ambient
	var profile: LightProfile = LightProfile.named(str(row.profile)) if row.has("profile") else LightProfile.of_probe_rooms()
	return Room.new(str(row.room), air, Vector3.ONE * PROBE_WALL, air[0].position.y, profile,
		Color(Values.real(a[0]), Values.real(a[1]), Values.real(a[2])))

## The openings of a table's `openings` (BuildingSchemas.opening()). A wall's
## opening without a floor of its own has its room's.
func add_openings(rows: Array) -> void:
	for row: Dictionary in rows:
		var opening := Opening.new()
		opening.name = str(row.name)
		opening.kind = str(row.kind)
		opening.rooms = PackedStringArray(Values.list(row.rooms))
		if opening.in_floor():
			var h: Array = row.hole
			opening.height = Values.real(row.height)
			opening.hole = Rect2(Values.real(h[0]), Values.real(h[1]), Values.real(h[2]) - Values.real(h[0]),
				Values.real(h[3]) - Values.real(h[1]))
		else:
			opening.centre = Values.vec3(row.position)
			opening.inward = Values.vec3(row.inward)
			opening.width = Values.real(row.width)
			opening.sill = Values.real(row.sill)
			opening.top = Values.real(row.top)
			opening.spring = Values.real(row.get("spring", row.top))
			opening.reveal = Values.real(row.get("reveal", 0.0))
			opening.daylight = Values.flag(row.get("daylight", false))
			var side := room(opening.rooms[0])
			opening.floor_height = Values.real(row.get("floor", side.floor_height if side != null else 0.0))
		openings.append(opening)

## The room called `name`; null when there is none.
func room(name: String) -> Room:
	for found: Room in rooms:
		if found.name == name:
			return found
	return null

## Metres a point (world space) is inside the room it is deepest in: past
## the nearest face of that room's box, as far as the room reaches. Below
## zero it is outside every room by that much along the axis that parts it
## most; -INF with no rooms.
func depth_of(point: Vector3) -> float:
	var local := _to_local * point
	var deepest := -INF
	for found: Room in rooms:
		for box: AABB in found.reach:
			deepest = maxf(deepest, depth_in(box, local))
	return deepest

## The room a point (world space) is deepest in, or nearest to; null with no rooms.
func nearest_room(point: Vector3) -> Room:
	var local := _to_local * point
	var deepest := -INF
	var nearest: Room = null
	for found: Room in rooms:
		for box: AABB in found.reach:
			var depth := depth_in(box, local)
			if depth > deepest:
				deepest = depth
				nearest = found
	return nearest

## The rooms as world boxes: the least box round each reach box.
func room_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for found: Room in rooms:
		for box: AABB in found.reach:
			boxes.append(transform * box)
	return boxes

## The point `local` (in the box's frame) is this far inside `box`, m; below
## zero outside it.
static func depth_in(box: AABB, local: Vector3) -> float:
	var low := local - box.position
	var high := box.end - local
	return minf(minf(low.x, high.x), minf(minf(low.y, high.y), minf(low.z, high.z)))
