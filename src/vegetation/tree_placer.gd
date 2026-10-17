class_name TreePlacer
extends RefCounted
## Deterministic tree placement over the generated terrain.
##
## Three sources feed one TreeSet:
## 1. The Blender composition (assets/models/alpine/woodland.json): the framing
##    trees around the tavern keep their spot and turn, mapped onto the new
##    species and re-seated on the new ground; the dense backdrop forest of
##    that scene keeps its footprint but thins out towards the rectangle it was
##    scattered in, so it merges with the mask forest instead of ending in a
##    straight line.
## 2. The detail region (the walkable near field plus the margin the camera can
##    see up close): a jittered 4 m lattice where each cell holds one candidate
##    that survives with a probability proportional to the forest masks.
##    Candidates too close to an accepted trunk in the neighbouring cells are
##    dropped, which keeps trunks apart without showing the lattice.
## 3. The far field: the same lattice, coarsened per 256 m block with distance
##    from the walkable area. Density falls off beyond THIN_START and the
##    remaining crowns are widened so the canopy still reads as closed forest
##    from the valley floor.
##
## Every random choice comes from integer hashes of lattice coordinates, so the
## result depends only on the terrain fields, never on iteration order or
## threads. The hot loops are written out by hand: GDScript function calls
## cost more than the arithmetic they would wrap, and the far pass looks at
## about a million candidates.

const Composed = preload("res://src/vegetation/tree_pass_composed.gd")
const Detail = preload("res://src/vegetation/tree_pass_detail.gd")
const Far = preload("res://src/vegetation/tree_pass_far.gd")

## Bump when the placement changes, so cached placements are recomputed.
const VERSION := 2
const SPECIES_NAMES := ["spruce_a", "spruce_b", "spruce_c", "fir_young", "beech_a", "beech_b", "pine_a", "pine_b",
	"pine_c"]
const SPRUCE_A := 0
const SPRUCE_B := 1
const SPRUCE_C := 2
const FIR_YOUNG := 3
const BEECH_A := 4
const BEECH_B := 5
const PINE_A := 6
const PINE_B := 7
const PINE_C := 8
## Look groups: species of one group share bark and leaf textures and light.
const GROUP_CONIFER := 0
const GROUP_BROADLEAF := 1
const GROUP_PINE := 2
const SPECIES_GROUP := [GROUP_CONIFER, GROUP_CONIFER, GROUP_CONIFER, GROUP_CONIFER,
	GROUP_BROADLEAF, GROUP_BROADLEAF, GROUP_PINE, GROUP_PINE, GROUP_PINE]
## Model height (m) at scale 1, from assets/models/source/vegetation/trees_summary.json.
const SPECIES_HEIGHT := [24.5, 17.5, 20.0, 4.5, 17.3, 14.1, 20.3, 14.8, 17.5]
## Trunk-to-trunk distance (m) kept free around a tree of scale 1.
const SPECIES_SPACING := [3.0, 2.6, 3.4, 1.3, 4.5, 4.0, 3.2, 2.8, 3.0]
## Crown radius (m) at scale 1: buildings stay about this far from the trunk.
const SPECIES_CROWN := [3.4, 3.0, 3.8, 1.1, 6.5, 5.5, 4.0, 3.2, 3.6]
## How far a tree's foot spreads from its axis at scale 1, m: the root plate
## of a scanned trunk, the collar of a grown beech, the bare stem of a trunk
## cut to stand in the ground.
const FOOT_REACH := [0.9, 0.9, 0.2, 0.05, 0.5, 0.45, 0.7, 0.7, 0.7]
## A tree is let into a slope no deeper than this, m.
const SEAT_DEPTH := 0.7

## Ground area per tree where the forest mask is 1 (a closed spruce stand).
const AREA_PER_TREE := 30.0
const DETAIL_CELL := 4.0
## How far past the walkable near field trees still get mesh LODs.
const DETAIL_MARGIN := 260.0
## Beyond this distance from the walkable area far forests thin out.
const THIN_START := 900.0
const THIN_POWER := 1.5
const MAX_WIDEN := 4.0
const FAR_BLOCK := 256.0
const MAX_FAR_CELL := 64.0
## Far trees stop this far from the walkable area (hidden behind the ridges).
const FAR_REACH := 7500.0
## Tree line (m above the lake), as in far_masks of
## tools/pipeline/terrain/terrain.py.
const TREE_LINE := 1050.0
const SALT_CELL := 11
const SALT_PATCH := 37
const SALT_EDGE := 41

