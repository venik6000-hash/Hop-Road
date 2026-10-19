class_name TerrainTiles
extends RefCounted
## The terrain's heights as the CPU reads them: tiles of fine heights over
## the mid field, the mid field over the far field. The shaders read the same
## through height_at() of terrain_fields.gdshaderinc, the sun's shadow through
## sun_shadow_common.glslinc. TerrainSystem.height_at(),
## TerrainHeights.heights_at_grid() and VegetationTerrain.height() all ask
## this object.
##
## A tile holds `samples` squared heights `cell` m apart and `mask_samples`
## squared mask texels `mask_cell` m apart; its last row and column are the
## first of its neighbour. Tile (tx, tz) has its corner at origin + (tx, tz)
## * tile. A layer holds one tile. The map, MAP_SIZE squared texels from tile
## (MAP_FIRST, MAP_FIRST), names the layer of each tile and which of its eight
## neighbours no layer holds. A tile fades into the mid field over FADE m
## toward such a neighbour, the mid field fades into the far one over FADE m
## at the edge of the walkable land, and beyond the land the far field is the
## ground.
##
## The tiles of a world come from tools/pipeline/terrain/terrain_tiles.py and
## cut_ground_tiles.gd (open_world(), read_tile()). A terrain the world was not
## built for has one tile, its near field, and no mid field (of_near()): it
## answers as the near field fading into the far one did.

const FADE := 40.0
const MAP_SIZE := 32
const MAP_FIRST := -16
## A layer that holds no tile.
const NONE := Vector2i(0x7fffffff, 0x7fffffff)
## The bits of `missing`: a neighbour no layer holds, by side, then by corner.
const WEST := 1
const EAST := 2
const NORTH := 4
const SOUTH := 8
const NORTH_WEST := 16
const NORTH_EAST := 32
const SOUTH_WEST := 64
const SOUTH_EAST := 128
const NEIGHBOURS := [[Vector2i(-1, 0), WEST], [Vector2i(1, 0), EAST], [Vector2i(0, -1), NORTH],
	[Vector2i(0, 1), SOUTH], [Vector2i(-1, -1), NORTH_WEST], [Vector2i(1, -1), NORTH_EAST],
	[Vector2i(-1, 1), SOUTH_WEST], [Vector2i(1, 1), SOUTH_EAST]]
const WORLD := "res://assets/generated/world/world.json"

var origin := Vector2.ZERO
var tile := 512.0
var samples := 1025
var cell := 0.5
var mask_samples := 513
var mask_cell := 1.0
## Per layer: the tile it holds (NONE: none) and its heights.
var coords: Array[Vector2i] = []
var heights: Array[PackedFloat32Array] = []
## Per map texel, row by row: the layer of its tile (-1: none) and the bits
## of its missing neighbours.
var slots := PackedInt32Array()
var missing := PackedInt32Array()
## The mid field over the walkable land; none when mid_size is 0.
var mid := PackedFloat32Array()
var mid_origin := Vector2.ZERO
var mid_cell := 2.0
var mid_size := 0
var far := PackedFloat32Array()
var far_origin := Vector2.ZERO
var far_cell := 8.0
var far_size := 0
## Grows with every change of a layer.
var revision := 0

func _init(layer_count := 0) -> void:
	coords.resize(layer_count)
	coords.fill(NONE)
	heights.resize(layer_count)
	slots.resize(MAP_SIZE * MAP_SIZE)
	slots.fill(-1)
	missing.resize(MAP_SIZE * MAP_SIZE)
	_mark_missing()

## One tile, the near field of `size` squared `heights` from `near_origin`,
## over the far field: the fields as they were before the world had tiles.
## The masks are `masks_size` squared texels `masks_cell` m apart from the same corner.
static func of_near(near_heights: PackedFloat32Array, near_origin: Vector2, near_cell: float, size: int,
		far_heights: PackedFloat32Array, field_origin: Vector2, field_cell: float, field_size: int,
		masks_size := 0, masks_cell := 1.0) -> TerrainTiles:
	var fields := TerrainTiles.new(1)
	fields.origin = near_origin
	fields.samples = size
	fields.cell = near_cell
	fields.tile = near_cell * (size - 1)
	fields.mask_samples = masks_size
	fields.mask_cell = masks_cell
	fields.set_far(far_heights, field_origin, field_cell, field_size)
	fields.put(0, Vector2i.ZERO, near_heights)
	return fields

