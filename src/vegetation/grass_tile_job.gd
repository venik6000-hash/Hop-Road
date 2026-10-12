extends RefCounted
## One tile of GrassField, scattered away from the main thread: clumps of
## meadow plants and flowers over a square of the terrain, from a block of
## its heights and from the masks the terrain blends its ground by.
##
## What grows where follows the ground, as on a real alpine meadow. At the
## masks' 1 m nodes the job works out how wet the soil is (the brook's banks,
## the lake's margin, gullies, hollows), how dry and thin (steep and sunward
## slopes, rock near the surface), how shaded (the crowns over it, from the
## canopy field) and how closed the stand round it is, whether a crown's
## fringe is near, how trodden (the rim of a path) and whether a path runs
## by, how high and cold, and whether something solid stands beside (a wall,
## a fence, a boulder).
##
## No meadow is an even carpet, and these make the sward's vigour: rank where
## the soil is deep and wet and at the foot of a rock or a wall, poor where
## it is thin, dry or cold, and between the two by the terrain's macro noise
## in swathes tens of metres across with ragged edges. A rank sward stands
## tall, closed and dark green; a poor one is short turf dried to straw on
## the stalk, broken into tussocks with bare ground between them. Under trees
## the grass thins with the stand: in patches under high pines and in open
## stands, all but none under spruces and where the crowns close, thick again
## in a glade. Feet and wheels wear a path's rim to turf; along it, where
## nothing treads or grazes, the grass stands tall in ragged stretches.
##
## From these every node gets its share of each kind of plant:
##   tall grass in seed   rank swards in the open, along a path
##   shorter green grass  everywhere, the meadow's ground tone
##   low turf             poor swards, a path's rim, shade, thin dry soil,
##                        the heights, the strand
##   leafy stalks         in stands on wet ground and at the foot of walls,
##                        round the fringe of a crown
##   ferns                under the crowns, at their fringe, on a wood's floor
##   shrubs               the fringe of a crown and under it, rock, wet
##                        ground, in thickets
## and how tall they stand there, their tone (the green of growth or grass
## dried on the stalk: sward.gdshaderinc), how much blooms and which flowers
## (buttercups in the wet, yarrow on dry and trodden ground,
## bellflowers on slopes and heights, dandelions on a path's rim and by
## walls, celandine in damp half-shade, knapweed among rank grass in seed). A
## clump then reads the node next to it, picked by chance in proportion to
## how near each is, which costs one lookup and leaves no grid in the meadow.
## Heights are read bilinearly from the half-metre block, as the terrain
## draws them.
##
## Under and between these stands the mat (GrassClump.MAT): rosettes of
## loose low blades, made only for a tile near the eye. It covers the ground wherever
## grass grows, skirts every patch of it on thin ground and runs out onto
## stonier ground than the grass holds, the edge of a path or of scree,
## growing smaller as it goes: a meadow has no edge cut with a knife, and
## seen from above no bare soil between its plants.
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

const CanopyField = preload("res://src/vegetation/canopy_field.gd")

## The terrain's fields as flat arrays, shared by every job and only read.
class Ground:
	var water_level := 0.72
	var near_origin := Vector2.ZERO
	var near_cell := 0.5
	var near_size := 0
	## RGBA8, `mask_size` squared (control: R path, G beach, A flowers; extra:
	## R rock outcrop, G wet, B metres from the lake's edge + 128, A open sky),
	## sample [z][x] at mask_origin + (x, z) * mask_cell.
	var control := PackedByteArray()
	var extra := PackedByteArray()
	var mask_origin := Vector2.ZERO
	var mask_cell := 1.0
	var mask_size := 0
	## RGBA8, the far masks (R snow, G bare rock, A gullies) cut to the near
	## field: `far_size` samples from far_origin every far_cell.
	var far := PackedByteArray()
	var far_origin := Vector2.ZERO
	var far_cell := 8.0
	var far_size := Vector2i.ZERO
	## RGBA8, the terrain's tileable macro noise, `macro_size` squared.
	var macro := PackedByteArray()
	var macro_size := 0
	## Ground covered by buildings and props (ObstacleMap), empty when none.
	var cover := PackedByteArray()
	var cover_origin := Vector2.ZERO
	var cover_cell := 0.5
	var cover_size := Vector2i.ZERO
	## The cover of the trees' crowns, none where no trees stand.
	var canopy: CanopyField
	## The atlas's cells by kind (GrassClump.Sheet.cells).
	var cells: Array[PackedInt32Array] = []

