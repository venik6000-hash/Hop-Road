class_name CellContent
extends RefCounted
## The content of one cell of the level (docs/LEVEL.md, «Общие системы и
## содержимое»): the parts of the region that are built, unloaded and built
## again, under one node of "Content". The whole region is one cell for now.
## A content step (LevelParts) takes the shared systems (SharedSystems) and
## this, and sees no other cell. What the content gives the shared systems it
## puts in the registries of WorldContext (docs/LEVEL.md, «Реестры»); it goes
## from them when its node leaves the tree. A part the region does not have
## (RegionDef.parts) stays null, or empty for a list.

const VILLAGE_PACK = preload("res://src/village/village_pack.gd")

## The cell's node under "Content"; null once the content is unloaded.
var node: Node3D
## The region's Blender map (node "Map"), its manifest and the village plan
## (VillageLayout.read_plan).
var map: Node3D
## The pieces of the map by their labels (MapIndex), made as the map comes
## in: the systems ask it, not the map's tree.
var map_index: MapIndex
var manifest: Dictionary
var village_plan: Dictionary

var falls: WaterfallSystem
var brook: VillageBrook
var tavern: TavernSystem
var cottages: Array[VillageCottage] = []
var buildings: Array[VillageBuilding] = []
var village_pack: VILLAGE_PACK
var rocks: RockField
var vegetation: VegetationSystem
var flora: VillageFlora
var wildlife: WildlifeSystem
var dragon: LakeDragon
var lakeside: LakesideSystem

## Adds `part` to the cell's node.
func add(part: Node) -> void:
	node.add_child(part)

## The cell stands whole: what is drawn from all of it (the rain's shelter
## map) takes it now (WorldContext.shelters). Its node leaving the tree takes
## it away again.
func stand(world: WorldContext) -> void:
	world.shelters.add(node, node)
