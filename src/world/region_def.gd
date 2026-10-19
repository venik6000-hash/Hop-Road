@tool
class_name RegionDef
extends Resource
## One region of the world: the ground it stands on and the files that fill
## it. The level (src/alpine/level.gd) builds what this names; another region
## is another such resource and its files (docs/LEVEL.md, «Области»).

## The valley of the tavern.
const VALLEY := "res://assets/regions/valley.tres"
## The regions of the game by id, the first one where a new game starts.
const LIST := "res://assets/regions/regions.json"
## The parts of a level a region can name (`parts`), in the order the level
## builds them (LevelParts).
const PARTS: Array[StringName] = [&"falls", &"brook", &"tavern", &"cottages", &"buildings", &"village_pack",
	&"rocks", &"vegetation", &"flora", &"people", &"camping", &"wildlife", &"dragon", &"lakeside"]
## The parts a part cannot stand without.
const NEEDS := {
	&"brook": [&"falls"],
	&"camping": [&"people"],
	&"lakeside": [&"camping"],
}
## The parts that read the village plan (`village_plan`): the cottages stand
## at its places, the plants keep off its ways and grow on its green.
const PLAN_PARTS: Array[StringName] = [&"cottages", &"flora"]
## The parts that stand on the lake (`lake`): the boat moors on it, its shore
## takes the waves. A region without a lake builds neither these nor the
## lake's bed (WildlifeSystem).
const LAKE_PARTS: Array[StringName] = [&"lakeside"]
## The fields a part reads. The first one must name a file; a region without
## the part names none of them.
const PART_FILES := {
	&"falls": ["falls"],
	&"brook": ["brook"],
	&"tavern": ["tavern", "tavern_ground"],
	&"cottages": ["cottages"],
	&"buildings": ["buildings"],
	&"village_pack": ["props", "forest_wood", "forest_floor", "animals"],
	&"rocks": ["rocks", "cliff", "cliff_faces"],
	&"vegetation": ["woodland", "village_trees", "placement", "placement_manifest"],
	&"people": ["villagers", "tavern_work"],
	&"wildlife": ["wildlife"],
	&"dragon": ["dragon"],
}

@export var id: StringName
@export var title := ""
## The land the region covers (world x, z). The terrain's far field covers it,
## and every spawn and zone lies in it.
@export var bounds := Rect2()
## The parts of the level the region has (PARTS), in any order. The level
## builds these and its core; a region without a part does not build it
## (docs/LEVEL.md, «Части уровня»).
@export var parts: Array[StringName] = []

@export_group("Terrain")
## The walkable land (world x, z): the near field of heights and its masks
## cover it (tools/pipeline/terrain/terrain.py; tools/lib/region.py has their
## cells).
@export var near_bounds := Rect2()
## The fields of terrain.py: terrain.json, the heightfields, the masks and
## the layer textures.
@export_dir var terrain_dir := ""
## The ground recipe of the bake (tools/pipeline/terrain/ground_bake.gd): a
## script that lays the region's rocks, buildings and water courses into the
## near heights and paints its beds, yards and worn ground into the masks.
## Empty: the bake keeps the fields of terrain.py as they are.
@export_file("*.gd") var ground_recipe := ""
## What the ground bake writes (TerrainBake): the near heights with the
## recipe's work laid in, the masks with its paint, and the manifest with the
## courses.
@export_file("*.bin") var settled_heights := ""
@export_file("*.bin") var settled_masks := ""
@export_file("*.json") var settled_ground := ""

@export_group("Places")
## The named places (ValleyZones).
@export_file("*.json") var zones := ""
## Where a player comes into the region; the first one is the default.
@export var spawns: Array[RegionSpawn] = []
## The ways out into other regions (GameFlow.travel).
@export var exits: Array[RegionExit] = []
## The middle of the built-up land (x, z): what RainShelter maps for the
## rain to fall on.
@export var shelter_centre := Vector2.ZERO

@export_group("Environment")
## The air, the season and the look of the ground (EnvironmentDef).
@export var environment: EnvironmentDef

@export_group("Layout")
## The Blender map the level stands its systems in (node "Map"), and its
## lights and cameras (tools/pipeline/alpine_scene/export_godot.py). A path:
## the map loads when the level of this region is built (map_scene), not
## with the region.
@export_file("*.glb", "*.tscn") var map := ""
@export_file("*.json") var map_manifest := ""
## The edits of the map's pieces by their labels (MapEdits): pieces dropped,
## raised, moved and lowered, and the walkways laid over them.
@export_file("*.json") var map_edits := ""
## The pieces of the map the loaded level still shows, for the layout scene
## (tools/pipeline/layout/bake_map_context.gd).
@export_file("*.json") var map_context := ""
## The hand-placed objects (src/layout/layout_store.gd): houses and cottages
## with the village's ways and green, yard props, scanned stones, the
## forest's wood. A region without a village names no plan.
@export_file("*.json") var village_plan := ""
@export_file("*.json") var props := ""
@export_file("*.json") var rocks := ""
@export_file("*.json") var forest_wood := ""
## Where the forest floor's ferns, clover and bracken are scattered (VillagePack).
@export_file("*.json") var forest_floor := ""

@export_group("Buildings")
## The tables of the parts of the tavern (TavernSystem), shell first.
@export var tavern: PackedStringArray = []
## Where the tavern stands in the region: the transform of its node.
@export var tavern_at := Transform3D.IDENTITY
## The cottages of the village plan (VillageCottage): one file, every cottage's
## table, scene and lantern.
@export_file("*.json") var cottages := ""
## The tables of the buildings tools/pipeline/buildings/kit.py makes (VillageBuildings).
@export var buildings: PackedStringArray = []
## The yards, routes and patches the ground wears bare (GroundWear).
@export_file("*.json") var worn_ground := ""
## The floors of the tavern the ground bake takes the ground down under
## (TavernGround).
@export_file("*.json") var tavern_ground := ""
## Where the tavern's staff work (NpcPopulation): the cook's board and pot,
## the maid's round and the tops she wipes.
@export_file("*.json") var tavern_work := ""