## Heights are sampled every GRAIN metres, the fields every NODE metres.
const GRAIN := 0.5
const NODE := 1.0
## Wide plants leave room round them: the share of a leafy stalk's, a fern's
## and a shrub's places that are taken.
const LUSH_FILL := 0.62
const FERN_FILL := 0.45
const SHRUB_FILL := 0.5
## The flowers in the order their shares are kept in (see _survey).
const FLOWERS := [GrassClump.Flower.BUTTERCUP, GrassClump.Flower.YARROW, GrassClump.Flower.BELLFLOWER,
	GrassClump.Flower.DANDELION, GrassClump.Flower.CELANDINE, GrassClump.Flower.KNAPWEED]
## Numbers kept per node for the plants' shares and for the flowers'.
const KIND_STOPS := 6
const FLOWER_STOPS := 5
## Height above the lake (m) over which the valley's meadow gives way to the
## short turf of the heights.
const HEIGHTS := Vector2(70.0, 150.0)
## How far beyond a crown its fringe of shrubs and tall herbs reaches (m).
const FRINGE := 3.0
## Swathes of rank and of poor grass follow the green of the macro noise at
## x metres to a repeat, shifted by y of one.
const SWATHE := Vector2(137.0, 0.29)
## The vigour of the sward (see sward()) between which it turns from poor to
## plain, and from plain to rank.
const POOR := Vector2(0.22, 0.4)
const RANK := Vector2(0.58, 0.72)
## The share of its grass a poor sward keeps: the patch gate breaks what is
## left into tussocks.
const POOR_KEEPS := 0.45
## The tone of a plain sward (the shaders' SWARD_PLAIN): under GREEN_TONE a
## tone is the green of growth, from old to young; over it, grass dried on
## the stalk. Plants that keep their leaves stay green.
const PLAIN_TONE := 0.45
const GREEN_TONE := 0.5
## Along a path the grass stands tall in stretches that follow the blue of
## the macro noise at x metres to a repeat, shifted by y of one.
const WAYSIDE := Vector2(11.0, 0.19)
## What _scatter() lays out.
enum Layer { CLUMPS, FLOWERS, MAT }

var ground: Ground
## Lowest corner (x, z) and side (m, a whole number of NODE).
var origin := Vector2.ZERO
var side := 16.0
## Side (m) of the squares the clumps are handed out in.
var piece := 16.0
## Ground heights every GRAIN from origin - GRAIN to origin + side + GRAIN,
## row by row along z.
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

var _density := PackedFloat32Array()
var _size := PackedFloat32Array()
var _tone := PackedFloat32Array()
## How closely tall plants stand at the node (GrassScatter's crowd).
var _crowd := PackedFloat32Array()
var _bloom := PackedFloat32Array()
var _patch := PackedFloat32Array()
## The chance that a clump of the mat grows at the node, and the size of low
## growth there (the mat's, and the turf's among the grass).
var _mat := PackedFloat32Array()
var _low := PackedFloat32Array()
## Per node, where each kind's share ends along 0..1, in GrassClump.Kind's
## order (KIND_STOPS numbers; past the last nothing grows), and where each
## flower's does, in FLOWERS' order (FLOWER_STOPS numbers; the rest is the
## last).
var _kinds := PackedFloat32Array()
var _blooms := PackedFloat32Array()

