class_name VillagerSpots
extends RefCounted
## Where a villager's body can be put (VillagerPresence): on the ground, with
## room for the capsule and nobody too near. Finds the point of their road,
## the spot of the yard and the way out of a seat.

## How near another body a villager is not put.
const ELBOW := 0.6
## How near another body a walker is not put on the road.
const ROAD_GAP := 3.0
## The centre of a villager's capsule over the feet, and the gap left under it
## for the unevenness of the ground.
const BODY_CENTRE := 0.83
const BODY_GAP := 0.1
## The height of the yard's ground, and how far from it a place to stand may
## lie: the steps of the door and the top of a barrel are not the yard.
const YARD_LEVEL := 6.6
const YARD_STEP := 0.3
## The rings round a yard spot that are tried when the spot itself is taken.
const YARD_RINGS: Array[float] = [0.6, 1.2, 1.8]

var population: NpcPopulation
var player: Player
var interactions: TavernInteractions
var sight: VillagerSight
var _fit := PhysicsShapeQueryParameters3D.new()

func _init(people: NpcPopulation, viewer: Player, hall: TavernInteractions, seen: VillagerSight) -> void:
	population = people
	player = viewer
	interactions = hall
	sight = seen
	var body := CapsuleShape3D.new()
	body.radius = VillageNPC.RADIUS
	body.height = VillageNPC.HEIGHT
	_fit.shape = body
	_fit.collision_mask = PhysicsLayers.GROUND | PhysicsLayers.PLAYER | PhysicsLayers.VILLAGERS

## The point of the villager's road farthest from the player among those the
## player does not see; the farthest of all when every one is seen:
## {at: Vector3, index: the route point}, {} when there is none.
func road_goal(actor: VillageNPC) -> Dictionary:
	var out_of_sight: Dictionary = {}
	var in_sight: Dictionary = {}
	var farthest_hidden := -1.0
	var farthest_seen := -1.0
	var route := actor.rounds.route
	for index in route.size():
		var ground := _ground(route[index].x, route[index].z, 40.0, -10.0)
		if ground.is_empty():
			continue
		var at: Vector3 = ground.position
		if _crowded(actor, at, ROAD_GAP):
			continue
		var distance := at.distance_to(player.global_position)
		if sight.unseen(at, actor):
			if distance > farthest_hidden:
				farthest_hidden = distance
				out_of_sight = {"at": at, "index": index}
		elif distance > farthest_seen:
			farthest_seen = distance
			in_sight = {"at": at, "index": index}
	return out_of_sight if not out_of_sight.is_empty() else in_sight

## The villager's spot of the yard, or the nearest place round it where a
## body can stand: {at: Vector3}, {} when there is none.
func yard_goal(actor: VillageNPC, sheet: PersonSheet) -> Dictionary:
	if not sheet.has_yard_spot():
		return {}
	var tries: Array[Vector2] = [sheet.yard_spot]
	for radius: float in YARD_RINGS:
		for index in range(8):
			var angle := TAU * float(index) / 8.0
			tries.append(sheet.yard_spot + Vector2(cos(angle), sin(angle)) * radius)
	for spot: Vector2 in tries:
		var ground := _ground(spot.x, spot.y, YARD_LEVEL + 1.9, YARD_LEVEL - 1.0)
		if ground.is_empty():
			continue
		var normal: Vector3 = ground.normal
		var feet: Vector3 = ground.position
		if normal.y >= 0.7 and absf(feet.y - YARD_LEVEL) <= YARD_STEP and _fits(actor, feet):
			return {"at": feet}
	return {}

## The villager who got up from `seat` steps to the first way out of it where
## a body can stand; when every way out is taken, anywhere round the seat with
## a floor and room for a body.
func step_out(actor: VillageNPC, seat: Dictionary) -> void:
	var exits: Array = seat.get("exits", [])
	for exit: Variant in exits:
		if not exit is Array:
			continue
		var way: Array = exit
		var point := Values.vec3(way)
		if _fits(actor, point):
			actor.global_position = point + Vector3.UP * 0.015
			return
	var origin := Values.vec3(seat.position)
	var stepped := false
	for radius: float in [0.8, 1.0, 1.25]:
		for index in range(16):
			var angle := TAU * float(index) / 16.0
			var around := origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if not stepped and interactions.can_stand(around) and _fits(actor, around):
				actor.global_position = around + Vector3.UP * 0.015
				stepped = true

## Whether the villager's body can stand with its feet at `feet`: nothing
## solid is in its way and nobody stands there.
func _fits(actor: VillageNPC, feet: Vector3) -> bool:
	_fit.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (BODY_CENTRE + BODY_GAP))
	var passed: Array[RID] = [actor.get_rid()]
	_fit.exclude = passed
	if not _space().intersect_shape(_fit, 1).is_empty():
		return false
	return not _crowded(actor, feet, ELBOW)

## Whether the player or another villager who is in the valley stands within
## `reach` of `at`.
func _crowded(actor: VillageNPC, at: Vector3, reach: float) -> bool:
	if player.global_position.distance_to(at) < reach:
		return true
	for other in population.actors:
		if other != actor and is_instance_valid(other) and other.visible and other.global_position.distance_to(at) < reach:
			return true
	return false

## The ground under (x, z) between two heights, through the people.
func _ground(x: float, z: float, top: float, bottom: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, bottom, z), PhysicsLayers.GROUND)
	var passed: Array[RID] = [player.get_rid()]
	for actor in population.actors:
		if is_instance_valid(actor):
			passed.append(actor.get_rid())
	query.exclude = passed
	return _space().intersect_ray(query)

func _space() -> PhysicsDirectSpaceState3D:
	return population.get_world_3d().direct_space_state
