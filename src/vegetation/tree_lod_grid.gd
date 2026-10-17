class_name TreeLodGrid
extends RefCounted
## The trees that get mesh LODs, bucketed on a 16 m grid (cell-major,
## species-minor) with their MultiMesh rows precomputed: a 3x4 transform and
## the custom data (seed, species, crown widening, 0).
##
## select() fills one buffer per distance band, species and 64 m world tile
## in a window around the camera: square tiles give tight bounds, so the
## camera and every shadow cascade cull what they do not see. A cell that lies
## wholly inside a band is copied in one piece; only cells that straddle a
## band edge are tested tree by tree. Bands are half-open, [near, far).
##
## For an eye in the tavern's rooms select() takes what that eye sees of the
## outdoors (InteriorSight.Sight) and leaves out, cell by cell, the trees no
## opening shows; of the bands that only cast shadows, the trees whose
## shadow reaches nothing seen.

const CELL := 16.0
const TILE := 64.0
const STRIDE := 16
## Tallest tree and widest crown (m), for the draw bounds of a buffer.
const MAX_HEIGHT := 34.0
const MAX_CROWN := 10.0
## How far the wind may carry a crown past where it stands, m.
const SWAY := 1.5

var origin := Vector2.ZERO
var size := Vector2i.ZERO
var kinds := 0
var rows := PackedFloat32Array()
var xs := PackedFloat32Array()
var zs := PackedFloat32Array()
## First tree of (cell, species); one more entry closes the last range.
var offsets := PackedInt32Array()
## Lowest and highest tree base in each cell.
var cell_low := PackedFloat32Array()
var cell_high := PackedFloat32Array()
## Per cell, once measure() has run: how far the widest crown reaches past
## its trunk (m) and the height of the tallest tree's top.
var cell_reach := PackedFloat32Array()
var cell_top := PackedFloat32Array()
## The last select(): cells of the visible bands left out as unseen and
## asked about, the same of the shadow bands.
var unseen := Vector4i.ZERO

## Buckets the trees of `trees` whose flags have TreeSet.DETAIL.
func _init(trees: TreeSet, species_count: int) -> void:
	kinds = species_count
	var picked := PackedInt32Array()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in trees.size():
		if trees.flags[i] & TreeSet.DETAIL == 0:
			continue
		picked.append(i)
		low = Vector2(minf(low.x, trees.x[i]), minf(low.y, trees.z[i]))
		high = Vector2(maxf(high.x, trees.x[i]), maxf(high.y, trees.z[i]))
	if picked.is_empty():
		offsets.resize(1)
		return
	origin = (low / CELL).floor() * CELL
	size = Vector2i(int((high.x - origin.x) / CELL) + 1, int((high.y - origin.y) / CELL) + 1)
	var cells := size.x * size.y
	# Counting sort by cell and species.
	var keys := PackedInt32Array()
	keys.resize(picked.size())
	offsets.resize(cells * kinds + 1)
	for n in picked.size():
		var i := picked[n]
		var cx := int((trees.x[i] - origin.x) / CELL)
		var cz := int((trees.z[i] - origin.y) / CELL)
		keys[n] = (cz * size.x + cx) * kinds + trees.species[i]
		offsets[keys[n] + 1] += 1
	for k in range(1, offsets.size()):
		offsets[k] += offsets[k - 1]
	var fill := offsets.slice(0, offsets.size() - 1)
	rows.resize(picked.size() * STRIDE)
	xs.resize(picked.size())
	zs.resize(picked.size())
	cell_low.resize(cells)
	cell_high.resize(cells)
	cell_low.fill(INF)
	cell_high.fill(-INF)
	for n in picked.size():
		var i := picked[n]
		var slot := fill[keys[n]]
		fill[keys[n]] += 1
		xs[slot] = trees.x[i]
		zs[slot] = trees.z[i]
		var row := instance_row(trees, i)
		for f in STRIDE:
			rows[slot * STRIDE + f] = row[f]
		var cell := keys[n] / kinds
		cell_low[cell] = minf(cell_low[cell], trees.y[i])
		cell_high[cell] = maxf(cell_high[cell], trees.y[i])

