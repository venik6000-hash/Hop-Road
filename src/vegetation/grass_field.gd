class_name GrassField
extends Node3D
## Grass and meadow plants round the camera: clumps of textured cards
## (GrassClump) scattered over the terrain from its own heights and masks,
## drawn by shaders/grass.gdshader.
##
## The terrain has no mesh to read (TerrainSystem raises flat patches in its
## vertex shader), so the clumps stand on the height fields it is drawn from.
## The ground is cut into square tiles (GrassTile), scattered on worker
## threads (grass_tile_job.gd) as the camera comes near and freed behind it.
## The shader thins the meadow with distance (GrassScatter.keep), and a
## buffer's rows are in the order clumps drop out, so a far tile holds only
## the first share of its clumps and every MultiMesh draws only the first
## rows of what it holds: those that stand at its distance. A tile near the
## camera is held as patches, a MultiMesh each, so that each patch draws by
## its own distance and takes the mesh its distance asks for. A tile within
## the mat's reach also holds the mat (GrassClump.MAT), the low growth that
## hides the ground between the plants from an eye that looks down.
##
## For an eye in the tavern's rooms the tiles and pieces no opening shows are
## not drawn; they are scattered and kept as ever, so that nothing has to be
## waited for when the eye turns to another window.
##
## Nothing in view is ever waited for: a tile needed at once (the first
## frame, a jump) is finished before that frame is drawn, the ring beyond is
## made ahead of the walk.
##
## What grows where is the survey's to say (GrassSurvey): swathes of rank
## grass in seed beside swathes of poor turf in tussocks on the open meadow,
## leafy stalks on wet ground and along walls, turf on the verges and the
## heights, little under a tree's crown and shrubs round its fringe. Clumps
## keep off paths, beach, the stream's bed, rock, water, snow and steep
## ground and thin out under the trees by the terrain's grass_cover() (so the
## ground the terrain darkens under the plants is the ground that has them)
## and off the buildings' footprints (ObstacleMap). Flowers stand among the
## grass, thickest where the terrain's flower mask says so, one kind to a
## patch of meadow.
##
## The plants cast no shadows; they receive those of the trees and houses.

const TileJob = preload("res://src/vegetation/grass_tile_job.gd")
const CanopyField = preload("res://src/vegetation/canopy_field.gd")
const SHADER := preload("res://src/vegetation/shaders/grass.gdshader")
## Side (m) of a tile, and of the patches a tile near the camera is held as.
const TILE := 16.0
const PATCH := 4.0
## A tile nearer than SPLIT_REACH (m) is held as patches; it goes back to one
## piece SPLIT_SLACK farther out.
const SPLIT_REACH := 20.0
const SPLIT_SLACK := 8.0
## Clumps to the square metre of open meadow, and flowers where the flower
## mask is full.
const DENSITY := 9.0
const FLOWER_DENSITY := 1.4
## Clumps of the mat to the square metre, and the side (m) of the squares a
## tile's mat is held as.
const MAT_DENSITY := 12.0
const MAT_PIECE := 8.0
## A tile holds the first 1 / 2^level of its clumps; farther than the last
## level's share it holds that share still.
const MAX_LEVEL := 6
## Steeper ground than this (radians from level) grows nothing.
const SLOPE_LIMIT := PI * 0.25
## Tiles are made this far (m) ahead of the distance at which they show.
const LOOKAHEAD := 8.0
## Tiles are looked over again once the camera has moved this far (m).
const REFRESH_STEP := 1.0
## Finished tiles handed to the renderer per frame, beyond those needed at once.
const UPLOADS_PER_FRAME := 2

