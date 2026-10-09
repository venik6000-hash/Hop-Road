class_name GrassField
extends Node3D
## Grass and meadow plants round the camera: clumps of textured cards
## (GrassClump) scattered over the terrain from its own heights and masks,
## drawn by shaders/grass.gdshader.
##
## The terrain has no mesh to read (TerrainSystem raises flat patches in its
## vertex shader), so the clumps stand on the height fields it is drawn from.
## The ground is cut into square tiles, scattered on worker threads
## (grass_tile_job.gd) as the camera comes near and freed behind it. The shader
## thins the meadow with distance (GrassScatter.keep), and a buffer's rows are
## in the order clumps drop out, so a far tile holds only the first share of
## its clumps and every MultiMesh draws only the first rows of what it holds:
## those that stand at its distance. A tile near the camera is held as
## patches, a MultiMesh each, so that each patch draws by its own distance
## and takes the mesh its distance asks for: three bent cards a clump near
## the eye, two flat ones farther out, a single card that faces the eye far
## away. A tile within the mat's reach also holds the mat (GrassClump.MAT),
## the low growth that hides the ground between the plants from an eye that
## looks down.
##
## Nothing in view is ever waited for: a tile needed at once (the first
## frame, a jump) is finished before that frame is drawn, the ring beyond is
## made ahead of the walk.
##
## What grows where is the job's to say (grass_tile_job.gd): tall grass in
## seed on the open meadow, leafy stalks on wet ground and along walls, turf
## on the verges and the heights, little under a tree's crown and shrubs
## round its fringe. Clumps keep
## off paths, beach, the stream's bed, rock, water, snow and steep ground by
## the terrain's grass_cover() (so the ground the terrain darkens under the
## plants is the ground that has them) and off the buildings' footprints
## (ObstacleMap). Flowers stand among the grass, thickest where the terrain's
## flower mask says so, one kind to a patch of meadow.
##
## The plants cast no shadows; they receive those of the trees and houses.

const TileJob = preload("res://src/vegetation/grass_tile_job.gd")
const ImageUtil = preload("res://src/common/image_util.gd")
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
## A piece's clumps are GrassClump.DETAIL's first mesh within NEAR_REACH
## metres, its second to FAR_REACH, its last beyond. Flowers, thin as they
## are, take the second and the last.
const NEAR_REACH := 14.0
const FAR_REACH := 50.0
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

class Tile:
	var key := Vector2i.ZERO
	var rect := Rect2()
	## Lowest and highest ground under it (TerrainSystem.height_range).
	var span := Vector2.ZERO
	## False where nothing can grow (under the lake, off the near field).
	var grows := true
	## The level it holds, -1 while it holds nothing.
	var level := -1
	## Side (m) of the pieces it is held as: TILE or PATCH.
	var piece := TILE
	## Its clumps by piece (GrassScatter.split's keys), the rows each piece
	## was filled from and their ranks in their order.
	var pieces := {}
	var piece_rows := {}
	var piece_ranks := {}
	var flowers: MultiMeshInstance3D
	var flower_rows := PackedFloat32Array()
	var flower_ranks := PackedFloat32Array()
	## Whether it holds the mat, and the mat by square of MAT_PIECE metres
	## with each square's ranks.
	var matted := false
	var mats := {}
	var mat_ranks := {}
	## The job being worked on for it and its WorkerThreadPool task, or -1.
	var job: TileJob
	var task := -1
	## Left the field while its job was still running.
	var dropped := false

@export var terrain: TerrainSystem
## Footprint of the buildings (from the vegetation placement).
var obstacles: ObstacleMap
## The trees the meadow gives way to, and per species the radius of a crown
## at scale 1 (m) and how deep its shade is (0..1).
var woods: TreeLodGrid
var crowns := PackedVector2Array()
var material := ShaderMaterial.new()
## Jobs done: count, total and longest time (us), clumps made.
var job_stats := Vector4i.ZERO

