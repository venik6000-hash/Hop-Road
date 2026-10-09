class_name LampShadowGuard
extends Node
## Keeps what lives out of the lanterns' shadow maps. A lamp keeps its map
## while nothing that casts a shadow moves in its reach; a dog asleep by the
## door breathes, and every lantern near it drew its map again in each frame
## of the night (two lanterns and a porch lamp: a thousand draw calls). So a
## skinned body within reach of a lit lantern casts no shadow until it leaves
## or the lantern goes out: it stays lit by the lamp, and loses only a shadow
## the moon would have given it.

## Seconds between looks.
const INTERVAL := 0.25
## Beyond a lantern's range, m: a body's bounds reach further than its origin.
const MARGIN := 2.5
## Looks between two searches for bodies that came or went.
const SEARCH_EVERY := 20

## The lanterns outdoors that cast shadows.
var lamps: Array[Light3D] = []
## Where the animals are (their skinned meshes are found below these).
var roots: Array[Node] = []
var population: NpcPopulation

var _clock := 0.0
var _looks := 0
var _bodies: Array[MeshInstance3D] = []

func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = INTERVAL
	if _looks % SEARCH_EVERY == 0:
		_search()
	_looks += 1
	var lit: Array[Light3D] = []
	for lamp: Light3D in lamps:
		if lamp.visible and lamp.shadow_enabled:
			lit.append(lamp)
	for body: MeshInstance3D in _bodies:
		if not is_instance_valid(body):
			continue
		var near := _near(body.global_position, lit)
		var wanted: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if near else body.get_meta(&"open_shadow")
		if body.cast_shadow != wanted:
			body.cast_shadow = wanted
	if population != null:
		for actor: VillageNPC in population.actors:
			if is_instance_valid(actor):
				actor.near_lit_lamp = _near(actor.global_position, lit)

static func _near(point: Vector3, lit: Array[Light3D]) -> bool:
	for lamp: Light3D in lit:
		var reach: float = (lamp.omni_range if lamp is OmniLight3D else lamp.spot_range) + MARGIN
		if point.distance_squared_to(lamp.global_position) < reach * reach:
			return true
	return false

func _search() -> void:
	_bodies.clear()
	for root: Node in roots:
		if not is_instance_valid(root):
			continue
		for body: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if body.skin == null:
				continue
			# The setting the body came with is the one it has in the open.
			if not body.has_meta(&"open_shadow"):
				body.set_meta(&"open_shadow", body.cast_shadow)
			if body.get_meta(&"open_shadow") != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				_bodies.append(body)
