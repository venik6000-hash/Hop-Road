class_name NpcPopulation
extends Node3D
var actors: Array[VillageNPC] = []
var bartender: VillageNPC
## The villagers' sheets and what has grown between them and the player.
var people := PeopleBook.load_folder()

func _ready() -> void:
	bartender = settle("borr", "civilian_1", "bartender", Vector3(11.6, 6.95, -12.43), PI)
	# The cook and his brother wear the monk's model here: the licence of
	# theirs does not let its files be shared.
	settle("tomas", "monk", "chop", Vector3(21.15, 6.66, -4.78))
	settle("marta", "bartender", "stir", Vector3(23.7, 6.66, -8.61))
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
	puff.material = NpcProps.material(Color(0.65,0.62,0.57,0.15))
	puff.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam.mesh = puff
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var maid := settle("lina", "bartender", "maid", Vector3(13.9, 6.95, -10.65))
	if maid != null:
		maid.route.assign([Vector3(13.9,6.95,-10.65), Vector3(13.9,6.95,-7.5), Vector3(11,6.95,-7.5), Vector3(11,6.95,-3.0)])
	# The tested village road; no diagonal shortcuts through houses. Beside
	# the tavern's yard its retaining wall takes the lane's east side, and
	# the road keeps a metre further west.
	var road: Array[Vector3] = []
	for source_y in range(-12, 45, 4):
		var y := float(source_y)
		var x := -3.5 + 3.5 * sin((y + 11.0) * 0.079) - 0.09 * maxf(0.0, y) + 0.63 * maxf(0.0, -y - 3.0) - minf(10.0, maxf(0.0, (y - 20.0) * 0.5))
		x -= smoothstep(-12.0, -8.0, y) * (1.0 - smoothstep(0.0, 4.0, y))
		road.append(Vector3(x, 15, -y))
	var monk := settle("savva", "monk", "wander", road[3])
	if monk != null: monk.route.assign(road)
	# The innkeeper's double and the cook's are their brothers; both join the
	# village foot traffic.
	for i in range(2):
		var villager := settle(["kul", "ivar"][i], ["civilian_1", "monk"][i], "wander", road[6 + i * 3])
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
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, 40, point.z), Vector3(point.x, -10, point.z), 1)
		ray.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): actor.global_position = hit.position + Vector3.UP * 0.03

## The villager with the sheet `person`; null when there is none.
func actor_of(person: String) -> VillageNPC:
	for actor in actors:
		if actor.person_id == person:
			return actor
	return null
