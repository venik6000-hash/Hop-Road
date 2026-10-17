extends RefCounted
## Where the ground floor of the tavern is walked and where dust lies, drawn
## once from above for tavern_surface.gdshader (`floor_wear`): red is how much
## a spot is walked, green how much dust it keeps.
##
## People walk where nothing stands: the farther from the walls and the
## furniture (the tavern's box colliders), the more a board is polished. Every
## way ends at a door, and feet shuffle under every seat, so the boards are
## worn there as well. Dust is left along the walls and under what stands.

## Metres to a cell of the map.
const CELL := 0.125
## A box counts when it stands on the floor: between these heights over the
## boards (the floor's own collider ends below them).
const STANDS := Vector2(0.15, 1.5)
## How far from anything a board is walked in full, and how far dust reaches
## from a wall's foot.
const FREE := 1.1
const DUSTY := 0.45
const DOOR_REACH := 1.6
const SEAT_REACH := 0.7

## The map's texture and its place for the shader (corner xz, 1 / size), from
## the box colliders under `body`. `bounds` is the building in the world,
## `floor_height` the boards that are walked, `doors` and `seats` points of
## the world.
static func build(body: Node3D, bounds: AABB, floor_height: float, doors: PackedVector3Array,
		seats: PackedVector3Array) -> Dictionary:
	var width := ceili(bounds.size.x / CELL)
	var depth := ceili(bounds.size.z / CELL)
	var origin := Vector2(bounds.position.x, bounds.position.z)
	# 0 where something stands, far away elsewhere; then the distance to it.
	var far := PackedFloat32Array()
	far.resize(width * depth)
	far.fill(1000.0)
	for holder: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
		var box := holder.shape as BoxShape3D
		if box == null:
			continue
		var place := holder.global_transform
		var solid := place * AABB(-box.size * 0.5, box.size)
		if solid.position.y > floor_height + STANDS.y or solid.end.y < floor_height + STANDS.x:
			continue
		var inverse := place.affine_inverse()
		var half := box.size * 0.5
		var x0 := clampi(floori((solid.position.x - origin.x) / CELL), 0, width - 1)
		var x1 := clampi(ceili((solid.end.x - origin.x) / CELL), 0, width - 1)
		var z0 := clampi(floori((solid.position.z - origin.y) / CELL), 0, depth - 1)
		var z1 := clampi(ceili((solid.end.z - origin.y) / CELL), 0, depth - 1)
		for z: int in range(z0, z1 + 1):
			for x: int in range(x0, x1 + 1):
				var local: Vector3 = inverse * Vector3(origin.x + (x + 0.5) * CELL, place.origin.y,
					origin.y + (z + 0.5) * CELL)
				if absf(local.x) <= half.x and absf(local.z) <= half.z:
					far[z * width + x] = 0.0
	_spread(far, width, depth)
	var walked := PackedFloat32Array()
	walked.resize(width * depth)
	for index: int in width * depth:
		walked[index] = clampf(far[index] * CELL / FREE, 0.0, 1.0)
	_tread(walked, far, width, depth, origin, doors, DOOR_REACH, 1.0)
	_tread(walked, far, width, depth, origin, seats, SEAT_REACH, 0.8)
	var bytes := PackedByteArray()
	bytes.resize(width * depth * 2)
	for index: int in width * depth:
		var distance := far[index] * CELL
		var dust := 1.0 if distance <= 0.0 else 1.0 - clampf(distance / DUSTY, 0.0, 1.0)
		bytes[index * 2] = int(roundf(walked[index] * 255.0))
		bytes[index * 2 + 1] = int(roundf(dust * 255.0))
	var image := Image.create_from_data(width, depth, false, Image.FORMAT_RG8, bytes)
	return {"texture": ImageTexture.create_from_image(image),
		"rect": Vector4(origin.x, origin.y, 1.0 / (width * CELL), 1.0 / (depth * CELL))}

## Wears the free boards round each of `points`: `most` at the point, falling
## to nothing at `reach` from it (in plan).
static func _tread(walked: PackedFloat32Array, far: PackedFloat32Array, width: int, depth: int, origin: Vector2,
		points: PackedVector3Array, reach: float, most: float) -> void:
	var cells := ceili(reach / CELL)
	for point: Vector3 in points:
		var cx := floori((point.x - origin.x) / CELL)
		var cz := floori((point.z - origin.y) / CELL)
		for z: int in range(maxi(cz - cells, 0), mini(cz + cells, depth - 1) + 1):
			for x: int in range(maxi(cx - cells, 0), mini(cx + cells, width - 1) + 1):
				var index := z * width + x
				if far[index] <= 0.0:
					continue
				var gap := Vector2(origin.x + (x + 0.5) * CELL - point.x, origin.y + (z + 0.5) * CELL - point.z).length()
				walked[index] = maxf(walked[index], most * (1.0 - gap / reach))

## Turns a field that is 0 on what stands into the distance to it, in cells
## (two sweeps with the 3-4 chamfer, a third of a cell fine).
static func _spread(far: PackedFloat32Array, width: int, depth: int) -> void:
	const STEP := 1.0
	const SLANT := 1.3333
	for z: int in depth:
		for x: int in width:
			var index := z * width + x
			var best := far[index]
			if x > 0:
				best = minf(best, far[index - 1] + STEP)
			if z > 0:
				best = minf(best, far[index - width] + STEP)
				if x > 0:
					best = minf(best, far[index - width - 1] + SLANT)
				if x < width - 1:
					best = minf(best, far[index - width + 1] + SLANT)
			far[index] = best
	for z: int in range(depth - 1, -1, -1):
		for x: int in range(width - 1, -1, -1):
			var index := z * width + x
			var best := far[index]
			if x < width - 1:
				best = minf(best, far[index + 1] + STEP)
			if z < depth - 1:
				best = minf(best, far[index + width] + STEP)
				if x < width - 1:
					best = minf(best, far[index + width + 1] + SLANT)
				if x > 0:
					best = minf(best, far[index + width - 1] + SLANT)
			far[index] = best