var _ground: TileJob.Ground
var _ground_key: Array = []
var _tiles := {}
var _pending: Array[Tile] = []
## GrassClump.DETAIL's meshes for the grass and for the flowers.
var _meshes: Array[ArrayMesh] = []
var _flower_meshes: Array[ArrayMesh] = []
var _mat_mesh: ArrayMesh
var _surveyed := false
var _eye := Vector3.ZERO
var _fade := Vector4.ZERO
var _mat_fade := Vector2.ZERO
var _wind := Vector4.ZERO
var _wind_sent := false

func _ready() -> void:
	# Bounds are set in world space.
	top_level = true
	material.shader = SHADER
	var noise := load("res://assets/generated/sky/cloud_weather.png")
	material.set_shader_parameter("wind_noise", noise)
	material.set_shader_parameter("cloud_weather", noise)
	GrassClump.dress(material)
	for detail in GrassClump.DETAIL.size():
		_meshes.append(GrassClump.mesh(detail))
		_flower_meshes.append(GrassClump.mesh(detail, true))
	_mat_mesh = GrassClump.mat_mesh()
	for mesh: ArrayMesh in _meshes + _flower_meshes + [_mat_mesh]:
		mesh.surface_set_material(0, material)
	_ground_key = _key()
	_read_ground()

func _exit_tree() -> void:
	for tile: Tile in _pending:
		WorkerThreadPool.wait_for_task_completion(tile.task)
	_pending.clear()

## Keeps the tiles round the camera; VegetationSystem calls it every frame.
func follow(eye: Vector3, wind: Vector4) -> void:
	# A uniform set to the value it already holds changes nothing; skip those.
	if not _wind_sent or wind != _wind:
		material.set_shader_parameter("wind", wind)
		_wind = wind
		_wind_sent = true
	# The clumps stand on the fields as they were read: read them again when
	# the terrain is given other ones.
	var key := _key()
	if key != _ground_key:
		_ground_key = key
		_read_ground()
		_clear()
	var fade := GrassScatter.fade_of(material)
	var mat_fade := GrassScatter.mat_fade_of(material)
	if not _surveyed or eye.distance_to(_eye) >= REFRESH_STEP or fade != _fade or mat_fade != _mat_fade:
		_surveyed = true
		_eye = eye
		_fade = fade
		_mat_fade = mat_fade
		_look_over(eye, fade)
	_collect(UPLOADS_PER_FRAME)

## Clumps and flowers the tiles hold, and how many of them are drawn; for the probes.
func clump_count() -> Vector2i:
	var count := Vector2i.ZERO
	for item: MultiMeshInstance3D in get_children():
		count += Vector2i(item.multimesh.instance_count, item.multimesh.visible_instance_count if item.visible else 0)
	return count

## The level a tile must hold to show `share` of its clumps (-1: none of them).
static func level_for(share: float) -> int:
	if share <= 0.0:
		return -1
	return clampi(int(floor(-log(share) / log(2.0))), 0, MAX_LEVEL)

## Clumps in the first 1 / 2^level of `total`.
static func prefix(total: int, level: int) -> int:
	return ceili(total / float(1 << level))

static func tile_may_grow(rect: Rect2, height_upper: float, near_bounds: Rect2, lake_height: float) -> bool:
	# grass_cover is identically zero at <= 0.08 m above water, and outside the
	# near field nothing grows (its weight is zero there). Keep a tiny margin
	# below the threshold for rounding.
	return rect.intersects(near_bounds) and height_upper > lake_height + 0.0799

## Distance from `eye` to the nearest point of the box over `rect` between the
## heights `span`.
static func distance_to_tile(eye: Vector3, rect: Rect2, span: Vector2) -> float:
	var nearest := Vector3(clampf(eye.x, rect.position.x, rect.end.x), clampf(eye.y, span.x, span.y),
		clampf(eye.z, rect.position.y, rect.end.y))
	return nearest.distance_to(eye)

