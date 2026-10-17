extends RefCounted
## The builders of the level's map, buildings and people (LevelParts): each
## takes what the steps before it built (LevelSystems), adds its system to the
## level and leaves it there for the steps after it.

const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
const VILLAGE_MATERIALS = preload("res://src/village/village_materials.gd")
const VILLAGE_PACK = preload("res://src/village/village_pack.gd")
const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
const GROUND_TRACKS = preload("res://src/terrain/ground_tracks.gd")
const CHIMNEY_SMOKE = preload("res://src/alpine/chimney_smoke.gd")
const STILL_SURFACE = preload("res://src/alpine/surface_still.gdshader")

## The refined tavern in place of the Blender map's blockout one; before the
## vegetation, which scans the colliders it keeps.
static func tavern(s: LevelSystems) -> void:
	s.tavern = TavernSystem.new()
	s.tavern.name = "Tavern"
	s.tavern.map = s.map
	s.tavern.parts = s.region.tavern
	s.tavern.sky_system = s.sky
	s.tavern.terrain = s.terrain
	s.tavern.world = s.world
	s.add(s.tavern)

## The map as the region stands it: its surfaces settled, its pieces edited
## (MapEdits), its houses on their lots, the village's materials.
static func map(s: LevelSystems) -> void:
	_settle_surfaces(s.map)
	MapEdits.apply(s.map, s.terrain)
	VILLAGE_LAYOUT.place_houses(s.map, s.terrain, s.village_plan)
	VILLAGE_MATERIALS.apply(s.map, s.terrain)

## The importer gives every surface of the map the leaves' shader, whose
## vertex function sways by TIME. Such a material is animated to the renderer
## even with a sway of zero, and a lamp draws its shadow map again in every
## frame an animated caster is in it: the lanterns outside did, all night. So
## the surfaces that do not sway get the same shader without the sway, and a
## piece that does sway goes on the plants' render layer, which the lanterns
## leave out of their shadow maps.
static func _settle_surfaces(map_root: Node) -> void:
	for item: MeshInstance3D in map_root.find_children("*", "MeshInstance3D", true, false):
		for surface in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface) as ShaderMaterial
			if material == null or material.shader == null:
				continue
			var sway: Variant = material.get_shader_parameter("leaf_motion")
			if sway != null and sway > 0.0:
				item.layers = VegetationSystem.VISUAL_LAYER
			elif material.shader.resource_path == "res://src/alpine/surface.gdshader":
				material.shader = STILL_SURFACE

## The tracks the player leaves on soft ground.
static func tracks(s: LevelSystems) -> void:
	var ground_tracks := GROUND_TRACKS.new()
	ground_tracks.name = "Tracks"
	ground_tracks.terrain = s.terrain
	ground_tracks.walker = s.player
	s.add(ground_tracks)

## The region's cottages under the map; before the vegetation, so that their
## porches and wood stores are solid obstacles.
static func cottages(s: LevelSystems) -> void:
	for entry: Dictionary in VillageCottage.entries(s.region.cottages):
		var cottage := VillageCottage.new()
		cottage.name = str(entry.node)
		cottage.spec = entry
		s.map.add_child(cottage)
		cottage.install(s.map, s.sky, s.village_plan)
		s.cottages.append(cottage)

## The brewery behind the tavern, the lighthouse on the island and the rest;
## before the vegetation, whose obstacle scan must see their colliders. The
## ground bake shaped the ground under them (VillageBuildings.settle_ground).
static func buildings(s: LevelSystems) -> void:
	for table: Dictionary in VILLAGE_BUILDINGS.tables(s.region):
		var building := VillageBuilding.new()
		building.name = str(table.title)
		building.table = table
		building.sky_system = s.sky
		building.falls = s.falls
		building.world = s.world
		s.add(building)
		s.buildings.append(building)
		# The brewery's trade stands about the valley.
		if building.brew_house != null:
			s.add(building.brew_house.make_stalls())

