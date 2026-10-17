class_name LightLayers
extends RefCounted
## The render layers the light of the world goes by (docs/LEVEL.md, «Свет
## помещений»). The engine has no walls for light: a lamp lights whatever
## its cull mask meets in its reach, through a floor or a wall. So what a
## room holds is on ROOMS, the only layer the rooms' lamps reach, and no lamp
## of a room shines onto the ground outside.

## Everything a building draws in and round its rooms: the rooms' lamps light this alone.
const ROOMS := 512
## The still pieces, which alone go into the shadow maps of the rooms' lamps.
## A lamp keeps its shadow map while nothing in it moves, and draws all six
## faces of it again in every frame in which a caster in its reach moves or
## has an animated material. The fluttering ivy, the flames and the people are
## therefore on ROOMS alone: lit by the lamps, not drawn into their shadows.
const LAMP_CASTERS := 1024
## The sun's shadow map leaves both layers above out and draws a building by
## these: the shell always, the rooms' pieces only while the eye is in or near
## the building (Interiors). From the yard nobody sees the shadow a stool casts
## in a window's light, yet the rooms were four tenths of the tavern's
## triangles in every cascade.
const SUN := 2048
const ROOM_SUN := 4096
## Both are the sun's alone: a lantern's shadow map must leave them out, or
## the ivy they carry is drawn into it again in every frame.
const SUN_ONLY := SUN | ROOM_SUN
## What never stands still outdoors and casts the sun's shadow: a mill's
## wheel, a goat. A lamp with a shadow draws its map again in every frame in
## which such a thing moves in its light, in the map or not. A village
## building's lamp outdoors that casts a shadow leaves this layer to a twin
## that casts none (VillageBuilding.twin_for_the_restless).
const RESTLESS := 8192

## Puts a piece on other render layers. Godot 4.7.2 keeps a piece paired with
## the lights in whose reach it stands while its layers change (Forward+), yet
## counts a pair only where the light's cull mask meets the layers. A piece
## that takes ROOMS under a lamp is therefore missing from the engine's count
## of the lights that give it a soft shadow, and the engine prints
## "geom->softshadow_count==0 - BUG!" when it leaves the lamp or is hidden. So
## the server holds the piece hidden over the change: hidden it has no pairs,
## and shown again it is paired by its new layers. The engine's master does the
## same on its own (53ec17a1d).
static func set_layers(item: GeometryInstance3D, layers: int) -> void:
	if item.layers == layers:
		return
	var instance := item.get_instance()
	RenderingServer.instance_set_visible(instance, false)
	item.layers = layers
	RenderingServer.instance_set_visible(instance, item.is_visible_in_tree())
