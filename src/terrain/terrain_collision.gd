class_name TerrainCollision
extends StaticBody3D
## The physics body of TerrainSystem, named "TerrainBody" (PhysicsLayers.hit_terrain
## matches the name): HeightMapShape3D chunks CHUNK m a side, a sample every
## STEP m, over the walkable land. Each chunk is a CollisionShape3D of this
## body. Beyond the land there is no ground: the drawn slope goes on there,
## so a wall stands along each side of the land (wall_in()) and nothing walks
## or falls out through it.
##
## A chunk stands while the focus (the player) is nearer to its rectangle than
## LOAD_RADIUS and goes once the focus is farther than DROP_RADIUS
## (docs/plans/open_world.md, 4.2). A held rectangle (hold()) keeps its chunks
## whatever the focus. Until a focus is set, the region's land
## (RegionDef.near_bounds) is held: a tool that builds the terrain alone has
## the ground the whole region over. The level sets the player as the focus
## and holds the region's land while it builds.
##
## Building goes in steps (step()): a chunk inside a tile is one step, a chunk
## whose heights blend fields is a band of BAND rows a step. Each physics
## frame takes one step and drops one chunk. The chunk under the focus is
## built whole at once, before the bodies move.
##
## The heights are TerrainTiles.height() at the samples. Inside a tile, away
## from its fade, they are every second sample of the tile, copied without a
## loop; elsewhere TerrainSystem.heights_at_grid() reads them. When the tiles
## change (TerrainSystem.tiles_changed), each chunk is built again in its
## turn and stands as it was until then.

## A chunk's side and the step of its samples, m: 129 squared samples.
const CHUNK := 128.0
const STEP := 1.0
## The radii of open_world.md 4.2, m from the focus to a chunk's rectangle.
const LOAD_RADIUS := 256.0
const DROP_RADIUS := 320.0
## Rows of a blended chunk one step builds.
const BAND := 8
## The walls round the land: thickness, m, and the heights they span, m.
const WALL := 2.0
const WALL_SPAN := Vector2(-1000.0, 5000.0)

## The collision of each physics space by the space's RID (ground_under()).
static var _of_space := {}

var terrain: TerrainSystem
## The node the chunks follow; none: only the held rectangles stand.
var focus: Node3D
## The walkable land (x, z): the world's, or the near field of a terrain the
## world was not built for. The chunk grid starts at its corner.
var land := Rect2()
## The chunks that stand: CollisionShape3D by chunk (column, row).
var _chunks := {}
## The chunks built before the tiles last changed.
var _stale := {}
## The chunk being built in bands: {at, heights, rows done}; empty if none.
var _job := {}
## Held rectangles: {rect, until: Callable() -> bool, true once released;
## an empty one releases once a focus is set}.
var _holds: Array[Dictionary] = []
var _space := RID()

## A body for `owner_terrain`, its land from the terrain's world or near field, as its child.
static func build(owner_terrain: TerrainSystem) -> TerrainCollision:
	var body := TerrainCollision.new()
	body.name = "TerrainBody"
	body.terrain = owner_terrain
	body.land = land_of(owner_terrain)
	# Before the bodies that stand on the ground.
	body.process_physics_priority = -10
	owner_terrain.tiles_changed.connect(body._on_tiles_changed)
	body.wall_in()
	owner_terrain.add_child(body)
	body.hold(owner_terrain.region.near_bounds, Callable())
	return body

## The walkable land of `owner_terrain`: the world's `land`, or its near field.
static func land_of(owner_terrain: TerrainSystem) -> Rect2:
	var world := owner_terrain.tile_world
	if not world.is_empty() and world.has("land"):
		var corners: Array = world.land
		return Rect2(Values.real(corners[0]), Values.real(corners[1]), Values.real(corners[2]) - Values.real(corners[0]),
			Values.real(corners[3]) - Values.real(corners[1]))
	return Rect2(owner_terrain.near_origin, Vector2.ONE * owner_terrain.near_cell * (owner_terrain.near_size - 1))