## MultiMesh row of tree `i`: yaw about +Y and uniform scale as a 3x4 matrix
## in the row order MultiMesh expects, then the custom data.
static func instance_row(trees: TreeSet, i: int) -> PackedFloat32Array:
	var s := trees.scale[i]
	var c := cos(trees.yaw[i]) * s
	var n := sin(trees.yaw[i]) * s
	return PackedFloat32Array([c, 0.0, n, trees.x[i], 0.0, s, 0.0, trees.y[i], -n, 0.0, c, trees.z[i],
		trees.seed[i], float(trees.species[i]), trees.width[i], 0.0])

func tree_count() -> int:
	return xs.size()

## Takes the sizes of the trees from `frames` (per species: the width and the
## height of its picture at scale 1, m), so that cell_box() is the bounds of
## what stands in a cell and not of the largest tree there could be.
func measure(frames: PackedVector4Array) -> void:
	var cells := size.x * size.y
	cell_reach.resize(cells)
	cell_top.resize(cells)
	for cell in cells:
		var reach := 0.0
		var top := -INF
		for slot in range(offsets[cell * kinds], offsets[(cell + 1) * kinds]):
			var k := slot * STRIDE
			var frame := frames[int(rows[k + 13])]
			reach = maxf(reach, frame.x * 0.5 * rows[k + 5] * rows[k + 14])
			top = maxf(top, rows[k + 7] + frame.y * rows[k + 5])
		cell_reach[cell] = reach + SWAY
		cell_top[cell] = top + SWAY

