extends RefCounted
## Batched height reads of TerrainSystem: height_at() for a whole grid of
## points at once.

## height_at(xs[i], zs[j]) for every pair, row by row (index j * xs.size() + i),
## stored as 32-bit floats. The same arithmetic in the same order, but each
## image is read once (only the pixels the grid touches) instead of eight
## Image.get_pixel calls per point.
static func heights_at_grid(terrain: TerrainSystem, xs: PackedFloat64Array, zs: PackedFloat64Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(xs.size() * zs.size())
	if xs.is_empty() or zs.is_empty():
		return result
	var far := _GridSampler.new(terrain.far_image, terrain.far_origin, terrain.far_cell, terrain.far_size, xs, zs)
	var near := _GridSampler.new(terrain.near_image, terrain.near_origin, terrain.near_cell, terrain.near_size, xs, zs)
	# _near_weight's edge is the least of four terms, two from x and two from
	# z; the least of the x pair and of the z pair is the same value (minf
	# only selects; a -0/+0 tie gives a weight <= 0 either way). `local` comes
	# from the same per-component Vector2 arithmetic.
	var edge_x := PackedFloat64Array()
	edge_x.resize(xs.size())
	for i: int in xs.size():
		var local := (Vector2(xs[i], 0.0) - terrain.near_origin) / terrain.near_cell
		edge_x[i] = minf(local.x, terrain.near_size - 1 - local.x)
	var edge_z := PackedFloat64Array()
	edge_z.resize(zs.size())
	for j: int in zs.size():
		var local := (Vector2(0.0, zs[j]) - terrain.near_origin) / terrain.near_cell
		edge_z[j] = minf(local.y, terrain.near_size - 1 - local.y)
	var far_data := far.data
	var far_width := far.width
	var far_ix := far.ix
	var far_tx := far.tx
	var near_data := near.data
	var near_width := near.width
	var near_ix := near.ix
	var near_tx := near.tx
	var k := 0
	for j: int in zs.size():
		var far_row := far.iz[j]
		var far_t := far.tz[j]
		var near_row := near.iz[j]
		var near_t := near.tz[j]
		var edge_row := edge_z[j]
		for i: int in xs.size():
			var near_weight := clampf(minf(edge_x[i], edge_row) * terrain.near_cell / 40.0, 0.0, 1.0)
			var at := far_row + far_ix[i]
			var t := far_tx[i]
			var far_h := lerpf(lerpf(far_data[at], far_data[at + 1], t),
				lerpf(far_data[at + far_width], far_data[at + far_width + 1], t), far_t)
			if near_weight <= 0.0:
				result[k] = far_h
			else:
				at = near_row + near_ix[i]
				t = near_tx[i]
				var near_h := lerpf(lerpf(near_data[at], near_data[at + 1], t),
					lerpf(near_data[at + near_width], near_data[at + near_width + 1], t), near_t)
				result[k] = lerpf(far_h, near_h, near_weight)
			k += 1
	return result

## _sample() prepared for a grid of x and z values: the per-axis terms (ix, tx
## and iz, tz) come from the same expressions, the four corners from a block
## copy of the pixels the grid can reach (32-bit floats, as Image.get_pixel().r).
## ix and iz become offsets into `data` (iz already times `width`).
class _GridSampler:
	var ix := PackedInt32Array()
	var tx := PackedFloat64Array()
	var iz := PackedInt32Array()
	var tz := PackedFloat64Array()
	var data := PackedFloat32Array()
	var width := 0

	func _init(image: Image, origin: Vector2, cell: float, size: int, xs: PackedFloat64Array, zs: PackedFloat64Array) -> void:
		ix.resize(xs.size())
		tx.resize(xs.size())
		for i: int in xs.size():
			var fx := clampf((xs[i] - origin.x) / cell, 0.0, size - 1.001)
			ix[i] = int(fx)
			tx[i] = fx - ix[i]
		iz.resize(zs.size())
		tz.resize(zs.size())
		for j: int in zs.size():
			var fz := clampf((zs[j] - origin.y) / cell, 0.0, size - 1.001)
			iz[j] = int(fz)
			tz[j] = fz - iz[j]
		# ix <= size - 2, so the block (with the +1 neighbours) stays inside the image.
		var x0 := ix[0]
		var x1 := ix[0]
		for value: int in ix:
			x0 = mini(x0, value)
			x1 = maxi(x1, value)
		var z0 := iz[0]
		var z1 := iz[0]
		for value: int in iz:
			z0 = mini(z0, value)
			z1 = maxi(z1, value)
		width = x1 + 2 - x0
		var block := image.get_region(Rect2i(x0, z0, width, z1 + 2 - z0))
		data = block.get_data().to_float32_array()
		for i: int in ix.size():
			ix[i] -= x0
		for j: int in iz.size():
			iz[j] = (iz[j] - z0) * width
