extends RefCounted
## One tile of GrassField, scattered away from the main thread: clumps of
## meadow plants and flowers over a square of the terrain, from a block of
## its heights and from the masks the terrain blends its ground by
## (GrassGround). What grows where at the nodes of a 1 m grid is the
## survey's to say (GrassSurvey). A clump then reads the node next to it,
## picked by chance in proportion to how near each is, which costs one lookup
## and leaves no grid in the meadow. Heights are read bilinearly from the
## half-metre block, as the terrain draws them.
##
## The mat (GrassClump.MAT) is made only for a tile near the eye.
##
## Clump k of a tile stands where the k-th point of a low-discrepancy sequence
## falls, shifted by a jitter that shrinks as k grows: any first share of the
## clumps covers the tile evenly and shows no rows. So a far tile is the first
## `wanted` of its `total` clumps, and asking for more later adds clumps
## without moving those already there.
##
## The clumps come out in pieces: squares of `piece` metres, the whole tile or
## the patches a tile near the camera is drawn by. Each piece keeps the tile's
## order, so each can be drawn by its own distance.

## What _scatter() lays out.
enum Layer { CLUMPS, FLOWERS, MAT }

var ground: GrassGround
## Lowest corner (x, z) and side (m, a whole number of GrassSurvey.NODE).
var origin := Vector2.ZERO
var side := 16.0
## Side (m) of the squares the clumps are handed out in.
var piece := 16.0
## Ground heights every GrassSurvey.GRAIN from origin - GRAIN to origin +
## side + GRAIN, row by row along z.
var heights := PackedFloat32Array()
## The trees whose crowns may reach the tile: x, z, the crown's radius (m)
## and how deep its shade is (0..1) of each, one after another. The fringe of
## shrubs and tall herbs rings each; their shade is the canopy field's.
var trees := PackedFloat32Array()
## Clumps and flowers the tile would hold on open meadow, and how many of the
## first of them to make.
var total := 0
var wanted := 0
var flower_total := 0
var flower_wanted := 0
## Clumps of the mat the tile would hold on open meadow (none are made at 0),
## and the side (m) of the squares they are handed out in.
var mat_total := 0
var mat_piece := 8.0
## Ground whose normal's y is under this grows nothing.
var slope_floor := 0.7
var salt := 0
## The share of the tile this job makes: 1 / 2^level (GrassField).
var level := 0

## The results: the clumps (GrassScatter rows) by the square of `piece` metres
## they stand in (GrassScatter.split's keys) and the ranks of each piece's
## rows; the flowers and theirs; the mat and its ranks by square of
## `mat_piece` metres; how many clumps; the lowest and highest root; the time
## it took.
var pieces := {}
var piece_ranks := {}
var flowers := PackedFloat32Array()
var flower_ranks := PackedFloat32Array()
var mats := {}
var mat_ranks := {}
var clump_count := 0
var low := INF
var high := -INF
var usec := 0

func run() -> void:
	var start := Time.get_ticks_usec()
	var survey := GrassSurvey.new()
	survey.run(ground, origin, side, heights, trees)
	var clumps := _scatter(survey, total, wanted, Layer.CLUMPS)
	clump_count = clumps.size() / GrassScatter.STRIDE
	pieces = GrassScatter.split(clumps, piece)
	for key: Vector2i in pieces:
		var rows: PackedFloat32Array = pieces[key]
		piece_ranks[key] = GrassScatter.ranks(rows)
	flowers = _scatter(survey, flower_total, flower_wanted, Layer.FLOWERS)
	flower_ranks = GrassScatter.ranks(flowers)
	mats = GrassScatter.split(_scatter(survey, mat_total, mat_total, Layer.MAT), mat_piece)
	for key: Vector2i in mats:
		var rows: PackedFloat32Array = mats[key]
		mat_ranks[key] = GrassScatter.ranks(rows)
	usec = Time.get_ticks_usec() - start

