extends Node3D
signal loading_stage(message: String)
## Direct main.tscn instantiation remains synchronous for tools and tests.
var staged_loading := false
## Playable wrapper around a region (RegionDef): its Blender map, physical
## sky, generated terrain, the FFT lake and the buildings on top of it.
const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
const VILLAGE_MATERIALS = preload("res://src/village/village_materials.gd")
const GROUND_TRACKS = preload("res://src/terrain/ground_tracks.gd")
const VILLAGE_PACK = preload("res://src/village/village_pack.gd")
const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
## The HUD, the chimney smoke and the debug keys live in these helpers.
const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")
const CHIMNEY_SMOKE = preload("res://src/alpine/chimney_smoke.gd")
const LEVEL_CONTROLS = preload("res://src/alpine/level_controls.gd")
const RenderQuality = preload("res://src/render/render_quality.gd")
const SHARPEN_POST = preload("res://src/render/sharpen_post.gd")
const GAME_SETTINGS = preload("res://src/settings/game_settings.gd")
const STILL_SURFACE = preload("res://src/alpine/surface_still.gdshader")
const LEVEL_POST = preload("res://src/alpine/level_post.gd")
const VIEW_DISTANCE := 24000.0
## The middle of the built-up land (tavern, village, island), x and z:
## what RainShelter maps for the rain to fall on.
const SHELTER_CENTRE := Vector2(-24.0, -44.0)
## The region this level builds; main.tscn names the valley, WorldLoader may
## set another before the level enters the tree.
@export var region: RegionDef
var manifest: Dictionary
## What the level's systems share (WorldContext); a tool sets its switches
## before the level enters the tree.
var world := WorldContext.new()
## The region's village plan (VillageLayout.read_plan).
var village_plan: Dictionary
var overview_active := false
var spawn_position := Vector3.ZERO
var sky_system: SkySystem
var weather: WeatherSystem
var post: LEVEL_POST
var lightning: LightningFx
var weather_sound: WeatherSound
var rain_fall: RainFall
var rain_shelter: RainShelter
var terrain: TerrainSystem
var sun_shadow: SunShadowField
var water: WaterSystem
var vegetation: VegetationSystem
var litter: ForestLitter
var rocks: RockField
var tavern: TavernSystem
var tavern_interactions: TavernInteractions
## The region's buildings (RegionDef.buildings): the brewery, the lighthouse and the rest.
var buildings: Array[VillageBuilding] = []
## The region's cottages (RegionDef.cottages), under the map.
var cottages: Array[VillageCottage] = []
var npc_population: NpcPopulation
var camping: CampSystem
var wildlife: WildlifeSystem
var waterfall: WaterfallSystem
var eye_adaptation: EyeAdaptation
var far_lights: FarLights
var lamp_guard: LampShadowGuard
var lakeside: LakesideSystem
var lake_audio: LakeSoundscape
var lake_shore: LakeShore
var village_pack: VILLAGE_PACK
var brook: VillageBrook
var flora: VillageFlora
var lake_refraction: LakeRefraction
var status: Label
## Checks every body of the level as it comes (docs/LEVEL.md, «Сторож»).
var physics_audit: PhysicsAudit
# Inputs of the last wind update in _process.
var _wind_heading_deg := NAN
var _wind_speed := NAN
var _wind_sent := Vector4.ZERO
@onready var player: Player = $Player
@onready var rig: CameraRig = $Player/CameraRig
@onready var player_camera: Camera3D = $Player/CameraRig/Camera3D
@onready var overview: Camera3D = $Overview

