extends RefCounted
## The builders of the level's map, buildings and people (LevelParts): each
## takes what the steps before it built, adds its shared system
## (SharedSystems) or its part of the content (CellContent) and leaves it there
## for the steps after it. A content step puts what its part gives the shared
## systems in the registries of WorldContext (docs/LEVEL.md, «Реестры»).

const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
const VILLAGE_MATERIALS = preload("res://src/village/village_materials.gd")
const VILLAGE_PACK = preload("res://src/village/village_pack.gd")
const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
const GROUND_TRACKS = preload("res://src/terrain/ground_tracks.gd")
const CHIMNEY_SMOKE = preload("res://src/alpine/chimney_smoke.gd")
const STILL_SURFACE = preload("res://src/alpine/surface_still.gdshader")

## The refined tavern in place of the Blender map's blockout one; before the
## vegetation, which scans the colliders it keeps.
static func tavern(s: SharedSystems, c: CellContent) -> void:
	c.tavern = TavernSystem.new()
	c.tavern.name = "Tavern"
	c.tavern.transform = s.region.tavern_at
	c.tavern.map = c.map
	c.tavern.parts = s.region.tavern
	c.tavern.sky_system = s.sky
	c.tavern.terrain = s.terrain
	c.tavern.world = s.world
	c.add(c.tavern)
	s.world.interaction_sources.add(c.tavern, c.tavern.furnish)
	s.world.lamps.add(c.tavern, c.tavern.lamps_for)

## The map as the region stands it: its surfaces settled, its pieces edited
## (MapEdits), its houses on their lots, the village's materials. Its pieces
## outdoors are hidden from an eye in a room (Interiors).
static func map(s: SharedSystems, c: CellContent) -> void:
	_settle_surfaces(c.map_index)
	MapEdits.apply(c.map, s.terrain)
	VILLAGE_LAYOUT.place_houses(c.map, s.terrain, c.village_plan)
	VILLAGE_MATERIALS.apply(c.map, s.terrain)
	s.world.interiors.watch_pieces(c.map)

## The importer gives every surface of the map the leaves' shader, whose
## vertex function sways by TIME. Such a material is animated to the renderer
## even with a sway of zero, and a lamp draws its shadow map again in every
## frame an animated caster is in it: the lanterns outside did, all night. So
## the surfaces that do not sway get the same shader without the sway, and a
## piece that does sway goes on the plants' render layer, which the lanterns
## leave out of their shadow maps.
static func _settle_surfaces(index: MapIndex) -> void:
	for item: MeshInstance3D in index.pieces():
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
static func tracks(s: SharedSystems) -> void:
	var ground_tracks := GROUND_TRACKS.new()
	ground_tracks.name = "Tracks"
	ground_tracks.terrain = s.terrain
	ground_tracks.walker = s.player
	s.add(ground_tracks)

## The region's cottages under the map; before the vegetation, so that their
## porches and wood stores are solid obstacles.
static func cottages(s: SharedSystems, c: CellContent) -> void:
	for entry: Dictionary in VillageCottage.entries(s.region.cottages):
		var cottage := VillageCottage.new()
		cottage.name = str(entry.node)
		cottage.spec = entry
		c.map.add_child(cottage)
		cottage.install(c.map, s.sky, c.village_plan)
		c.cottages.append(cottage)
		s.world.lamps.add(cottage, cottage.lamps_for)

## The brewery behind the tavern, the lighthouse on the island and the rest;
## before the vegetation, whose obstacle scan must see their colliders. The
## ground bake shaped the ground under them (VillageBuildings.settle_ground).
static func buildings(s: SharedSystems, c: CellContent) -> void:
	for table: Dictionary in VILLAGE_BUILDINGS.tables(s.region):
		var building := VillageBuilding.new()
		building.name = str(table.title)
		building.table = table
		building.sky_system = s.sky
		building.falls = c.falls
		building.world = s.world
		c.add(building)
		c.buildings.append(building)
		s.world.lamps.add(building, building.lamps_for)
		s.world.wind_vanes.add(building, building.take_wind)
		# The brewery's trade stands about the valley.
		if building.brew_house != null:
			c.add(building.brew_house.make_stalls())
			s.world.interaction_sources.add(building.brew_house, building.brew_house.attach)

## The village's props, its animals and the forest's wood, from the models
## the loader fetched first.
static func village_pack(s: SharedSystems, c: CellContent) -> void:
	c.village_pack = VILLAGE_PACK.new()
	c.village_pack.name = "VillagePack"
	c.village_pack.terrain = s.terrain
	c.village_pack.player = s.player
	c.village_pack.region = s.region
	c.map.add_child(c.village_pack)
	await c.village_pack.wait_for_prefetch()
	c.village_pack.install(c.map, false)
	s.world.animals.add(c.village_pack, c.village_pack)

## The plants of the village's yards and paths; they grow once the colliders
## stand (Level, step "placement").
static func flora(s: SharedSystems, c: CellContent) -> void:
	c.flora = VillageFlora.new()
	c.flora.name = "Flora"
	c.flora.terrain = s.terrain
	c.flora.map = c.map
	c.flora.village_plan = c.village_plan
	c.add(c.flora)

## The chimneys' smoke of the map, of the cottages and of the buildings.
static func smoke(s: SharedSystems, c: CellContent) -> void:
	CHIMNEY_SMOKE.build(c.node, c.manifest, s.terrain, c.cottages, c.village_plan)
	for building: VillageBuilding in c.buildings:
		building.take_plumes(CHIMNEY_SMOKE.over(c.node, building.smoke_vents()))

## The people of the region at their work and on their walks. They are the
## shared registry's: they stay while the content goes (docs/LEVEL.md,
## «Общие системы и содержимое»).
static func people(s: SharedSystems) -> void:
	s.people = NpcPopulation.new()
	s.people.name = "Population"
	s.people.villagers = s.region.villagers
	s.people.tavern_work = s.region.tavern_work
	s.people.interiors = s.world.interiors
	s.add(s.people)

## What the player's E reaches (TavernInteractions): the innkeeper, the
## content's doors and handles (Interaction.GROUP), and what the content gives
## (WorldContext.interaction_sources): the tavern's seats, ladder and beds, the
## brewery's things and stations. A region without the tavern has none of
## its furnishings.
static func interactions(s: SharedSystems) -> void:
	s.interactions = TavernInteractions.new()
	s.interactions.name = "TavernInteractions"
	s.interactions.player = s.player
	s.interactions.population = s.people
	s.interactions.givers = s.world.interaction_sources
	s.add(s.interactions)

## The campfires the player lays, and the walks and talks with the people.
static func camping(s: SharedSystems) -> void:
	s.camping = CampSystem.new()
	s.camping.name = "Camping"
	s.camping.player = s.player
	s.camping.interactions = s.interactions
	s.camping.population = s.people
	s.camping.water_level = s.terrain.water_level
	s.interactions.camping = s.camping
	s.add(s.camping)

## The lanterns' far glows, and the watch that keeps what lives out of their
## shadow maps; both take the content's lamps (WorldContext.lamps) and the
## watch its animals (WorldContext.animals).
static func lamps(s: SharedSystems) -> void:
	s.far_lights = FarLights.new()
	s.far_lights.lamps = s.world.lamps
	s.add(s.far_lights)
	s.lamp_guard = LampShadowGuard.new()
	s.lamp_guard.name = "LampShadowGuard"
	s.lamp_guard.population = s.people
	s.lamp_guard.givers = s.world.lamps
	s.lamp_guard.animals = s.world.animals
	s.add(s.lamp_guard)