@export var terrain: TerrainSystem
## Footprint of the buildings (from the vegetation placement).
var obstacles: ObstacleMap
## The level's context (its rooms' sight, Interiors); null in a tool that builds
## a part of the level alone.
var world: WorldContext
## The trees the meadow gives way to, and per species the radius of a crown
## at scale 1 (m) and how deep its shade is (0..1).
var woods: TreeLodGrid
var crowns := PackedVector2Array()
## The cover of those crowns as a field, for every shader outdoors and for
## the jobs: the grass gives way to a wood where its trees stand.
var canopy: CanopyField
var material := ShaderMaterial.new()
## Jobs done: count, total and longest time (us), clumps made.
var job_stats := Vector4i.ZERO

var _ground: GrassGround
var _ground_key: Array = []
var _tiles := {}
var _pending: Array[GrassTile] = []
## The eye and the sight the tiles are drawn for, and their meshes.
var _view: GrassTile.View
var _surveyed := false
var _wind := Vector4.ZERO
var _wind_sent := false
## The Interiors.revision the pieces were last shown by.
var _portal_revision := 0

func _ready() -> void:
	# Bounds are set in world space.
	top_level = true
	material.shader = SHADER
	var noise := load("res://assets/generated/sky/cloud_weather.png")
	material.set_shader_parameter("wind_noise", noise)
	material.set_shader_parameter("cloud_weather", noise)
	GrassClump.dress(material)
	set_fade(QualityProfile.of(world).grass_fade)
	if world != null:
		world.quality_changed.connect(_quality_changed)
	_view = GrassTile.View.new(material)
	# Made here and not by VegetationSystem, which holds the same trees: the
	# field is no part of where a tree stands.
	if woods != null:
		canopy = canopy_of(woods, crowns)
		canopy.publish()
		print("CANOPY trees=%d side=%d build=%.0fms" % [canopy.tree_count, canopy.samples, canopy.build_usec / 1000.0])
	_ground_key = GrassGround.source_of(terrain)
	_ground = GrassGround.read(terrain, obstacles, canopy)

## Where the grass starts to fade and where it is gone (m): the shader's
## fade_start and fade_end. The field looks over its tiles at the next step.
func set_fade(fade: Vector2) -> void:
	material.set_shader_parameter("fade_start", fade.x)
	material.set_shader_parameter("fade_end", fade.y)

func _quality_changed(profile: QualityProfile) -> void:
	set_fade(profile.grass_fade)

func _exit_tree() -> void:
	for tile: GrassTile in _pending:
		WorkerThreadPool.wait_for_task_completion(tile.task)
	_pending.clear()
	if canopy != null:
		canopy.withdraw()

## Keeps the tiles round the camera; VegetationSystem calls it every frame.
func follow(eye: Vector3, wind: Vector4) -> void:
	# A uniform set to the value it already holds changes nothing; skip those.
	if not _wind_sent or wind != _wind:
		material.set_shader_parameter("wind", wind)
		_wind = wind
		_wind_sent = true
	# The clumps stand on the fields as they were read: read them again when
	# the terrain is given other ones.
	var key := GrassGround.source_of(terrain)
	if key != _ground_key:
		_ground_key = key
		_ground = GrassGround.read(terrain, obstacles, canopy)
		_clear()
	var fade := GrassScatter.fade_of(material)
	var mat_fade := GrassScatter.mat_fade_of(material)
	var interiors := world.interiors if world != null else null
	var revision := interiors.revision if interiors != null else 0
	_view.sight = interiors.sight if interiors != null and interiors.sight.active else null
	if not _surveyed or eye.distance_to(_view.eye) >= REFRESH_STEP or fade != _view.fade or mat_fade != _view.mat_fade:
		_surveyed = true
		_view.eye = eye
		_view.fade = fade
		_view.mat_fade = mat_fade
		_look_over(eye, fade)
	elif revision != _portal_revision:
		for tile: GrassTile in _tiles.values():
			tile.resee(_view)
	if revision != _portal_revision:
		_portal_revision = revision
		if interiors != null:
			interiors.counts[&"grass"] = hidden_count()
	_collect(UPLOADS_PER_FRAME)

