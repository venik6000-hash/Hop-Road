extends Node3D
## Playable wrapper around a region (RegionDef): its Blender map, physical
## sky, generated terrain, the FFT lake and the buildings on top of it. The
## loading screen (src/loading/world_loader.gd) builds it, in the game and in
## the tools alike: _ready goes by the stages and steps of LevelParts and
## waits for the loader's prefetch. The core steps are built for every
## region, a part only when the region names it (RegionDef.parts).
##
## Its face to others is narrow (docs/LEVEL.md, «Фасад уровня»): `region`,
## `world`, `player`, loading_stage, built(), ready_for_visitors(),
## start_loop(), spawn_point(), apply_quality(), toggle_overview(). The
## systems are its own (LevelSystems): it hands each the others it needs. A
## tool reaches a system by its class (tools/lib/tool_level.gd).

## Told as the build goes from stage to stage, for the loading screen.
signal loading_stage(message: String)
const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
## The HUD and the level's keys live in these helpers.
const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")
const LEVEL_CONTROLS = preload("res://src/alpine/level_controls.gd")
const RenderQuality = preload("res://src/render/render_quality.gd")
const SHARPEN_POST = preload("res://src/render/sharpen_post.gd")
const GAME_SETTINGS = preload("res://src/settings/game_settings.gd")
const VIEW_DISTANCE := 24000.0
## The region this level builds; main.tscn names the valley, WorldLoader may
## set another before the level enters the tree.
@export var region: RegionDef
## The spawn of the region the player comes in at (RegionSpawn.id); "" for
## its first. WorldLoader sets it.
var spawn_id := &""
## What the level's systems share (WorldContext); a tool sets its switches
## before the level enters the tree.
var world := WorldContext.new()
## The systems built so far.
var _systems := LevelSystems.new()
var _spawn_position := Vector3.ZERO
var _status: Label
var _controls: LEVEL_CONTROLS
## The stages of _ready are done; the deferred placement may still run.
var _built := false
## Checks every body of the level as it comes (docs/LEVEL.md, «Сторож»).
var _physics_audit: PhysicsAudit
# Inputs of the last wind update in _process.
var _wind_heading_deg := NAN
var _wind_speed := NAN
var _wind_sent := Vector4.ZERO
@onready var player: Player = $Player
@onready var _rig: CameraRig = $Player/CameraRig
@onready var _player_camera: Camera3D = $Player/CameraRig/Camera3D
@onready var _overview: Camera3D = $Overview

func _ready() -> void:
	_physics_audit = PhysicsAudit.new()
	_physics_audit.name = "PhysicsAudit"
	add_child(_physics_audit)
	# The ready notification turns the callbacks on again; the loader turns
	# them on once the level stands.
	set_process(false)
	set_physics_process(false)
	player.set_physics_process(false)
	var map := region.map.instantiate() as Node3D
	map.name = "Map"
	add_child(map)
	move_child(map, 0)
	var s := _systems
	s.level = self
	s.region = region
	s.world = world
	s.player = player
	s.camera = _player_camera
	s.environment = $WorldEnvironment
	s.map = map
	s.manifest = DataFile.read(region.map_manifest, WorldSchemas.map_manifest())
	s.village_plan = VILLAGE_LAYOUT.read_plan(region.village_plan)
	_player_camera.far = VIEW_DISTANCE
	for stage: Dictionary in LevelParts.STAGES:
		await _loading_step(str(stage.message))
		for step: StringName in stage.steps:
			if LevelParts.builds(region, step):
				await _build(step)
	_built = true

## Builds the step `step`: the level's own, or a system's (LevelParts.build).
func _build(step: StringName) -> void:
	match step:
		&"quality": setup_render_quality()
		&"interface": setup_interface()
		&"panels": _add_panels()
		&"spawn": _place_spawn()
		&"controls": setup_controls()
		&"placement": _queue_placement()
		_: await LevelParts.build(step, _systems)

## Whether the stages of the build are done. The forest, the plants and the
## animals are still placed afterwards (ready_for_visitors).
func built() -> bool:
	return _built

## Whether the placement deferred past the stages is done too: the forest,
## the village's plants and the wild animals stand.
func ready_for_visitors() -> bool:
	var s := _systems
	return _built and (s.wildlife == null or s.wildlife.ready_for_visitors) \
		and (s.village_pack == null or s.village_pack.forest_ready) and (s.flora == null or s.flora.ready_for_visitors)

## Starts the game's day and night in the built level (ValleyLoop): the
## valley is kept in the file SaveService has open; none keeps nothing.
func start_loop() -> ValleyLoop:
	var loop := ValleyLoop.new()
	loop.name = "ValleyLoop"
	loop.region = region
	loop.zones = ValleyZones.load_file(region.zones)
	loop.sky = _systems.sky
	loop.weather = _systems.weather
	loop.player = player
	loop.interactions = _systems.interactions
	loop.population = _systems.people
	loop.camping = _systems.camping
	loop.lakeside = _systems.lakeside
	add_child(loop)
	return loop

## Where the player comes into the region: its spawn, set on the ground once
## the colliders stand.
func spawn_point() -> Vector3:
	return _spawn_position

func _loading_step(message: String) -> void:
	loading_stage.emit(message)
	# Housing transforms and the obstacle scan form one atomic stage. A yield
	# between them flushes other physics transforms and changes the grass
	# mask, even when all tree positions remain equal.
	if _systems.vegetation != null:
		await get_tree().process_frame

