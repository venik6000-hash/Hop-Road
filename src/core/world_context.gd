class_name WorldContext
extends RefCounted
## What the systems of one level share while it runs (docs/LEVEL.md,
## «Контекст мира»). The level makes one (level.world) and hands it to each
## system that needs it before the system enters the tree. A tool that builds
## a part of the level alone gives none: a system without one acts as in a
## level without rooms.

## Told when RenderQuality names another profile.
signal quality_changed(profile: QualityProfile)

## The level's rooms (Interiors): how far an eye is indoors and what it sees
## of the outdoors from there; null in a tool without them.
var interiors: Interiors
## The quality profile of the level; null until RenderQuality has named one
## (QualityProfile.of gives the authored one then).
var quality: QualityProfile
## The trees are placed anew instead of read from a stored placement (the
## bake tool's --force). Set before the level enters the tree.
var place_trees_anew := false
## The build waits a frame after each stage (Level): the loading screen draws
## the stage's words, and no frame holds the whole build. A test turns it off
## to show that the placement does not depend on these frames.
var stage_frames := true

## The registries of the shared systems (docs/LEVEL.md, «Реестры»): what the
## region's content gives them while it stands. They are here before any
## system, so content built before its shared system is not lost.
## Sources of E (TavernInteractions): Callable(TavernInteractions) that hands
## the giver's targets, holds and seats.
var interaction_sources := ContentRegistry.new()
## Lamps (FarLights, LampShadowGuard): Callable() -> LampSet (lamps_for()).
var lamps := ContentRegistry.new()
## Where the animals are (LampShadowGuard): a node with skinned bodies below.
var animals := ContentRegistry.new()
## What the rain's shelter map is drawn from (RainShelter): a cell's node, once
## the cell stands (CellContent.stand).
var shelters := ContentRegistry.new()
## The forest's crowns (the fog, the eye's adaptation): a CanopyField.
var canopies := ContentRegistry.new()
## Points where the lake's waves are asked for, after the player's:
## Callable() -> PackedVector2Array (x, z).
var water_probes := ContentRegistry.new()
## What the wind turns (WeatherSystem): Callable(heading: float), the heading
## the wind blows along in radians (WeatherSystem.wind_heading_deg).
var wind_vanes := ContentRegistry.new()

## Names `profile` the level's and gives `sky` its reach of the shadows.
func set_quality(sky: SkySystem, profile: QualityProfile) -> void:
	quality = profile
	if sky != null:
		set_shadow_reach(sky)
	quality_changed.emit(profile)

## The reach of the sun's shadows the profile asks for, m; 0 until
## RenderQuality has named one.
func shadow_reach() -> float:
	return quality.shadows.distance if quality != null else 0.0

## Gives the sun and the moon the reach of their shadows: the profile's
## outdoors, InteriorSight.SHADOW_REACH at most for an eye in a room.
func set_shadow_reach(sky: SkySystem) -> void:
	var distance := InteriorSight.reach_for(shadow_reach(), interiors != null and interiors.sight.active)
	for light: DirectionalLight3D in [sky.sun, sky.moon]:
		light.directional_shadow_max_distance = distance
	# Past the shadow map the trees' shadow is the canopy field's
	# (src/vegetation/shaders/canopy.gdshaderinc).
	RenderingServer.global_shader_parameter_set("sun_shadow_reach",
		Vector2(sky.sun.directional_shadow_fade_start, 1.0) * distance)
