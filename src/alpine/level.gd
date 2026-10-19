extends Node3D
## Playable wrapper around a region (RegionDef): its Blender map, physical
## sky, generated terrain, the FFT lake and the buildings on top of it. The
## loading screen (src/loading/world_loader.gd) builds it, in the game and in
## the tools alike: _ready goes by the stages and steps of LevelParts and
## waits for the loader's prefetch. The core steps are built for every
## region, a part only when the region names it (RegionDef.parts).
##
## Its systems stand under two nodes (docs/LEVEL.md, «Общие системы и
## содержимое»): "Shared" holds what lives for the whole game (SharedSystems),
## "Content" the region's content (CellContent), which unload_content() and
## build_content() take away and build again without another scene. The
## content gives the shared systems what they need through the registries of
## WorldContext (docs/LEVEL.md, «Реестры»).
##
## Its face to others is narrow (docs/LEVEL.md, «Фасад уровня»): `region`,
## `world`, `player`, loading_stage, build_steps, built(), ready_for_visitors(),
## start_loop(), spawn_point(), apply_quality(), toggle_overview(),
## unload_content(), build_content(). The systems are its own: it hands each
## the others it needs. A tool reaches a system by its class
## (tools/lib/tool_level.gd).

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
## How far (m) below the lowest ground of the region a fall resets the player
## to the spawn: under the ground there is nothing to stand on.
const FALL_MARGIN := 20.0
## The overview camera of a map without cameras: this far above and behind
## the spawn (m), looking at it.
const OVERVIEW_OFFSET := Vector3(0.0, 40.0, 60.0)
## The region this level builds. WorldLoader sets it before the level enters
## the tree: main.tscn names none.
@export var region: RegionDef
## The spawn of the region the player comes in at (RegionSpawn.id); "" for
## its first. WorldLoader sets it.
var spawn_id := &""
## What the level's systems share (WorldContext); a tool sets its switches
## before the level enters the tree.
var world := WorldContext.new()
## The shared systems and the region's content built so far.
var _shared := SharedSystems.new()
var _content := CellContent.new()
## The loop start_loop() started; null before.
var _loop: ValleyLoop
## The player's physics ran when the content was unloaded: it runs again once
## the content stands.
var _player_moved := false
var _spawn_position := Vector3.ZERO
## A player below this height has fallen through the world (FALL_MARGIN).
var _fall_floor := -INF
var _status: Label
var _controls: LEVEL_CONTROLS
## The stages of _ready are done; the deferred placement may still run.
var _built := false
## Each step of the build in order: its name, its time (ms, frames it waits
## included) and how much the engine's memory grew (MB, debug builds).
var build_steps: Array[Dictionary] = []
## Checks every body of the level as it comes (docs/LEVEL.md, «Сторож»).
var _physics_audit: PhysicsAudit
@onready var player: Player = $Shared/Player
@onready var _rig: CameraRig = $Shared/Player/CameraRig
@onready var _overview: Camera3D = $Shared/Overview

func _ready() -> void:
	var s := _shared
	s.level = self
	s.node = $Shared
	s.region = region
	s.world = world
	s.player = player
	s.camera = player.camera
	s.environment = $Shared/WorldEnvironment
	_physics_audit = PhysicsAudit.new()
	_physics_audit.name = "PhysicsAudit"
	_physics_audit.scope = self
	s.add(_physics_audit)
	# The ready notification turns the callbacks on again; the loader turns
	# them on once the level stands.
	set_process(false)
	set_physics_process(false)
	player.set_physics_process(false)
	_content = _new_content()
	player.camera.far = VIEW_DISTANCE
	for stage: Dictionary in LevelParts.STAGES:
		await _loading_step(str(stage.message))
		for step: StringName in stage.steps:
			if LevelParts.builds(region, step):
				var started := Time.get_ticks_usec()
				var memory := OS.get_static_memory_usage()
				await _build(step)
				var ms := (Time.get_ticks_usec() - started) / 1000.0
				build_steps.append({"step": String(step), "ms": snappedf(ms, 0.1),
					"memory_mb": snappedf((OS.get_static_memory_usage() - memory) / 1048576.0, 0.1)})
				print("WORLD_STEP %s %.1f ms" % [step, ms])
	_content.stand(world)
	_built = true

## The region's content as it starts: its node under "Content" (named by the
## region), the Blender map in it with its index (MapIndex), the map's
## manifest and the village plan.
func _new_content() -> CellContent:
	var c := CellContent.new()
	c.node = Node3D.new()
	c.node.name = String(region.id) if not region.id.is_empty() else "Region"
	$Content.add_child(c.node)
	c.map = region.map_scene().instantiate() as Node3D
	c.map.name = "Map"
	c.node.add_child(c.map)
	# The one walk of the map: every step after asks the index.
	c.map_index = MapIndex.of(c.map)
	c.manifest = DataFile.read(region.map_manifest, WorldSchemas.map_manifest())
	c.village_plan = VILLAGE_LAYOUT.read_plan(region.village_plan)
	return c