func _ready() -> void:
	physics_audit = PhysicsAudit.new()
	physics_audit.name = "PhysicsAudit"
	add_child(physics_audit)
	if staged_loading:
		set_process(false)
		set_physics_process(false)
		player.set_physics_process(false)
	var map := region.map.instantiate()
	map.name = "Map"
	add_child(map)
	move_child(map, 0)
	manifest = DataFile.read(region.map_manifest, WorldSchemas.map_manifest())
	village_plan = VILLAGE_LAYOUT.read_plan(region.village_plan)
	player_camera.far = VIEW_DISTANCE
	if staged_loading:
		await _loading_step("Готовим небо и землю…")
	setup_lighting()
	setup_render_quality()
	setup_terrain()
	setup_water()
	setup_waterfall()
	setup_brook()
	if staged_loading:
		await _loading_step("Открываем таверну…")
	setup_tavern()
	settle_map_surfaces($Map)
	VILLAGE_LAYOUT.settle_landmarks($Map, terrain)
	VILLAGE_LAYOUT.place_houses($Map, terrain, village_plan)
	VILLAGE_LAYOUT.settle_bridge($Map, terrain)
	VILLAGE_MATERIALS.apply($Map, terrain)
	var tracks := GROUND_TRACKS.new()
	tracks.name = "Tracks"
	tracks.terrain = terrain
	tracks.walker = player
	add_child(tracks)
	if staged_loading:
		await _loading_step("Собираем деревню…")
	setup_cottages()
	setup_buildings()
	if staged_loading:
		await setup_village_pack()
	else:
		setup_village_pack()
	if staged_loading:
		await _loading_step("Рассаживаем лес…")
	setup_rocks()
	setup_vegetation()
	flora = VillageFlora.new()
	flora.name = "Flora"
	flora.auto_grow = not staged_loading
	flora.terrain = terrain
	flora.map = $Map
	flora.village_plan = village_plan
	add_child(flora)
	if staged_loading:
		await _loading_step("Готовим жителей и озеро…")
	setup_post()
	setup_smoke()
	setup_interface()
	npc_population = NpcPopulation.new()
	npc_population.name = "Population"
	add_child(npc_population)
	tavern_interactions = TavernInteractions.new()
	tavern_interactions.name = "TavernInteractions"
	tavern_interactions.player = player
	tavern_interactions.tavern = tavern
	tavern_interactions.population = npc_population
	add_child(tavern_interactions)
	camping = CampSystem.new()
	camping.name = "Camping"
	camping.player = player
	camping.interactions = tavern_interactions
	camping.population = npc_population
	camping.water_level = terrain.water_level
	tavern_interactions.camping = camping
	add_child(camping)
	wildlife = WildlifeSystem.new()
	wildlife.name = "Wildlife"
	wildlife.auto_populate = not staged_loading
	wildlife.terrain = terrain
	wildlife.player = player
	wildlife.sky = sky_system
	wildlife.water = water
	wildlife.rocks = rocks
	add_child(wildlife)
	village_pack.populate_life(npc_population)
	setup_lamps()
	setup_lakeside()
	var settings_panel := SettingsPanel.new()
	settings_panel.name = "Settings"
	add_child(settings_panel)
	var sharpen := SHARPEN_POST.new()
	sharpen.name = "SharpenPost"
	add_child(sharpen)
	var view: Dictionary = manifest.cameras[0]
	set_camera(overview, view)
	var spawn := region.spawn()
	spawn_position = spawn.position
	player.position = spawn_position
	rig.sensitivity = 0.12
	rig.yaw_deg = spawn.yaw_deg
	rig.pitch_deg = spawn.pitch_deg
	rig.apply_look(Vector2.ZERO)
	place_on_ground.call_deferred()
	if staged_loading:
		village_pack._scatter_forest.call_deferred()
		flora._grow.call_deferred()
		wildlife.populate.call_deferred()
	# Last: its map is drawn from what stands by now.
	rain_shelter = RainShelter.new()
	rain_shelter.terrain = terrain
	rain_shelter.centre = SHELTER_CENTRE
	add_child(rain_shelter)
	set_meta("load_complete", true)

func _loading_step(message: String) -> void:
	loading_stage.emit(message)
	# Housing transforms and the obstacle scan form one atomic stage. Yielding
	# between them flushes different physics transforms than synchronous _ready
	# and changes the grass mask, even when all tree positions remain equal.
	if vegetation != null:
		await get_tree().process_frame

func setup_village_pack() -> void:
	village_pack = VILLAGE_PACK.new()
	village_pack.name = "VillagePack"
	village_pack.terrain = terrain
	village_pack.player = player
	village_pack.region = region
	$Map.add_child(village_pack)
	if staged_loading:
		await village_pack.wait_for_prefetch()
		village_pack.install($Map, false)
	else:
		village_pack.install($Map)

func setup_lakeside() -> void:
	lakeside = LakesideSystem.new()
	lakeside.player = player
	lakeside.terrain = terrain
	lakeside.water = water
	lakeside.sky = sky_system
	lakeside.interactions = tavern_interactions
	lakeside.camping = camping
	tavern_interactions.lakeside = lakeside
	add_child(lakeside)
	lake_audio = LakeSoundscape.new()
	lake_audio.player = player
	lake_audio.water = water
	lake_audio.terrain = terrain
	lake_audio.sky = sky_system
	lake_audio.activities = lakeside
	add_child(lake_audio)
	lakeside.soundscape = lake_audio
	lake_shore = LakeShore.new()
	lake_shore.water = water
	lake_shore.terrain = terrain
	lake_shore.activities = lakeside
	water.shore = lake_shore
	add_child(lake_shore)
	lake_refraction = LakeRefraction.new()
	lake_refraction.water = water
	lake_refraction.world = world
	add_child(lake_refraction)

