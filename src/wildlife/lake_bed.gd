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
## The lake boulders' body answers on this layer as well as the world's, so
## the bed can be read without the pier or the shore stones answering.
const BOULDER_LAYER := 16
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
## Where the lake is searched (world x, z).
const LAKE := Rect2(-192.0, -114.0, 165.0, 124.0)
## The village beach and pier (the beach zone of
## tools/pipeline/terrain/terrain.py): no reeds on the bathing shore (x range,
## z range).
const BEACH := Rect2(-132.0, -62.0, 106.0, 88.0)
const VILLAGE := Vector2(0.0, -35.0)
const POOL := Vector2(-50.0, -119.5)
## The cove under the waterfall cliff: bare rock and plunging water, no reeds.
const COVE := Rect2(-74.0, -142.0, 50.0, 38.0)
## The village's two marsh shores (tools/pipeline/terrain/terrain_village.py:
## the MARSH reaches of SHORE) are reed beds all the same, drawn stand by stand
## (x, z, radius): the corner of the bay by the bridge, with windows of open
## water between its stands, and the fishing cove, whose stands leave the way
## from the ditch's mouth to the lake clear for a boat.
const MARSH_STANDS: Array[Vector3] = [
	Vector3(-35.5, -25.0, 3.4), Vector3(-36.5, -20.0, 3.8), Vector3(-33.2, -17.4, 2.8), Vector3(-32.8, -22.2, 2.2),
	Vector3(-27.0, -72.6, 3.2), Vector3(-29.0, -69.8, 2.2), Vector3(-29.6, -74.0, 1.8), Vector3(-27.6, -81.6, 2.9),
	Vector3(-25.4, -80.4, 1.7),
]

var habitat: WildlifeSystem
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
var _rng := RandomNumberGenerator.new()
var _floor_cache: Dictionary = {}
var _groups: Dictionary = {}
var _materials: Dictionary = {}
var _shapes: Dictionary = {}
var _boulder_groups: Dictionary = {}
## Footprints of the drowned wood on the bed: {"center": Vector2, "u": Vector2, "v": Vector2, "half": Vector2}.
var _wood_footprints: Array[Dictionary] = []
var _solid: StaticBody3D

func build() -> void:
	_rng.seed = 68249
	_solid = StaticBody3D.new()
	_solid.name = "LakeRockFaces"
	_solid.collision_layer = 1 | BOULDER_LAYER
	add_child(_solid)
	Boulders.place(self)
	await get_tree().physics_frame
	Wood.place(self)
	Wood.litter(self)
	for kind: String in PLANTS:
		Plants.place(self, kind)
	Batches.build(self)

## The reeds bend in the wind that raises the waves.
func set_wind(wind: Vector4, eye: Vector3) -> void:
	if reed_material != null:
		reed_material.set_shader_parameter("wind", wind)
		reed_material.set_shader_parameter("lod_camera", eye)

## Height of the bed (terrain or a boulder) under a point, cached per metre.
func seabed_at(x: float, z: float) -> float:
	var cell := Vector2i(roundi(x), roundi(z))
	if not _floor_cache.has(cell):
		var bed := Ground.bed_at(self, cell.x, cell.y, true)
		_floor_cache[cell] = bed if not is_nan(bed) else habitat.terrain.height_at(cell.x, cell.y)
	return maxf(_floor_cache[cell], habitat.terrain.height_at(x, z))

# Kept for tools/probes/bed_probe.gd.
func _slope(point: Vector3) -> float:
	return Ground.slope(self, point)

func _reed_shore(point: Vector3) -> bool:
	return Plants.reed_shore(self, point)