## The first `first` of `count` clumps of a layer, those the survey's fields
## let grow.
func _scatter(survey: GrassSurvey, count: int, first: int, layer: Layer) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	if count <= 0 or first <= 0:
		return buffer
	buffer.resize(first * GrassScatter.STRIDE)
	var g := ground
	var nodes := int(side / GrassSurvey.NODE) + 1
	var width := int(side / GrassSurvey.GRAIN) + 3
	var per_metre := 1.0 / GrassSurvey.GRAIN
	var per_node := 1.0 / GrassSurvey.NODE
	# Locals: the loop below runs for every clump of the tile.
	var flower := layer == Layer.FLOWERS
	var chances := survey.bloom_chances if flower else (survey.mat_chances if layer == Layer.MAT else survey.densities)
	var sizes := survey.sizes
	var lows := survey.low_sizes
	var tones := survey.tones
	var crowds := survey.crowds
	var patches := survey.flower_patches
	var kinds := survey.kind_reach
	var blooms := survey.flower_reach
	var cells := g.cells
	var flower_cells := cells[GrassClump.Kind.FLOWER]
	var mat_cells := cells[GrassClump.Kind.MAT]
	var held := heights
	var cover := g.cover
	var cover_w := g.cover_size.x
	var cover_h := g.cover_size.y
	var cover_x := g.cover_origin.x
	var cover_z := g.cover_origin.y
	var per_cover := 1.0 / g.cover_cell
	var covered := not cover.is_empty()
	var origin_x := origin.x
	var origin_z := origin.y
	var steep := slope_floor
	var lowest := low
	var highest := high
	var rng := RandomNumberGenerator.new()
	rng.seed = salt * 4 + layer
	var start_u := rng.randf()
	var start_v := rng.randf()
	var salted := rng.randi() & 0x3fffffff
	# The sequence lays its first points in rows; every tile turns them its own
	# way, or a thinned hillside shows them from one tile to the next.
	var turned := rng.randi() & 7
	var step_u := GrassScatter.R2.x
	var step_v := GrassScatter.R2.y
	var at := 0
	for k in first:
		# Numbers of chance for this clump from an integer hash of k.
		var bits := (k * 2654435761 + salted) & 0x7fffffff
		bits = ((bits ^ (bits >> 15)) * 2246822519) & 0x7fffffff
		bits = ((bits ^ (bits >> 13)) * 3266489917) & 0x7fffffff
		bits ^= bits >> 16
		var chance := (bits & 0x3ff) / 1024.0
		var pick_x := ((bits >> 10) & 0x3ff) / 1024.0
		var pick_z := ((bits >> 20) & 0x3ff) / 1024.0
		var more := (bits * 1103515245 + 12345) & 0x7fffffff
		# The jitter is half as wide again as the spacing of the first k clumps:
		# less leaves the sequence's rows standing among them.
		var jitter := 1.5 / sqrt(k + 1.0)
		var u := start_u + k * step_u + ((more & 0x7fff) / 32768.0 - 0.5) * jitter
		var v := start_v + k * step_v + ((more >> 16) / 32768.0 - 0.5) * jitter
		u -= floorf(u)
		v -= floorf(v)
		if turned & 1:
			u = 1.0 - u
		if turned & 2:
			v = 1.0 - v
		var px := (v if turned & 4 else u) * side
		var pz := (u if turned & 4 else v) * side
		var node := int(pz * per_node + pick_z) * nodes + int(px * per_node + pick_x)
		if chances[node] <= chance:
			continue
		# Three more numbers: which plant, which of its cells, how big.
		var mixed := ((bits ^ 0x2545f491) * 2246822519) & 0x7fffffff
		mixed = ((mixed ^ (mixed >> 13)) * 3266489917) & 0x7fffffff
		mixed ^= mixed >> 16
		var pick := (mixed & 0x3ff) / 1024.0
		var grown := ((mixed >> 10) & 0x3ff) / 1024.0
		var size := sizes[node]
		var tone := tones[node]
		var cell := 0
		if flower:
			# The patch's kind, with a few strays.
			var second := fposmod(patches[node] * 1.9 + (0.37 if pick > 0.85 else 0.0), 1.0)
			var share := node * GrassSurvey.FLOWER_STOPS
			var which := int(second >= blooms[share]) + int(second >= blooms[share + 1]) + int(second >= blooms[share + 2]) \
				+ int(second >= blooms[share + 3]) + int(second >= blooms[share + 4])
			var bloom: int = GrassSurvey.FLOWERS[which]
			cell = flower_cells[bloom]
			if bloom == GrassClump.Flower.DANDELION or bloom == GrassClump.Flower.CELANDINE:
				# Low plants, the size they are.
				size = lerpf(0.85, 1.25, grown)
			else:
				# A flower on a stem stands a little over the grass round it.
				size = lerpf(0.8, 1.4, grown) * clampf(size * 1.05, 0.55, 1.1)
		elif layer == Layer.MAT:
			cell = mat_cells[(mixed >> 20) % mat_cells.size()]
			size = lerpf(1.0, 1.6, grown) * lows[node]
		else:
			var share := node * GrassSurvey.KIND_STOPS
			if pick >= kinds[share + 5]:
				continue
			var kind := int(pick >= kinds[share]) + int(pick >= kinds[share + 1]) + int(pick >= kinds[share + 2]) \
				+ int(pick >= kinds[share + 3]) + int(pick >= kinds[share + 4])
			var kin := cells[kind]
			cell = kin[(mixed >> 20) % kin.size()]
			if kind == GrassClump.Kind.TURF:
				# Turf is low wherever it grows, and lowest where it is trodden.
				size = lerpf(0.9, 1.5, grown) * lows[node]
			elif kind == GrassClump.Kind.FERN:
				# A fern is the size of its kind, in shade or out of it.
				size = lerpf(0.8, 1.2, grown)
			elif kind == GrassClump.Kind.SHRUB:
				size = lerpf(0.75, 1.2, grown) * clampf(size + 0.25, 0.6, 1.0)
			else:
				size *= lerpf(0.9, 1.1, grown)
			if kind >= GrassClump.Kind.LUSH:
				# Leafy stalks, ferns and shrubs stay green where the grass
				# round them has dried.
				tone = minf(tone, GrassSurvey.GREEN_TONE)
		var x := origin_x + px
		var z := origin_z + pz
		if covered:
			var cx := int(floorf((x - cover_x) * per_cover + 0.5))
			var cz := int(floorf((z - cover_z) * per_cover + 0.5))
			if cx >= 0 and cz >= 0 and cx < cover_w and cz < cover_h and cover[cz * cover_w + cx] > 0:
				continue
		# The ground under the clump and its normal, from the four heights round it.
		var gx := px * per_metre + 1.0
		var gz := pz * per_metre + 1.0
		var ix := int(gx)
		var iz := int(gz)
		var tx := gx - ix
		var tz := gz - iz
		var corner := iz * width + ix
		var a := held[corner]
		var b := held[corner + 1]
		var c := held[corner + width]
		var d := held[corner + width + 1]
		var dx := ((b - a) + ((d - c) - (b - a)) * tz) * per_metre
		var dz := ((c - a) + ((d - b) - (c - a)) * tx) * per_metre
		var ny := 1.0 / sqrt(dx * dx + dz * dz + 1.0)
		if ny < steep:
			continue
		var top := a + (b - a) * tx
		var y := top + (c + (d - c) * tx - top) * tz
		GrassScatter.put(buffer, at, x, y, z, -dx * ny, ny, -dz * ny, size, cell, crowds[node], tone,
			(k + 0.5) / count)
		at += GrassScatter.STRIDE
		lowest = minf(lowest, y)
		highest = maxf(highest, y)
	low = lowest
	high = highest
	buffer.resize(at)
	return buffer