## Clumps and flowers the tiles hold, and how many of them are drawn; for the probes.
func clump_count() -> Vector2i:
	var count := Vector2i.ZERO
	for item: MultiMeshInstance3D in get_children():
		count += Vector2i(item.multimesh.instance_count, item.multimesh.visible_instance_count if item.visible else 0)
	return count

## The pieces that hold clumps to draw and are hidden from an eye indoors,
## and how many hold clumps to draw; for the portals' log.
func hidden_count() -> Vector2i:
	var count := Vector2i.ZERO
	for item: MultiMeshInstance3D in get_children():
		if item.multimesh.visible_instance_count != 0:
			count += Vector2i(int(not item.visible), 1)
	return count

## The cover of the crowns of every tree of `grid` that has a mesh, over the
## square those trees stand in. `shades` holds, per species, a crown's radius
## at scale 1 (m) and how deep its shade is (0..1).
static func canopy_of(grid: TreeLodGrid, shades: PackedVector2Array) -> CanopyField:
	var span := Vector2(grid.size) * TreeLodGrid.CELL
	return CanopyField.new(grid.near(Rect2(grid.origin, span), shades), grid.origin,
		int(maxf(span.x, span.y) / CanopyField.CELL))

## The level a tile must hold to show `share` of its clumps (-1: none of them).
static func level_for(share: float) -> int:
	if share <= 0.0:
		return -1
	return clampi(floori(-log(share) / log(2.0)), 0, MAX_LEVEL)

## Clumps in the first 1 / 2^level of `total`.
static func prefix(total: int, level: int) -> int:
	return ceili(total / float(1 << level))

static func tile_may_grow(rect: Rect2, height_upper: float, near_bounds: Rect2, lake_height: float) -> bool:
	# grass_cover is identically zero at <= 0.08 m above water, and outside the
	# near field nothing grows (its weight is zero there). Keep a tiny margin
	# below the threshold for rounding.
	return rect.intersects(near_bounds) and height_upper > lake_height + 0.0799

## Gives every tile in reach what it needs at its distance, starts the jobs
## for those that lack it and frees the tiles left behind.
func _look_over(eye: Vector3, fade: Vector4) -> void:
	var near_rect := Rect2(terrain.near_origin, Vector2.ONE * terrain.near_cell * (terrain.near_size - 1))
	var reach := fade.w + LOOKAHEAD
	var low := Vector2i(floori((eye.x - reach) / TILE), floori((eye.z - reach) / TILE))
	var high := Vector2i(floori((eye.x + reach) / TILE), floori((eye.z + reach) / TILE))
	var needed_now: Array[GrassTile] = []
	for j in range(low.y, high.y + 1):
		for i in range(low.x, high.x + 1):
			var key := Vector2i(i, j)
			var tile: GrassTile = _tiles.get(key)
			if tile == null:
				tile = GrassTile.new(key, TILE)
				tile.span = terrain.height_range(tile.rect)
				tile.grows = tile_may_grow(tile.rect, tile.span.y, near_rect, _ground.water_level)
				_tiles[key] = tile
			if not tile.grows:
				continue
			var distance := GrassTile.distance_to_tile(eye, tile.rect, tile.span)
			# What it must show before the tiles are looked over again, and
			# what it will have to show a little further on.
			var now := level_for(GrassScatter.share(maxf(distance - REFRESH_STEP, 0.0), fade))
			var soon := level_for(GrassScatter.share(maxf(distance - LOOKAHEAD, 0.0), fade))
			if soon < 0:
				tile.empty()
				continue
			if _provide(tile, now, soon, distance - LOOKAHEAD):
				needed_now.append(tile)
			tile.trim(_view)
	# The jobs run side by side; wait for those this frame cannot do without.
	for tile: GrassTile in needed_now:
		_finish(tile)
	for key: Vector2i in _tiles.keys():
		if key.x < low.x or key.y < low.y or key.x > high.x or key.y > high.y:
			var tile: GrassTile = _tiles[key]
			_drop(tile)