@export_group("Nature")
## The scanned faces of the region's cliffs and the ground behind them
## (RockField; tools/pipeline/rocks/cliff_seat.py writes it).
@export_file("*.json") var cliff := ""
## The scans cliff_seat.py stands as the cliff's faces and where: what it
## writes `cliff` from. The game does not read it.
@export_file("*.json") var cliff_faces := ""
## The brook and the street's rill the ground bake cuts and the level fills
## with water (VillageBrook).
@export_file("*.json") var brook := ""
## The lake (LakePlan): where its bed lies, its shore, its reeds, where the
## boat moors. Empty: the region has no lake. The water lies wherever the
## ground is below the terrain's water level (WaterSystem).
@export_file("*.json") var lake := ""
## The falls, the stream that feeds the upper one and the stream between
## them (WaterfallSystem).
@export_file("*.json") var falls := ""
## The trees the placer is given (VegetationCache): the composed woodland of
## the Blender map, and the village's own trees.
@export_file("*.json") var woodland := ""
@export_file("*.json") var village_trees := ""
## The baked placement of the trees and its manifest (VegetationCache).
## Empty: none is baked, and the level places the trees as it loads.
@export_file("*.bin") var placement := ""
@export_file("*.json") var placement_manifest := ""

@export_group("Life")
## Who lives and works in the region (NpcPopulation): the tavern's staff at
## their work and the villagers on their walks.
@export_file("*.json") var villagers := ""
## The village's animals in their yards (VillagePack).
@export_file("*.json") var animals := ""
## The wild animals, the birds and the fish, and where each kind keeps
## (WildlifeSystem).
@export_file("*.json") var wildlife := ""
## The circuit the dragon flies (LakeDragon).
@export_file("*.json") var dragon := ""

static func valley() -> RegionDef:
	return load(VALLEY) as RegionDef

## The entries of the list `list` (LIST by default), in its order: {id,
## region (the file)}.
static func entries(list := LIST) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var data: Variant = DataFile.read(list, WorldSchemas.regions())
	if data is Dictionary:
		var table: Dictionary = data
		var listed_entries: Array = table.get("regions", [])
		for entry: Dictionary in listed_entries:
			found.append(entry)
	return found

## The regions of the list `list`, in its order.
static func listed(list := LIST) -> Array[RegionDef]:
	var regions: Array[RegionDef] = []
	for entry: Dictionary in entries(list):
		var region := load(str(entry.region)) as RegionDef
		if region != null:
			regions.append(region)
	return regions

## The file of the region `region_id` of the list `list`, read without
## loading any region; the file of the first region when the list has no such
## id; "" when the list is empty.
static func path_of(region_id: StringName, list := LIST) -> String:
	var found := entries(list)
	for entry: Dictionary in found:
		if StringName(str(entry.id)) == region_id:
			return str(entry.region)
	return str(found[0].region) if not found.is_empty() else ""

## The scene of the map; null when the region names none or it does not load.
func map_scene() -> PackedScene:
	return load(map) as PackedScene if not map.is_empty() else null

## What is wrong with the region's environment (EnvironmentDef.problems), or
## that it names none.
func environment_problems() -> PackedStringArray:
	if environment == null:
		return PackedStringArray(["the region names no environment"])
	return environment.problems()

## Whether the region has the part `part` (PARTS).
func has_part(part: StringName) -> bool:
	return part in parts

## What is wrong with the parts the region names: a part no level builds, a
## part without a part it needs, a part without its file, a file of a part
## the region does not have.
func part_problems() -> PackedStringArray:
	var found := PackedStringArray()
	for part: StringName in parts:
		if not part in PARTS:
			found.append("no such part: %s" % part)
			continue
		for need: StringName in NEEDS.get(part, []):
			if not has_part(need):
				found.append("part %s needs part %s" % [part, need])
		if part in PLAN_PARTS and village_plan.is_empty():
			found.append("part %s names no village_plan" % part)
		if part in LAKE_PARTS and lake.is_empty():
			found.append("part %s names no lake" % part)
	for part: StringName in PART_FILES:
		var fields: Array = PART_FILES[part]
		for index in fields.size():
			var field := str(fields[index])
			var value: Variant = get(field)
			var named := not str(value).is_empty()
			if value is PackedStringArray:
				var files: PackedStringArray = value
				named = not files.is_empty()
			if has_part(part) and index == 0 and not named:
				found.append("part %s names no %s" % [part, field])
			elif not has_part(part) and named:
				found.append("%s names a file of part %s, which the region does not have" % [field, part])
	return found

## The spawn with `spawn_id`, or the first one.
func spawn(spawn_id := &"") -> RegionSpawn:
	for entry: RegionSpawn in spawns:
		if entry.id == spawn_id:
			return entry
	return spawns[0] if not spawns.is_empty() else null

## Every file this names, for a check that they exist. An empty path is a
## part the region does not have.
func files() -> PackedStringArray:
	var named := PackedStringArray([terrain_dir.path_join("terrain.json"), ground_recipe, settled_heights, settled_masks,
		settled_ground, zones, map, map_manifest, map_edits, map_context,
		village_plan, props, rocks, forest_wood, forest_floor, cottages, worn_ground, tavern_ground, tavern_work, cliff, cliff_faces, brook,
		lake, falls, woodland, village_trees, placement, placement_manifest, villagers, animals, wildlife, dragon])
	named.append_array(tavern)
	named.append_array(buildings)
	return named
