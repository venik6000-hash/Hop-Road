class_name GrassSurvey
extends RefCounted
## What grows where over one tile of GrassField, at the nodes of a 1 m grid:
## the fields a tile job (grass_tile_job.gd) scatters its clumps by.
##
## What grows where follows the ground, as on a real alpine meadow. At the
## masks' 1 m nodes the survey works out how wet the soil is (the brook's
## banks, the lake's margin, gullies, hollows), how dry and thin (steep and
## sunward slopes, rock near the surface), how shaded (the crowns over it,
## from the canopy field) and how closed the stand round it is, whether a
## crown's fringe is near, how trodden (the rim of a path) and whether a path
## runs by, how high and cold, and whether something solid stands beside (a
## wall, a fence, a boulder).
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
## walls, celandine in damp half-shade, knapweed among rank grass in seed).
##
## Under and between these stands the mat (GrassClump.MAT): rosettes of
## loose low blades. It covers the ground wherever grass grows, skirts every
## patch of it on thin ground and runs out onto stonier ground than the grass
## holds, the edge of a path or of scree, growing smaller as it goes: a
## meadow has no edge cut with a knife, and seen from above no bare soil
## between its plants.

const CanopyField = preload("res://src/vegetation/canopy_field.gd")

## Heights are sampled every GRAIN metres, the fields every NODE metres.
const GRAIN := 0.5
const NODE := 1.0
## Wide plants leave room round them: the share of a leafy stalk's, a fern's
## and a shrub's places that are taken.
const LUSH_FILL := 0.62
const FERN_FILL := 0.45
const SHRUB_FILL := 0.5
## The flowers in the order their shares are kept in (flower_reach).
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

## The fields, one number a node, row by row along z: the chance that a
## clump grows there, its size and tone, how closely tall plants stand
## (GrassScatter's crowd), the chance that a flower blooms and the flowers'
## patch.
var densities := PackedFloat32Array()
var sizes := PackedFloat32Array()
var tones := PackedFloat32Array()
var crowds := PackedFloat32Array()
var bloom_chances := PackedFloat32Array()
var flower_patches := PackedFloat32Array()
## The chance that a clump of the mat grows at the node, and the size of low
## growth there (the mat's, and the turf's among the grass).
var mat_chances := PackedFloat32Array()
var low_sizes := PackedFloat32Array()
## Per node, where each kind's share ends along 0..1, in GrassClump.Kind's
## order (KIND_STOPS numbers; past the last nothing grows), and where each
## flower's does, in FLOWERS' order (FLOWER_STOPS numbers; the rest is the
## last).
var kind_reach := PackedFloat32Array()
var flower_reach := PackedFloat32Array()