func _key() -> Array:
	return [terrain.near_image, terrain.far_image, terrain.material.get_shader_parameter("near_control"),
		terrain.material.get_shader_parameter("near_extra"), terrain.material.get_shader_parameter("water_level")]

## Copies of the terrain's masks for the jobs, as the terrain's material holds
## them now (the village and the brook have painted theirs in by this time).
func _read_ground() -> void:
	var ground := TileJob.Ground.new()
	ground.water_level = terrain.material.get_shader_parameter("water_level")
	ground.near_origin = terrain.near_origin
	ground.near_cell = terrain.near_cell
	ground.near_size = terrain.near_size
	var masks: Dictionary = terrain.meta.masks
	ground.mask_origin = Vector2(masks.origin[0], masks.origin[1])
	ground.mask_cell = masks.cell
	ground.mask_size = int(masks.size)
	ground.control = _bytes(terrain.material.get_shader_parameter("near_control"))
	ground.extra = _bytes(terrain.material.get_shader_parameter("near_extra"))
	# The far masks matter under the near field only: keep that part.
	var far := ImageUtil.rgba8(terrain.material.get_shader_parameter("far_masks"))
	var first := Vector2i(((terrain.near_origin - terrain.far_origin) / terrain.far_cell).floor()) - Vector2i.ONE
	var span := int(ceil(terrain.near_size * terrain.near_cell / terrain.far_cell)) + 3
	var part := Rect2i(first, Vector2i(span, span)).intersection(Rect2i(0, 0, far.get_width(), far.get_height()))
	far.clear_mipmaps()
	ground.far = far.get_region(part).get_data()
	ground.far_origin = terrain.far_origin + Vector2(part.position) * terrain.far_cell
	ground.far_cell = terrain.far_cell
	ground.far_size = part.size
	var macro := ImageUtil.rgba8(terrain.material.get_shader_parameter("macro_noise"))
	macro.clear_mipmaps()
	ground.macro = macro.get_data()
	ground.macro_size = macro.get_width()
	if obstacles != null:
		ground.cover = obstacles.cover
		ground.cover_origin = obstacles.origin
		ground.cover_cell = obstacles.cell
		ground.cover_size = obstacles.size
	ground.cells = GrassClump.sheet().cells
	_ground = ground

static func _bytes(texture: Texture2D) -> PackedByteArray:
	var image := ImageUtil.rgba8(texture)
	image.clear_mipmaps()
	return image.get_data()

## Gives every tile in reach what it needs at its distance, starts the jobs
## for those that lack it and frees the tiles left behind.
func _look_over(eye: Vector3, fade: Vector4) -> void:
	var near_rect := Rect2(terrain.near_origin, Vector2.ONE * terrain.near_cell * (terrain.near_size - 1))
	var reach := fade.w + LOOKAHEAD
	var low := Vector2i(floori((eye.x - reach) / TILE), floori((eye.z - reach) / TILE))
	var high := Vector2i(floori((eye.x + reach) / TILE), floori((eye.z + reach) / TILE))
	var needed_now: Array[Tile] = []
	for j in range(low.y, high.y + 1):
		for i in range(low.x, high.x + 1):
			var key := Vector2i(i, j)
			var tile: Tile = _tiles.get(key)
			if tile == null:
				tile = Tile.new()
				tile.key = key
				tile.rect = Rect2(Vector2(key) * TILE, Vector2(TILE, TILE))
				tile.span = terrain.height_range(tile.rect)
				tile.grows = tile_may_grow(tile.rect, tile.span.y, near_rect, _ground.water_level)
				_tiles[key] = tile
			if not tile.grows:
				continue
			var distance := distance_to_tile(eye, tile.rect, tile.span)
			# What it must show before the tiles are looked over again, and
			# what it will have to show a little further on.
			var now := level_for(GrassScatter.share(maxf(distance - REFRESH_STEP, 0.0), fade))
			var soon := level_for(GrassScatter.share(maxf(distance - LOOKAHEAD, 0.0), fade))
			if soon < 0:
				_empty(tile)
				continue
			if _provide(tile, now, soon, distance - LOOKAHEAD):
				needed_now.append(tile)
			_trim(tile, eye, fade)
	# The jobs run side by side; wait for those this frame cannot do without.
	for tile: Tile in needed_now:
		_finish(tile)
	for key: Vector2i in _tiles.keys():
		if key.x < low.x or key.y < low.y or key.x > high.x or key.y > high.y:
			_drop(_tiles[key])