func run() -> void:
	var start := Time.get_ticks_usec()
	_survey()
	var clumps := _scatter(total, wanted, Layer.CLUMPS)
	clump_count = clumps.size() / GrassScatter.STRIDE
	pieces = GrassScatter.split(clumps, piece)
	for key: Vector2i in pieces:
		piece_ranks[key] = GrassScatter.ranks(pieces[key])
	flowers = _scatter(flower_total, flower_wanted, Layer.FLOWERS)
	flower_ranks = GrassScatter.ranks(flowers)
	mats = GrassScatter.split(_scatter(mat_total, mat_total, Layer.MAT), mat_piece)
	for key: Vector2i in mats:
		mat_ranks[key] = GrassScatter.ranks(mats[key])
	usec = Time.get_ticks_usec() - start

## The fields at the tile's nodes.
func _survey() -> void:
	var g := ground
	var nodes := int(side / NODE) + 1
	var width := int(side / GRAIN) + 3
	var per_node := int(NODE / GRAIN)
	_density.resize(nodes * nodes)
	_size.resize(nodes * nodes)
	_tone.resize(nodes * nodes)
	_crowd.resize(nodes * nodes)
	_bloom.resize(nodes * nodes)
	_patch.resize(nodes * nodes)
	_mat.resize(nodes * nodes)
	_low.resize(nodes * nodes)
	_kinds.resize(nodes * nodes * KIND_STOPS)
	_blooms.resize(nodes * nodes * FLOWER_STOPS)
	var crowns := trees
	for j in nodes:
		var z := origin.y + j * NODE
		for i in nodes:
			var x := origin.x + i * NODE
			var at := (j * per_node + 1) * width + i * per_node + 1
			var height := heights[at]
			var above := height - g.water_level
			# The terrain's own normal: height_normal() with a half-metre step.
			var dx := heights[at - 1] - heights[at + 1]
			var dz := heights[at - width] - heights[at + width]
			var run_length := sqrt(dx * dx + dz * dz + 4.0 * GRAIN * GRAIN)
			var slope := 1.0 - 2.0 * GRAIN / run_length
			# How far the ground leans toward the midday sun: south is +z
			# (SkySystem.solar_direction).
			var sunward := dz / run_length
			var path := 0.0
			var beach := 0.0
			var meadow := 0.0
			var outcrop := 0.0
			var wet := 0.0
			var shore := 127.0
			var hollow := 0.0
			var trodden := 0.0
			var wayside := 0.0
			var mx := roundi((x - g.mask_origin.x) / g.mask_cell)
			var mz := roundi((z - g.mask_origin.y) / g.mask_cell)
			if mx >= 0 and mz >= 0 and mx < g.mask_size and mz < g.mask_size:
				var m := (mz * g.mask_size + mx) * 4
				path = g.control[m] / 255.0
				beach = g.control[m + 1] / 255.0
				meadow = g.control[m + 3] / 255.0
				outcrop = g.extra[m] / 255.0
				shore = g.extra[m + 2] - 128.0
				# Most of the valley sees nine tenths of the sky; a hollow far less.
				hollow = clampf((0.72 - g.extra[m + 3] / 255.0) * 4.0, 0.0, 1.0)
				# Water soaks a few metres into a bank, feet and wheels wear a
				# metre of a path's rim: both masks reach beyond their own metre.
				wet = maxf(g.extra[m + 1] / 255.0,
					maxf(0.8 * _around(g.extra, mx, mz, 1, 2), 0.5 * _around(g.extra, mx, mz, 1, 4)))
				trodden = maxf(path, 0.7 * _around(g.control, mx, mz, 0, 1))
				# The two or three metres beyond the rim are a path's wayside.
				wayside = maxf(_around(g.control, mx, mz, 0, 2), 0.8 * _around(g.control, mx, mz, 0, 3))
			# The trees over the node: the crowns right over it and how closed the
			# stand round it is, as the terrain reads them from the canopy field.
			var shade := 0.0
			var wooded := 0.0
			if g.canopy != null:
				shade = g.canopy.cover_at(x, z)
				wooded = g.canopy.wooded_at(x, z)
			# The ring just outside a crown is the edge of the wood or a tree that
			# stands alone: among many crowns the ground is a wood's floor, not
			# one thicket.
			var fringe := 0.0
			var stand := 0
			for t in range(0, crowns.size(), 4):
				var tx := x - crowns[t]
				var tz := z - crowns[t + 1]
				var radius := crowns[t + 2]
				var away := tx * tx + tz * tz
				if away >= (radius + FRINGE) * (radius + FRINGE):
					continue
				away = sqrt(away)
				stand += 1
				fringe = maxf(fringe, smoothstep(radius * 0.75, radius, away) * (1.0 - smoothstep(radius, radius + FRINGE, away)))
			fringe *= (1.0 - shade) / maxf(1.0, 0.6 * stand)
			var snow := _far(x, z, 0)
			var bare_rock := _far(x, z, 1)
			var gully := _far(x, z, 3)

			# -- The site. Broad patches come from the terrain's macro noise:
			# dry ones hundreds of metres across, swathes of rank and of poor
			# grass tens of metres across, tone, height and thickets a few metres
			# across.
			var lakeside := (1.0 - smoothstep(2.0, 14.0, shore)) * (1.0 - smoothstep(1.5, 4.0, above))
			var moist := clampf(maxf(wet, lakeside) + 0.7 * gully + 0.5 * hollow, 0.0, 1.0)
			var parched := smoothstep(0.5, 0.82, _macro(x / 430.0, z / 430.0, 0)) * 0.45
			var rim := smoothstep(0.01, 0.08, outcrop)
			var dry := clampf(smoothstep(0.04, 0.2, slope) * (0.45 + 0.55 * clampf(sunward * 3.0 + 0.5, 0.0, 1.0))
				+ 0.6 * bare_rock + parched, 0.0, 1.0) * (1.0 - moist)
			var forest := CanopyField.floor_of(wooded)
			var woodland := smoothstep(0.3, 0.8, forest)
			var verge := smoothstep(0.03, 0.3, trodden)
			var strand := smoothstep(0.01, 0.15, beach)
			var high := smoothstep(HEIGHTS.x, HEIGHTS.y, above)
			var cold := maxf(high, smoothstep(0.02, 0.15, snow))
			var beside := 1.0 if _beside_cover(x, z) else 0.0
			# Nothing treads or grazes a path's wayside: the grass stands tall
			# there as at the foot of a wall, in stretches a few metres long.
			var uncut := smoothstep(0.2, 0.6, wayside) * (1.0 - verge) \
				* smoothstep(0.55, 0.75, _macro(x / WAYSIDE.x + WAYSIDE.y, z / WAYSIDE.x + WAYSIDE.y, 2))
			var ragged := _macro(x / 61.0 + 0.37, z / 61.0 + 0.37, 0)
			var vigour := sward(_macro(x / SWATHE.x + SWATHE.y, z / SWATHE.x + SWATHE.y, 1), ragged, moist,
				maxf(maxf(rim, beside), uncut), dry, cold)
			var rank := smoothstep(RANK.x, RANK.y, vigour)
			var poor := 1.0 - smoothstep(POOR.x, POOR.y, vigour)
			var thicket := _macro(x / 31.0 + 0.83, z / 31.0 + 0.83, 2)
			var tall := _macro(x / 23.0 + 0.61, z / 23.0 + 0.61, 1)

			# -- How much grows. grass_cover() and sward_at() of
			# terrain_fields.gdshaderinc, by which the terrain shades the ground
			# under the plants.
			var trail := clampf(path * 1.2, 0.0, 1.0)
			var scree := clampf(smoothstep(0.18, 0.38, slope) * 0.8 + bare_rock * 0.4, 0.0, 1.0)
			var rock := clampf(smoothstep(0.34, 0.55, slope) + outcrop * 0.9, 0.0, 1.0)
			var bare := maxf(maxf(trail, beach), maxf(scree, rock))
			var rest := (1.0 - 0.75 * smoothstep(0.3, 0.85, wooded)) * (1.0 - 0.92 * shade) \
				* (1.0 - smoothstep(0.15, 0.5, snow)) * smoothstep(0.08, 0.45, above) * lerpf(1.0, POOR_KEEPS, poor)
			# The near field's last 40 m, where the terrain fades into the far one.
			var lx := (x - g.near_origin.x) / g.near_cell
			var lz := (z - g.near_origin.y) / g.near_cell
			var edge := minf(minf(lx, lz), minf(g.near_size - 1 - lx, g.near_size - 1 - lz)) * g.near_cell
			rest *= smoothstep(0.0, 0.6, clampf(edge / 40.0, 0.0, 1.0))
			var density := (1.0 - smoothstep(0.02, 0.2, bare)) * rest
			# The mat holds stonier ground than the grass does.
			var low := (1.0 - smoothstep(0.08, 0.5, bare)) * rest
			# Thin ground is not thin all over: grass holds it in patches a few
			# metres across, as thick as the meadow, and leaves the rest bare.
			# Lone tussocks strewn evenly are what a card meadow gives away. The
			# terrain shades the ground under the plants by the same gate
			# (terrain.gdshader).
			var thin := density
			var patchy := clampf(0.5 + (_macro(x / 19.0 + 0.47, z / 19.0 + 0.47, 1) - 0.5) * 1.8, 0.0, 1.0)
			density = clampf((density * 1.2 - patchy) * 5.0, 0.0, 1.0)
			# The mat goes on a little beyond the patch and grows smaller toward
			# its own rim.
			var mat := clampf((low * 1.2 - patchy + 0.3) * 3.0, 0.0, 1.0)

			# -- The plants' shares of it.
			# By the water the rank growth is green and leafy, not hay.
			var seeding := 1.6 * rank * (1.0 - shade) * (1.0 - 0.5 * woodland) * (1.0 - verge) * (1.0 - 0.8 * cold) \
				* (1.0 - 0.8 * moist) * (1.0 - 0.5 * dry)
			var green := 0.8 + 0.4 * shade
			var turf := 0.05 + 1.4 * poor + 2.5 * verge + 1.2 * shade + 0.9 * dry + 1.6 * cold + 1.5 * strand
			# Leafy stalks hold wet ground and the foot of a wall in stands a few
			# metres across, with grass between them: never a hedge the length of
			# a bank or a fence.
			var stands := smoothstep(0.42, 0.62, _macro(x / 27.0 + 0.11, z / 27.0 + 0.11, 0))
			var lush := (1.8 * moist * stands + 1.4 * beside * smoothstep(0.35, 0.6, thicket)
				+ 0.8 * fringe * smoothstep(0.3, 0.6, thicket) + 0.5 * smoothstep(0.74, 0.86, thicket)) \
				* (1.0 - 0.8 * cold) * (1.0 - verge) * (1.0 - 0.7 * dry)
			# Ferns take the shade the grasses leave, in colonies.
			var fern := (1.4 * shade + 0.7 * fringe + 0.5 * woodland * (1.0 - shade)) * (1.0 - 0.7 * dry) \
				* (1.0 - 0.8 * cold) * (1.0 - verge) * smoothstep(0.3, 0.55, _macro(x / 17.0 + 0.91, z / 17.0 + 0.91, 2))
			# Willows and alder on wet ground, as on a bank.
			var shrub := (0.8 * fringe + 0.5 * shade + 0.8 * rim + 0.5 * beside + 0.4 * high + 0.5 * moist) \
				* smoothstep(0.45, 0.7, thicket)
			var sum := seeding + green + turf + lush + fern + shrub
			var n := j * nodes + i
			var reach := seeding / sum
			_kinds[n * KIND_STOPS] = reach
			reach += green / sum
			_kinds[n * KIND_STOPS + 1] = reach
			reach += turf / sum
			_kinds[n * KIND_STOPS + 2] = reach
			reach += lush / sum * LUSH_FILL
			_kinds[n * KIND_STOPS + 3] = reach
			reach += fern / sum * FERN_FILL
			_kinds[n * KIND_STOPS + 4] = reach
			reach += shrub / sum * SHRUB_FILL
			_kinds[n * KIND_STOPS + 5] = reach
			_density[n] = density
			_size[n] = lerpf(0.8, 1.2, tall) * lerpf(1.0, 1.15, moist) * lerpf(1.0, 0.7, dry) * lerpf(1.0, 0.65, cold) \
				* lerpf(1.0, 0.75, shade) * lerpf(1.0, 0.55, verge) * lerpf(0.6, 1.0, thin) * lerpf(0.7, 1.0, density) \
				* lerpf(1.0, 0.55, poor) * lerpf(0.82, 1.05, rank) * lerpf(1.0, 1.2, uncut)
			_tone[n] = sward_tone(ragged, _macro(x / 17.0 + 0.53, z / 17.0 + 0.53, 1), poor, rank, dry, cold, moist, shade)
			_crowd[n] = density * (1.0 - turf / sum)
			_mat[n] = mat
			_low[n] = lerpf(0.55, 1.0, low) * lerpf(0.6, 1.0, mat) * lerpf(1.0, 0.8, dry) * lerpf(1.0, 0.75, cold) \
				* lerpf(1.0, 0.6, verge)

			# -- Flowers: everywhere on open meadow, thick in clusters a few
			# metres across where the terrain's flower mask says so, one kind
			# to a patch.
			var clusters := _macro(x / 25.0 + 0.23, z / 25.0 + 0.23, 0)
			var in_bloom := smoothstep(0.15, 0.8, meadow * smoothstep(0.3, 0.7, clusters) * 1.6)
			# They bloom on the mat too, where no tall grass stands over it.
			_bloom[n] = maxf(density, 0.6 * mat) * (1.0 - shade) * (1.0 - 0.7 * verge) * maxf(in_bloom, 0.12)
			_patch[n] = _macro(x / 55.0 + 0.71, z / 55.0 + 0.71, 2)
			var buttercup := 0.7 + 1.6 * moist
			var yarrow := 0.55 + 1.1 * dry + 0.9 * verge
			var bellflower := 0.4 + 1.2 * high + 0.8 * smoothstep(0.05, 0.2, slope) + 0.7 * rim + 0.5 * fringe
			var dandelion := 0.3 + 1.6 * verge + 0.8 * beside
			var celandine := 0.1 + 1.0 * moist + 1.0 * fringe + 0.8 * woodland
			var knapweed := 0.5 + 0.9 * rank * (1.0 - cold) * (1.0 - moist)
			var blooms := buttercup + yarrow + bellflower + dandelion + celandine + knapweed
			var bloomed := buttercup / blooms
			_blooms[n * FLOWER_STOPS] = bloomed
			bloomed += yarrow / blooms
			_blooms[n * FLOWER_STOPS + 1] = bloomed
			bloomed += bellflower / blooms
			_blooms[n * FLOWER_STOPS + 2] = bloomed
			bloomed += dandelion / blooms
			_blooms[n * FLOWER_STOPS + 3] = bloomed
			bloomed += celandine / blooms
			_blooms[n * FLOWER_STOPS + 4] = bloomed

