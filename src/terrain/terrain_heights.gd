extends RefCounted
## Batched height reads of TerrainSystem: height_at() for a whole grid of
## points at once.

## TerrainTiles.height(xs[i], zs[j]) of `fields` for every pair, row by row
## (index j * xs.size() + i), stored as 32-bit floats. The same arithmetic in
## the same order, but the terms of one axis (the cell, the fraction, the
## distance to an edge, the tile) are worked out once per row and column
## instead of once per point.
static func heights_at_grid(fields: TerrainTiles, xs: PackedFloat64Array, zs: PackedFloat64Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(xs.size() * zs.size())
	if xs.is_empty() or zs.is_empty():
		return result
	var far_x := _Axis.new(xs, fields.far_origin.x, fields.far_cell, fields.far_size)
	var far_z := _Axis.new(zs, fields.far_origin.y, fields.far_cell, fields.far_size)
	var mid_x := _Axis.new(xs, fields.mid_origin.x, fields.mid_cell, fields.mid_size)
	var mid_z := _Axis.new(zs, fields.mid_origin.y, fields.mid_cell, fields.mid_size)
	var tile_x := _TileAxis.new(xs, fields.origin.x, fields.tile, fields.cell, fields.samples)
	var tile_z := _TileAxis.new(zs, fields.origin.y, fields.tile, fields.cell, fields.samples)
	var far := fields.far
	var far_size := fields.far_size
	var mid := fields.mid
	var mid_size := fields.mid_size
	var samples := fields.samples
	var slots := fields.slots
	var missing := fields.missing
	var k := 0
	for j: int in zs.size():
		var far_row := far_z.index[j] * far_size
		var far_t := far_z.fraction[j]
		var mid_row := mid_z.index[j] * mid_size
		var mid_t := mid_z.fraction[j]
		var mid_edge := mid_z.edge[j]
		var tile_row := tile_z.map_row[j]
		var tile_at := tile_z.index[j] * samples
		var tile_t := tile_z.fraction[j]
		var tile_l := tile_z.local[j]
		for i: int in xs.size():
			var weight := 0.0
			var data := PackedFloat32Array()
			var column := tile_x.map_column[i]
			if tile_row >= 0 and column >= 0:
				var index := tile_row + column
				var layer := slots[index]
				if layer >= 0:
					weight = TerrainTiles.edge_weight(tile_x.local[i], tile_l, fields.tile, missing[index])
					data = fields.heights[layer]
			var at := 0
			var t := 0.0
			var tile_h := 0.0
			if weight > 0.0:
				at = tile_at + tile_x.index[i]
				t = tile_x.fraction[i]
				tile_h = lerpf(lerpf(data[at], data[at + 1], t), lerpf(data[at + samples], data[at + samples + 1], t), tile_t)
				if weight >= 1.0:
					result[k] = tile_h
					k += 1
					continue
			at = far_row + far_x.index[i]
			t = far_x.fraction[i]
			var h := lerpf(lerpf(far[at], far[at + 1], t), lerpf(far[at + far_size], far[at + far_size + 1], t), far_t)
			if mid_size > 0:
				var mid_weight := clampf(minf(mid_x.edge[i], mid_edge) * fields.mid_cell / TerrainTiles.FADE, 0.0, 1.0)
				if mid_weight > 0.0:
					at = mid_row + mid_x.index[i]
					t = mid_x.fraction[i]
					h = lerpf(h, lerpf(lerpf(mid[at], mid[at + 1], t), lerpf(mid[at + mid_size], mid[at + mid_size + 1], t),
						mid_t), mid_weight)
			if weight > 0.0:
				h = lerpf(h, tile_h, weight)
			result[k] = h
			k += 1
	return result

## TerrainTiles.bilinear()'s cell and fraction along one axis of a field of
## `size` samples `cell` m apart from `start`, and the distance in samples to
## the nearer end (land_weight()).
class _Axis:
	var index := PackedInt32Array()
	var fraction := PackedFloat64Array()
	var edge := PackedFloat64Array()

	func _init(values: PackedFloat64Array, start: float, cell: float, size: int) -> void:
		index.resize(values.size())
		fraction.resize(values.size())
		edge.resize(values.size())
		if size == 0:
			return
		for i: int in values.size():
			var local := (values[i] - start) / cell
			edge[i] = minf(local, size - 1 - local)
			var f := clampf(local, 0.0, size - 1.001)
			index[i] = int(f)
			fraction[i] = f - index[i]

## The tile along one axis (TerrainTiles.height()): its column on the map
## (-1 off it, times MAP_SIZE for rows), the metres into it, and the cell and
## fraction of its heights there.
class _TileAxis:
	var map_column := PackedInt32Array()
	var map_row := PackedInt32Array()
	var local := PackedFloat64Array()
	var index := PackedInt32Array()
	var fraction := PackedFloat64Array()

	func _init(values: PackedFloat64Array, start: float, tile: float, cell: float, samples: int) -> void:
		map_column.resize(values.size())
		map_row.resize(values.size())
		local.resize(values.size())
		index.resize(values.size())
		fraction.resize(values.size())
		for i: int in values.size():
			var at := floori((values[i] - start) / tile)
			var on := at - TerrainTiles.MAP_FIRST
			map_column[i] = on if on >= 0 and on < TerrainTiles.MAP_SIZE else -1
			map_row[i] = on * TerrainTiles.MAP_SIZE if map_column[i] >= 0 else -1
			local[i] = values[i] - (start + at * tile)
			var f := clampf(local[i] / cell, 0.0, samples - 1.001)
			index[i] = int(f)
			fraction[i] = f - index[i]
