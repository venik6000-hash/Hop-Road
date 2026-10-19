class_name LakeBed
extends Node3D
## The bed of the mountain lake: drowned trees and boulders from the valley's
## scans, and the freshwater plants of a cold clear lake, placed on the real
## terrain and rock faces.
##
## Zonation follows a real alpine lake. Reed stands (Phragmites) rise from
## sheltered shallows up to knee deep; pondweed (Potamogeton) stems reach up
## from a metre or three; eelgrass (Vallisneria) meadows carpet the gentle
## slopes between one and five metres; stonewort (Chara) cushions sit on the
## silt below. Trunks and branches lie on the slopes where the forest meets
## the water, the stumps of the drowned shore forest stand in their silted
## root mounds, bark and small stones around them.
##
## Everything lies on the bed as it is drawn (TerrainSystem.height_at, not the
## coarser physics grid) or on a lake boulder. A scanned piece is tilted to
## the plane of the bed under its footprint and lowered until its underside
## rests there; a spot where it would bridge a hollow, slide down a steep
## slope, stand on something built or reach the surface is passed over.
const Ground = preload("res://src/wildlife/lake_bed_ground.gd")
const Boulders = preload("res://src/wildlife/lake_bed_boulders.gd")
const Wood = preload("res://src/wildlife/lake_bed_wood.gd")
const Plants = preload("res://src/wildlife/lake_bed_plants.gd")
const Batches = preload("res://src/wildlife/lake_bed_batches.gd")
const DIRECTORY := "res://assets/models/lakebed/"
const TILE := 24.0
## Nothing drowned comes closer to the surface than this (m).
const CLEARANCE := 0.35
## Steepest bed a scanned piece comes to rest on (degrees).
const STEEPEST := 32.0
## Sunken wood: kind, how many, depth band (m), how far it sinks into the bed
## (share of its scale), scale, steepest bed it lies on (degrees).
const WOOD := [
	{"kind": "sunken_trunk_a", "count": 12, "depth": Vector2(1.4, 7.5), "sink": 0.05, "size": Vector2(1.6, 2.6), "steepest": STEEPEST},
	{"kind": "sunken_trunk_b", "count": 10, "depth": Vector2(2.0, 8.5), "sink": 0.12, "size": Vector2(1.3, 2.0), "steepest": STEEPEST},
	{"kind": "stump_a", "count": 6, "depth": Vector2(1.8, 12.0), "sink": 0.08, "size": Vector2(1.2, 1.9), "steepest": 18.0},
	{"kind": "stump_b", "count": 5, "depth": Vector2(1.6, 12.0), "sink": 0.08, "size": Vector2(1.1, 1.8), "steepest": 18.0},
	{"kind": "driftwood", "count": 14, "depth": Vector2(0.8, 6.0), "sink": 0.03, "size": Vector2(1.0, 1.7), "steepest": STEEPEST},
	{"kind": "branches", "count": 10, "depth": Vector2(0.8, 7.0), "sink": 0.02, "size": Vector2(1.1, 1.8), "steepest": STEEPEST},
]
## Litter: kind, how many around each piece of wood and each boulder group,
## scatter radius (m), how many more anywhere in the depth band, how far it
## sinks into the bed (share of its scale), scale. The stones are a scanned
## patch of sand and pebbles: sunk until only the pebbles break the silt.
const LITTER := [
	{"kind": "bark_debris", "per_wood": 1, "per_boulder": 0.0, "radius": 3.0, "loose": 0, "depth": Vector2(0.6, 9.0),
		"sink": 0.02, "size": Vector2(0.7, 1.3)},
	{"kind": "lake_stones", "per_wood": 0, "per_boulder": 0.6, "radius": 4.5, "loose": 22, "depth": Vector2(0.7, 9.0),
		"sink": 0.09, "size": Vector2(0.6, 1.1)},
]
## Boulder groups: how many, depth band (m), width of the big stone and of the
## smaller ones that lie around it (m).
const BOULDERS := {"groups": 28, "depth": Vector2(1.4, 10.0), "width": Vector2(2.0, 4.5), "satellites": Vector2i(0, 3),
	"satellite_width": Vector2(0.6, 1.5)}
