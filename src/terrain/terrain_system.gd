class_name TerrainSystem
extends Node3D
## Heightfield terrain of a region (RegionDef): the fields of
## tools/pipeline/terrain/terrain.py, the near heights and masks as the
## region's ground bake settled and painted them (TerrainBake), with the water
## courses cut there.
##
## The ground is read from tiles over the mid and the far field (TerrainTiles):
## the world's tiles of tools/pipeline/terrain/terrain_tiles.py, with the
## settled ground cut into those the bake covers (cut_ground_tiles.gd). The
## terrain loads the tiles that cover the region's near field when it enters
## the tree; fill_layer() loads one more. A region the world was not built
## for has its near field as its one tile. The near field itself stays as
## the lake's field: the frozen WaterSystem copies `near_height` and
## `near_rect` from the material. The collision is chunks of the tiles and the
## mid field round the player (TerrainCollision).
##
## Rendering is CDLOD (Strugar 2009): a quadtree over the 16 km far field is
## walked every frame from the camera; each selected node draws one shared grid
## patch through a MultiMesh and the vertex shader samples the heightmaps and
## morphs odd vertices toward the next coarser grid, so neighbouring levels meet
## without cracks. Quads are 0.25 m under the feet and grow with distance.
##
## Nodes whose parent is split but which are themselves out of range are drawn
## as quadrants at the parent's resolution (a half-size patch), exactly as the
## paper does with quadrant index buffers.
##
## The terrain does not draw into the sun's shadow map (every cascade would
## otherwise draw every node out to the horizon). Its own shadow, on itself and
## on whatever stands on it, is the field SunShadowField sweeps from the
## heightmaps (src/terrain/sun_shadow.gdshaderinc). Houses, trees and props
## still cast onto it through the shadow map.

const TerrainMaterial = preload("res://src/terrain/terrain_material.gd")
const TerrainPatchMesh = preload("res://src/terrain/terrain_patch_mesh.gd")
const TerrainHeights = preload("res://src/terrain/terrain_heights.gd")
const SHADER := preload("res://src/terrain/terrain.gdshader")
const PATCH_QUADS := 32
const LOD0_SIZE := 8.0
const LEVELS := 12
const MAX_NODES := 1400
## A tile this near an opening's wedge (m) is drawn for an eye indoors.
const SIGHT_MARGIN := 4.0
## Render layer of the terrain's patches. The quadtree picks them for the
## main camera alone, so a camera of a capture leaves this layer out: it
## would draw whatever part the eye happens to look at (RainShelter).
const VISUAL_LAYER := 1 << 19
## A test turns this on (tests/test_flat_region.gd): a height asked outside
## the far field is not read off the field's clamped edge. The ask goes to
## the error log and to `strays`, once per chain of callers.
static var strict := false
## The asks outside the far field in strict mode: the callers ("file:line <
## file:line ...") to the first point asked, Vector2(x, z).
static var strays := {}

## Uniforms of terrain_fields.gdshaderinc, which other materials share.
const FIELD_PARAMS := ["tile_heights", "tile_control", "tile_extra", "tile_slots", "tile_rect", "tile_cells",
	"mid_height", "mid_rect", "far_height", "far_masks", "far_rect"]

## A layer of the tiles was filled or emptied (fill_layer()).
signal tiles_changed

## LOD k is used out to lod_distance * (size of a level-k node); larger = denser.
@export var lod_distance := 2.4
## Ground that stands high shows its outline against the sky from kilometres
## away, where a patch is drawn with quads of 64 to 128 m. Its patches are
## chosen as if it were nearer: by 1 + z above the height y (m), not at all
## below x. The shader morphs by the same measure.
@export var high_detail := Vector3(150.0, 700.0, 2.5):
	set(value):
		high_detail = value
		material.set_shader_parameter("high_detail", value)
		_selection_valid = false
@export var collision_enabled := true
@export var camera: Camera3D
## The level's context (its rooms' sight, Interiors); null in a tool that builds
## a part of the level alone.
var world: WorldContext
## Set before the terrain enters the tree.
var region: RegionDef

