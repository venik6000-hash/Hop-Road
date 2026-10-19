class_name QualityProfile
extends Resource
## One level of quality (assets/quality/<id>.tres): what the light, the
## shadows, the effects, the plants, the water and the textures may cost. It
## is the one source of these budgets (docs/PERFORMANCE.md, rule 1). As the
## scalability groups of large engines, it names one level of each group
## (QualityGroup: QualityShadows, QualityEffects, QualityVegetation,
## QualityWater, QualityPost); a level of a group is a file
## assets/quality/<group>/<level>.tres that several profiles may share.
## GameSettings keeps the player's choice; RenderQuality applies it to the
## level and names it in WorldContext.quality, which the systems of the level
## read.
##
## What changes at once: the picture, the sun's shadows, the clouds, the
## ambient occlusion and the reach of the grass. What changes after a restart
## (needs_restart): the textures, which are swapped before the scene loads,
## and each group's fields that a system reads when the level is built
## (QualityGroup.read_at_start).

const DIRECTORY := "res://assets/quality/"
## From the lightest to the heaviest, in the order of the settings panel.
const IDS: Array[StringName] = [&"low", &"medium", &"high", &"maximum"]
const DEFAULT := &"high"
## The picture as it was authored: a tool that draws the level into its own
## SubViewport, a system built without a level.
const AUTHORED := &"maximum"
## The texture sets GameSettings.install_textures knows.
const TEXTURE_TIERS: Array[String] = ["maximum", "medium", "low"]
## The fields that hold the groups.
const GROUPS: Array[StringName] = [&"shadows", &"effects", &"vegetation", &"water", &"post"]

@export var id := &""
## The line of the settings panel.
@export var title := ""

@export_group("Picture")
## 3D pixels shaded per frame, whatever the window measures.
@export var pixels := 0
## The texture set (GameSettings.install_textures).
@export_enum("maximum", "medium", "low") var textures := "maximum"

@export_group("Groups")
@export var shadows: QualityShadows
@export var effects: QualityEffects
@export var vegetation: QualityVegetation
@export var water: QualityWater
@export var post: QualityPost

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
	if textures != running.textures:
		return true
	for group: StringName in GROUPS:
		var level: QualityGroup = get(group)
		var old: QualityGroup = running.get(group)
		if level.needs_restart(old):
			return true
	return false