## The village's props, its animals and the forest's wood, from the models
## the loader fetched first.
static func village_pack(s: LevelSystems) -> void:
	s.village_pack = VILLAGE_PACK.new()
	s.village_pack.name = "VillagePack"
	s.village_pack.terrain = s.terrain
	s.village_pack.player = s.player
	s.village_pack.region = s.region
	s.map.add_child(s.village_pack)
	await s.village_pack.wait_for_prefetch()
	s.village_pack.install(s.map, false)

## The plants of the village's yards and paths; they grow once the colliders
## stand (Level, step "placement").
static func flora(s: LevelSystems) -> void:
	s.flora = VillageFlora.new()
	s.flora.name = "Flora"
	s.flora.terrain = s.terrain
	s.flora.map = s.map
	s.flora.village_plan = s.village_plan
	s.add(s.flora)

## The chimneys' smoke of the map, of the cottages and of the buildings.
static func smoke(s: LevelSystems) -> void:
	CHIMNEY_SMOKE.build(s.level, s.manifest, s.terrain, s.cottages, s.village_plan)
	for building: VillageBuilding in s.buildings:
		building.take_plumes(CHIMNEY_SMOKE.over(s.level, building.smoke_vents()))

## The people of the region at their work and on their walks.
static func people(s: LevelSystems) -> void:
	s.people = NpcPopulation.new()
	s.people.name = "Population"
	s.people.villagers = s.region.villagers
	s.people.tavern_work = s.region.tavern_work
	s.people.interiors = s.world.interiors
	s.add(s.people)

## What the player's E reaches (TavernInteractions): the tavern's furnishings
## and its innkeeper, when the region has them, and the brewery's things and
## stations.
static func interactions(s: LevelSystems) -> void:
	s.interactions = TavernInteractions.new()
	s.interactions.name = "TavernInteractions"
	s.interactions.player = s.player
	s.interactions.tavern = s.tavern
	s.interactions.population = s.people
	s.add(s.interactions)
	for building: VillageBuilding in s.buildings:
		if building.brew_house != null:
			building.brew_house.attach(s.interactions)

## The campfires the player lays, and the walks and talks with the people.
static func camping(s: LevelSystems) -> void:
	s.camping = CampSystem.new()
	s.camping.name = "Camping"
	s.camping.player = s.player
	s.camping.interactions = s.interactions
	s.camping.population = s.people
	s.camping.water_level = s.terrain.water_level
	s.interactions.camping = s.camping
	s.add(s.camping)

## The lanterns' far glows, and the watch that keeps what lives out of their
## shadow maps; after the tavern, the cottages and the animals.
static func lamps(s: LevelSystems) -> void:
	s.far_lights = FarLights.new()
	s.add(s.far_lights)
	s.lamp_guard = LampShadowGuard.new()
	s.lamp_guard.name = "LampShadowGuard"
	if s.tavern != null:
		s.lamp_guard.lamps = s.tavern.light.lamps.shadowed_lanterns()
		for glow: Dictionary in s.tavern.light.lamps.far_glows:
			var at: Vector3 = glow.at
			var facing: Vector3 = glow.facing
			var color: Color = glow.color
			s.far_lights.add_glow(s.tavern.to_global(at), color, Values.real(glow.radius), s.tavern.global_basis * facing)
	for cottage: VillageCottage in s.cottages:
		s.lamp_guard.lamps.append(cottage.lantern)
		s.far_lights.add_glow(cottage.lantern.global_position, cottage.lantern.light_color, 0.2)
	for building: VillageBuilding in s.buildings:
		s.lamp_guard.lamps.append_array(building.lamps.shadowed_lanterns())
		building.light_from_afar(s.far_lights)
	s.far_lights.build()
	for root: Node in [s.wildlife, s.village_pack]:
		if root != null:
			s.lamp_guard.roots.append(root)
	s.lamp_guard.population = s.people
	s.add(s.lamp_guard)
