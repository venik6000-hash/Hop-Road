class_name WildlifeSystem
extends Node3D
## Habitat placement and distance budgets for the alpine world's wildlife:
## the herds, flocks, fish waters and birdsong of the region's file
## (RegionDef.wildlife; "" for none), and the lake's bed.

## The region's file of its wild animals (WorldSchemas.wildlife).
var wildlife := ""
var terrain: TerrainSystem
var player: Player
var sky: SkySystem
var water: WaterSystem
var rocks: RockField
var ground_animals: Array[GroundAnimal] = []
var flyers: Array[FlyingAnimal] = []
var schools: Array[FishSchool] = []
var bed: LakeBed
## The level's rooms: the lake bed's pieces are hidden from an eye in a room
## that sees none of them (Interiors.watch_pieces). Null: never hidden.
var interiors: Interiors
var ready_for_visitors := false
var auto_populate := true
var audio: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _budget_clock := 0.0
var _clearance: Dictionary = {}

func _ready() -> void:
	_rng.seed = 702026
	for kind: String in ["deer", "fox", "chicken"]:
		var shape := CapsuleShape3D.new()
		shape.radius = 0.36 if kind == "deer" else 0.22
		shape.height = 1.25 if kind == "deer" else 0.48
		_clearance[kind] = shape
	if auto_populate:
		populate.call_deferred()

func populate() -> void:
	await get_tree().physics_frame
	var data: Variant = DataFile.read(wildlife, WorldSchemas.wildlife()) if not wildlife.is_empty() else {}
	var plan: Dictionary = data if data is Dictionary else {}
	var herds: Array = plan.get("herds", [])
	for herd: Dictionary in herds:
		var middle := Values.vec2(herd.at)
		_add_ground(str(herd.kind), Vector3(middle.x, 0.0, middle.y), Values.real(herd.radius), Values.whole(herd.count))
	var flocks: Array = plan.get("flocks", [])
	for flock: Dictionary in flocks:
		var middle := Values.vec2(flock.at)
		_add_flock(str(flock.kind), Vector3(middle.x, 0.0, middle.y), Values.whole(flock.count), str(flock.get("species", "bird")))
	bed = LakeBed.new()
	bed.name = "LakeBed"
	bed.habitat = self
	add_child(bed)
	if interiors != null:
		interiors.watch_pieces(bed, bed.seen_bounds)
	await bed.build()
	if plan.has("fish_water"):
		var box: Array = plan.fish_water
		_add_schools(Vector4(Values.real(box[0]), Values.real(box[1]), Values.real(box[2]), Values.real(box[3])))
	if plan.has("birdsong"):
		_setup_audio(Values.vec2(plan.birdsong))
	ready_for_visitors = true
	print("WILDLIFE ground=%d flyers=%d schools=%d fish=%d wood=%d boulders=%d plants=%d" % [ground_animals.size(), flyers.size(), schools.size(), fish_count(), bed.wood_count, bed.rock_count, bed.plant_count])

func _add_ground(kind: String, zone: Vector3, radius: float, count: int) -> void:
	for index in count:
		var point := ground_target(zone, radius, kind, _rng)
		if not ground_safe(point, kind):
			continue
		var animal := GroundAnimal.new()
		animal.name = kind.capitalize() + str(ground_animals.size())
		animal.kind = kind
		animal.habitat = self
		animal.home = point
		animal.home_radius = radius
		animal.position = point + Vector3.UP * 0.08
		animal.rotation.y = _rng.randf_range(0, TAU)
		animal.rng.seed = _rng.randi()
		add_child(animal)
		ground_animals.append(animal)

func ground_target(home: Vector3, radius: float, kind: String, rng: RandomNumberGenerator) -> Vector3:
	for attempt in 24:
		var angle := rng.randf_range(0, TAU)
		var distance := sqrt(rng.randf()) * radius
		var point := home + Vector3(cos(angle), 0, sin(angle)) * distance
		point.y = terrain.height_at(point.x, point.z)
		if ground_safe(point, kind):
			return point
	return Vector3(home.x, terrain.height_at(home.x, home.z), home.z)

func ground_safe(point: Vector3, kind: String) -> bool:
	var y := terrain.height_at(point.x, point.z)
	if y < terrain.water_level + 0.8:
		return false
	var slope := Vector2(terrain.height_at(point.x + 0.8, point.z) - y,
		terrain.height_at(point.x, point.z + 0.8) - y).length() / 0.8
	if slope > 0.65:
		return false
	var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, y + 16.0, point.z), Vector3(point.x, y - 1.0, point.z), PhysicsLayers.GROUND)
	if player != null:
		ray.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not PhysicsLayers.hit_terrain(hit):
		return false
	var shape: CapsuleShape3D = _clearance[kind]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, Values.real(hit.position.y + shape.height * 0.5 + 0.12), point.z))
	query.collision_mask = PhysicsLayers.GROUND | PhysicsLayers.VILLAGERS
	if player != null:
		query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _add_flock(kind: String, zone: Vector3, count: int, species := "bird") -> void:
	zone.y = maxf(terrain.height_at(zone.x, zone.z), terrain.water_level)
	for index in count:
		var flyer := FlyingAnimal.new()
		flyer.name = kind.capitalize() + str(flyers.size())
		flyer.kind = kind
		flyer.species = species
		flyer.habitat = self
		flyer.home = zone
		if kind == "bird":
			flyer.phase = float(index) * 0.045 + _rng.randf_range(0, 0.02)
			flyer.flock_offset = Vector3(index * 1.3, index * 0.5, index * 0.6)
			match species:
				"seagull":
					flyer.radius = Vector2(42, 26)
					flyer.height = _rng.randf_range(5, 11)
					flyer.rate = 0.1
				"raven":
					flyer.radius = Vector2(30, 22)
					flyer.height = _rng.randf_range(22, 34)
					flyer.rate = 0.12
				_:
					flyer.radius = Vector2(25, 17)
					flyer.height = _rng.randf_range(12, 20)
					flyer.rate = 0.19
		else:
			flyer.radius = Vector2(_rng.randf_range(1.5, 5), _rng.randf_range(1.5, 4))
			flyer.phase = _rng.randf_range(0, TAU)
			flyer.height = _rng.randf_range(0.65, 1.2)
			flyer.rate = _rng.randf_range(0.25, 0.55)
		add_child(flyer)
		flyers.append(flyer)

