class_name NpcPopulation
extends Node3D
## The people of a region (RegionDef.villagers): the tavern's staff at their
## work, the villagers on their walks along the village road, and passers-by
## without a sheet of their own. Where the staff work in the tavern (the
## cook's board and pot, the maid's round) is the tavern's
## (RegionDef.tavern_work); how they work there (the innkeeper's bar, the
## cook's board and pot, the maid's wiping) is their job's (NpcJob).

## The region's file of who lives there (PeopleSchemas.villagers); "" for
## nobody.
var villagers := ""
## The region's file of where the tavern's staff work
## (BuildingSchemas.tavern_work); "" for a tavern without that work.
var tavern_work := ""
## The level's rooms: an actor in one is lit by its lamps (NpcLampZone). Set
## before the population enters the tree; null in a tool without them.
var interiors: Interiors
var actors: Array[VillageNPC] = []
var bartender: VillageNPC
## The innkeeper's keg, tankard and draw at his place behind the counter.
var bar: NpcBarWork
## The villagers' sheets and what has grown between them and the player.
var people := PeopleBook.load_folder()
## The ragdolls the villagers run at once (NpcPoses.bump).
var ragdolls := RagdollBudget.new()

func _ready() -> void:
	var data: Variant = DataFile.read(villagers, PeopleSchemas.villagers()) if not villagers.is_empty() else {}
	var cast: Dictionary = data if data is Dictionary else {}
	var spots: Variant = DataFile.read(tavern_work, BuildingSchemas.tavern_work()) if not tavern_work.is_empty() else {}
	var work: Dictionary = spots if spots is Dictionary else {}
	var staff: Array = cast.get("staff", [])
	for entry: Dictionary in staff:
		var actor := settle(str(entry.person), str(entry.model), str(entry.job), Values.vec3(entry.at),
			deg_to_rad(Values.real(entry.yaw)))
		if actor != null:
			actor.duty.place_work(self, actor, work)
	var road: Array[Vector3] = []
	for point: Variant in Values.list(cast.get("road", [])):
		road.append(Values.vec3(point))
	var walkers: Array = cast.get("walkers", [])
	for entry: Dictionary in walkers:
		var walker := settle(str(entry.person), str(entry.model), "wander", road[mini(Values.whole(entry.from), road.size() - 1)])
		if walker != null:
			walker.rounds.route.assign(road)
	var passers: Array = cast.get("passers", [])
	for entry: Dictionary in passers:
		var passer := spawn(str(entry.model), "wander", str(entry.title), road[mini(Values.whole(entry.from), road.size() - 1)])
		if passer != null:
			passer.rounds.route.assign(road)
			passer.rounds.wait_time = Values.real(entry.wait)
	place_walkers.call_deferred()

## A villager with a sheet (PeopleBook): goes by the role until the name is told.
func settle(person: String, model: String, job: String, point: Vector3, yaw := 0.0) -> VillageNPC:
	var actor := spawn(model, job, people.label(person), point, yaw)
	if actor != null:
		actor.person_id = person
		actor.work_point = point
		actor.work_yaw = yaw
	return actor

## What the player has with the villagers, for the save (section "people").
func to_dict() -> Dictionary:
	return people.to_dict()

## Takes back to_dict(): those who told their names go by them again.
func restore(saved: Dictionary) -> void:
	people.restore(saved)
	refresh_titles()

## Names the villagers by what the player knows of them now.
func refresh_titles() -> void:
	for actor in actors:
		if people.knows(actor.person_id):
			actor.title = people.label(actor.person_id)

func spawn(model: String, job: String, title: String, point: Vector3, yaw := 0.0) -> VillageNPC:
	var path := "res://assets/models/npc/" + model + ".glb"
	if not ResourceLoader.exists(path):
		push_error("Missing NPC model: " + path)
		return null
	var actor := VillageNPC.new()
	actor.model_path = path
	actor.poses.ragdolls = ragdolls
	actor.job = job
	actor.title = title
	actor.name = job.to_pascal_case() + str(actors.size())
	actor.position = point
	actor.rotation.y = yaw
	actor.lamp_zone.interiors = interiors
	add_child(actor)
	actors.append(actor)
	return actor

## Puts each walker on the ground under them, the next point of the road
## ahead, once the ground under the first of them answers a ray.
func place_walkers() -> void:
	var walkers := actors.filter(func(actor: VillageNPC) -> bool: return actor.duty.walks)
	if walkers.is_empty():
		return
	var first: VillageNPC = walkers[0]
	await PhysicsLayers.ground_stands(self, first.global_position)
	if not is_inside_tree():
		return
	var exclude: Array[RID] = []
	for actor in actors: exclude.append(actor.get_rid())
	for actor in actors:
		if not actor.duty.walks: continue
		var nearest := 0
		var best := INF
		for i in actor.rounds.route.size():
			var distance := Vector2(actor.rounds.route[i].x - actor.position.x, actor.rounds.route[i].z - actor.position.z).length()
			if distance < best:
				best = distance
				nearest = i
		actor.rounds.route_point = mini(nearest + 1, actor.rounds.route.size() - 1)
		var point := actor.global_position
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, 40, point.z), Vector3(point.x, -10, point.z), PhysicsLayers.GROUND)
		ray.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): actor.global_position = hit.position + Vector3.UP * 0.03

## The villager with the sheet `person`; null when there is none.
func actor_of(person: String) -> VillageNPC:
	for actor in actors:
		if actor.person_id == person:
			return actor
	return null