var meta: Dictionary
var material := ShaderMaterial.new()
var water_level := 0.72
## The near field's settled heights (the lake's field)
## and the far field's. A terrain in the tree lets them go once it is ready:
## the tiles and the textures hold the heights. A terrain built outside the
## tree sets them and asks fields().
var near_image: Image
var far_image: Image
## The physics body of the ground (TerrainCollision); null with
## collision_enabled off.
var collision: TerrainCollision
## The ground the terrain draws and height_at() reads (see fields()).
var tiles: TerrainTiles
## The world the tiles come from (TerrainTiles.open_world()); empty for a
## region it was not built for.
var tile_world := {}
## The settled masks of the near field (TerrainBake.read_masks, RGBA8, no
## mipmaps; null if missing): what the grass, the flowers and the trees read
## on the CPU.
var near_control: Image
var near_extra: Image
var near_origin := Vector2.ZERO
var near_cell := 0.5
var near_size := 2048
var far_origin := Vector2.ZERO
var far_cell := 8.0
var far_size := 2048
var selected_nodes := 0
## The water courses of the ground bake by name (TerrainBake.courses_of).
var courses := {}
## The key of the ground bake the settled tiles must be cut from.
var _bake_key := ""

var _minmax: Array[PackedFloat32Array] = []
var _minmax_cell := 32.0
## Per pyramid level, from _load_minmax: cell size (m) and cells per side.
var _minmax_cells := PackedFloat64Array()
var _minmax_counts := PackedInt32Array()
## Pyramid level per node size seen by _bounds (the sizes repeat every frame).
var _minmax_levels := {}
var _ranges := PackedFloat32Array()
var _full: MultiMeshInstance3D
var _quad: MultiMeshInstance3D
var _full_buffer := PackedFloat32Array()
var _quad_buffer := PackedFloat32Array()
var _full_count := 0
var _quad_count := 0
# Exact view keys: no movement threshold, so even sub-pixel motion rebuilds.
var _selection_valid := false
var _selection_eye := Vector3.ZERO
var _selection_planes: Array[Plane] = []
var _selection_origin := Vector2.ZERO
## The revision of the rooms' sight (Interiors) the tiles were chosen by (-1: outdoors).
var _selection_sight := -1
var _sight: InteriorSight.Sight

func _ready() -> void:
	meta = DataFile.read(region.terrain_dir.path_join("terrain.json"), WorldSchemas.terrain())
	water_level = meta.water_level
	near_origin = Values.vec2(meta.near.origin)
	near_cell = meta.near.cell
	near_size = Values.whole(meta.near.size)
	far_origin = Values.vec2(meta.far.origin)
	far_cell = meta.far.cell
	far_size = Values.whole(meta.far.size)
	near_image = _load_height(region.settled_heights, near_size)
	var saved: Variant = TerrainBake.read_manifest(region)
	var settled: Dictionary = saved if saved is Dictionary else {}
	courses = TerrainBake.courses_of(settled)
	_bake_key = str(settled.get("key", ""))
	far_image = _load_height(region.terrain_dir.path_join("far_height.bin"), far_size)
	var baked := TerrainBake.read_masks(region, settled)
	near_control = baked.get("control")
	near_extra = baked.get("extra")
	var start := _open_world()
	_load_minmax()
	for level in LEVELS:
		_ranges.append(lod_distance * LOD0_SIZE * pow(2.0, level))
	TerrainMaterial.setup(self, baked)
	if tile_world.is_empty():
		TerrainMaterial.fill_layer(self, 0, _blank_if_null(near_control), _blank_if_null(near_extra))
	for layer in start.size():
		if not fill_layer(layer, start[layer]):
			push_error("TerrainSystem: tile %s of %s is missing or short; run tools/run/rebuild.sh --only world-tiles,world-ground-tiles"
				% [start[layer], tile_world.path])
	_full = _make_layer("TerrainPatches", PATCH_QUADS)
	_quad = _make_layer("TerrainQuadrants", PATCH_QUADS / 2)
	_full_buffer.resize(MAX_NODES * 16)
	_quad_buffer.resize(MAX_NODES * 16)
	if collision_enabled:
		collision = TerrainCollision.build(self)
	# The tiles and the textures hold the heights from here on.
	near_image = null
	far_image = null

## Opens the world's tiles for this region and returns the tiles to load at
## start: those that cover the near field. Without a world built for this
## terrain, or with tiles cut from another bake, the near field is the one
## tile and nothing is to load.
func _open_world() -> Array[Vector2i]:
	tile_world = TerrainTiles.open_world(region.terrain_dir, near_origin)
	var start: Array[Vector2i] = []
	if not tile_world.is_empty():
		start = TerrainTiles.covering(tile_world, Rect2(near_origin, Vector2.ONE * near_cell * (near_size - 1)))
		for at: Vector2i in start:
			if TerrainTiles.tile_files(tile_world, at, _bake_key).is_empty():
				push_error("TerrainSystem: tile %s of %s is not cut from the ground bake %s; run tools/run/rebuild.sh --only world-ground-tiles"
					% [at, tile_world.path, _bake_key.left(12)])
				tile_world = {}
				break
	if tile_world.is_empty():
		tiles = null
		fields()
		return []
	tiles = TerrainTiles.of_world(tile_world, start.size())
	tiles.set_far(far_image.get_data().to_float32_array(), far_origin, far_cell, far_size)
	return start