## Fills the fields over the square of `side` metres (a whole number of NODE)
## from `origin` (x, z): `heights` every GRAIN from origin - GRAIN to origin +
## side + GRAIN, row by row along z; `crowns` the trees whose crowns may reach
## it (x, z, the crown's radius and its shade of each, one after another).
func run(ground: GrassGround, origin: Vector2, side: float, heights: PackedFloat32Array,
		crowns: PackedFloat32Array) -> void:
	var g := ground
	var nodes := int(side / NODE) + 1
	var width := int(side / GRAIN) + 3
	var per_node := int(NODE / GRAIN)
	densities.resize(nodes * nodes)
	sizes.resize(nodes * nodes)
	tones.resize(nodes * nodes)
	crowds.resize(nodes * nodes)
	bloom_chances.resize(nodes * nodes)
	flower_patches.resize(nodes * nodes)
	mat_chances.resize(nodes * nodes)
	low_sizes.resize(nodes * nodes)
	kind_reach.resize(nodes * nodes * KIND_STOPS)
	flower_reach.resize(nodes * nodes * FLOWER_STOPS)
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
					maxf(0.8 * g.around(g.extra, mx, mz, 1, 2), 0.5 * g.around(g.extra, mx, mz, 1, 4)))
				trodden = maxf(path, 0.7 * g.around(g.control, mx, mz, 0, 1))
				# The two or three metres beyond the rim are a path's wayside.
				wayside = maxf(g.around(g.control, mx, mz, 0, 2), 0.8 * g.around(g.control, mx, mz, 0, 3))
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
			var snow := g.far_at(x, z, 0)
			var bare_rock := g.far_at(x, z, 1)
			var gully := g.far_at(x, z, 3)

			# -- The site. Broad patches come from the terrain's macro noise:
			# dry ones hundreds of metres across, swathes of rank and of poor
			# grass tens of metres across, tone, height and thickets a few metres
			# across.
			var lakeside := (1.0 - smoothstep(2.0, 14.0, shore)) * (1.0 - smoothstep(1.5, 4.0, above))
			var moist := clampf(maxf(wet, lakeside) + 0.7 * gully + 0.5 * hollow, 0.0, 1.0)
			var parched := smoothstep(0.5, 0.82, g.macro_at(x / 430.0, z / 430.0, 0)) * 0.45
			var rim := smoothstep(0.01, 0.08, outcrop)
			var dry := clampf(smoothstep(0.04, 0.2, slope) * (0.45 + 0.55 * clampf(sunward * 3.0 + 0.5, 0.0, 1.0))
				+ 0.6 * bare_rock + parched, 0.0, 1.0) * (1.0 - moist)
			var forest := CanopyField.floor_of(wooded)
			var woodland := smoothstep(0.3, 0.8, forest)
			var verge := smoothstep(0.03, 0.3, trodden)
			var strand := smoothstep(0.01, 0.15, beach)
			var high := smoothstep(HEIGHTS.x, HEIGHTS.y, above)
			var cold := maxf(high, smoothstep(0.02, 0.15, snow))
			var beside := 1.0 if g.beside_cover(x, z) else 0.0
			# Nothing treads or grazes a path's wayside: the grass stands tall
			# there as at the foot of a wall, in stretches a few metres long.
			var uncut := smoothstep(0.2, 0.6, wayside) * (1.0 - verge) \
				* smoothstep(0.55, 0.75, g.macro_at(x / WAYSIDE.x + WAYSIDE.y, z / WAYSIDE.x + WAYSIDE.y, 2))
			var ragged := g.macro_at(x / 61.0 + 0.37, z / 61.0 + 0.37, 0)
			var vigour := sward(g.macro_at(x / SWATHE.x + SWATHE.y, z / SWATHE.x + SWATHE.y, 1), ragged, moist,
				maxf(maxf(rim, beside), uncut), dry, cold)
			var rank := smoothstep(RANK.x, RANK.y, vigour)
			var poor := 1.0 - smoothstep(POOR.x, POOR.y, vigour)
			var thicket := g.macro_at(x / 31.0 + 0.83, z / 31.0 + 0.83, 2)
			var tall := g.macro_at(x / 23.0 + 0.61, z / 23.0 + 0.61, 1)

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
			var patchy := clampf(0.5 + (g.macro_at(x / 19.0 + 0.47, z / 19.0 + 0.47, 1) - 0.5) * 1.8, 0.0, 1.0)
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
			var stands := smoothstep(0.42, 0.62, g.macro_at(x / 27.0 + 0.11, z / 27.0 + 0.11, 0))
			var lush := (1.8 * moist * stands + 1.4 * beside * smoothstep(0.35, 0.6, thicket)
				+ 0.8 * fringe * smoothstep(0.3, 0.6, thicket) + 0.5 * smoothstep(0.74, 0.86, thicket)) \
				* (1.0 - 0.8 * cold) * (1.0 - verge) * (1.0 - 0.7 * dry)
			# Ferns take the shade the grasses leave, in colonies.
			var fern := (1.4 * shade + 0.7 * fringe + 0.5 * woodland * (1.0 - shade)) * (1.0 - 0.7 * dry) \
				* (1.0 - 0.8 * cold) * (1.0 - verge) * smoothstep(0.3, 0.55, g.macro_at(x / 17.0 + 0.91, z / 17.0 + 0.91, 2))
			# Willows and alder on wet ground, as on a bank.
			var shrub := (0.8 * fringe + 0.5 * shade + 0.8 * rim + 0.5 * beside + 0.4 * high + 0.5 * moist) \
				* smoothstep(0.45, 0.7, thicket)
			var sum := seeding + green + turf + lush + fern + shrub
			var n := j * nodes + i
			var reach := seeding / sum
			kind_reach[n * KIND_STOPS] = reach
			reach += green / sum
			kind_reach[n * KIND_STOPS + 1] = reach
			reach += turf / sum
			kind_reach[n * KIND_STOPS + 2] = reach
			reach += lush / sum * LUSH_FILL
			kind_reach[n * KIND_STOPS + 3] = reach
			reach += fern / sum * FERN_FILL
			kind_reach[n * KIND_STOPS + 4] = reach
			reach += shrub / sum * SHRUB_FILL
			kind_reach[n * KIND_STOPS + 5] = reach
			densities[n] = density
			sizes[n] = lerpf(0.8, 1.2, tall) * lerpf(1.0, 1.15, moist) * lerpf(1.0, 0.7, dry) * lerpf(1.0, 0.65, cold) \
				* lerpf(1.0, 0.75, shade) * lerpf(1.0, 0.55, verge) * lerpf(0.6, 1.0, thin) * lerpf(0.7, 1.0, density) \
				* lerpf(1.0, 0.55, poor) * lerpf(0.82, 1.05, rank) * lerpf(1.0, 1.2, uncut)
			tones[n] = sward_tone(ragged, g.macro_at(x / 17.0 + 0.53, z / 17.0 + 0.53, 1), poor, rank, dry, cold, moist, shade)
			crowds[n] = density * (1.0 - turf / sum)
			mat_chances[n] = mat
			low_sizes[n] = lerpf(0.55, 1.0, low) * lerpf(0.6, 1.0, mat) * lerpf(1.0, 0.8, dry) * lerpf(1.0, 0.75, cold) \
				* lerpf(1.0, 0.6, verge)

			# -- Flowers: everywhere on open meadow, thick in clusters a few
			# metres across where the terrain's flower mask says so, one kind
			# to a patch.
			var clusters := g.macro_at(x / 25.0 + 0.23, z / 25.0 + 0.23, 0)
			var in_bloom := smoothstep(0.15, 0.8, meadow * smoothstep(0.3, 0.7, clusters) * 1.6)
			# They bloom on the mat too, where no tall grass stands over it.
			bloom_chances[n] = maxf(density, 0.6 * mat) * (1.0 - shade) * (1.0 - 0.7 * verge) * maxf(in_bloom, 0.12)
			flower_patches[n] = g.macro_at(x / 55.0 + 0.71, z / 55.0 + 0.71, 2)
			var buttercup := 0.7 + 1.6 * moist
			var yarrow := 0.55 + 1.1 * dry + 0.9 * verge
			var bellflower := 0.4 + 1.2 * high + 0.8 * smoothstep(0.05, 0.2, slope) + 0.7 * rim + 0.5 * fringe
			var dandelion := 0.3 + 1.6 * verge + 0.8 * beside
			var celandine := 0.1 + 1.0 * moist + 1.0 * fringe + 0.8 * woodland
			var knapweed := 0.5 + 0.9 * rank * (1.0 - cold) * (1.0 - moist)
			var blooms := buttercup + yarrow + bellflower + dandelion + celandine + knapweed
			var bloomed := buttercup / blooms
			flower_reach[n * FLOWER_STOPS] = bloomed
			bloomed += yarrow / blooms
			flower_reach[n * FLOWER_STOPS + 1] = bloomed
			bloomed += bellflower / blooms
			flower_reach[n * FLOWER_STOPS + 2] = bloomed
			bloomed += dandelion / blooms
			flower_reach[n * FLOWER_STOPS + 3] = bloomed
			bloomed += celandine / blooms
			flower_reach[n * FLOWER_STOPS + 4] = bloomed

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
