class_name WorldContext
extends RefCounted
## What the systems of one level share while it runs (docs/LEVEL.md,
## «Контекст мира»). The level makes one (level.world) and hands it to each
## system that needs it before the system enters the tree. A tool that builds
## a part of the level alone gives none: a system without one acts as in a
## level without a tavern.

## Told when RenderQuality names another profile.
signal quality_changed(profile: QualityProfile)

## The tavern's portals: what an eye in its rooms sees of the outdoors; null
## without a tavern.
var portals: TavernPortals
## The quality profile of the level; null until RenderQuality has named one
## (QualityProfile.of gives the authored one then).
var quality: QualityProfile
## The trees are placed anew instead of read from a stored placement (the
## bake tool's --force). Set before the level enters the tree.
var place_trees_anew := false

## Names `profile` the level's and gives `sky` its reach of the shadows.
func set_quality(sky: SkySystem, profile: QualityProfile) -> void:
	quality = profile
	if sky != null:
		set_shadow_reach(sky)
	quality_changed.emit(profile)

## The reach of the sun's shadows the profile asks for, m; 0 until
## RenderQuality has named one.
func shadow_reach() -> float:
	return quality.shadow_distance if quality != null else 0.0

## Gives the sun and the moon the reach of their shadows: the profile's
## outdoors, TavernPortals.SHADOW_REACH at most for an eye in the rooms.
func set_shadow_reach(sky: SkySystem) -> void:
	var distance := TavernPortals.reach_for(shadow_reach(), portals != null and portals.sight.active)
	for light: DirectionalLight3D in [sky.sun, sky.moon]:
		light.directional_shadow_max_distance = distance
	# Past the shadow map the trees' shadow is the canopy field's
	# (src/vegetation/shaders/canopy.gdshaderinc).
	RenderingServer.global_shader_parameter_set("sun_shadow_reach",
		Vector2(sky.sun.directional_shadow_fade_start, 1.0) * distance)