## One step of a build queue: layer `layer` takes tile `at` of the world:
## its heights for height_at(), its heights and masks for the shaders, its
## place on the map. False if its files are missing or short, or if the
## terrain has no world.
func fill_layer(layer: int, at: Vector2i) -> bool:
	if tile_world.is_empty():
		return false
	var files := TerrainTiles.tile_files(tile_world, at, _bake_key)
	if files.is_empty():
		return false
	var data := tiles.read_tile(files)
	if data.is_empty():
		return false
	var tile_heights: PackedFloat32Array = data.heights
	var control: PackedByteArray = data.control
	var extra: PackedByteArray = data.extra
	tiles.put(layer, at, tile_heights)
	TerrainMaterial.fill_layer(self, layer, control, extra)
	tiles_changed.emit()
	return true

## The tiles height_at() reads. A terrain built outside the tree (a tool's,
## a test's) with only its near and far images set gets the near field as
## its one tile on first use.
func fields() -> TerrainTiles:
	if tiles == null:
		var masks_size := 0
		var masks_cell := 1.0
		if meta.has("masks"):
			masks_size = Values.whole(meta.masks.size)
			masks_cell = Values.real(meta.masks.cell)
		tiles = TerrainTiles.of_near(near_image.get_data().to_float32_array(), near_origin, near_cell, near_size,
			far_image.get_data().to_float32_array(), far_origin, far_cell, far_size, masks_size, masks_cell)
	return tiles

func _blank_if_null(mask: Image) -> PackedByteArray:
	if mask != null:
		return mask.get_data()
	var blank := PackedByteArray()
	blank.resize(tiles.mask_samples * tiles.mask_samples * 4)
	return blank