## Builds the step `step`: the level's own, or a system's (LevelParts.build).
func _build(step: StringName) -> void:
	match step:
		&"quality": setup_render_quality()
		&"interface": setup_interface()
		&"panels": _add_panels()
		&"spawn": _place_spawn()
		&"controls": setup_controls()
		&"placement":
			_place_on_ground.call_deferred()
			_queue_placement()
		&"terrain":
			await LevelParts.build(step, _shared, _content)
			_hold_ground()
		_: await LevelParts.build(step, _shared, _content)

## The terrain's collision follows the player, and holds the region's land
## while the content builds: the rays of the build meet the ground anywhere
## in the region until the forest, the plants and the animals stand.
func _hold_ground() -> void:
	if _shared.terrain == null or _shared.terrain.collision == null:
		return
	_shared.terrain.collision.focus = player
	_shared.terrain.collision.hold(region.near_bounds, ready_for_visitors)

## Builds the content of the step `step` again (LevelParts.rebuild): the
## level's own steps take the new content too.
func _rebuild(step: StringName) -> void:
	match step:
		&"controls": _controls.lakeside = _content.lakeside
		&"placement": _queue_placement()
		_: await LevelParts.rebuild(step, _shared, _content)

## Unloads the region's content without another scene: the villagers and the
## player hold still, and its node goes. Leaving the tree, the content takes
## what it gave the shared systems out of the registries. False when it
## cannot: the level is not built, or the loop runs (its save sections hold
## the content's systems).
func unload_content() -> bool:
	if not _built or _content.node == null:
		push_error("Level: no content stands to unload")
		return false
	if is_instance_valid(_loop):
		push_error("Level: the content cannot unload while the loop runs")
		return false
	_built = false
	if _controls != null:
		_controls.lakeside = null
	if _shared.people != null:
		_shared.people.process_mode = Node.PROCESS_MODE_DISABLED
	_player_moved = player.is_physics_processing()
	player.set_physics_process(false)
	var node := _content.node
	# Out of the tree at once: its bodies leave the physics space now.
	node.get_parent().remove_child(node)
	node.queue_free()
	_content = CellContent.new()
	return true

## Builds the region's content again after unload_content(), by the steps of
## the first build in their order, under the shared systems that stand
## (LevelParts.rebuild). built() is true again once it returns; the forest,
## the plants and the animals are placed after it (ready_for_visitors).
func build_content() -> void:
	if _built or _content.node != null:
		push_error("Level: the content stands already")
		return
	_content = _new_content()
	_hold_ground()
	for stage: Dictionary in LevelParts.STAGES:
		await _stage_gap()
		for step: StringName in stage.steps:
			if LevelParts.builds(region, step) and LevelParts.rebuilds(step):
				await _rebuild(step)
	_content.stand(world)
	player.set_physics_process(_player_moved)
	_built = true

## Whether the stages of the build are done. The forest, the plants and the
## animals are still placed afterwards (ready_for_visitors).
func built() -> bool:
	return _built

## Whether the placement deferred past the stages is done too: the forest,
## the village's plants and the wild animals stand.
func ready_for_visitors() -> bool:
	var c := _content
	return _built and (c.wildlife == null or c.wildlife.ready_for_visitors) \
		and (c.village_pack == null or c.village_pack.forest_ready) and (c.flora == null or c.flora.ready_for_visitors)

## Starts the game's day and night in the built level (ValleyLoop): the
## valley is kept in the file SaveService has open; none keeps nothing.
func start_loop() -> ValleyLoop:
	var s := _shared
	_loop = ValleyLoop.new()
	_loop.name = "ValleyLoop"
	_loop.region = region
	_loop.zones = ValleyZones.load_file(region.zones)
	_loop.weather = s.weather
	_loop.player = player
	_loop.interactions = s.interactions
	_loop.population = s.people
	_loop.camping = s.camping
	_loop.lakeside = _content.lakeside
	s.add(_loop)
	return _loop

## Where the player comes into the region: its spawn, set on the ground once
## the colliders stand.
func spawn_point() -> Vector3:
	return _spawn_position

func _loading_step(message: String) -> void:
	loading_stage.emit(message)
	await _stage_gap()

## The frame between two stages (WorldContext.stage_frames). The obstacle
## scan writes the bodies' places into physics itself (ObstacleMap.settle):
## the frames do not change the grass's mask or the trees.
func _stage_gap() -> void:
	if world.stage_frames:
		await get_tree().process_frame