## Blender composition templates: [species picked by hash, template height (m),
## height gain]. The old scene was built somewhat under life size.
const COMPOSED := {
	"oak_hero": [[BEECH_A], 11.0, 1.2],
	"beech": [[BEECH_A, BEECH_B], 8.3, 1.35],
	"birch": [[BEECH_B], 7.4, 1.3],
	"Young meadow oak": [[BEECH_B, BEECH_A], 6.3, 1.25],
	"Mountain fir": [[SPRUCE_C, SPRUCE_B], 10.5, 1.3],
	"Narrow alpine spruce": [[SPRUCE_C], 8.5, 1.35],
	"Dense distant fir sprays": [[SPRUCE_B, SPRUCE_A, PINE_B, SPRUCE_B, SPRUCE_C, FIR_YOUNG, PINE_A], 11.0, 1.35],
	"Dense distant deciduous crown": [[BEECH_A, BEECH_B], 8.5, 1.35],
}
## The rectangle the Blender backdrop forest was scattered in (Godot x/z).
const BACKDROP := Rect2(-112.0, -174.0, 236.0, 95.0)
const PATCH_COARSE := 150.0
const PATCH_FINE := 57.0
## Pines read the patch noise this far away, so their groups are not the
## beech's; this shift puts pines into the woods around the village.
const PINE_SHIFT := Vector2(1000.0, -1000.0)

var terrain: VegetationTerrain
var near_rect: Rect2
var detail_rect: Rect2
var far_rect: Rect2
var trees := TreeSet.new()
## Accepted composed trees on an 8 m grid, to keep the lattice pass clear of them.
var composed_grid := {}
var composed_bounds := Rect2()
var has_composed := false
var _patch_coarse := PackedFloat32Array()
var _patch_fine := PackedFloat32Array()
var _patch_origin := Vector2.ZERO
var _patch_coarse_n := 0
var _patch_fine_n := 0

func _init(fields: VegetationTerrain) -> void:
	terrain = fields
	near_rect = Rect2(fields.near_origin, Vector2.ONE * fields.near_cell * (fields.near_size - 1))
	detail_rect = near_rect.grow(DETAIL_MARGIN)
	far_rect = Rect2(fields.far_origin, Vector2.ONE * fields.far_cell * (fields.far_size - 1))
	_build_patches()

## Runs all three passes; `composed` is the "trees" array of woodland.json.
func place_all(composed: Array) -> TreeSet:
	place_composed(composed)
	place_detail()
	place_far()
	return trees

func place_composed(composed: Array) -> void:
	Composed.place_composed(self, composed)

func place_detail() -> void:
	Detail.place_detail(self)

func place_far() -> void:
	Far.place_far(self)

# --- hashing and noise -----------------------------------------------------

static func hash_u32(value: int) -> int:
	var h := value & 0xffffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff
	return (h >> 16) ^ h

static func cell_hash(ix: int, iz: int, salt: int) -> int:
	return hash_u32((ix * 73856093) ^ (iz * 19349663) ^ (salt * 83492791))

## 0..1 from the low 24 bits of a hash.
static func unit(h: int) -> float:
	return float(h & 0xffffff) / 16777216.0

static func rect_rect_distance(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)

## Fraction of the full forest density kept at `distance` from the walkable area.
static func thinning(distance: float) -> float:
	if distance <= THIN_START:
		return 1.0
	return pow(THIN_START / distance, THIN_POWER)

## Crown widening that keeps canopy cover when density is thinned by `thin`.
static func widening(thin: float) -> float:
	return clampf(1.0 / sqrt(thin), 1.0, MAX_WIDEN)

## Lattice cell (m) for a block whose densest point keeps `thin` of full density:
## the largest power-of-two multiple of DETAIL_CELL that still offers at least
## one candidate per expected tree.
static func far_cell_size(thin: float) -> float:
	var limit := sqrt(AREA_PER_TREE / maxf(thin, 1e-4))
	var cell := DETAIL_CELL
	while cell * 2.0 <= limit and cell * 2.0 <= MAX_FAR_CELL:
		cell *= 2.0
	return cell

func _build_patches() -> void:
	_patch_origin = far_rect.position - Vector2.ONE * PATCH_COARSE
	_patch_coarse_n = ceili((far_rect.size.x + 2.0 * PATCH_COARSE) / PATCH_COARSE) + 2
	_patch_fine_n = ceili((far_rect.size.x + 2.0 * PATCH_COARSE) / PATCH_FINE) + 2
	_patch_coarse = _lattice(_patch_coarse_n, SALT_PATCH)
	_patch_fine = _lattice(_patch_fine_n, SALT_PATCH + 1)