## The first `first` of `count` clumps of a layer, those the fields let grow.
func _scatter(count: int, first: int, layer: Layer) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	if count <= 0 or first <= 0:
		return buffer
	buffer.resize(first * GrassScatter.STRIDE)
	var g := ground
	var nodes := int(side / NODE) + 1
	var width := int(side / GRAIN) + 3
	var per_metre := 1.0 / GRAIN
	var per_node := 1.0 / NODE
	# Locals: the loop below runs for every clump of the tile.
	var flower := layer == Layer.FLOWERS
	var chances := _bloom if flower else (_mat if layer == Layer.MAT else _density)
	var sizes := _size
	var lows := _low
	var tones := _tone
	var crowds := _crowd
	var patches := _patch
	var kinds := _kinds
	var blooms := _blooms
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
			var share := node * FLOWER_STOPS
			var which := int(second >= blooms[share]) + int(second >= blooms[share + 1]) + int(second >= blooms[share + 2]) \
				+ int(second >= blooms[share + 3]) + int(second >= blooms[share + 4])
			var bloom: int = FLOWERS[which]
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
			var share := node * KIND_STOPS
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
				tone = minf(tone, GREEN_TONE)
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

## How well the sward does at a place, about 0 (poor) .. 1 (rank): `swathe`
## and `ragged` are the macro noise in broad swathes and at their edges;
## `foot` is the foot of a rock or a wall, or a path's wayside. sward_at() of
## terrain_fields.gdshaderinc is the same sum.
static func sward(swathe: float, ragged: float, moist: float, foot: float, dry: float, cold: float) -> float:
	return 0.5 + (swathe - 0.5) * 1.3 + (ragged - 0.5) * 0.5 + 0.45 * moist + 0.3 * foot - 0.55 * dry - 0.35 * cold