## The settings panel and the sharpening pass.
func _add_panels() -> void:
	var settings_panel := SettingsPanel.new()
	settings_panel.name = "Settings"
	_shared.add(settings_panel)
	var sharpen := SHARPEN_POST.new()
	sharpen.name = "SharpenPost"
	_shared.add(sharpen)

## The overview camera at the map's first view, and the player at the spawn.
## A map without cameras gives the overview a view of the spawn
## (OVERVIEW_OFFSET, turned by the spawn's yaw).
func _place_spawn() -> void:
	var spawn := region.spawn(spawn_id)
	var cameras: Array = _content.manifest.get("cameras", [])
	if not cameras.is_empty():
		var view: Dictionary = cameras[0]
		_overview.position = Values.vec3(view.position)
		_overview.look_at(_overview.position + Values.vec3(view.forward))
		_overview.fov = view.fov
	else:
		_overview.position = spawn.position + OVERVIEW_OFFSET.rotated(Vector3.UP, deg_to_rad(spawn.yaw_deg))
		_overview.look_at(spawn.position)
	_overview.far = VIEW_DISTANCE
	_spawn_position = spawn.position
	_fall_floor = _shared.terrain.lowest() - FALL_MARGIN
	player.position = _spawn_position
	_rig.sensitivity = 0.12
	_rig.yaw_deg = spawn.yaw_deg
	_rig.pitch_deg = spawn.pitch_deg
	_rig.apply_look(Vector2.ZERO)

## What waits for every building, stone and prop of the content to have its
## collider: the forest's wood, the village's plants, the wild animals. The
## first build sets the player on the ground before them.
func _queue_placement() -> void:
	var c := _content
	if c.village_pack != null:
		c.village_pack.scatter_forest.call_deferred()
	if c.flora != null:
		c.flora.grow_plants.call_deferred()
	if c.wildlife != null:
		c.wildlife.populate.call_deferred()

## Sets the player on what stands under the spawn, once the ground there
## answers a ray (PhysicsLayers.ground_stands).
func _place_on_ground() -> void:
	await PhysicsLayers.ground_stands(self, _spawn_position)
	if not is_inside_tree():
		return
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
	RenderQuality.apply(get_viewport(), _shared.sky, profile, world)

func _fit_render_resolution() -> void:
	RenderQuality.apply_resolution(get_viewport(), QualityProfile.of(world))

func _process(delta: float) -> void:
	var s := _shared
	var eye := get_viewport().get_camera_3d().global_position
	# The fields round the eye follow it (FieldWindow); the crowns' field
	# follows the grass's eye (GrassField.follow).
	s.sun_shadow.follow(Vector2(eye.x, eye.z))
	s.rain_shelter.follow(Vector2(eye.x, eye.z))
	s.post.update(delta, eye, get_tree())
	s.rain_fall.wind = s.post.fog.wind
	s.rain_fall.building = s.post.fog.building

## The HUD, and the status line kept up with the weather, the waves and the hour.
func setup_interface() -> void:
	_status = LEVEL_HUD.build(_shared.node, LEVEL_CONTROLS.debug_keys())
	_shared.weather.weather_changed.connect(func(_kind: String) -> void: _update_status())
	_shared.water.ocean.weather_changed.connect(func(_preset: String) -> void: _update_status())
	GameClock.changed.connect(_update_status)
	_update_status()

## The level's keys (level_controls.gd), on what they work.
func setup_controls() -> void:
	var s := _shared
	_controls = LEVEL_CONTROLS.new()
	_controls.name = "LevelControls"
	_controls.hud = s.node
	_controls.region = region
	_controls.player = player
	_controls.overview = _overview
	_controls.sky = s.sky
	_controls.weather = s.weather
	_controls.water = s.water
	_controls.interactions = s.interactions
	_controls.camping = s.camping
	_controls.lakeside = _content.lakeside
	_controls.spawn = _spawn_position
	_controls.spawn_id = spawn_id
	_controls.status_changed.connect(_update_status)
	s.add(_controls)

func _update_status() -> void:
	if _status == null:
		return
	_status.text = LEVEL_HUD.status_text(_shared.water, _shared.weather)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_status()

## The overview camera in place of the player's eye, or back (F9).
func toggle_overview() -> void:
	_controls.toggle_overview()

func _physics_process(_delta: float) -> void:
	var s := _shared
	# Swimming follows the waves under the player; the GPU answers a frame late.
	# The player's point is the first, the content's (WorldContext.water_probes)
	# follow.
	var probes := PackedVector2Array([Vector2(player.position.x, player.position.z)])
	for points: Callable in world.water_probes.entries():
		var more: PackedVector2Array = points.call()
		probes.append_array(more)
	s.water.probe_points = probes
	player.water_surface = s.water.surface_height(0)
	# Only a fall through the world resets: below the lowest ground of the region.
	if player.position.y < _fall_floor:
		player.position = _spawn_position
		player.velocity = Vector3.ZERO
