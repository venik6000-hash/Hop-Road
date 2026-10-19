class_name TavernBeds
extends RefCounted
## The beds of the guest rooms: the boxes of a table's `beds` in the
## tavern's frame (tools/pipeline/tavern/furnish_upstairs.py marks the beds,
## export.py writes their boxes).

## The boxes of a table's `beds`: rows of x0, y0, z0, x1, y1, z1.
static func from_table(rows: Array) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for row: Variant in rows:
		var b: Array = row
		var low := Vector3(Values.real(b[0]), Values.real(b[1]), Values.real(b[2]))
		var high := Vector3(Values.real(b[3]), Values.real(b[4]), Values.real(b[5]))
		boxes.append(AABB(low, high - low))
	return boxes

## Where a look from `eye` along `forward` (in the world) first meets one of
## the `beds` of a tavern standing at `place`, in the world; null for none.
static func looked_at(beds: Array[AABB], place: Transform3D, eye: Vector3, forward: Vector3) -> Variant:
	var into := place.affine_inverse()
	var from := into * eye
	var along := into.basis * forward
	var nearest: Variant = null
	var best := INF
	for bed: AABB in beds:
		var hit: Variant = bed.intersects_ray(from, along)
		if hit == null:
			continue
		var point: Vector3 = hit
		var away := from.distance_squared_to(point)
		if away < best:
			best = away
			nearest = place * point
	return nearest