## Starts the job that gives a tile the level it will need (`soon`) in the
## pieces its distance asks for, with the mat if that reaches it, unless it
## holds that already. True when the frame cannot do without the job: the
## tile falls short of what it must show now (`now`).
func _provide(tile: GrassTile, now: int, soon: int, distance: float) -> bool:
	var lacking := now >= 0 and (tile.level < 0 or tile.level > now)
	if tile.task >= 0:
		if not lacking:
			return false
		# The job under way may fall short of it too: see what it brings.
		_finish(tile)
		lacking = tile.level < 0 or tile.level > now
	var piece := TILE
	if distance < SPLIT_REACH or (tile.piece == PATCH and distance < SPLIT_REACH + SPLIT_SLACK):
		piece = PATCH
	var matted := distance < _view.mat_fade.y or (tile.matted and distance < _view.mat_fade.y + SPLIT_SLACK)
	var target := soon
	if tile.level >= 0 and tile.level <= soon:
		# It holds enough. Thin it only once it holds four times too much.
		if soon - tile.level < 2:
			if piece == tile.piece and matted == tile.matted:
				return false
			target = tile.level
		else:
			target = soon - 1
	_start(tile, target, piece, matted)
	return lacking

func _start(tile: GrassTile, level: int, piece: float, matted: bool) -> void:
	var job := TileJob.new()
	job.ground = _ground
	job.origin = tile.rect.position
	job.side = TILE
	job.piece = piece
	job.level = level
	job.total = roundi(DENSITY * TILE * TILE)
	job.wanted = prefix(job.total, level)
	# Flowers are few and outlast the grass: a tile holds all of its own.
	job.flower_total = roundi(FLOWER_DENSITY * TILE * TILE)
	job.flower_wanted = job.flower_total
	job.mat_total = roundi(MAT_DENSITY * TILE * TILE) if matted else 0
	job.mat_piece = MAT_PIECE
	job.slope_floor = cos(SLOPE_LIMIT)
	job.salt = hash(tile.key) & 0x3fffffff
	# Heights every half metre, one sample beyond each edge for the normals.
	var samples := int(TILE / GrassSurvey.GRAIN) + 3
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	xs.resize(samples)
	zs.resize(samples)
	for n in samples:
		xs[n] = tile.rect.position.x + (n - 1) * GrassSurvey.GRAIN
		zs[n] = tile.rect.position.y + (n - 1) * GrassSurvey.GRAIN
	job.heights = terrain.heights_at_grid(xs, zs)
	if woods != null:
		job.trees = woods.near(tile.rect, crowns)
	tile.job = job
	tile.task = WorkerThreadPool.add_task(job.run)
	_pending.append(tile)

## Waits for a tile's job and shows what it made.
func _finish(tile: GrassTile) -> void:
	WorkerThreadPool.wait_for_task_completion(tile.task)
	_pending.erase(tile)
	_show(tile)

## Shows the tiles whose jobs are done, `limit` of them at most.
func _collect(limit: int) -> void:
	var shown := 0
	var index := 0
	while index < _pending.size() and shown < limit:
		var tile := _pending[index]
		if not WorkerThreadPool.is_task_completed(tile.task):
			index += 1
			continue
		WorkerThreadPool.wait_for_task_completion(tile.task)
		_pending.remove_at(index)
		if not tile.dropped:
			shown += 1
		_show(tile)

## Puts what a tile's job made in place of what the tile showed.
func _show(tile: GrassTile) -> void:
	var job := tile.job
	tile.job = null
	tile.task = -1
	if tile.dropped:
		return
	job_stats += Vector4i(1, job.usec, 0, job.clump_count)
	job_stats.z = maxi(job_stats.z, job.usec)
	tile.show_job(job, self, _view)

func _drop(tile: GrassTile) -> void:
	tile.empty()
	tile.dropped = true
	_tiles.erase(tile.key)

func _clear() -> void:
	for tile: GrassTile in _tiles.values():
		_drop(tile)
	_surveyed = false
