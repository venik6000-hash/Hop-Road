class_name LampShadowGuard
extends Node
## Keeps what lives out of the lanterns' shadow maps. A lamp keeps its map
## while nothing that casts a shadow moves in its reach; a dog asleep by the
## door breathes, and every lantern near it drew its map again in each frame
## of the night (two lanterns and a porch lamp: a thousand draw calls). So a
## skinned body within reach of a lit lantern casts no shadow until it leaves
## or the lantern goes out: it stays lit by the lamp, and loses only a shadow
## the moon would have given it. The lanterns and the animals are the
## content's (WorldContext.lamps, WorldContext.animals).

## Seconds between looks.
const INTERVAL := 0.25
## Beyond a lantern's range, m: a body's bounds reach further than its origin.
const MARGIN := 2.5
## Looks between two searches for bodies that came or went.
const SEARCH_EVERY := 20

## The content's lamps (WorldContext.lamps): Callable() -> LampSet, whose
## lanterns outdoors cast shadows.
var givers: ContentRegistry
## Where the content's animals are (WorldContext.animals): their skinned
## meshes are found below these nodes.
var animals: ContentRegistry
var population: NpcPopulation

var _clock := 0.0
var _looks := 0
var _bodies: Array[MeshInstance3D] = []

func _ready() -> void:
	if animals != null:
		animals.added.connect(_animals_changed)
		animals.removed.connect(_animals_changed)

## Animals came or went: the bodies are looked for again at the next look.
func _animals_changed(_entry: Variant) -> void:
	_bodies.clear()
	_looks = 0

## The lanterns outdoors that cast shadows, of every lamp of the content.
func lamps() -> Array[Light3D]:
	var found: Array[Light3D] = []
	if givers != null:
		for entry: Variant in givers.entries():
			var lamps_for: Callable = entry
			var given: LampSet = lamps_for.call()
			found.append_array(given.lanterns)
	return found

## The nodes the animals are below.
func roots() -> Array[Node]:
	var found: Array[Node] = []
	if animals != null:
		for entry: Variant in animals.entries():
			var root: Node = entry
			found.append(root)
	return found

func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = INTERVAL
	if _looks % SEARCH_EVERY == 0:
		_search()
	_looks += 1
	var lit: Array[Light3D] = []
	for lamp: Light3D in lamps():
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
				actor.lamp_zone.near_lit_lamp = _near(actor.global_position, lit)

static func _near(point: Vector3, lit: Array[Light3D]) -> bool:
	for lamp: Light3D in lit:
		var reach: float = ((lamp as OmniLight3D).omni_range if lamp is OmniLight3D else (lamp as SpotLight3D).spot_range) + MARGIN
		if point.distance_squared_to(lamp.global_position) < reach * reach:
			return true
	return false

func _search() -> void:
	_bodies.clear()
	for root: Node in roots():
		for body: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if body.skin == null:
				continue
			# The setting the body came with is the one it has in the open.
			if not body.has_meta(&"open_shadow"):
				body.set_meta(&"open_shadow", body.cast_shadow)
			if body.get_meta(&"open_shadow") != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				_bodies.append(body)
