class_name LakePlan
extends RefCounted
## The lake of a region (RegionDef.lake, WorldSchemas.lake): where its bed is
## searched, the field of its shore's waves, the shores without reeds, the
## reed beds drawn stand by stand and where the boat moors. The terrain
## (tools/lib/lake_plan.py) reads the same file: the beach it shapes and the kinds
## of the village's waterline. The water's level is the terrain's
## (TerrainSystem.water_level, the global `lake_level`).

## Where the bed is searched (world x, z).
var search := Rect2()
## The square of the shore's waves and wakes (LakeShore): x, z of its corner,
## its side, 0.
var shore_field := Vector4.ZERO
## The beach and the pier: no reeds on the bathing shore.
var beach := Rect2()
## The cove under the waterfall cliff: bare rock and plunging water, no reeds.
var cove := Rect2()
## More shores without reeds: (x, z, radius).
var reedless: Array[Vector3] = []
## The marsh shores, drawn stand by stand (x, z, radius): reed beds all the
## same, with windows of open water between their stands. A stand grows even
## where the shore keeps other reeds off (keeps_reeds_off).
var marsh_stands: Array[Vector3] = []
## Where the boat's mooring is searched (x, z; every 2 m from the corner,
## the far edges left out), the point it moors nearest to and the
## mooring when none is found (x, z).
var mooring_search := Rect2()
var mooring_near := Vector2.ZERO
var mooring_fallback := Vector2.ZERO

## The lake of the file `path`; null for "" (a region without a lake) or a
## file that does not read.
static func read(path: String) -> LakePlan:
	if path.is_empty():
		return null
	var data: Variant = DataFile.read(path, WorldSchemas.lake())
	if not data is Dictionary:
		return null
	var file: Dictionary = data
	var plan := LakePlan.new()
	plan.search = _rect(file.search)
	var field: Array = file.shore_field
	plan.shore_field = Vector4(Values.real(field[0]), Values.real(field[1]), Values.real(field[2]), 0.0)
	var beach_data: Dictionary = file.beach
	plan.beach = _rect(beach_data.rect)
	plan.cove = _rect(file.cove)
	plan.reedless = _points(file.reedless)
	plan.marsh_stands = _points(file.marsh_stands)
	var mooring: Dictionary = file.mooring
	plan.mooring_search = _rect(mooring.search)
	plan.mooring_near = Values.vec2(mooring.near)
	plan.mooring_fallback = Values.vec2(mooring.fallback)
	return plan

## Whether reeds keep off the shore at `point` (x, z).
func keeps_reeds_off(point: Vector2) -> bool:
	if beach.has_point(point) or cove.has_point(point):
		return true
	return reedless.any(func(spot: Vector3) -> bool: return point.distance_to(Vector2(spot.x, spot.y)) < spot.z)

static func _rect(values: Variant) -> Rect2:
	var listed: Array = values
	return Rect2(Values.real(listed[0]), Values.real(listed[1]), Values.real(listed[2]), Values.real(listed[3]))

static func _points(values: Variant) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for point: Variant in Values.list(values):
		points.append(Values.vec3(point))
	return points