## The sward's tone at a place (see PLAIN_TONE). A rank sward is the deep
## green, and wet ground and shade keep the growth dark; a poor sward, thin
## dry soil and the cold of the heights dry the grass on the stalk. `ragged`
## and `fine` are the macro noise in patches tens of metres across and a few:
## no meadow is of one colour. sward_at() of terrain_fields.gdshaderinc is the
## same sum, by which the terrain colours the ground under the plants.
static func sward_tone(ragged: float, fine: float, poor: float, rank: float, dry: float, cold: float, moist: float,
		shade: float) -> float:
	return clampf(PLAIN_TONE + (ragged - 0.5) * 0.5 + (fine - 0.5) * 0.4 + 0.4 * poor + 0.3 * dry + 0.1 * cold
		- 0.15 * moist - 0.15 * shade - 0.15 * rank, 0.0, 1.0)

## The most of one channel (0..1) of a mask at the eight texels `reach` away
## from (mx, mz).
func _around(mask: PackedByteArray, mx: int, mz: int, channel: int, reach: int) -> float:
	var size := ground.mask_size
	var most := 0
	for dz in range(-reach, reach + 1, reach):
		var row := mz + dz
		if row < 0 or row >= size:
			continue
		for dx in range(-reach, reach + 1, reach):
			var column := mx + dx
			if column >= 0 and column < size:
				most = maxi(most, mask[(row * size + column) * 4 + channel])
	return most / 255.0

