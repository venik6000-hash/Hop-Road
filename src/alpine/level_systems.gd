class_name LevelSystems
extends RefCounted
## What a level (src/alpine/level.gd) has built so far, for the steps built
## after it (LevelParts). The level holds it to itself. A part the region
## does not have (RegionDef.parts) stays null, or empty for a list.

const LEVEL_POST = preload("res://src/alpine/level_post.gd")
const VILLAGE_PACK = preload("res://src/village/village_pack.gd")

## The level node the systems are added to, and what it starts with.
var level: Node3D
var region: RegionDef
var world: WorldContext
var player: Player
## The player's eye.
var camera: Camera3D
var environment: WorldEnvironment
## The region's Blender map (node "Map"), its manifest and the village plan
## (VillageLayout.read_plan).
var map: Node3D
var manifest: Dictionary
var village_plan: Dictionary

# The core: every region has these.
var sky: SkySystem
var weather: WeatherSystem
var terrain: TerrainSystem
var sun_shadow: SunShadowField
var water: WaterSystem
var eye_adaptation: EyeAdaptation
var post: LEVEL_POST
var rain_fall: RainFall
var interactions: TavernInteractions
var far_lights: FarLights
var lamp_guard: LampShadowGuard

# The parts (RegionDef.PARTS).
var falls: WaterfallSystem
var brook: VillageBrook
var tavern: TavernSystem
var cottages: Array[VillageCottage] = []
var buildings: Array[VillageBuilding] = []
var village_pack: VILLAGE_PACK
var rocks: RockField
var vegetation: VegetationSystem
var flora: VillageFlora
var people: NpcPopulation
var camping: CampSystem
var wildlife: WildlifeSystem
var lakeside: LakesideSystem

## Adds `node` to the level.
func add(node: Node) -> void:
	level.add_child(node)