## Starts the job that gives a tile the level it will need (`soon`) in the
## pieces its distance asks for, with the mat if that reaches it, unless it
## holds that already. True when the frame cannot do without the job: the
## tile falls short of what it must show now (`now`).
func _provide(tile: Tile, now: int, soon: int, distance: float) -> bool:
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
	var matted := distance < _mat_fade.y or (tile.matted and distance < _mat_fade.y + SPLIT_SLACK)
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

## Draws of every piece of a tile the clumps that stand at the piece's
## distance, the first rows of what it holds, with the mesh that distance
## asks for.
func _trim(tile: Tile, eye: Vector3, fade: Vector4) -> void:
	for key: Vector2i in tile.pieces:
		var distance := distance_to_tile(eye, Rect2(Vector2(key) * tile.piece, Vector2(tile.piece, tile.piece)), tile.span)
		_limit(tile.pieces[key], tile.piece_rows[key], tile.piece_ranks[key],
			GrassScatter.share(maxf(distance - REFRESH_STEP, 0.0), fade), _meshes[detail_for(distance)])
	if tile.flowers != null:
		var distance := distance_to_tile(eye, tile.rect, tile.span)
		_limit(tile.flowers, tile.flower_rows, tile.flower_ranks,
			GrassScatter.share(maxf(distance - REFRESH_STEP, 0.0), fade, true), _flower_meshes[maxi(detail_for(distance), 1)])
	# The mat has one mesh, so its rows are never asked for again.
	for key: Vector2i in tile.mats:
		var distance := distance_to_tile(eye, Rect2(Vector2(key) * MAT_PIECE, Vector2(MAT_PIECE, MAT_PIECE)), tile.span)
		_limit(tile.mats[key], PackedFloat32Array(), tile.mat_ranks[key],
			GrassScatter.mat_share(maxf(distance - REFRESH_STEP, 0.0), _mat_fade), _mat_mesh)

## The mesh (an index of GrassClump.DETAIL) a piece `distance` metres away is drawn with.
static func detail_for(distance: float) -> int:
	return 0 if distance <= NEAR_REACH else (1 if distance <= FAR_REACH else 2)

static func _limit(item: MultiMeshInstance3D, rows: PackedFloat32Array, ranks: PackedFloat32Array, share: float,
		mesh: ArrayMesh) -> void:
	# Another mesh means another MultiMesh, filled from the rows again: giving
	# a filled one a new mesh makes the renderer read its instances back from
	# the GPU, which waits for every frame under way.
	if item.multimesh.mesh != mesh:
		item.multimesh = _fill(rows, mesh)
	var count := ranks.bsearch(share)
	if item.multimesh.visible_instance_count != count:
		item.multimesh.visible_instance_count = count
	if item.visible != (count > 0):
		item.visible = count > 0