## Whether the ground under `body` stands: false where a terrain in its space
## has no chunk under it. A body there holds still (BodyPace): the chunk went
## with the player far away.
static func ground_under(body: Node3D) -> bool:
	var found: Variant = _of_space.get(body.get_world_3d().space)
	if found == null:
		return true
	var collision: TerrainCollision = found
	return collision.stands_at(body.global_position.x, body.global_position.z)

func _enter_tree() -> void:
	_space = get_world_3d().space
	_of_space[_space] = self

func _exit_tree() -> void:
	if _of_space.get(_space) == self:
		_of_space.erase(_space)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(focus):
		focus = null
	for index in range(_holds.size() - 1, -1, -1):
		var until: Callable = _holds[index].until
		if until.is_null() and focus != null or until.is_valid() and until.call():
			_holds.remove_at(index)
	if focus != null:
		var under := chunk_at(focus.global_position.x, focus.global_position.z)
		if on_land(under) and not _chunks.has(under):
			build_whole(under)
	step()
	_drop_one()

## Puts a wall WALL m thick against each side of the land, outside it, over
## the heights of WALL_SPAN. The walls are shapes of this body and stand for
## good.
func wall_in() -> void:
	var middle := land.get_center()
	var height := WALL_SPAN.y - WALL_SPAN.x
	var y := (WALL_SPAN.x + WALL_SPAN.y) * 0.5
	var across := land.size + Vector2.ONE * WALL * 2.0
	var sides := {
		"West": [Vector3(land.position.x - WALL * 0.5, y, middle.y), Vector3(WALL, height, across.y)],
		"East": [Vector3(land.end.x + WALL * 0.5, y, middle.y), Vector3(WALL, height, across.y)],
		"North": [Vector3(middle.x, y, land.position.y - WALL * 0.5), Vector3(across.x, height, WALL)],
		"South": [Vector3(middle.x, y, land.end.y + WALL * 0.5), Vector3(across.x, height, WALL)],
	}
	for side: String in sides:
		var place: Array = sides[side]
		var box := BoxShape3D.new()
		box.size = place[1]
		var holder := CollisionShape3D.new()
		holder.name = "Wall" + side
		holder.shape = box
		holder.position = place[0]
		add_child(holder)

## Keeps the chunks over `rect` until `until` returns true (an empty
## Callable: until a focus is set), and builds them now.
func hold(rect: Rect2, until: Callable) -> void:
	_holds.append({"rect": rect, "until": until})
	for at: Vector2i in chunks_over(rect):
		if not _chunks.has(at):
			build_whole(at)

## The chunk (column, row) that holds the point (x, z).
func chunk_at(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - land.position.x) / CHUNK), floori((z - land.position.y) / CHUNK))

## Whether the chunk `at` lies on the walkable land. A strip of the land
## narrower than STEP past the last whole chunk has none.
func on_land(at: Vector2i) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x <= floori((land.size.x - STEP) / CHUNK) \
		and at.y <= floori((land.size.y - STEP) / CHUNK)

