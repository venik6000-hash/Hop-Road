class_name DataFiles
extends RefCounted
## Every data file the game reads while it runs, with the schema of each, and
## the check of all of them together: each file against its schema, then the
## ids they point at in each other and in the code. The loaders of the systems
## check their own file when they read it (DataFile.read); this is the whole.
##
## A file the game reads and no entry names here is found by the test
## (tests/test_data_files.gd), so a new loader brings its schema.

const GAME_SETTINGS := preload("res://src/settings/game_settings.gd")
const TREE_MATERIALS := preload("res://src/vegetation/tree_materials.gd")
const VILLAGE_BUILDINGS := preload("res://src/village/village_buildings.gd")

## Entries {path, schema} of the files of `region`, then of the files that
## are not any region's. A region without a part names no file for it.
static func all(region: RegionDef) -> Array[Dictionary]:
	var files := of_region(region)
	files.append({"path": RegionDef.LIST, "schema": WorldSchemas.regions()})
	files.append({"path": TREE_MATERIALS.IMPOSTORS, "schema": WorldSchemas.impostors()})
	files.append({"path": GrassClump.CARDS, "schema": WorldSchemas.grass_cards()})
	files.append({"path": GAME_SETTINGS.MANIFEST, "schema": WorldSchemas.texture_quality()})
	files.append({"path": LakeSoundscape.BANK, "schema": BodySchemas.lake_bank()})
	files.append({"path": JointLimits.TABLE, "schema": BodySchemas.joint_limits()})
	for path in _files_in(NpcMotion.FOLDER, ".json"):
		files.append({"path": path, "schema": BodySchemas.npc_motion()})
	files.append({"path": BrewBook.RECIPES, "schema": BrewingSchemas.recipes()})
	files.append({"path": BrewBook.FLAWS, "schema": BrewingSchemas.flaws()})
	files.append({"path": BrewGuide.PATH, "schema": BrewingSchemas.guide()})
	files.append({"path": BrewTrade.DATA, "schema": BrewingSchemas.trade()})
	files.append({"path": BrewStalls.POINTS, "schema": BuildingSchemas.trade_models()})
	for id in PeopleIds.VILLAGERS:
		files.append({"path": PeopleBook.FOLDER + String(id) + ".json", "schema": PeopleSchemas.sheet()})
	files.append({"path": PeopleBook.FOLDER + String(PeopleIds.COMMON) + ".json", "schema": PeopleSchemas.sheet()})
	return files

## Entries {path, schema} of the files `region` names (RegionDef).
static func of_region(region: RegionDef) -> Array[Dictionary]:
	var files: Array[Dictionary] = []
	var named := {
		region.terrain_dir.path_join("terrain.json"): WorldSchemas.terrain(),
		region.settled_ground: WorldSchemas.settled_ground(),
		region.zones: WorldSchemas.zones(),
		region.map_manifest: WorldSchemas.map_manifest(),
		region.map_context: WorldSchemas.map_context(),
		region.village_plan: WorldSchemas.village_plan(),
		region.props: WorldSchemas.props(),
		region.rocks: WorldSchemas.rocks(),
		region.forest_wood: WorldSchemas.forest_wood(),
		region.cottages: BuildingSchemas.cottages(),
		region.worn_ground: BuildingSchemas.worn_ground(),
		region.cliff: WorldSchemas.cliff_seat(),
		region.woodland: WorldSchemas.woodland(),
		region.village_trees: WorldSchemas.trees(),
		region.placement_manifest: WorldSchemas.placement_manifest(),
	}
	for path: String in named:
		if not path.is_empty():
			files.append({"path": path, "schema": named[path]})
	for entry: Dictionary in VillageCottage.entries(region.cottages):
		files.append({"path": str(entry.table), "schema": BuildingSchemas.cottage()})
	for path: String in region.buildings:
		files.append({"path": path, "schema": VILLAGE_BUILDINGS.schema(path)})
	for path: String in region.tavern:
		files.append({"path": path, "schema": BuildingSchemas.tavern_part()})
	return files

## The ids the code names, by kind.
static func code_ids() -> Dictionary:
	var people: Array[StringName] = PeopleIds.VILLAGERS.duplicate()
	people.append(PeopleIds.COMMON)
	return {
		&"sort": BrewIds.SORTS,
		&"note": BrewIds.NOTES,
		&"flaw": BrewIds.FLAWS,
		&"ware": BrewIds.WARES,
		&"stock": BrewIds.STOCK,
		&"sack": BrewIds.SACKS,
		&"profile_key": BrewIds.PROFILE_KEYS,
		&"person": people,
	}

## What is wrong with the data files of `region`: the problems of each file,
## then the ids that point nowhere or are defined twice.
static func problems(region: RegionDef) -> PackedStringArray:
	var found := PackedStringArray()
	var links := DataLinks.new()
	var named := code_ids()
	for kind: StringName in named:
		links.provide(kind, named[kind])
	# The stalls of trade.json are places too; the code names the two besides.
	links.provide(&"place", [&"brewery", &"order_board"], false)
	for entry in all(region):
		var path: String = entry.path
		var check := DataFile.inspect(path, entry.schema)
		for problem in check.problems:
			found.append("%s: %s" % [path, problem])
		links.add(path, check)
	found.append_array(links.problems())
	return found

static func _files_in(folder: String, extension: String) -> PackedStringArray:
	var result := PackedStringArray()
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for file_name in names:
		if file_name.ends_with(extension):
			result.append(folder + file_name)
	return result