static func _fill(rows: PackedFloat32Array, mesh: ArrayMesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = rows.size() / GrassScatter.STRIDE
	multimesh.buffer = rows
	return multimesh

func _start(tile: Tile, level: int, piece: float, matted: bool) -> void:
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
	var samples := int(TILE / TileJob.GRAIN) + 3
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	xs.resize(samples)
	zs.resize(samples)
	for n in samples:
		xs[n] = tile.rect.position.x + (n - 1) * TileJob.GRAIN
		zs[n] = tile.rect.position.y + (n - 1) * TileJob.GRAIN
	job.heights = terrain.heights_at_grid(xs, zs)
	if woods != null:
		job.trees = woods.near(tile.rect)
		for at in range(0, job.trees.size(), 4):
			var crown := crowns[int(job.trees[at + 3])]
			job.trees[at + 2] *= crown.x
			job.trees[at + 3] = crown.y
	tile.job = job
	tile.task = WorkerThreadPool.add_task(job.run)
	_pending.append(tile)

## Waits for a tile's job and shows what it made.
func _finish(tile: Tile) -> void:
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
func _show(tile: Tile) -> void:
	var job := tile.job
	tile.job = null
	tile.task = -1
	if tile.dropped:
		return
	job_stats += Vector4i(1, job.usec, 0, job.clump_count)
	job_stats.z = maxi(job_stats.z, job.usec)
	_empty(tile)
	tile.level = job.level
	tile.piece = job.piece
	tile.piece_rows = job.pieces
	tile.piece_ranks = job.piece_ranks
	tile.flower_rows = job.flowers
	tile.flower_ranks = job.flower_ranks
	tile.matted = job.mat_total > 0
	tile.mat_ranks = job.mat_ranks
	var height := maxf(job.high - job.low, 0.0)
	for key: Vector2i in job.pieces:
		var square := Rect2(Vector2(key) * job.piece, Vector2(job.piece, job.piece))
		var box := AABB(Vector3(square.position.x, job.low, square.position.y), Vector3(job.piece, height, job.piece))
		tile.pieces[key] = _make("Clumps_%d_%d_%d" % [int(job.piece), key.x, key.y], job.pieces[key],
			_meshes[detail_for(distance_to_tile(_eye, square, tile.span))], box.grow(GrassClump.REACH))
	if not job.flowers.is_empty():
		var box := AABB(Vector3(tile.rect.position.x, job.low, tile.rect.position.y), Vector3(TILE, height, TILE))
		tile.flowers = _make("Flowers_%d_%d" % [tile.key.x, tile.key.y], job.flowers,
			_flower_meshes[maxi(detail_for(distance_to_tile(_eye, tile.rect, tile.span)), 1)], box.grow(GrassClump.REACH))
	for key: Vector2i in job.mats:
		var box := AABB(Vector3(key.x * MAT_PIECE, job.low, key.y * MAT_PIECE), Vector3(MAT_PIECE, height, MAT_PIECE))
		tile.mats[key] = _make("Mat_%d_%d" % [key.x, key.y], job.mats[key], _mat_mesh, box.grow(GrassClump.REACH))
	_trim(tile, _eye, _fade)

func _make(item_name: String, rows: PackedFloat32Array, mesh: ArrayMesh, box: AABB) -> MultiMeshInstance3D:
	var item := MultiMeshInstance3D.new()
	item.name = item_name
	item.multimesh = _fill(rows, mesh)
	item.custom_aabb = box
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	item.layers = VegetationSystem.VISUAL_LAYER
	add_child(item)
	return item

## Takes away what a tile shows; a job under way for it is left to finish.
func _empty(tile: Tile) -> void:
	for item: MultiMeshInstance3D in tile.pieces.values():
		item.free()
	tile.pieces = {}
	tile.piece_rows = {}
	tile.piece_ranks = {}
	if tile.flowers != null:
		tile.flowers.free()
		tile.flowers = null
	tile.flower_rows = PackedFloat32Array()
	for item: MultiMeshInstance3D in tile.mats.values():
		item.free()
	tile.mats = {}
	tile.mat_ranks = {}
	tile.matted = false
	tile.level = -1

func _drop(tile: Tile) -> void:
	_empty(tile)
	tile.dropped = true
	_tiles.erase(tile.key)

func _clear() -> void:
	for tile: Tile in _tiles.values():
		_drop(tile)
	_surveyed = false
