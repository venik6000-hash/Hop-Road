class_name NpcPopulation
extends Node3D
const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
## Where the staff stand at work.
const WORK := {
	PeopleIds.BORR: Vector3(11.75, 6.95, -12.32),
	PeopleIds.TOMAS: Vector3(21.15, 6.66, -4.78),
	PeopleIds.MARTA: Vector3(23.7, 6.66, -8.61),
	PeopleIds.LINA: Vector3(13.9, 6.95, -10.78),
}
## Where the maid stands to wipe the small table by the counter (centre
## 12.6, -8.75, radius 0.46 m), between its stools, and the way she faces it.
const TABLE_WIPE := Vector3(12.26, 6.95, -9.34)
const TABLE_WIPE_YAW := -2.62
var actors: Array[VillageNPC] = []
var bartender: VillageNPC
## The innkeeper's keg, tankard and draw at his place behind the counter.
var bar: NpcBarWork
## The villagers' sheets and what has grown between them and the player.
var people := PeopleBook.load_folder()
## The ragdolls the villagers run at once (VillageNPC.bump).
var ragdolls := RagdollBudget.new()

func _ready() -> void:
	bartender = settle(PeopleIds.BORR, "innkeeper", "bartender", WORK[PeopleIds.BORR], PI)
	if bartender != null:
		bar = NpcBarWork.new()
		bar.name = "Bar"
		bar.actor = bartender
		bar.transform = Transform3D(Basis(Vector3.UP, PI), WORK[PeopleIds.BORR])
		add_child(bar)
		bartender.bar = bar
		bartender.posed.connect(bar.follow)
	# The cook and his brother wear the monk's model here: the licence of
	# theirs does not let its files be shared.
	settle(PeopleIds.TOMAS, "monk", "chop", WORK[PeopleIds.TOMAS])
	settle(PeopleIds.MARTA, "bartender", "stir", WORK[PeopleIds.MARTA])
	var cutting := Node3D.new()
	cutting.name = "FoodPreparation"
	add_child(cutting)
	cutting.position = Vector3(21.22, 7.60, -5.21)
	var board := BoxMesh.new()
	board.size = Vector3(0.32, 0.018, 0.23)
	NpcProps.mesh(cutting, board, Color("85633f"))
	for i in range(4):
		var carrot := NpcProps.mesh(cutting, NpcProps.cylinder(0.013, 0.04), Color("b97a3f"), Vector3(0.04 * i - 0.06, 0.022, -0.025))
		carrot.rotation.x = PI / 2.0
	var pot := Node3D.new()
	pot.name = "CookingStew"
	add_child(pot)
	pot.position = Vector3(23.7, 7.15, -9.12)
	NpcProps.mesh(pot, NpcProps.cylinder(0.17, 0.18, true), Color("786847"), Vector3.ZERO, 0.5)
	NpcProps.mesh(pot, NpcProps.cylinder(0.155, 0.012), Color("704b26"), Vector3.UP * 0.075)
	# These never move: the lamps draw them into their shadow maps with the
	# tavern's own pieces.
	for prop: Node3D in [cutting, pot]:
		for item: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
			item.layers |= TavernSystem.SHADOW_LAYER
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
	var maid := settle(PeopleIds.LINA, "maid", "maid", WORK[PeopleIds.LINA])
	if maid != null:
		maid.route.assign([WORK[PeopleIds.LINA], TABLE_WIPE, Vector3(13.9,6.95,-7.5), Vector3(11,6.95,-7.5), Vector3(11,6.95,-3.0)])
		# She wipes the counter facing it, the other hand on its top, and the small
		# table by it from its free side, a narrower strip on the round top and the
		# other hand at her side.
		maid.wipes = {0: {"yaw": 0.0, "middle": 0.1, "across": 0.16, "near": 0.33, "far": 0.42,
				"rest": Vector3(-0.25, 0.0, -0.34)},
			1: {"yaw": TABLE_WIPE_YAW, "middle": 0.08, "across": 0.12, "near": 0.27, "far": 0.36, "drop": 0.17, "rest": Vector3.ZERO}}
	# The tested village road; no diagonal shortcuts through houses. Beside
	# the tavern's yard its retaining wall takes the lane's east side, and
	# the road keeps a metre further west.
	var road: Array[Vector3] = []
	for source_y in range(-12, 45, 4):
		var y := float(source_y)
		var x := VILLAGE_LAYOUT.road_x(y)
		x -= smoothstep(-12.0, -8.0, y) * (1.0 - smoothstep(0.0, 4.0, y))
		road.append(Vector3(x, 15, -y))
	var monk := settle(PeopleIds.SAVVA, "monk", "wander", road[3])
	if monk != null: monk.route.assign(road)
	# The innkeeper's double and the cook's are their brothers; both join the
	# village foot traffic.
	for i in range(2):
		var villager := settle([PeopleIds.KUL, PeopleIds.IVAR][i], ["innkeeper", "monk"][i], "wander", road[6 + i * 3])
		if villager != null: villager.route.assign(road)
	_place_walkers.call_deferred()

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
	actor.ragdolls = ragdolls
	actor.job = job
	actor.title = title
	actor.name = job.to_pascal_case() + str(actors.size())
	actor.position = point
	actor.rotation.y = yaw
	add_child(actor)
	actors.append(actor)
	return actor

func _place_walkers() -> void:
	await get_tree().physics_frame
	var exclude: Array[RID] = []
	for actor in actors: exclude.append(actor.get_rid())
	for actor in actors:
		if actor.job != "wander": continue
		var nearest := 0
		var best := INF
		for i in actor.route.size():
			var distance := Vector2(actor.route[i].x - actor.position.x, actor.route[i].z - actor.position.z).length()
			if distance < best:
				best = distance
				nearest = i
		actor._point = mini(nearest + 1, actor.route.size() - 1)
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
