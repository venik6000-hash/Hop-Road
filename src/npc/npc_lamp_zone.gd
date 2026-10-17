class_name NpcLampZone
extends RefCounted
## Which lights a villager's meshes take (VillageNPC.lamp_zone). The rooms'
## lamps keep their shadow maps while nothing they light moves
## (LightLayers.LAMP_CASTERS); a body that could cast a shadow has every lamp
## in whose reach it is animated drawn again in each frame. So an actor is on
## the rooms' layer, lit by their lamps, only in a room (REACH of one at most),
## and casts no shadow there. Outdoors it is lit by the sun and casts the
## sun's shadow.

## Seconds between checks of whether the actor stands in a room.
const SECONDS := 0.25
## An actor whose chest is no further than this outside a room's box is in
## it (m): the lamps of the room light the doorway too.
const REACH := 0.3

var actor: VillageNPC
## The level's rooms (null in a tool without them: the actor is then outdoors).
var interiors: Interiors
## Within reach of a lit lantern outdoors (LampShadowGuard sets it): no shadow
## there either, or the lantern draws its shadow map again in every frame.
var near_lit_lamp := false:
	set(value):
		if value != near_lit_lamp:
			near_lit_lamp = value
			light(actor)
# 1 in a room, 0 outside, -1 before the first check.
var _zone := -1
var _clock := 0.0

func _init(lit_actor: VillageNPC) -> void:
	actor = lit_actor

## Counts `delta` seconds down to the next check of the room.
func tick(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = SECONDS
		check()

## Whether the actor stands in a room now; the meshes change their lights
## when that changes.
func check() -> void:
	var chest := actor.global_position + Vector3.UP * 0.9
	var zone := int(interiors != null and interiors.depth_of(chest) > -REACH)
	if zone == _zone:
		return
	_zone = zone
	light(actor)

## Puts the meshes of `root` (the actor, or what it is handed) under the
## lights of the actor's zone.
func light(root: Node) -> void:
	if _zone < 0:
		return
	var items: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		items.append(root)
	for item: GeometryInstance3D in items:
		# The setting the piece came with is the one it has in the open.
		if not item.has_meta(&"outdoor_shadow"):
			item.set_meta(&"outdoor_shadow", item.cast_shadow)
		LightLayers.set_layers(item, (1 | LightLayers.ROOMS) if _zone == 1 else 1)
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _zone == 1 or near_lit_lamp \
			else item.get_meta(&"outdoor_shadow")