func _load_height(path: String, size: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	return Image.create_from_data(size, size, false, Image.FORMAT_RF, bytes)

## The rows of the water course `course_name`; none if the bake cut no such course.
func course(course_name: StringName) -> Array[Dictionary]:
	if courses.has(course_name):
		return courses[course_name]
	return []

## The bounds of the patches: terrain.py's pyramid, with the land's tiles
## folded in when the ground is the world's (terrain_tiles.py).
func _load_minmax() -> void:
	var path := region.terrain_dir.path_join("far_minmax.bin")
	if not tile_world.is_empty():
		path = str(tile_world.path).get_base_dir().path_join(str(tile_world.minmax.file))
	var data := FileAccess.get_file_as_bytes(path).to_float32_array()
	_minmax_cell = meta.minmax.cell
	var size := Values.whole(meta.minmax.size)
	var offset := 0
	while size >= 1:
		_minmax.append(data.slice(offset, offset + size * size * 2))
		offset += size * size * 2
		size /= 2
	# The same expressions _bounds evaluated per node before.
	_minmax_levels.clear()
	_minmax_cells.resize(_minmax.size())
	_minmax_counts.resize(_minmax.size())
	var total := Values.whole(meta.minmax.size)
	for level in _minmax.size():
		_minmax_cells[level] = _minmax_cell * pow(2.0, level)
		_minmax_counts[level] = total >> level

## Gives `other` the heightfields and masks terrain_fields.gdshaderinc reads.
func share_fields(other: ShaderMaterial) -> void:
	for param: String in FIELD_PARAMS:
		other.set_shader_parameter(param, material.get_shader_parameter(param))

func _make_layer(layer_name: String, quads: int) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = layer_name
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _patch_mesh(quads)
	multimesh.instance_count = MAX_NODES
	multimesh.visible_instance_count = 0
	# The vertex shader moves everything; culling happens in the quadtree.
	multimesh.custom_aabb = AABB(Vector3(-20000, -200, -20000), Vector3(40000, 4400, 40000))
	instance.multimesh = multimesh
	instance.material_override = material
	instance.layers = VISUAL_LAYER
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.extra_cull_margin = 4000.0
	add_child(instance)
	return instance

static func patch_mesh(quads: int) -> ArrayMesh:
	return _patch_mesh(quads)

static func _patch_mesh(quads: int) -> ArrayMesh:
	return TerrainPatchMesh.patch_mesh(quads)

## Height at a world position from the same fields the shader uses.
func height_at(x: float, z: float) -> float:
	check_field(x, z, far_origin, far_cell, far_size)
	return fields().height(x, z)

## height_at(xs[i], zs[j]) for every pair, row by row (index j * xs.size() + i),
## stored as 32-bit floats (see terrain_heights.gd).
func heights_at_grid(xs: PackedFloat64Array, zs: PackedFloat64Array) -> PackedFloat32Array:
	if strict and not xs.is_empty() and not zs.is_empty():
		for x: float in [_least(xs), _most(xs)]:
			for z: float in [_least(zs), _most(zs)]:
				check_field(x, z, far_origin, far_cell, far_size)
	return TerrainHeights.heights_at_grid(fields(), xs, zs)

static func _least(values: PackedFloat64Array) -> float:
	var least := values[0]
	for value: float in values:
		least = minf(least, value)
	return least

static func _most(values: PackedFloat64Array) -> float:
	var most := values[0]
	for value: float in values:
		most = maxf(most, value)
	return most

## In strict mode, notes a height asked at (x, z) outside the far field of
## `origin`, `cell` and `size` (strays).
static func check_field(x: float, z: float, origin: Vector2, cell: float, size: int) -> void:
	if not strict:
		return
	var span := cell * (size - 1)
	if x >= origin.x and z >= origin.y and x <= origin.x + span and z <= origin.y + span:
		return
	var callers := PackedStringArray()
	for frame: Dictionary in get_stack().slice(1):
		callers.append("%s:%d" % [str(frame.source).trim_prefix("res://"), Values.whole(frame.line)])
	var chain := " < ".join(callers)
	if strays.has(chain):
		return
	strays[chain] = Vector2(x, z)
	push_error("TerrainSystem: height asked outside the field at (%.1f, %.1f) by %s" % [x, z, chain])

func _process(_delta: float) -> void:
	var view := camera if camera != null else get_viewport().get_camera_3d()
	if view == null:
		return
	var eye := view.global_position
	material.set_shader_parameter("terrain_camera", eye)
	var planes: Array[Plane] = view.get_frustum()
	# An eye in the tavern's rooms sees the ground through the openings alone.
	var interiors := world.interiors if world != null and camera == null else null
	var sight: InteriorSight.Sight = interiors.sight if interiors != null and interiors.sight.active else null
	var revision := interiors.revision if sight != null else -1
	if _selection_valid and eye == _selection_eye and planes == _selection_planes \
			and far_origin == _selection_origin and revision == _selection_sight:
		return
	_sight = sight
	_selection_sight = revision
	_selection_valid = true
	_selection_eye = eye
	_selection_planes = planes
	_selection_origin = far_origin
	_full_count = 0
	_quad_count = 0
	var root_size := LOD0_SIZE * pow(2.0, LEVELS - 1)
	_visit(far_origin.x, far_origin.y, root_size, LEVELS - 1, eye, planes)
	_commit(_full, _full_buffer, _full_count)
	_commit(_quad, _quad_buffer, _quad_count)
	selected_nodes = _full_count + _quad_count

func _commit(instance: MultiMeshInstance3D, buffer: PackedFloat32Array, count: int) -> void:
	var multimesh := instance.multimesh
	multimesh.buffer = buffer
	multimesh.visible_instance_count = count

## Returns false when the node is beyond this level's range (the caller then
## covers that area at its own, coarser level).
func _visit(x: float, z: float, size: float, level: int, eye: Vector3, planes: Array[Plane]) -> bool:
	var bounds := _bounds(x, z, size)
	# No point of the node can measure nearer than its nearest point does at
	# the boost of its highest ground.
	var boost := detail_boost(bounds.end.y)
	if not _within(bounds, eye, _ranges[level] * boost):
		return false
	if not _seen(bounds, planes):
		return true
	if level == 0 or not _within(bounds, eye, _ranges[level - 1] * boost):
		_emit(false, x, z, size, level)
		return true
	var half := size * 0.5
	# Children in the order (x, z), (x + half, z), (x, z + half), (x + half, z + half).
	# The Vector2 rounds the corner to 32 bits exactly as before.
	for index: int in 4:
		var child := Vector2(x + half if index & 1 else x, z + half if index & 2 else z)
		if not _visit(child.x, child.y, half, level - 1, eye, planes):
			if _seen(_bounds(child.x, child.y, half), planes):
				_emit(true, child.x, child.y, half, level)
	return true

func _emit(quadrant: bool, x: float, z: float, size: float, level: int) -> void:
	var end := _ranges[level]
	var start := lerpf(_ranges[level - 1] if level > 0 else 0.0, end, 0.55)
	var quads := PATCH_QUADS / 2 if quadrant else PATCH_QUADS
	# One instance row: transform (3 x 4), then custom data (start, end, quads, level).
	var buffer := _quad_buffer if quadrant else _full_buffer
	var k: int
	if quadrant:
		if _quad_count >= MAX_NODES:
			return
		k = _quad_count * 16
		_quad_count += 1
	else:
		if _full_count >= MAX_NODES:
			return
		k = _full_count * 16
		_full_count += 1
	buffer[k] = size
	buffer[k + 1] = 0.0
	buffer[k + 2] = 0.0
	buffer[k + 3] = x
	buffer[k + 4] = 0.0
	buffer[k + 5] = 1.0
	buffer[k + 6] = 0.0
	buffer[k + 7] = 0.0
	buffer[k + 8] = 0.0
	buffer[k + 9] = 0.0
	buffer[k + 10] = size
	buffer[k + 11] = z
	buffer[k + 12] = start
	buffer[k + 13] = end
	buffer[k + 14] = float(quads)
	buffer[k + 15] = float(level)

## Lowest and highest ground under `rect` (world x/z) with a 2 m margin, from
## every 32 m cell of the min/max pyramid it touches (near field folded in).
func height_range(rect: Rect2) -> Vector2:
	var count := Values.whole(meta.minmax.size)
	var last := Vector2i.ONE * (count - 1)
	var low := Vector2i(((rect.position - far_origin) / _minmax_cell).floor()).clamp(Vector2i.ZERO, last)
	var high := Vector2i(((rect.end - far_origin) / _minmax_cell).floor()).clamp(Vector2i.ZERO, last)
	var data := _minmax[0]
	var result := Vector2(INF, -INF)
	for iz in range(low.y, high.y + 1):
		for ix in range(low.x, high.x + 1):
			var k := (iz * count + ix) * 2
			result = Vector2(minf(result.x, data[k]), maxf(result.y, data[k + 1]))
	return result + Vector2(-2.0, 2.0)

## The lowest ground of the whole far field (the top of the min/max pyramid).
func lowest() -> float:
	return _minmax[_minmax.size() - 1][0]

## Whether the far field has the height at (x, z): an ask outside it reads
## the clamped edge (check_field).
func covers(x: float, z: float) -> bool:
	var span := far_cell * (far_size - 1)
	return x >= far_origin.x and z >= far_origin.y and x <= far_origin.x + span and z <= far_origin.y + span

## Lowest and highest terrain height over the square [x, x+size] x [z, z+size].
func height_bounds(x: float, z: float, size: float) -> Vector2:
	var box := _bounds(x, z, size)
	return Vector2(box.position.y + 2.0, box.end.y - 2.0)

func _bounds(x: float, z: float, size: float) -> AABB:
	var level: int = _minmax_levels.get(size, -1)
	if level < 0:
		level = clampi(roundi(log(maxf(size, _minmax_cell) / _minmax_cell) / log(2.0)), 0, _minmax.size() - 1)
		# Selection asks for a few dozen distinct sizes; do not grow without end.
		if _minmax_levels.size() < 256:
			_minmax_levels[size] = level
	var cell := _minmax_cells[level]
	var count := _minmax_counts[level]
	var ix := clampi(int((x - far_origin.x) / cell), 0, count - 1)
	var iz := clampi(int((z - far_origin.y) / cell), 0, count - 1)
	var data := _minmax[level]
	var low := data[(iz * count + ix) * 2]
	var high := data[(iz * count + ix) * 2 + 1]
	return AABB(Vector3(x, low - 2.0, z), Vector3(size, high - low + 4.0, size))

## How much nearer ground at `height` counts than it is (see high_detail).
func detail_boost(height: float) -> float:
	return 1.0 + high_detail.z * smoothstep(high_detail.x, high_detail.y, height)

static func _within(bounds: AABB, eye: Vector3, radius: float) -> bool:
	var nearest := eye.clamp(bounds.position, bounds.end)
	return nearest.distance_squared_to(eye) <= radius * radius

## In the view, and for an eye indoors behind an opening: the box is taken
## SIGHT_MARGIN larger, for the lake's refraction, which looks a little aside.
func _seen(bounds: AABB, planes: Array[Plane]) -> bool:
	return _visible(bounds, planes) and (_sight == null or _sight.sees_box(bounds.grow(SIGHT_MARGIN)))

static func _visible(bounds: AABB, planes: Array[Plane]) -> bool:
	for plane in planes:
		var n := plane.normal
		# The corner furthest against the outward normal; if even that one is
		# outside, the whole box is.
		var corner := Vector3(
			bounds.position.x if n.x > 0.0 else bounds.end.x,
			bounds.position.y if n.y > 0.0 else bounds.end.y,
			bounds.position.z if n.z > 0.0 else bounds.end.z)
		if plane.distance_to(corner) > 0.0:
			return false
	return true
