class_name QualityProfile
extends Resource
## One level of quality (assets/quality/<id>.tres): what the light, the
## shadows, the grass, the trees and the textures may cost. It is the one
## source of these budgets. GameSettings keeps the player's choice;
## RenderQuality applies it to the level and names it in WorldContext.quality,
## which the systems of the level read.
##
## What changes at once: the picture, the shadows, the clouds and the reach
## of the grass. What changes after a restart (needs_restart): the textures,
## which are swapped before the scene loads, and the reach of the tree
## meshes, which sets the bands of the forest when it is built.

const DIRECTORY := "res://assets/quality/"
## From the lightest to the heaviest, in the order of the settings panel.
const IDS: Array[StringName] = [&"low", &"medium", &"high", &"maximum"]
const DEFAULT := &"high"
## The picture as it was authored: a tool that draws the level into its own
## SubViewport, a system built without a level.
const AUTHORED := &"maximum"
## The texture sets GameSettings.install_textures knows.
const TEXTURE_TIERS: Array[String] = ["maximum", "medium", "low"]

@export var id := &""
## The line of the settings panel.
@export var title := ""

@export_group("Picture")
## 3D pixels shaded per frame, whatever the window measures.
@export var pixels := 0
@export var ssao := RenderingServer.ENV_SSAO_QUALITY_VERY_LOW
## Samples of the cloud march along a view ray.
@export var cloud_steps := 0

@export_group("Shadows")
## Reach of the sun's shadow cascades, m.
@export var shadow_distance := 0.0
## The sun's shadow atlas, px.
@export var shadow_size := 0
@export var shadow_blend := false

@export_group("Vegetation")
## Where the grass starts to fade and where it is gone, m (the shader's
## fade_start and fade_end).
@export var grass_fade := Vector2.ZERO
## Where the last mesh LOD of a tree starts to give way to its impostor and
## where it is gone, m.
@export var tree_mesh_reach := Vector2.ZERO

@export_group("Textures")
## The texture set (GameSettings.install_textures).
@export_enum("maximum", "medium", "low") var textures := "maximum"

static func valid(value: String) -> StringName:
	return StringName(value) if StringName(value) in IDS else DEFAULT

static func named(value: StringName) -> QualityProfile:
	return load(DIRECTORY + String(valid(value)) + ".tres") as QualityProfile

## The profile of the level of `world`; the authored one without it or before
## RenderQuality has named one.
static func of(world: WorldContext) -> QualityProfile:
	return world.quality if world != null and world.quality != null else named(AUTHORED)

## The profile for preferences saved before profiles: a render tier
## ("performance", "balanced", "maximum") and a texture set. A lighter
## choice of either is kept: no textures come back larger than chosen.
static func from_tiers(render: String, texture_set: String) -> StringName:
	if render == "performance" or texture_set == "low":
		return &"low"
	if texture_set == "medium":
		return &"medium"
	return &"maximum" if render == "maximum" else DEFAULT

## Whether the game must restart before it shows this profile, when it runs
## with `running`.
func needs_restart(running: QualityProfile) -> bool:
	return textures != running.textures or tree_mesh_reach != running.tree_mesh_reach
