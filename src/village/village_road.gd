class_name VillageRoad
extends RefCounted
## The main road of a region's village plan (`main_road` of
## village_plan.json, WorldSchemas.village_plan): its centre line, a point
## every half metre from north to south with the half width of the paving
## there, and the stretch of it through the village (`street`). Between two
## points the road runs straight; the paving of a stretch is as wide as its
## north point says; the road ends at its first and last point.
## tools/lib/village_ground.py reads the same line for the terrain, the
## buildings' ground and the placed cottages.

## Metres between two points of the street (street()).
const STREET_STEP := 2.0

## The x of the centre line at `z`; past an end, the end's x.
static func centre(plan: Dictionary, z: float) -> float:
	var points := _points(plan)
	var i := mini(_north_of(points, z), points.size() - 2)
	var a: Array = points[i]
	var b: Array = points[i + 1]
	var t := clampf((Values.real(a[1]) - z) / (Values.real(a[1]) - Values.real(b[1])), 0.0, 1.0)
	return Values.real(a[0]) * (1.0 - t) + Values.real(b[0]) * t

## The street through the village: [x, z] every STREET_STEP m from north to
## south, the line the village's plants keep their verges to.
static func street(plan: Dictionary) -> Array:
	var road: Dictionary = plan.main_road
	var ends: Array = road.street
	var north := Values.real(ends[0])
	var count := roundi((north - Values.real(ends[1])) / STREET_STEP)
	var found := []
	for k in count + 1:
		var z := north - k * STREET_STEP
		found.append([centre(plan, z), z])
	return found

static func _points(plan: Dictionary) -> Array:
	var road: Dictionary = plan.main_road
	return road.points

## The index of the nearest point at `z` or north of it; 0 north of the road.
static func _north_of(points: Array, z: float) -> int:
	var low := 0
	var high := points.size() - 1
	if z > Values.real(points[0][1]):
		return 0
	# The last point whose z is not under `z`.
	while low < high:
		var middle := (low + high + 1) >> 1
		if Values.real(points[middle][1]) >= z:
			low = middle
		else:
			high = middle - 1
	return low
