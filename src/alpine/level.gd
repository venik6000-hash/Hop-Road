extends Node3D
signal loading_stage(message: String)
## Direct main.tscn instantiation remains synchronous for tools and tests.
var staged_loading := false
## Playable wrapper around the imported Blender map: physical sky, generated
## terrain, the FFT lake and the Blender buildings on top of it.
const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
const VILLAGE_MATERIALS = preload("res://src/village/village_materials.gd")
const GROUND_WEAR = preload("res://src/terrain/ground_wear.gd")
const GROUND_TRACKS = preload("res://src/terrain/ground_tracks.gd")
const VILLAGE_PACK = preload("res://src/village/village_pack.gd")
const COTTAGE = preload("res://src/village/herbalist_cottage.gd")
const POTTER = preload("res://src/village/potter_cottage.gd")
const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
## The HUD, the chimney smoke and the debug keys live in these helpers.
const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")
const CHIMNEY_SMOKE = preload("res://src/alpine/chimney_smoke.gd")
const LEVEL_CONTROLS = preload("res://src/alpine/level_controls.gd")
const RenderQuality = preload("res://src/render/render_quality.gd")
const STILL_SURFACE = preload("res://src/alpine/surface_still.gdshader")
const SPAWN := Vector3(0, 12, 15)
## Height above the lake level that no wave crest reaches: five times the
## storm preset's significant height at the largest local wave scale. An eye
## above it lets the lens pass skip its water block.
const LENS_CREST_BOUND := 30.0
const VIEW_DISTANCE := 24000.0
## The middle of the built-up land (tavern, village, island), x and z:
## what RainShelter maps for the rain to fall on.
const SHELTER_CENTRE := Vector2(-24.0, -44.0)
var manifest: Dictionary
var overview_active := false
var spawn_position := SPAWN
var sky_system: SkySystem
var weather: WeatherSystem
var fog: AtmosphereFog
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
## The brewery and the lighthouse (VillageBuildings.TABLES).
var buildings: Array[VillageBuilding] = []
var npc_population: NpcPopulation
var camping: CampSystem
var wildlife: WildlifeSystem
var waterfall: WaterfallSystem
var lens: LensPost
var refraction: RefractionPost
var eye_adaptation: EyeAdaptation
var far_lights: FarLights
var lamp_guard: LampShadowGuard
var lakeside: LakesideSystem
var lake_audio: LakeSoundscape
var lake_shore: LakeShore
var village_pack: Node3D
var brook: VillageBrook
var flora: VillageFlora
var lake_refraction: LakeRefraction
var status: Label
# Inputs of the last lens and wind updates in _process.
var _lens_water_valid := false
var _lens_level := 0.0
var _lens_tiles := Vector4.ZERO
var _lens_weights := Vector4.ZERO
var _lens_eye_x := 0.0
var _lens_eye_z := 0.0
var _lens_sun_valid := false
var _lens_sun_direction := Vector3.ZERO
var _lens_sun_radiance := Vector3.ZERO
var _lens_viewer_radius := 0.0
var _wind_heading_deg := NAN
var _wind_speed := NAN
var _wind_sent := Vector4.ZERO
@onready var player: Player = $Player
@onready var rig: CameraRig = $Player/CameraRig
@onready var player_camera: Camera3D = $Player/CameraRig/Camera3D
@onready var overview: Camera3D = $Overview

func _ready() -> void:
	if staged_loading:
		set_process(false)
		set_physics_process(false)
		player.set_physics_process(false)
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/alpine/manifest.json"))
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
	VILLAGE_LAYOUT.place_houses($Map, terrain)
	VILLAGE_LAYOUT.settle_bridge($Map, terrain)
	VILLAGE_MATERIALS.apply($Map, terrain)
	VILLAGE_LAYOUT.paint_aprons($Map, terrain)
	GROUND_WEAR.apply(terrain)
	var tracks := GROUND_TRACKS.new()
	tracks.name = "Tracks"
	tracks.terrain = terrain
	tracks.walker = player
	add_child(tracks)
	if staged_loading:
		await _loading_step("Собираем деревню…")
	setup_cottage()
	setup_potter()
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
	add_child(flora)
	if staged_loading:
		await _loading_step("Готовим жителей и озеро…")
	setup_lens()
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
	var graphics := preload("res://src/settings/graphics_panel.gd").new()
	graphics.name = "GraphicsSettings"
	graphics.level = self
	add_child(graphics)
	var view: Dictionary = manifest.cameras[0]
	set_camera(overview, view)
	player.position = SPAWN
	rig.sensitivity = 0.12
	rig.yaw_deg = -30.0
	rig.pitch_deg = 10.0
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
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 40, 15), Vector3(0, -10, 15))
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
	$WorldEnvironment.environment = RealismEnvironment.build(sky_system.make_sky())
	sky_system.environment = $WorldEnvironment.environment
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