static func _lattice(n: int, salt: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(n * n)
	for iz in n:
		for ix in n:
			values[iz * n + ix] = unit(cell_hash(ix, iz, salt))
	return values

## Two octaves of smooth value noise (0..1): where beech stands in patches,
## and, read at PINE_SHIFT from there, where pines do.
func patch(x: float, z: float) -> float:
	return _smooth(_patch_coarse, _patch_coarse_n, PATCH_COARSE, x, z) * 0.65 \
		+ _smooth(_patch_fine, _patch_fine_n, PATCH_FINE, x, z) * 0.35

func _smooth(values: PackedFloat32Array, n: int, size: float, x: float, z: float) -> float:
	var fx := clampf((x - _patch_origin.x) / size, 0.0, n - 1.001)
	var fz := clampf((z - _patch_origin.y) / size, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var i := iz * n + ix
	return lerpf(lerpf(values[i], values[i + 1], tx), lerpf(values[i + n], values[i + n + 1], tx), tz)

# --- species ---------------------------------------------------------------

## Species (x) and scale (y) for a tree at `altitude` metres above the lake.
## `density` is the local forest density: open edges get more young firs and
## smaller trees; beech keeps to the lower valley, in patches. Pines stand in
## groups among the spruces, about a third of them, fewer towards the tree line.
## Of the spruces, A and B have grown in a close wood and are bare for the lower
## third of the trunk, C is green to the ground: the more open the stand, the
## more of them are C.
func choose(x: float, z: float, altitude: float, density: float, pick: int) -> Vector2:
	var r1 := unit(pick)
	var r2 := unit(hash_u32(pick ^ 0x5bd1e995))
	var r3 := unit(hash_u32(pick + 0x27d4eb2d))
	var line := smoothstep(TREE_LINE - 260.0, TREE_LINE, altitude)
	var broadleaf := clampf(0.5 * (1.0 - smoothstep(110.0, 460.0, altitude)) + (patch(x, z) - 0.5) * 1.1, 0.0, 0.85)
	var kind := SPRUCE_A
	var grow := 0.78 + 0.36 * r3
	if r1 < broadleaf:
		kind = BEECH_A if r2 < 0.5 else BEECH_B
		grow = 0.72 + 0.4 * r3
	else:
		var young := 0.07 + 0.22 * (1.0 - density) + 0.3 * line
		if r2 < young:
			kind = FIR_YOUNG
			grow = 0.7 + 0.75 * r3
		else:
			var t := (r2 - young) / (1.0 - young)
			var pines := clampf(0.3 + (patch(x + PINE_SHIFT.x, z + PINE_SHIFT.y) - 0.5) * 1.6, 0.0, 0.8) \
				* (1.0 - 0.7 * line)
			if t < pines:
				t /= pines
				kind = PINE_A if t < 0.4 else (PINE_B if t < 0.7 else PINE_C)
			else:
				t = (t - pines) / (1.0 - pines)
				var open := lerpf(0.7, 0.15, density)
				if t < open:
					kind = SPRUCE_C
				else:
					kind = SPRUCE_A if (t - open) / (1.0 - open) < 0.55 else SPRUCE_B
	if kind != FIR_YOUNG:
		grow *= (1.0 - 0.45 * line) * (0.82 + 0.18 * density)
	return Vector2(kind, grow)

## Smooth value noise, 0..1, features about `size` metres across.
static func value_noise(x: float, z: float, size: float, salt: int) -> float:
	var fx := x / size
	var fz := z / size
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var a := unit(cell_hash(ix, iz, salt))
	var b := unit(cell_hash(ix + 1, iz, salt))
	var c := unit(cell_hash(ix, iz + 1, salt))
	var d := unit(cell_hash(ix + 1, iz + 1, salt))
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

## The height a tree of `kind`, grown `grow` times, stands at where the ground
## at (x, z) is `ground` high: let into a slope until the downhill side of its
## foot meets the ground, as the trunk of a tree that rose there would be. On
## the level the model's own foot hides in the ground; on a slope it would
## stand out over it like a plate.
static func seat(fields: VegetationTerrain, x: float, z: float, ground: float, kind: int, grow: float) -> float:
	var reach: float = FOOT_REACH[kind] * grow
	var lowest := ground
	for turn in 8:
		var side := Vector2.from_angle(turn * TAU / 8.0) * reach
		lowest = minf(lowest, fields.height(x + side.x, z + side.y))
	return maxf(lowest, ground - SEAT_DEPTH)

## Dry, open ground: above the lake and its wet margin, off paths and beaches,
## and `clearance` metres from buildings and props.
func ground_ok(x: float, z: float, clearance: float, path_limit: float) -> bool:
	if terrain.height(x, z) < terrain.water_level + 0.6:
		return false
	if terrain.near_weight(x, z) <= 0.0:
		return true
	if terrain.shore_distance(x, z) < 2.5:
		return false
	if terrain.control_at(x, z, 0) > path_limit:
		return false
	if terrain.control_at(x, z, 1) > 0.5:
		return false
	return terrain.obstacle_clear(x, z, clearance)