## Schools where each species lives: rudd in open water within `box` (x0,
## z0, x1, z1), perch over the eelgrass, trout by the drowned wood, a pike at
## a meadow's edge.
func _add_schools(box: Vector4) -> void:
	var meadows := bed.meadow_centers.duplicate()
	var wood := bed.wood_places.duplicate()
	meadows.shuffle()
	wood.shuffle()
	var plans: Array[Dictionary] = []
	for index in mini(5, meadows.size()):
		plans.append({"species": "perch", "at": meadows[index]})
	for index in mini(5, wood.size()):
		plans.append({"species": "trout", "at": wood[index]})
	for index in range(5, mini(8, meadows.size())):
		plans.append({"species": "pike", "at": meadows[index] + Vector3(bed.PLANTS.eelgrass.radius.x, 0, 0)})
	for attempt in 140:
		if plans.size() >= 20:
			break
		var point := Vector3(_rng.randf_range(box.x, box.z), 0, _rng.randf_range(box.y, box.w))
		var depth := terrain.water_level - terrain.height_at(point.x, point.z)
		if depth < 4.0 or depth > 18.0:
			continue
		var valid := true
		for sample in 16:
			var angle := TAU * sample / 16.0
			if terrain.height_at(point.x + cos(angle) * 10, point.z + sin(angle) * 8) > terrain.water_level - 2.7:
				valid = false
		for plan in plans:
			var planned: Vector3 = plan.at
			if point.distance_to(planned) < 10:
				valid = false
		if valid:
			plans.append({"species": "fish", "at": point})
	for plan in plans:
		var point: Vector3 = plan.at
		var floor_y := maxf(terrain.height_at(point.x, point.z), bed.seabed_at(point.x, point.z))
		var depth := terrain.water_level - floor_y
		var habit: Dictionary = FishSchool.HABITS[plan.species]
		if depth < habit.hover.x + habit.below + 0.6:
			continue
		var school := FishSchool.new()
		school.name = "School" + str(schools.size())
		school.habitat = self
		school.species = plan.species
		school.center = Vector3(point.x, floor_y + minf(depth * 0.5, 2.0), point.z)
		school.phase = _rng.randf_range(0, TAU)
		school.count = FishSchool.HABITS[plan.species].count + (schools.size() % 3 if plan.species in ["fish", "perch"] else 0)
		add_child(school)
		schools.append(school)

func fish_count() -> int:
	var total := 0
	for school in schools:
		total += school.fishes.size()
	return total

## The birdsong of the woods, sounding over the ground at `at` (x, z).
func _setup_audio(at: Vector2) -> void:
	audio = AudioStreamPlayer3D.new()
	audio.name = "ForestBirdsong"
	var birdsong: AudioStreamOggVorbis = load(WildlifeModel.DIRECTORY + "birds.ogg")
	audio.stream = birdsong
	birdsong.loop = true
	audio.unit_size = 24.0
	audio.max_distance = 230.0
	audio.volume_db = -16.0
	audio.bus = AudioBuses.AMBIENCE
	audio.position = Vector3(at.x, terrain.height_at(at.x, at.y) + 7, at.y)
	add_child(audio)
	audio.play()

func _process(delta: float) -> void:
	if not ready_for_visitors:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and water != null and bed != null:
		var heading := deg_to_rad(water.ocean.wind_direction_deg)
		var speed: float = water.ocean.wind_speed
		bed.set_wind(Vector4(cos(heading), sin(heading), minf(pow(speed / 9.0, 1.6), 2.2), speed), camera.global_position)
	_budget_clock -= delta
	if _budget_clock > 0.0:
		return
	_budget_clock = 0.5
	if camera == null:
		return
	var eye := camera.global_position
	var day := sky == null or (sky.time_of_day > 5.5 and sky.time_of_day < 20.5)
	for animal in ground_animals:
		animal.set_active(animal.global_position.distance_squared_to(eye) < 135.0 * 135.0)
	for flyer in flyers:
		var distance := 270.0 if flyer.kind == "bird" else 42.0
		flyer.set_active(flyer.global_position.distance_squared_to(eye) < distance * distance)
		flyer.visible = day
	for school in schools:
		school.set_active(school.center.distance_squared_to(eye) < 80.0 * 80.0)
	if audio == null:
		return
	var weather_loss := maxf(0, water.ocean.wind_speed - 6.0) * 0.8 if water != null else 0.0
	audio.volume_db = -16.0 - weather_loss - (0.0 if day else 30.0) - (22.0 if eye.y < terrain.water_level else 0.0)
