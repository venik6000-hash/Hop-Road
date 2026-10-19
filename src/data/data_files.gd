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

## Entries {path, schema} of the files of `region` and of its brewery, then of
## the files that are not any region's. A region without a part names no file
## for it; a region without a brewery reads none of the brewery's files.
static func all(region: RegionDef) -> Array[Dictionary]:
	var files := of_region(region)
	if has_brewery(region):
		files.append_array(of_brewery())
	files.append({"path": RegionDef.LIST, "schema": WorldSchemas.regions()})
	# The world's tiles are a build product; the terrain keeps its near field without them.
	if FileAccess.file_exists(TerrainTiles.WORLD):
		files.append({"path": TerrainTiles.WORLD, "schema": WorldSchemas.world_tiles()})
	files.append({"path": TREE_MATERIALS.IMPOSTORS, "schema": WorldSchemas.impostors()})
	files.append({"path": GrassClump.CARDS, "schema": WorldSchemas.grass_cards()})
	files.append({"path": GAME_SETTINGS.MANIFEST, "schema": WorldSchemas.texture_quality()})
	files.append({"path": LakeSoundscape.BANK, "schema": BodySchemas.lake_bank()})
	files.append({"path": JointLimits.TABLE, "schema": BodySchemas.joint_limits()})
	for path in _files_in(NpcMotion.FOLDER, ".json"):
		files.append({"path": path, "schema": BodySchemas.npc_motion()})
	files.append({"path": LineTable.CAMP, "schema": PeopleSchemas.camp_lines()})
	files.append({"path": FishingState.SPECIES, "schema": WorldSchemas.fish()})
	files.append({"path": WeatherTable.PATH, "schema": WorldSchemas.weathers()})
	files.append({"path": FloraTable.PATH, "schema": WorldSchemas.flora()})
	files.append({"path": LightProfile.FILE, "schema": BuildingSchemas.light_profiles()})
	for id in PeopleBook.roster():
		files.append({"path": PeopleBook.sheet_path(id), "schema": PeopleSchemas.sheet()})
	files.append({"path": PeopleBook.sheet_path(PeopleIds.COMMON), "schema": PeopleSchemas.sheet()})
	return files

## Whether one of the buildings of `region` is a brewery: its table has
## `utensils` (VillageBuildings).
static func has_brewery(region: RegionDef) -> bool:
	return VILLAGE_BUILDINGS.tables(region).any(func(table: Dictionary) -> bool: return table.has("utensils"))

## Entries {path, schema} of the files only the brewery reads (BrewHouse): the
## guide points at the stations of its table, the works at its utensils.
static func of_brewery() -> Array[Dictionary]:
	var files: Array[Dictionary] = [
		{"path": BrewBook.RECIPES, "schema": BrewingSchemas.recipes()},
		{"path": BrewBook.FLAWS, "schema": BrewingSchemas.flaws()},
		{"path": BrewGuide.PATH, "schema": BrewingSchemas.guide()},
		{"path": BrewTrade.DATA, "schema": BrewingSchemas.trade()},
		{"path": BrewStation.WORKS, "schema": BrewingSchemas.works()},
		{"path": MaltLot.MALTS, "schema": BrewingSchemas.malts()},
		{"path": LineTable.BREWERY, "schema": BrewingSchemas.lines()},
		{"path": BrewStalls.POINTS, "schema": BuildingSchemas.trade_models()},
	]
	return files

## Entries {path, schema} of the files `region` names (RegionDef).