## The chunks on the land that cover some of `rect`.
func chunks_over(rect: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var first := chunk_at(rect.position.x, rect.position.y)
	var last := chunk_at(rect.end.x - 0.001, rect.end.y - 0.001)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if on_land(Vector2i(x, z)):
				found.append(Vector2i(x, z))
	return found

## The rectangle of the chunk `at` on the land, m.
func chunk_rect(at: Vector2i) -> Rect2:
	var corner := land.position + Vector2(at) * CHUNK
	return Rect2(corner, (land.end - corner).min(Vector2.ONE * CHUNK))

## Samples of the chunk `at` along x and z: 129, fewer at the land's far edges.
func chunk_samples(at: Vector2i) -> Vector2i:
	var span := chunk_rect(at).size
	return Vector2i(floori(span.x / STEP + 0.001) + 1, floori(span.y / STEP + 0.001) + 1)

## Whether a chunk stands under the point (x, z).
func stands_at(x: float, z: float) -> bool:
	return _chunks.has(chunk_at(x, z))

## The chunks that stand, by (column, row).
func standing() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	found.assign(_chunks.keys())
	return found

## One step of the build: a band of the chunk being built, else the nearest
## chunk the focus wants or the nearest stale one begun. False when nothing
## was left to build.
func step() -> bool:
	if _job.is_empty():
		var next := _next_chunk()
		if next.x == -1:
			return false
		_begin(next)
	_advance()
	return true

## Builds the chunk `at` whole now.
func build_whole(at: Vector2i) -> void:
	if not _job.is_empty() and _job.at == at:
		_job = {}
	var heights := chunk_heights(at, 0, chunk_samples(at).y)
	_stand(at, heights)

## The heights of rows [first, first + rows) of the chunk `at`, row by row:
## TerrainTiles.height() at each sample.
func chunk_heights(at: Vector2i, first: int, rows: int) -> PackedFloat32Array:
	var tiles := terrain.fields()
	var samples := chunk_samples(at)
	var corner := chunk_rect(at).position
	var copied := _tile_samples(tiles, corner + Vector2(0.0, first * STEP), Vector2i(samples.x, rows))
	if not copied.is_empty():
		return copied
	var xs := PackedFloat64Array()
	xs.resize(samples.x)
	for i in samples.x:
		xs[i] = corner.x + i * STEP
	var zs := PackedFloat64Array()
	zs.resize(rows)
	for j in rows:
		zs[j] = corner.y + (first + j) * STEP
	return terrain.heights_at_grid(xs, zs)

## Every second sample of the one tile under `size` samples STEP apart from
## `corner`, if that tile is held and takes the whole ground there; else none.
## The tile's heights read as two-channel pixels in rows of `samples` pixels:
## such a row holds two rows of samples, its first half the even one, and
## each pixel's red channel an even column. A region copy and a channel drop
## copy the 32-bit floats unchanged.
func _tile_samples(tiles: TerrainTiles, corner: Vector2, size: Vector2i) -> PackedFloat32Array:
	if not is_equal_approx(tiles.cell * 2.0, STEP):
		return PackedFloat32Array()
	var far_corner := corner + Vector2(size - Vector2i.ONE) * STEP
	var tx := floori((corner.x - tiles.origin.x) / tiles.tile)
	var tz := floori((corner.y - tiles.origin.y) / tiles.tile)
	var tile_corner := tiles.origin + Vector2(tx, tz) * tiles.tile
	var index := TerrainTiles.map_index(Vector2i(tx, tz))
	if index < 0 or tiles.slots[index] < 0:
		return PackedFloat32Array()
	var local := corner - tile_corner
	var local_far := far_corner - tile_corner
	var column := roundi(local.x / tiles.cell)
	var row := roundi(local.y / tiles.cell)
	if column % 2 != 0 or row % 2 != 0 or roundi(local_far.x / tiles.cell) >= tiles.samples \
			or roundi(local_far.y / tiles.cell) >= tiles.samples:
		return PackedFloat32Array()
	for point: Vector2 in [local, local_far, Vector2(local.x, local_far.y), Vector2(local_far.x, local.y)]:
		if TerrainTiles.edge_weight(point.x, point.y, tiles.tile, tiles.missing[index]) < 1.0:
			return PackedFloat32Array()
	var source := tiles.heights[tiles.slots[index]]
	var start := row * tiles.samples
	var span := size.y * tiles.samples * 2
	var part := source.slice(start, start + span)
	part.resize(span)
	var pairs := Image.create_from_data(tiles.samples, size.y, false, Image.FORMAT_RGF, part.to_byte_array())
	var even := pairs.get_region(Rect2i(column >> 1, 0, size.x, size.y))
	even.convert(Image.FORMAT_RF)
	return even.get_data().to_float32_array()

## The nearest chunk within LOAD_RADIUS of the focus that does not stand or
## is stale, else the nearest stale chunk; (-1, -1) if none.
func _next_chunk() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	var at := _focus_point()
	if focus != null:
		var reach := Rect2(at - Vector2.ONE * LOAD_RADIUS, Vector2.ONE * LOAD_RADIUS * 2.0)
		for chunk: Vector2i in chunks_over(reach):
			var distance := distance_to_chunk(chunk, at)
			if distance < LOAD_RADIUS and distance < best_distance and (not _chunks.has(chunk) or _stale.has(chunk)):
				best = chunk
				best_distance = distance
	if best.x != -1:
		return best
	for chunk: Vector2i in _stale:
		var distance := distance_to_chunk(chunk, at)
		if distance <= best_distance:
			best = chunk
			best_distance = distance
	return best

## The focus on the ground plane; far off when there is none.
func _focus_point() -> Vector2:
	if focus == null:
		return Vector2.ONE * 1e9
	return Vector2(focus.global_position.x, focus.global_position.z)

func _begin(at: Vector2i) -> void:
	_job = {"at": at, "heights": PackedFloat32Array(), "rows": 0}

func _advance() -> void:
	var at: Vector2i = _job.at
	var samples := chunk_samples(at)
	var done: int = _job.rows
	var heights: PackedFloat32Array = _job.heights
	if done == 0:
		var whole := _tile_samples(terrain.fields(), chunk_rect(at).position, samples)
		if not whole.is_empty():
			_job = {}
			_stand(at, whole)
			return
	var rows := mini(BAND, samples.y - done)
	heights.append_array(chunk_heights(at, done, rows))
	done += rows
	if done < samples.y:
		_job = {"at": at, "heights": heights, "rows": done}
		return
	_job = {}
	_stand(at, heights)

## Puts the chunk `at` of `heights` up, in place of the one that stood there.
func _stand(at: Vector2i, heights: PackedFloat32Array) -> void:
	var samples := chunk_samples(at)
	var shape := HeightMapShape3D.new()
	shape.map_width = samples.x
	shape.map_depth = samples.y
	shape.map_data = heights
	_stale.erase(at)
	if _chunks.has(at):
		var standing_holder: CollisionShape3D = _chunks[at]
		standing_holder.shape = shape
		return
	var holder := CollisionShape3D.new()
	holder.name = "Chunk_%d_%d" % [at.x, at.y]
	holder.shape = shape
	holder.scale = Vector3(STEP, 1.0, STEP)
	var corner := chunk_rect(at).position
	holder.position = Vector3(corner.x + (samples.x - 1) * STEP * 0.5, 0.0, corner.y + (samples.y - 1) * STEP * 0.5)
	add_child(holder)
	_chunks[at] = holder

## Drops the farthest chunk beyond DROP_RADIUS of the focus that no hold keeps.
func _drop_one() -> void:
	var at := _focus_point()
	var worst := Vector2i(-1, -1)
	var worst_distance := DROP_RADIUS
	for chunk: Vector2i in _chunks:
		var distance := distance_to_chunk(chunk, at)
		if distance > worst_distance and not _held(chunk):
			worst = chunk
			worst_distance = distance
	if worst.x == -1:
		return
	var holder: CollisionShape3D = _chunks[worst]
	_chunks.erase(worst)
	_stale.erase(worst)
	if not _job.is_empty() and _job.at == worst:
		_job = {}
	remove_child(holder)
	holder.queue_free()

func _held(chunk: Vector2i) -> bool:
	var rect := chunk_rect(chunk)
	for held: Dictionary in _holds:
		var area: Rect2 = held.rect
		if area.intersects(rect):
			return true
	return false

## From `point` to the rectangle of the chunk `at`, m.
func distance_to_chunk(at: Vector2i, point: Vector2) -> float:
	var rect := chunk_rect(at)
	var nearest := point.clamp(rect.position, rect.end)
	return nearest.distance_to(point)

func _on_tiles_changed() -> void:
	for chunk: Vector2i in _chunks:
		_stale[chunk] = true
	_job = {}