func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func set_camera(camera: Camera3D, view: Dictionary) -> void:
	camera.position = vector(view.position)
	camera.look_at(camera.position + vector(view.forward))
	camera.fov = view.fov
	camera.far = VIEW_DISTANCE

func place_on_ground() -> void:
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(spawn_position + Vector3.UP * 28.0, spawn_position + Vector3.DOWN * 22.0)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		spawn_position = hit.position + Vector3.UP * 0.08
		player.position = spawn_position

func setup_lighting() -> void:
	sky_system = SkySystem.new()
	sky_system.name = "Sky"
	sky_system.day_of_year = 225
	sky_system.time_of_day = 14.6
	sky_system.viewer = player_camera
	# The weather first: the sky then draws the state of the same frame.
	weather = WeatherSystem.new()
	weather.name = "Weather"
	weather.sky = sky_system
	weather.viewer = player_camera
	add_child(weather)
	add_child(sky_system)
	var world_environment: WorldEnvironment = $WorldEnvironment
	world_environment.environment = RealismEnvironment.build(sky_system.make_sky())
	sky_system.environment = world_environment.environment
	for config: Dictionary in manifest.lights:
		var lamp := OmniLight3D.new()
		lamp.name = "TavernLantern"
		lamp.position = vector(config.position)
		lamp.light_color = Color(1.0, 0.63, 0.32)
		lamp.light_energy = 3.2
		lamp.omni_range = 9.0
		lamp.omni_attenuation = 1.3
		lamp.shadow_enabled = true
		# Omni shadows render six faces; trees near a lantern are not worth it.
		lamp.shadow_caster_mask = 0xFFFFFFFF & ~VegetationSystem.VISUAL_LAYER
		# The tavern's interior lights take over from these (TavernSystem).
		lamp.add_to_group(&"tavern_lantern")
		add_child(lamp)

## The importer gives every surface of the map the leaves' shader, whose
## vertex function sways by TIME. Such a material is animated to the renderer
## even with a sway of zero, and a lamp draws its shadow map again in every
## frame an animated caster is in it: the lanterns outside did, all night. So
## the surfaces that do not sway get the same shader without the sway, and a
## piece that does sway goes on the plants' render layer, which the lanterns
## leave out of their shadow maps.
static func settle_map_surfaces(map: Node) -> void:
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		for surface in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface) as ShaderMaterial
			if material == null or material.shader == null:
				continue
			var sway: Variant = material.get_shader_parameter("leaf_motion")
			if sway != null and sway > 0.0:
				item.layers = VegetationSystem.VISUAL_LAYER
			elif material.shader.resource_path == "res://src/alpine/surface.gdshader":
				material.shader = STILL_SURFACE

## Temporal resolve (TAA, or the upscaler of the lighter profiles) is what
## the cloud jitter, the foliage alpha and the water glints rely on; the
## quality profile of the settings picks which, and follows the window's size.
func setup_render_quality() -> void:
	# The budgets are for the game's window. A tool that draws the level into
	# its own SubViewport gets the picture as authored, pixel for pixel.
	if get_viewport() != get_tree().root:
		apply_quality(QualityProfile.named(QualityProfile.AUTHORED))
		return
	apply_quality(RenderQuality.selected(get_tree()))
	var settings: GAME_SETTINGS = get_node_or_null("/root/GameSettings")
	if settings != null:
		settings.quality_changed.connect(apply_quality)
	get_viewport().size_changed.connect(_fit_render_resolution)

func apply_quality(profile: QualityProfile) -> void:
	RenderQuality.apply(get_viewport(), sky_system, profile, world)

func _fit_render_resolution() -> void:
	RenderQuality.apply_resolution(get_viewport(), QualityProfile.of(world))

func setup_terrain() -> void:
	terrain = TerrainSystem.new()
	terrain.name = "Terrain"
	terrain.world = world
	terrain.region = region
	add_child(terrain)
	sun_shadow = SunShadowField.new()
	sun_shadow.name = "SunShadowField"
	sun_shadow.terrain = terrain
	sun_shadow.sky = sky_system
	add_child(sun_shadow)

