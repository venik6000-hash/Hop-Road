class_name SharedSystems
extends RefCounted
## The level's shared systems (docs/LEVEL.md, «Общие системы и содержимое»):
## what lives for the whole of a game on the level, under its node "Shared".
## The level (src/alpine/level.gd) builds them once by the steps of
## LevelParts and holds this to itself. The region's content (CellContent)
## comes and goes under them and gives them what they need through the
## registries of WorldContext (docs/LEVEL.md, «Реестры»). A part the region
## does not have (RegionDef.parts) stays null.

const LEVEL_POST = preload("res://src/alpine/level_post.gd")

## The level, the node "Shared" the systems are added to, and what the level
## starts with.
var level: Node3D
var node: Node3D
var region: RegionDef
var world: WorldContext
var player: Player
## The player's eye.
var camera: Camera3D
var environment: WorldEnvironment

var sky: SkySystem
var weather: WeatherSystem
var terrain: TerrainSystem
var sun_shadow: SunShadowField
var water: WaterSystem
## The region's lake (RegionDef.lake); null for a region without one.
var lake: LakePlan
var eye_adaptation: EyeAdaptation
var post: LEVEL_POST
var rain_fall: RainFall
var people: NpcPopulation
var interactions: TavernInteractions
var camping: CampSystem
var far_lights: FarLights
var lamp_guard: LampShadowGuard
var refraction: LakeRefraction
var rain_shelter: RainShelter

## Adds `system` to the node "Shared".
func add(system: Node) -> void:
	node.add_child(system)
