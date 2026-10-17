class_name NpcPopulation
extends Node3D
## The people of a region (RegionDef.villagers): the tavern's staff at their
## work, the villagers on their walks along the village road, and passers-by
## without a sheet of their own. Where the staff work in the tavern (the
## cook's board and pot, the maid's round) is the tavern's
## (RegionDef.tavern_work); how they work there (the innkeeper's bar, the
## cook's board and pot, the maid's wiping) is here.

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
		var at := Values.vec3(entry.at)
		var job := str(entry.job)
		var actor := settle(str(entry.person), str(entry.model), job, at, deg_to_rad(Values.real(entry.yaw)))
		if actor == null:
			continue
		if job == "bartender":
			bartender = actor
			bar = NpcBarWork.new()
			bar.name = "Bar"
			bar.actor = bartender
			bar.transform = Transform3D(Basis(Vector3.UP, actor.work_yaw), at)
			add_child(bar)
			bartender.bar = bar
			bartender.posed.connect(bar.follow)
		elif job == "chop" and work.has("board"):
			_add_board(Values.vec3(work.board))
		elif job == "stir" and work.has("pot"):
			_add_pot(Values.vec3(work.pot))
		elif job == "maid" and work.has("round"):
			var round_route: Array[Vector3] = [at]
			for point: Variant in Values.list(work.round):
				round_route.append(Values.vec3(point))
			actor.rounds.route.assign(round_route)
			# She wipes the counter facing it, the other hand on its top, and the small
			# table by it from its free side, a narrower strip on the round top and the
			# other hand at her side.
			for wipe: Dictionary in Values.list(work.wipes):
				var row := wipe.duplicate()
				row.rest = Values.vec3(wipe.rest)
				actor.rounds.wipes[Values.whole(wipe.stop)] = row
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

## The cook's cutting board with the carrots on it, at `at`.
func _add_board(at: Vector3) -> void:
	var cutting := Node3D.new()
	cutting.name = "FoodPreparation"
	add_child(cutting)
	cutting.position = at
	var board := BoxMesh.new()
	board.size = Vector3(0.32, 0.018, 0.23)
	NpcProps.mesh(cutting, board, Color("85633f"))
	for i in range(4):
		var carrot := NpcProps.mesh(cutting, NpcProps.cylinder(0.013, 0.04), Color("b97a3f"), Vector3(0.04 * i - 0.06, 0.022, -0.025))
		carrot.rotation.x = PI / 2.0
	_shade_with_tavern(cutting)

## The stew's pot, steaming, at `at`.
func _add_pot(at: Vector3) -> void:
	var pot := Node3D.new()
	pot.name = "CookingStew"
	add_child(pot)
	pot.position = at
	NpcProps.mesh(pot, NpcProps.cylinder(0.17, 0.18, true), Color("786847"), Vector3.ZERO, 0.5)
	NpcProps.mesh(pot, NpcProps.cylinder(0.155, 0.012), Color("704b26"), Vector3.UP * 0.075)
	_shade_with_tavern(pot)
	var steam := CPUParticles3D.new()
	pot.add_child(steam)
	steam.position.y = 0.1
	steam.amount = 10
	steam.lifetime = 1.6
	steam.direction = Vector3.UP
	steam.spread = 10
	steam.initial_velocity_min = 0.15
	steam.initial_velocity_max = 0.25
	steam.gravity = Vector3(0, 0.1, 0)
	steam.scale_amount_min = 0.04
	steam.scale_amount_max = 0.08
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	var puff_material := NpcProps.material(Color(0.65,0.62,0.57,0.15))
	puff.material = puff_material
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam.mesh = puff
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## `prop` never moves: the lamps draw it into their shadow maps with the
## tavern's own pieces.
static func _shade_with_tavern(prop: Node3D) -> void:
	for item: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		item.layers |= LightLayers.LAMP_CASTERS

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

func place_walkers() -> void:
	await get_tree().physics_frame
	var exclude: Array[RID] = []
	for actor in actors: exclude.append(actor.get_rid())
	for actor in actors:
		if actor.job != "wander": continue
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
