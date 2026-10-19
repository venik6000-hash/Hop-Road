class_name Interiors
extends Node
## Every interior of a level (Interior) and what the level's systems ask of
## them (docs/LEVEL.md, «Свет помещений»): how far an eye is indoors, which
## room it is in, what it sees of the outdoors from there, whether the rooms'
## probes have captured their rooms. WorldContext.interiors is the one of the
## level; a building that has rooms adds its Interior here.
##
## It writes the sun's and the moon's shadow masks for every building with
## rooms, and it keeps the one contact-shadow pass of the level (ContactShadows)
## fed with the lamps of the building the eye is in.
##
## What stands outdoors and holds its own place is hidden from an eye in a room
## by the InteriorSight of that room's building. The systems outdoors give it
## their things here (watch(), watch_pieces()); the trees, the grass, the
## ground and the lake ask `sight` themselves.
##
## It is a registry of the shared systems (docs/LEVEL.md, «Реестры»): an
## interior, a watched thing or a tree of pieces goes when its node leaves the
## tree (the interior's lamps, the thing, the root).

## A doorway is this deep: the eye goes from outdoors to indoors over it,
## half of it on each side of the face of a room's box.
const DOORWAY := 1.2
## Metres from a building within which its rooms cast the sun's shadows
## (LightLayers.ROOM_SUN).
const ROOM_SHADOW_REACH := 10.0

var sky: SkySystem
var interiors: Array[Interior] = []
## The level's contact shadows, for the compositor of whoever shows the rooms.
var contact := ContactShadows.new()
## What an eye in a room sees of the outdoors; not active outdoors.
var sight := InteriorSight.Sight.new()
## Counts up whenever `sight` changes: who hides by it looks again.
var revision := 0
## For the log: what each system hides, by its name: (hidden, of how many).
var counts := {}
## Watched things outdoors: {node, box, cast}; `cast` is the node's own
## shadow setting, -1 for a node drawn whole or not at all.
var watched: Array[Dictionary] = []
## Trees of pieces whose geometry is watched one by one: {root, bounds}, with
## `bounds` a Callable that gives a piece's box (its mesh's when empty).
var pieces: Array[Dictionary] = []

var _sight_from: InteriorSight
var _holders := {}
var _rooms_cast := -1

## Adds the interior of a building or a cave; it goes with its lamps.
func add(interior: Interior) -> void:
	interiors.append(interior)
	if interior.contact:
		contact.watch(interior)
	if interior.lamps != null:
		interior.lamps.tree_exiting.connect(_drop_interior.bind(interior), CONNECT_ONE_SHOT)

func _drop_interior(interior: Interior) -> void:
	interiors.erase(interior)
	contact.unwatch(interior)

## Metres the eye is inside the room it is deepest in, of every interior
## (Interior.depth_of); -INF without rooms.
func depth_of(eye: Vector3) -> float:
	var deepest := -INF
	for interior: Interior in interiors:
		deepest = maxf(deepest, interior.depth_of(eye))
	return deepest

## 0 outdoors .. 1 indoors, turning over a doorway's depth.
func inside(eye: Vector3) -> float:
	return share(depth_of(eye))

## The same for an eye `depth` metres inside a room.
static func share(depth: float) -> float:
	return smoothstep(-DOORWAY * 0.5, DOORWAY * 0.5, depth)

## The room the eye is in or nearest to; null without rooms.
func nearest_room(eye: Vector3) -> Interior.Room:
	var deepest := -INF
	var nearest: Interior.Room = null
	for interior: Interior in interiors:
		var depth := interior.depth_of(eye)
		if depth > deepest:
			deepest = depth
			nearest = interior.nearest_room(eye)
	return nearest

## The interior whose building is nearest the eye; null without any.
func nearest(eye: Vector3) -> Interior:
	var best := INF
	var found: Interior = null
	for interior: Interior in interiors:
		var box := interior.bounds
		var away := eye.distance_to(eye.clamp(box.position, box.end))
		if away < best:
			best = away
			found = interior
	return found

## The box the fog stays out of for an eye at `eye`: the rooms of the nearest
## building, as one box (none without rooms).
func fog_box(eye: Vector3) -> AABB:
	var interior := nearest(eye)
	var box := AABB()
	if interior == null:
		return box
	var rooms := interior.room_boxes()
	for index in rooms.size():
		box = rooms[index] if index == 0 else box.merge(rooms[index])
	return box

## Every probe of the rooms has captured its room once: until then the eye
## sees no haze anywhere, so that the first captures have clear air.
func probes_settled() -> bool:
	for interior: Interior in interiors:
		if interior.lamps != null and not interior.lamps.probes.is_empty() and not interior.lamps.probes_captured():
			return false
	return true

## Watches `node` (drawn whole or not at all) by `box` (world space) while
## it stands.
func watch(node: Node3D, box: AABB) -> void:
	watched.append({"node": node, "box": box, "cast": -1})
	if not node.tree_exiting.is_connected(_drop_watched.bind(node)):
		node.tree_exiting.connect(_drop_watched.bind(node), CONNECT_ONE_SHOT)

## Watches the geometry under `root` piece by piece, each by its box: the
## mesh's, or what `bounds` (GeometryInstance3D -> AABB) gives, while `root`
## stands.
func watch_pieces(root: Node, bounds := Callable()) -> void:
	pieces.append({"root": root, "bounds": bounds})
	if not root.tree_exiting.is_connected(_drop_pieces.bind(root)):
		root.tree_exiting.connect(_drop_pieces.bind(root), CONNECT_ONE_SHOT)

func _drop_watched(node: Node3D) -> void:
	watched = watched.filter(func(entry: Dictionary) -> bool: return entry.node != node)

func _drop_pieces(root: Node) -> void:
	pieces = pieces.filter(func(entry: Dictionary) -> bool: return entry.root != root)

## `holder` draws the level from above (RainShelter): nothing may be hidden
## from it while it does.
func hold_sight(holder: Object) -> void:
	_holders[holder] = true

func release_sight(holder: Object) -> void:
	_holders.erase(holder)

func sight_held() -> bool:
	return not _holders.is_empty()

## `from` gives the level what an eye in its rooms sees now.
func show_sight(from: InteriorSight, seen: InteriorSight.Sight) -> void:
	_sight_from = from
	sight = seen
	revision += 1

## `from` sees nothing any more: the eye has left its rooms.
func drop_sight(from: InteriorSight) -> void:
	if _sight_from != from:
		return
	_sight_from = null
	sight = InteriorSight.Sight.new()
	revision += 1

## The line of the portals' log of the building the eye is in (InteriorSight.report).
func report() -> String:
	return _sight_from.report() if _sight_from != null else "PORTALS active=false"

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_update_sun_casters(camera)
	if camera != null:
		contact.prepare(camera.global_position)

## The rooms' pieces are in the sun's shadow map only for an eye that can see
## what they shade (see LightLayers.ROOM_SUN).
func _update_sun_casters(camera: Camera3D) -> void:
	if sky == null:
		return
	var near := camera == null
	for interior: Interior in interiors:
		near = near or interior.bounds.grow(ROOM_SHADOW_REACH).has_point(camera.global_position)
	if int(near) == _rooms_cast:
		return
	_rooms_cast = int(near)
	var mask := 0xFFFFFFFF & ~LightLayers.ROOMS & ~LightLayers.LAMP_CASTERS
	if not near:
		mask &= ~LightLayers.ROOM_SUN
	sky.sun.shadow_caster_mask = mask
	sky.moon.shadow_caster_mask = mask