func setup_water() -> void:
	water = WaterSystem.new()
	water.name = "Lake"
	water.terrain = terrain
	add_child(water)
	water.ocean.set_preset("breeze", true)
	weather.ocean = water.ocean
	weather.weather_changed.connect(func(_kind: String) -> void: update_status())
	water.ocean.weather_changed.connect(func(_preset: String) -> void: update_status())
	sky_system.time_changed.connect(func(_hours: float) -> void: update_status())

## The refined tavern in place of the Blender map's blockout one; before the
## vegetation, which scans the colliders it keeps.
func setup_tavern() -> void:
	tavern = TavernSystem.new()
	tavern.name = "Tavern"
	tavern.map = $Map
	tavern.parts = region.tavern
	tavern.sky_system = sky_system
	tavern.terrain = terrain
	tavern.world = world
	add_child(tavern)
	eye_adaptation = EyeAdaptation.new()
	eye_adaptation.name = "EyeAdaptation"
	var world_environment: WorldEnvironment = $WorldEnvironment
	eye_adaptation.environment = world_environment.environment
	eye_adaptation.sky = sky_system
	eye_adaptation.weather = weather
	eye_adaptation.rooms = tavern.room_boxes()
	eye_adaptation.tavern = tavern
	add_child(eye_adaptation)

## The lanterns' far glows, and the watch that keeps what lives out of their
## shadow maps; after the tavern, the cottages and the animals.
func setup_lamps() -> void:
	far_lights = FarLights.new()
	add_child(far_lights)
	lamp_guard = LampShadowGuard.new()
	lamp_guard.name = "LampShadowGuard"
	lamp_guard.lamps = tavern.shadowed_lanterns()
	for glow: Dictionary in tavern.far_glows:
		far_lights.add_glow(tavern.to_global(glow.at), glow.color, glow.radius, tavern.global_basis * glow.facing)
	for cottage: VillageCottage in cottages:
		lamp_guard.lamps.append(cottage.lantern)
		far_lights.add_glow(cottage.lantern.global_position, cottage.lantern.light_color, 0.2)
	for building: VillageBuilding in buildings:
		lamp_guard.lamps.append_array(building.shadowed_lanterns())
		building.light_from_afar(far_lights)
	far_lights.build()
	lamp_guard.roots = [wildlife, village_pack]
	lamp_guard.population = npc_population
	add_child(lamp_guard)

## Before the vegetation, so that the new porches and wood stores are solid obstacles.
func setup_cottages() -> void:
	for entry: Dictionary in VillageCottage.entries(region.cottages):
		var cottage := VillageCottage.new()
		cottage.name = str(entry.node)
		cottage.spec = entry
		$Map.add_child(cottage)
		cottage.install($Map, sky_system, village_plan)
		cottages.append(cottage)

## The brewery behind the tavern, the lighthouse on the island and the rest;
## before the vegetation, whose obstacle scan must see their colliders. The
## ground bake shaped the ground under them (VillageBuildings.settle_ground).
func setup_buildings() -> void:
	for table: Dictionary in VILLAGE_BUILDINGS.tables(region):
		var building := VillageBuilding.new()
		building.name = str(table.title)
		building.table = table
		building.sky_system = sky_system
		building.falls = waterfall
		add_child(building)
		buildings.append(building)
		var rooms := building.room_boxes()
		eye_adaptation.rooms.append_array(rooms)
		# Only a building with rooms has pieces indoors for the sun to shade
		# (a boardwalk or a row of lanterns has none, and may be as long as the village).
		if not rooms.is_empty():
			tavern.room_shadow_bounds.append(building.bounds)
		# The brewery's trade stands about the valley.
		if building.brew_house != null:
			add_child(building.brew_house.make_stalls())

## Scanned boulders and cliff faces in place of the Blender blockout stones;
## before the vegetation, whose obstacle scan must see their colliders.
func setup_rocks() -> void:
	rocks = RockField.new()
	rocks.name = "Rocks"
	rocks.terrain = terrain
	rocks.map = $Map
	rocks.layout = region.rocks
	rocks.cliff = region.cliff
	add_child(rocks)

## The falls below the plateau with their spray, mist and the lake's foam.
func setup_waterfall() -> void:
	waterfall = WaterfallSystem.new()
	waterfall.name = "Waterfall"
	waterfall.map = $Map
	waterfall.water = water
	add_child(waterfall)

## The brook through the village, on the falls' water; before the rocks, whose
## Blender brook stones it drops. Its bed is in the baked masks.
func setup_brook() -> void:
	brook = VillageBrook.new()
	brook.name = "Brook"
	brook.map = $Map
	brook.terrain = terrain
	brook.falls = waterfall
	add_child(brook)

