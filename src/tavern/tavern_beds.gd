class_name TavernBeds
extends RefCounted
## The beds of the guest rooms, as the boxes of their colliders in the level:
## a Gothic bed in each front room, a plank bed in the back west room and two
## in the back east one (tools/pipeline/tavern/furnish_upstairs.py puts them
## there; the tavern stands at the level's origin, so the builder's (x, y, z)
## is the level's (x, z, -y)).

const BEDS: Array[AABB] = [
	# GothicBed_01 in the front rooms: the model's box, turned a quarter.
	AABB(Vector3(4.26, 10.86, -2.746), Vector3(2.041, 1.535, 1.492)),
	AABB(Vector3(15.699, 10.86, -2.696), Vector3(2.041, 1.535, 1.492)),
	# Plank beds: the builder's own collider boxes.
	AABB(Vector3(9.38, 10.86, -13.8), Vector3(1.04, 0.6, 2.08)),
	AABB(Vector3(15.7, 10.86, -9.82), Vector3(2.08, 0.6, 1.04)),
	AABB(Vector3(15.7, 10.86, -11.17), Vector3(2.08, 0.6, 1.04)),
]

## Where a look from `eye` along `forward` first meets a bed, or null.
static func looked_at(eye: Vector3, forward: Vector3) -> Variant:
	var nearest: Variant = null
	var best := INF
	for bed: AABB in BEDS:
		var hit: Variant = bed.intersects_ray(eye, forward)
		if hit == null:
			continue
		var point: Vector3 = hit
		var away := eye.distance_squared_to(point)
		if away < best:
			best = away
			nearest = point
	return nearest