## The world of terrain_tiles.py (world.json) if it was built from the terrain
## fields in `terrain_dir` whose near field starts at `near_origin`; empty if not.
static func open_world(terrain_dir: String, near_origin: Vector2, path := WORLD) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = DataFile.read(path, WorldSchemas.world_tiles())
	if not parsed is Dictionary:
		return {}
	var world: Dictionary = parsed
	var sources: Dictionary = world.get("sources", {})
	var terrain_json := terrain_dir.path_join("terrain.json")
	var built_from := str(sources.get(terrain_json.trim_prefix("res://"), ""))
	if built_from != FileAccess.get_sha256(terrain_json) or Values.vec2(world.get("origin", [])) != near_origin:
		return {}
	world.path = path
	return world

## An empty tile set of `layer_count` layers on the grid of `world` (open_world()), with its mid field.
static func of_world(world: Dictionary, layer_count: int) -> TerrainTiles:
	var fields := TerrainTiles.new(layer_count)
	fields.origin = Values.vec2(world.origin)
	fields.tile = Values.real(world.tile)
	var grid: Dictionary = world.height
	fields.samples = Values.whole(grid.samples)
	fields.cell = Values.real(grid.cell)
	var masks: Dictionary = world.masks
	fields.mask_samples = Values.whole(masks.samples)
	fields.mask_cell = Values.real(masks.cell)
	var middle: Dictionary = world.mid
	fields.mid_size = Values.whole(middle.samples)
	fields.mid_origin = Values.vec2(middle.origin)
	fields.mid_cell = Values.real(middle.cell)
	fields.mid = FileAccess.get_file_as_bytes(str(world.path).get_base_dir().path_join(str(middle.file))).to_float32_array()
	if fields.mid.size() != fields.mid_size * fields.mid_size:
		push_error("TerrainTiles: the mid field of %s is not %d squared heights" % [world.path, fields.mid_size])
		fields.mid_size = 0
		fields.mid = PackedFloat32Array()
	return fields