static func of_region(region: RegionDef) -> Array[Dictionary]:
	var files: Array[Dictionary] = []
	var named := {
		region.terrain_dir.path_join("terrain.json"): WorldSchemas.terrain(),
		region.settled_ground: WorldSchemas.settled_ground(),
		region.zones: WorldSchemas.zones(),
		region.map_manifest: WorldSchemas.map_manifest(),
		region.map_edits: WorldSchemas.map_edits(),
		region.map_context: WorldSchemas.map_context(),
		region.village_plan: WorldSchemas.village_plan(),
		region.props: WorldSchemas.props(),
		region.rocks: WorldSchemas.rocks(),
		region.forest_wood: WorldSchemas.forest_wood(),
		region.forest_floor: WorldSchemas.forest_floor(),
		region.cottages: BuildingSchemas.cottages(),
		region.worn_ground: BuildingSchemas.worn_ground(),
		region.tavern_ground: BuildingSchemas.tavern_ground(),
		region.tavern_work: BuildingSchemas.tavern_work(),
		region.cliff: WorldSchemas.cliff_seat(),
		region.cliff_faces: WorldSchemas.cliff_faces(),
		region.brook: WorldSchemas.brook(),
		region.lake: WorldSchemas.lake(),
		region.falls: WorldSchemas.falls(),
		region.villagers: PeopleSchemas.villagers(),
		region.animals: WorldSchemas.animals(),
		region.wildlife: WorldSchemas.wildlife(),
		region.dragon: WorldSchemas.dragon(),
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
	var beds: Array[String] = []
	for paths: PackedStringArray in [region.buildings, region.tavern]:
		for path: String in paths:
			for bed: String in FireBed.beds_of(path):
				if not beds.has(bed):
					beds.append(bed)
					files.append({"path": bed, "schema": BuildingSchemas.fire_bed()})
	return files

## The ids the code names, by kind. The people are the sheets of the folder
## (PeopleBook.roster) and the common sheet.
static func code_ids() -> Dictionary:
	var people: Array[StringName] = PeopleBook.roster()
	people.append(PeopleIds.COMMON)
	return {
		&"sort": BrewIds.SORTS,
		&"note": BrewIds.NOTES,
		&"flaw": BrewIds.FLAWS,
		&"ware": BrewIds.WARES,
		&"stock": BrewIds.STOCK,
		&"sack": BrewIds.SACKS,
		&"profile_key": BrewIds.PROFILE_KEYS,
		&"malt": BrewIds.MALTS,
		&"weather": WeatherTable.KINDS,
		&"person": people,
	}

## What is wrong with the data files of `region`: the problems of each file,
## the ids that point nowhere or are defined twice, then the parts the region
## names and its environment (RegionDef.part_problems,
## environment_problems). The villagers' sheets are the world's, not
## the region's: a zone a sheet names may lie in another region of the world
## (RegionDef.listed()). There the story is told; here the villager does not
## come. A zone that no region of the world has is a fault.
static func problems(region: RegionDef) -> PackedStringArray:
	var found := PackedStringArray()
	var links := DataLinks.new()
	for other: RegionDef in RegionDef.listed():
		if not other.zones.is_empty() and other.zones != region.zones:
			links.elsewhere(&"zone", ValleyZones.load_file(other.zones).zones.map(func(zone: Dictionary) -> String: return str(zone.id)))
	var named := code_ids()
	for kind: StringName in named:
		links.provide(kind, Values.list(named[kind]))
	# The stalls of trade.json are places too; the code names the two besides.
	links.provide(&"place", [&"brewery", &"order_board"], false)
	for entry in all(region):
		var path: String = entry.path
		var check := DataFile.inspect(path, Values.table(entry.schema))
		for problem in check.problems:
			found.append("%s: %s" % [path, problem])
		links.add(path, check)
	found.append_array(links.problems())
	for problem in region.part_problems() + region.environment_problems():
		found.append("%s: %s" % [region.resource_path, problem])
	return found

## What keeps the level of `region` from being built: a file of the region or
## of its brewery that is not there or does not parse, then the parts the
## region names and its environment (RegionDef.part_problems,
## environment_problems). The loader checks it before the
## build: the build stops at such a file without a word. A file that parses
## but does not fit its schema is read as far as it can be (DataFile.read).
static func unreadable(region: RegionDef) -> PackedStringArray:
	var found := PackedStringArray()
	var files := of_region(region)
	if has_brewery(region):
		files.append_array(of_brewery())
	for entry: Dictionary in files:
		var path: String = entry.path
		if not FileAccess.file_exists(path):
			found.append("%s: the file does not exist" % path)
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			found.append("%s: line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
	for problem in region.part_problems() + region.environment_problems():
		found.append("%s: %s" % [region.resource_path, problem])
	return found

static func _files_in(folder: String, extension: String) -> PackedStringArray:
	var result := PackedStringArray()
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for file_name in names:
		if file_name.ends_with(extension):
			result.append(folder + file_name)
	return result