## Temporal resolve (TAA, or the upscaler of the lighter tiers) is what the
## cloud jitter, the foliage alpha and the water glints rely on; the tier of
## the settings picks which, and follows the window's size.
func setup_render_quality() -> void:
	# The budgets are for the game's window. A tool that draws the level into
	# its own SubViewport gets the picture as authored, pixel for pixel.
	if get_viewport() != get_tree().root:
		apply_render_quality("maximum")
		return
	apply_render_quality(RenderQuality.selected(get_tree()))
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		settings.render_quality_changed.connect(apply_render_quality)
	get_viewport().size_changed.connect(_fit_render_resolution)

func apply_render_quality(tier: String) -> void:
	RenderQuality.apply(get_viewport(), sky_system, tier)

func _fit_render_resolution() -> void:
	RenderQuality.apply_resolution(get_viewport(), RenderQuality.selected(get_tree()))

func setup_terrain() -> void:
	terrain = TerrainSystem.new()
	terrain.name = "Terrain"
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
	tavern.sky_system = sky_system
	tavern.terrain = terrain
	add_child(tavern)
	eye_adaptation = EyeAdaptation.new()
	eye_adaptation.name = "EyeAdaptation"
	eye_adaptation.environment = $WorldEnvironment.environment
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
	for cottage: Node in [$Map.get_node("HerbalistCottage"), $Map.get_node("PotterCottage")]:
		var lantern: OmniLight3D = cottage.lantern
		lamp_guard.lamps.append(lantern)
		far_lights.add_glow(lantern.global_position, lantern.light_color, 0.2)
	for building: VillageBuilding in buildings:
		lamp_guard.lamps.append_array(building.shadowed_lanterns())
		building.light_from_afar(far_lights)
	far_lights.build()
	lamp_guard.roots = [wildlife, village_pack]
	lamp_guard.population = npc_population
	add_child(lamp_guard)

## Install before vegetation so the new porch and wood store are solid obstacles.
func setup_cottage() -> void:
	var cottage := COTTAGE.new()
	cottage.name = "HerbalistCottage"
	$Map.add_child(cottage)
	cottage.install($Map, sky_system)

func setup_potter() -> void:
	var cottage := POTTER.new()
	cottage.name = "PotterCottage"
	$Map.add_child(cottage)
	cottage.install($Map, sky_system)

## The brewery behind the tavern and the lighthouse on the island; before the
## vegetation, whose obstacle scan must see their colliders. The ground under
## them is shaped as the terrain loads (VillageBuildings.settle_ground).
func setup_buildings() -> void:
	for table: Dictionary in VILLAGE_BUILDINGS.tables():
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

## Scanned boulders and cliff faces in place of the Blender blockout stones;
## before the vegetation, whose obstacle scan must see their colliders.
func setup_rocks() -> void:
	rocks = RockField.new()
	rocks.name = "Rocks"
	rocks.terrain = terrain
	rocks.map = $Map
	add_child(rocks)

## The falls below the plateau with their spray, mist and the lake's foam.
func setup_waterfall() -> void:
	waterfall = WaterfallSystem.new()
	waterfall.name = "Waterfall"
	waterfall.map = $Map
	waterfall.water = water
	add_child(waterfall)

## The brook through the village, on the falls' water; before the rocks, whose
## Blender brook stones it drops, and the vegetation, which reads its bed.
func setup_brook() -> void:
	VillageBrook.paint(terrain)
	brook = VillageBrook.new()
	brook.name = "Brook"
	brook.map = $Map
	brook.falls = waterfall
	add_child(brook)

## Trees placed from the terrain masks, kept off the Blender buildings, and
## what they have shed onto the ground.
func setup_vegetation() -> void:
	vegetation = VegetationSystem.new()
	vegetation.name = "Vegetation"
	vegetation.terrain = terrain
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