## The settings panel and the sharpening pass.
func _add_panels() -> void:
	var settings_panel := SettingsPanel.new()
	settings_panel.name = "Settings"
	add_child(settings_panel)
	var sharpen := SHARPEN_POST.new()
	sharpen.name = "SharpenPost"
	add_child(sharpen)

## The overview camera at the map's first view, and the player at the spawn.
func _place_spawn() -> void:
	var view: Dictionary = _systems.manifest.cameras[0]
	_overview.position = Values.vec3(view.position)
	_overview.look_at(_overview.position + Values.vec3(view.forward))
	_overview.fov = view.fov
	_overview.far = VIEW_DISTANCE
	var spawn := region.spawn(spawn_id)
	_spawn_position = spawn.position
	player.position = _spawn_position
	_rig.sensitivity = 0.12
	_rig.yaw_deg = spawn.yaw_deg
	_rig.pitch_deg = spawn.pitch_deg
	_rig.apply_look(Vector2.ZERO)

## What waits for every building, stone and prop to have its collider: the
## player set on the ground, the forest's wood, the village's plants, the wild
## animals.
func _queue_placement() -> void:
	var s := _systems
	_place_on_ground.call_deferred()
	if s.village_pack != null:
		s.village_pack.scatter_forest.call_deferred()
	if s.flora != null:
		s.flora.grow_plants.call_deferred()
	if s.wildlife != null:
		s.wildlife.populate.call_deferred()

func _place_on_ground() -> void:
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(_spawn_position + Vector3.UP * 28.0, _spawn_position + Vector3.DOWN * 22.0)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_spawn_position = hit.position + Vector3.UP * 0.08
		player.position = _spawn_position
	_controls.spawn = _spawn_position

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
	RenderQuality.apply(get_viewport(), _systems.sky, profile, world)

func _fit_render_resolution() -> void:
	RenderQuality.apply_resolution(get_viewport(), QualityProfile.of(world))

func _process(delta: float) -> void:
	var s := _systems
	s.post.update(delta, get_viewport().get_camera_3d().global_position, get_tree())
	s.rain_fall.wind = s.post.fog.wind
	s.rain_fall.building = s.post.fog.building
	var ocean := s.water.ocean
	# Trees bend in the wind that raises the waves (F1-F4): pressure grows
	# with the square of the speed, so a storm bends them hard. They only take
	# a new wind when an input changed (NaN never compares equal, so the first
	# frame always does).
	var bent := s.vegetation.wind if s.vegetation != null else _wind_sent
	if ocean.wind_direction_deg != _wind_heading_deg or ocean.wind_speed != _wind_speed or bent != _wind_sent:
		_wind_heading_deg = ocean.wind_direction_deg
		_wind_speed = ocean.wind_speed
		var heading := deg_to_rad(ocean.wind_direction_deg)
		_wind_sent = Vector4(cos(heading), sin(heading), minf(pow(ocean.wind_speed / 9.0, 1.6), 2.2), ocean.wind_speed)
		if s.vegetation != null:
			s.vegetation.wind = _wind_sent
			_wind_sent = s.vegetation.wind
		for building: VillageBuilding in s.buildings:
			building.take_wind(heading)

## The HUD, and the status line kept up with the weather, the waves and the hour.
func setup_interface() -> void:
	_status = LEVEL_HUD.build(self, LEVEL_CONTROLS.debug_keys())
	_systems.weather.weather_changed.connect(func(_kind: String) -> void: _update_status())
	_systems.water.ocean.weather_changed.connect(func(_preset: String) -> void: _update_status())
	_systems.sky.time_changed.connect(func(_hours: float) -> void: _update_status())
	_update_status()

## The level's keys (level_controls.gd), on what they work.
func setup_controls() -> void:
	var s := _systems
	_controls = LEVEL_CONTROLS.new()
	_controls.name = "LevelControls"
	_controls.hud = self
	_controls.region = region
	_controls.player = player
	_controls.overview = _overview
	_controls.sky = s.sky
	_controls.weather = s.weather
	_controls.water = s.water
	_controls.interactions = s.interactions
	_controls.camping = s.camping
	_controls.lakeside = s.lakeside
	_controls.spawn = _spawn_position
	_controls.spawn_id = spawn_id
	_controls.status_changed.connect(_update_status)
	add_child(_controls)

func _update_status() -> void:
	if _status == null:
		return
	_status.text = LEVEL_HUD.status_text(_systems.water, _systems.sky, _systems.weather)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_status()

## The overview camera in place of the player's eye, or back (F9).
func toggle_overview() -> void:
	_controls.toggle_overview()

func _physics_process(_delta: float) -> void:
	var s := _systems
	# Swimming follows the waves under the player; the GPU answers a frame late.
	var probes := PackedVector2Array([Vector2(player.position.x, player.position.z)])
	if s.lakeside != null:
		probes.append(Vector2(s.lakeside.boat.position.x, s.lakeside.boat.position.z))
		probes.append(Vector2(s.lakeside.catch_point.x, s.lakeside.catch_point.z))
	s.water.probe_points = probes
	player.water_surface = s.water.surface_height(0)
	# The lake is up to 60 m deep; only a fall through the world resets.
	if player.position.y < -80.0:
		player.position = _spawn_position
		player.velocity = Vector3.ZERO