## The tiles of `world` that cover some of `rect` (not only its edge), row by row.
static func covering(world: Dictionary, rect: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var tiles: Dictionary = world.tiles
	var size := Values.real(world.tile)
	for tz in range(Values.whole(tiles.first), Values.whole(tiles.last) + 1):
		for tx in range(Values.whole(tiles.first), Values.whole(tiles.last) + 1):
			var corner := Values.vec2(world.origin) + Vector2(tx, tz) * size
			if Rect2(corner, Vector2.ONE * size).intersects(rect):
				found.append(Vector2i(tx, tz))
	return found

## What the terrain of `region` reads of the world when it enters the tree
## (TerrainSystem): {files: world.json, the mid field, the bounds and the
## files of the tiles over the near field; stale: the tiles not cut from the
## region's ground bake}. Both empty for a region the world was not built for.
static func start_files(region: RegionDef) -> Dictionary:
	var result := {"files": PackedStringArray(), "stale": PackedStringArray()}
	var meta: Dictionary = DataFile.read(region.terrain_dir.path_join("terrain.json"), WorldSchemas.terrain())
	var near_origin := Values.vec2(meta.near.origin)
	var world := open_world(region.terrain_dir, near_origin)
	if world.is_empty():
		return result
	var saved: Variant = TerrainBake.read_manifest(region)
	var manifest: Dictionary = saved if saved is Dictionary else {}
	var key := str(manifest.get("key", ""))
	var base := str(world.path).get_base_dir()
	var files: PackedStringArray = result.files
	files.append_array([str(world.path), base.path_join(str(world.mid.file)), base.path_join(str(world.minmax.file))])
	var rect := Rect2(near_origin, Vector2.ONE * Values.real(meta.near.cell) * (Values.whole(meta.near.size) - 1))
	for at: Vector2i in covering(world, rect):
		var found := tile_files(world, at, key)
		if found.is_empty():
			var stale: PackedStringArray = result.stale
			stale.append(folder(world, at))
			continue
		files.append_array([str(found.height), str(found.control), str(found.extra)])
		if FileAccess.file_exists(folder(world, at).path_join("settled.json")):
			files.append(folder(world, at).path_join("settled.json"))
	return result

## The folder of tile `at` of `world`.
static func folder(world: Dictionary, at: Vector2i) -> String:
	return str(world.path).get_base_dir().path_join("tiles/%d_%d" % [at.x, at.y])

## The files of tile `at` the game reads: {height, control, extra}. The
## settled ground (cut_ground_tiles.gd) where a region's bake covers the tile;
## it must be cut from the bake whose key is `bake_key`, or the result is
## empty. terrain_tiles.py's files elsewhere.
static func tile_files(world: Dictionary, at: Vector2i, bake_key: String) -> Dictionary:
	var place := folder(world, at)
	var settled_path := place.path_join("settled.json")
	if FileAccess.file_exists(settled_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(settled_path))
		var settled: Dictionary = parsed if parsed is Dictionary else {}
		if str(settled.get("bake_key", "")) != bake_key:
			return {}
		return {"height": place.path_join(str(settled.height.file)), "control": place.path_join(str(settled.control.file)),
			"extra": place.path_join(str(settled.extra.file))}
	var masks: Dictionary = world.masks
	return {"height": place.path_join(str(world.height.file)), "control": place.path_join(str(masks.control.file)),
		"extra": place.path_join(str(masks.extra.file))}

## The heights (float32) and masks (RGBA8) in `files` (tile_files()); empty if a file is short.
func read_tile(files: Dictionary) -> Dictionary:
	var data := {"heights": FileAccess.get_file_as_bytes(str(files.height)).to_float32_array(),
		"control": FileAccess.get_file_as_bytes(str(files.control)), "extra": FileAccess.get_file_as_bytes(str(files.extra))}
	var heights_read: PackedFloat32Array = data.heights
	var control: PackedByteArray = data.control
	var extra: PackedByteArray = data.extra
	if heights_read.size() != samples * samples or control.size() != mask_samples * mask_samples * 4 \
			or extra.size() != control.size():
		return {}
	return data

func set_far(far_heights: PackedFloat32Array, field_origin: Vector2, field_cell: float, field_size: int) -> void:
	far = far_heights
	far_origin = field_origin
	far_cell = field_cell
	far_size = field_size

## Layer `layer` holds tile `at` with `tile_heights` from now on.
func put(layer: int, at: Vector2i, tile_heights: PackedFloat32Array) -> void:
	var index := map_index(at)
	if index < 0:
		push_error("TerrainTiles: tile %s lies off the map" % at)
		return
	clear(layer)
	if slots[index] >= 0:
		clear(slots[index])
	coords[layer] = at
	heights[layer] = tile_heights
	slots[index] = layer
	_mark_missing()
	revision += 1

## Layer `layer` holds no tile from now on.
func clear(layer: int) -> void:
	if coords[layer] == NONE:
		return
	slots[map_index(coords[layer])] = -1
	coords[layer] = NONE
	heights[layer] = PackedFloat32Array()
	_mark_missing()
	revision += 1

## The map texel of tile `at`, row by row; -1 off the map.
static func map_index(at: Vector2i) -> int:
	var on := at - Vector2i(MAP_FIRST, MAP_FIRST)
	if on.x < 0 or on.y < 0 or on.x >= MAP_SIZE or on.y >= MAP_SIZE:
		return -1
	return on.y * MAP_SIZE + on.x

func _mark_missing() -> void:
	for z in MAP_SIZE:
		for x in MAP_SIZE:
			var bits := 0
			for neighbour: Array in NEIGHBOURS:
				var offset: Vector2i = neighbour[0]
				var bit: int = neighbour[1]
				var index := map_index(Vector2i(x + offset.x, z + offset.y) + Vector2i(MAP_FIRST, MAP_FIRST))
				if index < 0 or slots[index] < 0:
					bits |= bit
			missing[z * MAP_SIZE + x] = bits

## The map as the shaders read it (RGBA8): R the layer + 1 (0: no tile), G the missing neighbours.
func slot_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(MAP_SIZE * MAP_SIZE * 4)
	for index in MAP_SIZE * MAP_SIZE:
		bytes[index * 4] = slots[index] + 1
		bytes[index * 4 + 1] = missing[index]
	return Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, bytes)