## Whether something solid covers the ground a metre from (x, z) on any side.
func _beside_cover(x: float, z: float) -> bool:
	var g := ground
	if g.cover.is_empty():
		return false
	var cx := int(floorf((x - g.cover_origin.x) / g.cover_cell + 0.5))
	var cz := int(floorf((z - g.cover_origin.y) / g.cover_cell + 0.5))
	var step := maxi(int(roundf(1.0 / g.cover_cell)), 1)
	for dz in range(-step, step + 1, step):
		var row := cz + dz
		if row < 0 or row >= g.cover_size.y:
			continue
		for dx in range(-step, step + 1, step):
			var column := cx + dx
			if column >= 0 and column < g.cover_size.x and g.cover[row * g.cover_size.x + column] > 0:
				return true
	return false

## One channel (0..1) of the far masks at a world position, bilinear.
func _far(x: float, z: float, channel: int) -> float:
	var g := ground
	if g.far.is_empty():
		return 0.0
	var fx := clampf((x - g.far_origin.x) / g.far_cell, 0.0, g.far_size.x - 1.001)
	var fz := clampf((z - g.far_origin.y) / g.far_cell, 0.0, g.far_size.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var at := (iz * g.far_size.x + ix) * 4 + channel
	var row := g.far_size.x * 4
	var top := lerpf(g.far[at], g.far[at + 4], tx)
	var bottom := lerpf(g.far[at + row], g.far[at + row + 4], tx)
	return lerpf(top, bottom, fz - iz) / 255.0

## One channel (0..1) of the macro noise at uv (wrapping), nearest sample.
func _macro(u: float, v: float, channel: int) -> float:
	var g := ground
	if g.macro_size == 0:
		return 0.5
	var ix := posmod(int(floorf(u * g.macro_size)), g.macro_size)
	var iy := posmod(int(floorf(v * g.macro_size)), g.macro_size)
	return g.macro[(iy * g.macro_size + ix) * 4 + channel] / 255.0