## The trees whose crowns may reach over `rect` (x, z): x, z, the crown's
## radius (m) and how deep its shade is (0..1) of each, one after another.
## `crowns` holds, per species, the radius at scale 1 and the shade.
func near(rect: Rect2, crowns: PackedVector2Array) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	var reach := rect.grow(MAX_CROWN)
	if xs.is_empty() or not Rect2(origin, Vector2(size) * CELL).intersects(reach):
		return found
	var first := Vector2i(((reach.position - origin) / CELL).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var last := Vector2i(((reach.end - origin) / CELL).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	for cz in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var cell := cz * size.x + cx
			for slot in range(offsets[cell * kinds], offsets[(cell + 1) * kinds]):
				var crown := crowns[int(rows[slot * STRIDE + 13])]
				found.append(xs[slot])
				found.append(zs[slot])
				found.append(rows[slot * STRIDE + 5] * crown.x)
				found.append(crown.y)
	return found

## Tiles per side of the window that select() covers for bands reaching `reach` m.
static func window_tiles(reach: float) -> int:
	return ceili(2.0 * reach / TILE) + 1

## World position of the window corner tile for a camera at `eye`.
static func window_origin(eye: Vector2, reach: float) -> Vector2i:
	return Vector2i(floori((eye.x - reach) / TILE), floori((eye.y - reach) / TILE))

## Clears and refills `buffers` and `boxes` (bands.size() * kinds * window^2
## entries, window = window_tiles(largest band end)) with the trees whose
## horizontal distance from `eye` lies within bands[band] = [near, far).
## With a `sight` (see above) `shadow_bands` tells, band by band, which only
## cast shadows.
func select(eye: Vector2, bands: PackedVector2Array, buffers: Array[PackedFloat32Array], boxes: Array[AABB],
		sight: InteriorSight.Sight = null, shadow_bands := PackedByteArray()) -> void:
	var low := PackedFloat32Array()
	var high := PackedFloat32Array()
	low.resize(buffers.size() * 3)
	high.resize(buffers.size() * 3)
	low.fill(INF)
	high.fill(-INF)
	for slot in buffers.size():
		buffers[slot].clear()
	var reach := 0.0
	for band in bands:
		reach = maxf(reach, band.y)
	var window := window_tiles(reach)
	var corner := window_origin(eye, reach)
	unseen = Vector4i.ZERO
	if sight != null and not sight.active:
		sight = null
	if not xs.is_empty():
		_collect(eye, bands, reach, window, corner, buffers, low, high, sight, shadow_bands)
	for slot in boxes.size():
		var k := slot * 3
		if low[k] == INF:
			boxes[slot] = AABB()
			continue
		var start := Vector3(low[k] - MAX_CROWN, low[k + 1] - 1.0, low[k + 2] - MAX_CROWN)
		var end := Vector3(high[k] + MAX_CROWN, high[k + 1] + MAX_HEIGHT, high[k + 2] + MAX_CROWN)
		boxes[slot] = AABB(start, end - start)

## The bounds of what stands in a cell whose corner of least x and z is
## (x, z): its middle and half its size, crowns and tallest tree taken in.
func cell_box(cell: int, x: float, z: float) -> Array[Vector3]:
	var foot := cell_low[cell] - 1.0
	var top := cell_high[cell] + MAX_HEIGHT if cell_top.is_empty() else cell_top[cell]
	var reach := MAX_CROWN if cell_reach.is_empty() else cell_reach[cell]
	return [Vector3(x + CELL * 0.5, (foot + top) * 0.5, z + CELL * 0.5),
		Vector3(CELL * 0.5 + reach, (top - foot) * 0.5, CELL * 0.5 + reach)]

func _collect(eye: Vector2, bands: PackedVector2Array, reach: float, window: int, corner: Vector2i,
		buffers: Array[PackedFloat32Array], low: PackedFloat32Array, high: PackedFloat32Array,
		sight: InteriorSight.Sight, shadow_bands: PackedByteArray) -> void:
	var ix0 := clampi(floori((eye.x - reach - origin.x) / CELL), 0, size.x - 1)
	var ix1 := clampi(floori((eye.x + reach - origin.x) / CELL), 0, size.x - 1)
	var iz0 := clampi(floori((eye.y - reach - origin.y) / CELL), 0, size.y - 1)
	var iz1 := clampi(floori((eye.y + reach - origin.y) / CELL), 0, size.y - 1)
	var per_tile := window * window
	for iz in range(iz0, iz1 + 1):
		var z0 := origin.y + iz * CELL
		var z1 := z0 + CELL
		var dz_near := maxf(maxf(z0 - eye.y, eye.y - z1), 0.0)
		var dz_far := maxf(absf(eye.y - z0), absf(eye.y - z1))
		var tz := floori((z0 + 0.5 * CELL) / TILE) - corner.y
		for ix in range(ix0, ix1 + 1):
			var cell := iz * size.x + ix
			var base := cell * kinds
			if offsets[base] == offsets[base + kinds]:
				continue
			var x0 := origin.x + ix * CELL
			var x1 := x0 + CELL
			var dx_near := maxf(maxf(x0 - eye.x, eye.x - x1), 0.0)
			var dx_far := maxf(absf(eye.x - x0), absf(eye.x - x1))
			var near := sqrt(dx_near * dx_near + dz_near * dz_near)
			var far := sqrt(dx_far * dx_far + dz_far * dz_far)
			var tile := tz * window + floori((x0 + 0.5 * CELL) / TILE) - corner.x
			# For an eye indoors, asked once a cell: 0 not yet, 1 yes, 2 no.
			var seen := 0
			var casts := 0
			var box: Array[Vector3] = []
			for band_index in bands.size():
				var band := bands[band_index]
				if far < band.x or near >= band.y:
					continue
				if sight != null:
					if box.is_empty():
						box = cell_box(cell, x0, z0)
					if shadow_bands[band_index] == 1:
						if casts == 0:
							casts = 1 if sight.shaded_by(box[0], box[1]) else 2
						unseen += Vector4i(0, 0, casts - 1, 1)
						if casts == 2:
							continue
					else:
						if seen == 0:
							seen = 1 if sight.sees(box[0], box[1]) else 2
						unseen += Vector4i(seen - 1, 1, 0, 0)
						if seen == 2:
							continue
				var whole := near >= band.x and far < band.y
				var lo2 := band.x * band.x
				var hi2 := band.y * band.y
				for kind in kinds:
					var a := offsets[base + kind]
					var b := offsets[base + kind + 1]
					if a == b:
						continue
					var slot := (band_index * kinds + kind) * per_tile + tile
					var added := false
					if whole:
						buffers[slot].append_array(rows.slice(a * STRIDE, b * STRIDE))
						added = true
					else:
						for i in range(a, b):
							var dx := xs[i] - eye.x
							var dz := zs[i] - eye.y
							var d2 := dx * dx + dz * dz
							if d2 >= lo2 and d2 < hi2:
								buffers[slot].append_array(rows.slice(i * STRIDE, (i + 1) * STRIDE))
								added = true
					if added:
						var k := slot * 3
						low[k] = minf(low[k], x0)
						low[k + 1] = minf(low[k + 1], cell_low[cell])
						low[k + 2] = minf(low[k + 2], z0)
						high[k] = maxf(high[k], x1)
						high[k + 1] = maxf(high[k + 1], cell_high[cell])
						high[k + 2] = maxf(high[k + 2], z1)