## Height at a world position, as height_at() of terrain_fields.gdshaderinc:
## inside the tiles held the tile alone, else the far field, the mid field
## over it and the tile over both, each by its weight.
func height(x: float, z: float) -> float:
	var tx := floori((x - origin.x) / tile)
	var tz := floori((z - origin.y) / tile)
	var index := map_index(Vector2i(tx, tz))
	var weight := 0.0
	var lx := 0.0
	var lz := 0.0
	if index >= 0 and slots[index] >= 0:
		lx = x - (origin.x + tx * tile)
		lz = z - (origin.y + tz * tile)
		weight = edge_weight(lx, lz, tile, missing[index])
		if weight >= 1.0:
			return bilinear(heights[slots[index]], samples, lx / cell, lz / cell)
	var h := bilinear(far, far_size, (x - far_origin.x) / far_cell, (z - far_origin.y) / far_cell)
	var mid_weight := land_weight(x, z)
	if mid_weight > 0.0:
		h = lerpf(h, bilinear(mid, mid_size, (x - mid_origin.x) / mid_cell, (z - mid_origin.y) / mid_cell), mid_weight)
	if weight <= 0.0:
		return h
	return lerpf(h, bilinear(heights[slots[index]], samples, lx / cell, lz / cell), weight)

## How much of the tile under (x, z) the ground takes: 0 where no layer
## holds one, rising to 1 over FADE m from the edge of the tiles held.
func tile_weight(x: float, z: float) -> float:
	var tx := floori((x - origin.x) / tile)
	var tz := floori((z - origin.y) / tile)
	var index := map_index(Vector2i(tx, tz))
	if index < 0 or slots[index] < 0:
		return 0.0
	return edge_weight(x - (origin.x + tx * tile), z - (origin.y + tz * tile), tile, missing[index])

## How much of the mid field the ground takes where no tile is: 0 beyond
## the walkable land, rising to 1 over FADE m from its edge.
func land_weight(x: float, z: float) -> float:
	if mid_size == 0:
		return 0.0
	var lx := (x - mid_origin.x) / mid_cell
	var lz := (z - mid_origin.y) / mid_cell
	return clampf(minf(minf(lx, mid_size - 1 - lx), minf(lz, mid_size - 1 - lz)) * mid_cell / FADE, 0.0, 1.0)

## The weight of a point `lx`, `lz` m into a tile `span` m wide whose
## neighbours `bits` (missing) are missing: its distance to the nearest of
## them over FADE. To a missing corner neighbour the distance is the larger
## of the two, so the fade runs on across the edge to the next tile.
static func edge_weight(lx: float, lz: float, span: float, bits: int) -> float:
	var rx := span - lx
	var rz := span - lz
	var edge := INF
	if bits & WEST:
		edge = minf(edge, lx)
	if bits & EAST:
		edge = minf(edge, rx)
	if bits & NORTH:
		edge = minf(edge, lz)
	if bits & SOUTH:
		edge = minf(edge, rz)
	if bits & NORTH_WEST:
		edge = minf(edge, maxf(lx, lz))
	if bits & NORTH_EAST:
		edge = minf(edge, maxf(rx, lz))
	if bits & SOUTH_WEST:
		edge = minf(edge, maxf(lx, rz))
	if bits & SOUTH_EAST:
		edge = minf(edge, maxf(rx, rz))
	return clampf(edge / FADE, 0.0, 1.0)

## Bilinear read of `size` squared heights at sample (fx, fz), clamped to the field.
static func bilinear(data: PackedFloat32Array, size: int, fx: float, fz: float) -> float:
	if size == 0:
		return 0.0
	fx = clampf(fx, 0.0, size - 1.001)
	fz = clampf(fz, 0.0, size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * size + ix
	return lerpf(lerpf(data[i], data[i + 1], tx), lerpf(data[i + size], data[i + size + 1], tx), tz)

## Adds what height() reads to `context`: the grids, the tiles held and every height.
func digest_into(context: HashingContext) -> void:
	context.update(var_to_bytes([origin, tile, samples, cell, mid_origin, mid_cell, mid_size, far_origin, far_cell,
		far_size, coords, mid.size(), far.size()]))
	for values: PackedFloat32Array in heights:
		context.update(var_to_bytes(values.size()))
		if not values.is_empty():
			context.update(values.to_byte_array())
	for values: PackedFloat32Array in [mid, far]:
		if not values.is_empty():
			context.update(values.to_byte_array())
