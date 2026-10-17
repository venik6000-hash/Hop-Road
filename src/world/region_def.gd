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
	&"rocks", &"vegetation", &"flora", &"people", &"camping", &"wildlife", &"lakeside"]
## The parts a part cannot stand without.
const NEEDS := {
	&"brook": [&"falls"],
	&"camping": [&"people"],
	&"lakeside": [&"camping"],
}
## The fields a part reads. The first one must name a file; a region without
## the part names none of them.
const PART_FILES := {
	&"falls": ["falls"],
	&"brook": ["brook"],
	&"tavern": ["tavern", "tavern_ground"],
	&"cottages": ["cottages"],
	&"buildings": ["buildings"],
	&"village_pack": ["props", "forest_wood", "animals"],
	&"rocks": ["rocks", "cliff"],
	&"vegetation": ["woodland", "village_trees", "placement", "placement_manifest"],
	&"people": ["villagers", "tavern_work"],
	&"wildlife": ["wildlife"],
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
## The ways out into other regions (GameFlow.travel).
@export var exits: Array[RegionExit] = []
## The middle of the built-up land (x, z): what RainShelter maps for the
## rain to fall on.
@export var shelter_centre := Vector2.ZERO

@export_group("Layout")
## The Blender map the level stands its systems in (node "Map"), and its
## lights and cameras (tools/pipeline/alpine_scene/export_godot.py).
@export var map: PackedScene
@export_file("*.json") var map_manifest := ""
## The edits of the map's pieces by their labels (MapEdits): pieces dropped,
## raised, moved and lowered, and the walkways laid over them.
@export_file("*.json") var map_edits := ""
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
## The brook and the street's rill the ground bake cuts and the level fills
## with water (VillageBrook).
@export_file("*.json") var brook := ""
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

## The id of the first region of the list `list`: where a new game starts.
static func first_id(list := LIST) -> StringName:
	var found := entries(list)
	return StringName(str(found[0].id)) if not found.is_empty() else &""

## The file of the region `region_id` of the list `list`, read without
## loading any region; the file of the first region when the list has no such
## id; "" when the list is empty.
static func path_of(region_id: StringName, list := LIST) -> String:
	var found := entries(list)
	for entry: Dictionary in found:
		if StringName(str(entry.id)) == region_id:
			return str(entry.region)
	return str(found[0].region) if not found.is_empty() else ""

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
	var named := PackedStringArray([terrain_dir.path_join("terrain.json"), settled_heights, settled_masks,
		settled_ground, zones, map.resource_path if map != null else "", map_manifest, map_edits, map_context,
		village_plan, props, rocks, forest_wood, cottages, worn_ground, tavern_ground, tavern_work, cliff, brook,
		falls, woodland, village_trees, placement, placement_manifest, villagers, animals, wildlife])
	named.append_array(tavern)
	named.append_array(buildings)
	return named