## The contact shadows of the tavern's lamps on the opaque picture; then,
## after the transparent things, the hot air and the rain's rings, the
## weather's fog, the underwater view, waterline and vignette, as compositor
## passes for every camera; and what a storm adds to the land.
func setup_lens() -> void:
	fog = AtmosphereFog.new()
	fog.sky = sky_system
	fog.terrain = terrain
	fog.sun_shadow = sun_shadow
	fog.canopy = vegetation.grass.canopy
	fog.weather_map = load("res://assets/generated/sky/cloud_weather.png")
	var rooms := tavern.room_boxes()
	for index in rooms.size():
		fog.building = rooms[index] if index == 0 else fog.building.merge(rooms[index])
	# From here on every room of the village: the tavern's and the buildings'.
	rooms = eye_adaptation.rooms
	fog.rooms = rooms
	weather.fog = fog
	eye_adaptation.canopy = vegetation.grass.canopy
	eye_adaptation.terrain = terrain
	lightning = LightningFx.new()
	lightning.name = "Lightning"
	lightning.weather = weather
	lightning.terrain = terrain
	lightning.environment = $WorldEnvironment.environment
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
	rain_fall.building = fog.building
	rain_fall.water_level = terrain.water_level
	add_child(rain_fall)
	lens = LensPost.new()
	lens.skyview = sky_system.atmosphere.skyview_lut
	lens.transmittance = sky_system.atmosphere.transmittance_lut
	lens.displacement = water.ocean.displacement_texture
	# First what bends the picture itself (hot air, the rain's rings on the
	# lake), then the fog that lies before it all, then the lens.
	refraction = RefractionPost.new()
	# The eye meters the picture as the air leaves it, before the lens darkens
	# its corners.
	eye_adaptation.meter = LightMeter.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [tavern.contact_shadows, refraction, fog, eye_adaptation.meter, lens]
	$WorldEnvironment.compositor = compositor

func _process(delta: float) -> void:
	var eye := get_viewport().get_camera_3d().global_position
	var ocean := water.ocean
	var wind_heading := deg_to_rad(ocean.wind_direction_deg)
	fog.wind = Vector2(cos(wind_heading), sin(wind_heading)) * ocean.wind_speed
	rain_fall.wind = fog.wind
	fog.wave_height = ocean.significant_height()
	fog.prepare(delta, eye, get_tree().get_nodes_in_group(AtmosphereFog.LAMP_GROUP) if fog.active() else [])
	var falling := RainFall.amount(weather.state.rain, weather.state.storm)
	# The lake lies within the rings' view where the ground dips under its level.
	var lake_near := falling > 0.0 and terrain.height_range(Rect2(eye.x - RefractionPost.RING_VIEW, eye.z - RefractionPost.RING_VIEW,
		RefractionPost.RING_VIEW * 2.0, RefractionPost.RING_VIEW * 2.0)).x < water.water_level
	refraction.prepare(delta, eye, get_tree().get_nodes_in_group(RefractionPost.HEAT_GROUP), falling, water.water_level, lake_near,
		fog.wave_height)
	# The lens and the trees only take new values when an input changed:
	# the same inputs give the same packed parameters and the same wind.
	# wave_scale_at() depends on the eye's x/z, the lake level and fixed fields.
	# (NaN never compares equal, so it always takes the update path.)
	if not _lens_water_valid or water.water_level != _lens_level or ocean.tiles != _lens_tiles \
			or ocean.cascade_weights != _lens_weights or eye.x != _lens_eye_x or eye.z != _lens_eye_z:
		_lens_water_valid = true
		_lens_level = water.water_level
		_lens_tiles = ocean.tiles
		_lens_weights = ocean.cascade_weights
		_lens_eye_x = eye.x
		_lens_eye_z = eye.z
		lens.set_water(water.water_level, ocean.tiles, ocean.cascade_weights * water.wave_scale_at(eye.x, eye.z),
			WaterSystem.ABSORPTION + WaterSystem.SCATTERING, WaterSystem.SCATTERING, LENS_CREST_BOUND)
	var sun_radiance := Vector3.ONE * sky_system.sun_energy * PI
	var viewer_radius := sky_system.atmosphere.viewer_radius_km()
	if not _lens_sun_valid or sky_system.sun_direction != _lens_sun_direction \
			or sun_radiance != _lens_sun_radiance or viewer_radius != _lens_viewer_radius:
		_lens_sun_valid = true
		_lens_sun_direction = sky_system.sun_direction
		_lens_sun_radiance = sun_radiance
		_lens_viewer_radius = viewer_radius
		lens.set_sun(sky_system.sun_direction, sun_radiance, viewer_radius)
	# Trees bend in the wind that raises the waves (F1-F4): pressure grows
	# with the square of the speed, so a storm bends them hard.
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
	status = LEVEL_HUD.build(self)
	update_status()

func update_status() -> void:
	if status == null:
		return
	status.text = LEVEL_HUD.status_text(water, sky_system, weather)

func _unhandled_key_input(event: InputEvent) -> void:
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
	print("Снимок сохранён: ", ProjectSettings.globalize_path(path))