## Trees placed from the terrain masks, kept off the Blender buildings, and
## what they have shed onto the ground.
func setup_vegetation() -> void:
	vegetation = VegetationSystem.new()
	vegetation.name = "Vegetation"
	vegetation.terrain = terrain
	vegetation.world = world
	vegetation.map = $Map
	# The rays that find the buildings' footprints pass the rocks: the village's
	# trees and the grass stand among them. Named here because a physics engine
	# may or may not answer for bodies added in this same frame.
	vegetation.exclude = [player.get_rid()]
	for body: CollisionObject3D in rocks.find_children("*", "CollisionObject3D", true, false):
		vegetation.exclude.append(body.get_rid())
	add_child(vegetation)
	litter = ForestLitter.new()
	litter.name = "Litter"
	litter.terrain = terrain
	litter.woods = vegetation.grid
	litter.canopy = vegetation.grass.canopy
	litter.rocks = rocks
	add_child(litter)

## The compositor passes (level_post.gd), and what a storm adds to the land.
func setup_post() -> void:
	post = LEVEL_POST.new(self)
	eye_adaptation.canopy = vegetation.grass.canopy
	eye_adaptation.terrain = terrain
	var rooms := eye_adaptation.rooms
	lightning = LightningFx.new()
	lightning.name = "Lightning"
	lightning.weather = weather
	lightning.terrain = terrain
	var world_environment: WorldEnvironment = $WorldEnvironment
	lightning.environment = world_environment.environment
	lightning.rooms = rooms
	add_child(lightning)
	for building: VillageBuilding in buildings:
		if building.optic != null:
			building.optic.rooms = rooms
	weather_sound = WeatherSound.new()
	weather_sound.name = "WeatherSound"
	weather_sound.weather = weather
	weather_sound.rooms = rooms
	add_child(weather_sound)
	rain_fall = RainFall.new()
	rain_fall.weather = weather
	rain_fall.building = post.fog.building
	rain_fall.water_level = terrain.water_level
	add_child(rain_fall)

func _process(delta: float) -> void:
	post.update(delta, get_viewport().get_camera_3d().global_position, get_tree())
	rain_fall.wind = post.fog.wind
	var ocean := water.ocean
	# Trees bend in the wind that raises the waves (F1-F4): pressure grows
	# with the square of the speed, so a storm bends them hard. They only take
	# a new wind when an input changed (NaN never compares equal, so the first
	# frame always does).
	if ocean.wind_direction_deg != _wind_heading_deg or ocean.wind_speed != _wind_speed \
			or vegetation.wind != _wind_sent:
		_wind_heading_deg = ocean.wind_direction_deg
		_wind_speed = ocean.wind_speed
		var heading := deg_to_rad(ocean.wind_direction_deg)
		vegetation.wind = Vector4(cos(heading), sin(heading), minf(pow(ocean.wind_speed / 9.0, 1.6), 2.2), ocean.wind_speed)
		_wind_sent = vegetation.wind
		for building: VillageBuilding in buildings:
			building.take_wind(heading)

func setup_smoke() -> void:
	CHIMNEY_SMOKE.build(self, manifest, terrain)
	for building: VillageBuilding in buildings:
		building.take_plumes(CHIMNEY_SMOKE.over(self, building.smoke_vents()))

func setup_interface() -> void:
	status = LEVEL_HUD.build(self, LEVEL_CONTROLS.debug_keys())
	update_status()

func update_status() -> void:
	if status == null:
		return
	status.text = LEVEL_HUD.status_text(water, sky_system, weather)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		update_status()

func _unhandled_input(event: InputEvent) -> void:
	LEVEL_CONTROLS.key_input(self, event)

func toggle_overview() -> void:
	LEVEL_CONTROLS.toggle_overview(self)

func _physics_process(_delta: float) -> void:
	# Swimming follows the waves under the player; the GPU answers a frame late.
	water.probe_points = PackedVector2Array([Vector2(player.position.x, player.position.z),
		Vector2(lakeside.boat.position.x, lakeside.boat.position.z), Vector2(lakeside.catch_point.x, lakeside.catch_point.z)])
	player.water_surface = water.surface_height(0)
	# The lake is up to 60 m deep; only a fall through the world resets.
	if player.position.y < -80.0:
		player.position = spawn_position
		player.velocity = Vector3.ZERO

func capture() -> void:
	await RenderingServer.frame_post_draw
	var folder := "user://alpine-screenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/" + Time.get_datetime_string_from_system().replace(":", "-") + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot saved: ", ProjectSettings.globalize_path(path))
