class_name RegionDef
extends Resource
## One region of the world: the ground it stands on and the files that fill
## it. The level (src/alpine/level.gd) builds what this names; another region
## is another such resource and its files (docs/LEVEL.md, «Области»).

## The valley of the tavern.
const VALLEY := "res://assets/regions/valley.tres"
## The regions of the game, the first one where a new game starts.
const LIST := "res://assets/regions/regions.json"

@export var id: StringName
@export var title := ""
## The land the region covers (world x, z). The terrain's far field covers it,
## and every spawn and zone lies in it.
@export var bounds := Rect2()

@export_group("Terrain")
## The fields of tools/pipeline/terrain/terrain.py: terrain.json, the
## heightfields, the masks and the layer textures.
@export_dir var terrain_dir := ""
## What the ground bake writes (TerrainBake): the near heights with the
## region's rocks, buildings and water courses laid in, the masks of the near
## field with the region's beds, yards and worn ground painted in, and the
## manifest with the courses. The recipe that lays them in belongs to the
## bake, by id.
@export_file("*.bin") var settled_heights := ""
@export_file("*.bin") var settled_masks := ""
@export_file("*.json") var settled_ground := ""

@export_group("Places")
## The named places (ValleyZones).
@export_file("*.json") var zones := ""
## Where a player comes into the region; the first one is the default.
@export var spawns: Array[RegionSpawn] = []

@export_group("Layout")
## The Blender map the level stands its systems in (node "Map"), and its
## lights and cameras (tools/pipeline/alpine_scene/export_godot.py).
@export var map: PackedScene
@export_file("*.json") var map_manifest := ""
## The pieces of the map the loaded level still shows, for the layout scene
## (tools/pipeline/layout/bake_map_context.gd).
@export_file("*.json") var map_context := ""
## The hand-placed objects (src/layout/layout_store.gd): houses and cottages,
## yard props, scanned stones, the forest's wood.
@export_file("*.json") var village_plan := ""
@export_file("*.json") var props := ""
@export_file("*.json") var rocks := ""
@export_file("*.json") var forest_wood := ""

@export_group("Buildings")
## The tables of the parts of the tavern (TavernSystem), shell first.
@export var tavern: PackedStringArray = []
## The cottages of the village plan (VillageCottage): one file, every cottage's
## table, scene and lantern.
@export_file("*.json") var cottages := ""
## The tables of the buildings tools/pipeline/buildings/kit.py makes (VillageBuildings).
@export var buildings: PackedStringArray = []
## The yards, routes and patches the ground wears bare (GroundWear).
@export_file("*.json") var worn_ground := ""

@export_group("Nature")
## The scanned faces of the region's cliffs and the ground behind them
## (RockField; tools/pipeline/rocks/cliff_seat.py writes it).
@export_file("*.json") var cliff := ""
## The trees the placer is given (VegetationCache): the composed woodland of
## the Blender map, and the village's own trees.
@export_file("*.json") var woodland := ""
@export_file("*.json") var village_trees := ""
## The baked placement of the trees and its manifest (VegetationCache).
## Empty: none is baked, and the level places the trees as it loads.
@export_file("*.bin") var placement := ""
@export_file("*.json") var placement_manifest := ""

static func valley() -> RegionDef:
	return load(VALLEY) as RegionDef

## The regions of the game (LIST), in its order.
static func listed() -> Array[RegionDef]:
	var regions: Array[RegionDef] = []
	var data: Variant = DataFile.read(LIST, WorldSchemas.regions())
	if not data is Dictionary:
		return regions
	var list: Dictionary = data
	for path: String in list.regions:
		var region := load(path) as RegionDef
		if region != null:
			regions.append(region)
	return regions

## The spawn with `spawn_id`, or the first one.
func spawn(spawn_id := &"") -> RegionSpawn:
	for entry: RegionSpawn in spawns:
		if entry.id == spawn_id:
			return entry
	return spawns[0] if not spawns.is_empty() else null

## Every file this names, for a check that they exist. An empty path is a
## part the region does not have.
func files() -> PackedStringArray:
	var named := PackedStringArray([terrain_dir.path_join("terrain.json"), settled_heights, settled_masks,
		settled_ground, zones, map.resource_path if map != null else "", map_manifest, map_context, village_plan,
		props, rocks, forest_wood, cottages, worn_ground, cliff, woodland, village_trees, placement,
		placement_manifest])
	named.append_array(tavern)
	named.append_array(buildings)
	return named