## Plant kinds: model variants, height for the current bend (m), depth band
## (m, negative = above the waterline on the wet shore), steepest bed (rise
## per m), spacing in a patch (m), number of patches and their radius (m).
const PLANTS := {
	"eelgrass": {"variants": 3, "height": 1.25, "depth": Vector2(1.2, 5.2), "slope": 0.5, "spacing": 0.7,
		"patches": 46, "radius": Vector2(4.0, 9.0), "range": 50.0, "size": Vector2(0.7, 1.25)},
	"pondweed": {"variants": 3, "height": 1.0, "depth": Vector2(0.9, 3.4), "slope": 0.55, "spacing": 1.5,
		"patches": 32, "radius": Vector2(2.5, 5.5), "range": 48.0, "size": Vector2(0.75, 1.2)},
	"chara": {"variants": 2, "height": 0.26, "depth": Vector2(2.6, 8.5), "slope": 0.4, "spacing": 0.75,
		"patches": 40, "radius": Vector2(3.0, 7.0), "range": 34.0, "size": Vector2(0.8, 1.5)},
	"reed": {"variants": 3, "height": 2.2, "depth": Vector2(-0.4, 0.9), "slope": 0.6, "spacing": 0.8,
		"patches": 28, "radius": Vector2(2.0, 5.5), "range": 150.0, "size": Vector2(0.8, 1.15)},
}
## Through the water a thing is seen nearer the eye than it lies, by no more
## than this share of its depth (the steepest a ray goes down under a flat
## surface, and what the waves add), and this much (m) for its swaying.
const SEEN_SPREAD := 1.5
const SEEN_SWAY := 1.0

var habitat: WildlifeSystem
## Where the bed is searched, the shores without reeds and the reed beds
## (RegionDef.lake).
var plan: LakePlan
## Bed points under the centre of each piece of wood and each boulder group.
var wood_places: Array[Vector3] = []
var boulder_places: Array[Vector3] = []
var meadow_centers: Array[Vector3] = []
var reed_centers: Array[Vector3] = []
## Every scanned piece laid on the bed: {"kind", "transform"} (boulders not included).
var pieces: Array[Dictionary] = []
var plant_count := 0
var wood_count := 0
var rock_count := 0
var reed_material: ShaderMaterial
var rng := RandomNumberGenerator.new()
var _floor_cache: Dictionary = {}
var groups: Dictionary = {}
var materials: Dictionary = {}
var shapes: Dictionary = {}
var boulder_groups: Dictionary = {}
## Footprints of the drowned wood on the bed: {"center": Vector2, "u": Vector2, "v": Vector2, "half": Vector2}.
var wood_footprints: Array[Dictionary] = []
var solid: StaticBody3D

func build() -> void:
	rng.seed = 68249
	solid = StaticBody3D.new()
	solid.name = "LakeRockFaces"
	solid.collision_layer = PhysicsLayers.BOULDERS
	add_child(solid)
	Boulders.place(self)
	# The stones just laid enter the physics space at the next step: the wood
	# and the plants settle on them.
	await get_tree().physics_frame
	Wood.place(self)
	Wood.litter(self)
	for kind: String in PLANTS:
		Plants.place(self, kind)
	Batches.build(self)

## The reeds' level of detail is for the eye at `eye` (they bend in the
## global `wind`, as the trees).
func follow(eye: Vector3) -> void:
	if reed_material != null:
		reed_material.set_shader_parameter("lod_camera", eye)

## Height of the bed (terrain or a boulder) under a point, cached per metre.
func seabed_at(x: float, z: float) -> float:
	var cell := Vector2i(roundi(x), roundi(z))
	if not _floor_cache.has(cell):
		var bed := Ground.bed_at(self, cell.x, cell.y, true)
		_floor_cache[cell] = bed if not is_nan(bed) else habitat.terrain.height_at(cell.x, cell.y)
	return maxf(Values.real(_floor_cache[cell]), habitat.terrain.height_at(x, z))

## The box an eye over the lake may see `piece` in (seen_box()).
func seen_bounds(piece: GeometryInstance3D) -> AABB:
	return seen_box(piece.global_transform * piece.get_aabb(), habitat.terrain.water_level)

## The box an eye over water at `water_level` may see in what fills `box`:
## the box itself, up to the surface over it, and as much wider as the water
## shifts what lies deep.
static func seen_box(box: AABB, water_level: float) -> AABB:
	box = box.grow(SEEN_SWAY)
	var depth := water_level - box.position.y
	if depth <= 0.0:
		return box
	var spread := depth * SEEN_SPREAD
	box.position -= Vector3(spread, 0.0, spread)
	box.size += Vector3(spread, 0.0, spread) * 2.0
	box.size.y = maxf(box.size.y, depth)
	return box
