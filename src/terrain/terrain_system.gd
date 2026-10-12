class_name TerrainSystem
extends Node3D
## Heightfield terrain from assets/generated/terrain
## (tools/pipeline/terrain/terrain.py).
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
const TerrainCollision = preload("res://src/terrain/terrain_collision.gd")
const TerrainHeights = preload("res://src/terrain/terrain_heights.gd")
const DATA := "res://assets/generated/terrain/"
const SHADER := preload("res://src/terrain/terrain.gdshader")
const PATCH_QUADS := 32
const LOD0_SIZE := 8.0
const LEVELS := 12
const MAX_NODES := 1400
## Metres to a repeat of each layer (the L_* of terrain.gdshader). The last
## is no scan of its own: a yard's trodden earth, the scan of the forest's
## floor laid finer.
const LAYER_TILES := [3.2, 3.4, 3.6, 2.8, 3.4, 7.0, 6.0, 38.0, 1.9, 2.3, 2.6, 3.2, 5.0, 3.0, 2.7]
## rgb tint and saturation per layer (see terrain.gdshader grade()). The
## forest's floor is graded to rust: dry needles, not the scan's dull earth,
## and darker than the sward beside it in the same light; a yard's earth is
## that scan nearly as it was shot. The two rock scans are of red-brown rock: they
## are held to the grey of the scanned cliffs and boulders that stand on them
## (RockField.CLIFF_GRADES, rock_grey of rock.gdshaderinc), red to green 1.08
## and blue to green 0.89 in the mean of the graded scan, as those have.
const LAYER_GRADES := [
	Vector4(0.2, 0.47, 0.12, 0.7), Vector4(1.29, 2.39, 1.67, 0.7), Vector4(0.65, 0.635, 0.515, 1.5),
	Vector4(1.0, 0.97, 0.92, 0.75), Vector4(1.0, 1.0, 1.0, 0.55), Vector4(0.92, 1.0, 0.97, 0.2),
	Vector4(0.95, 1.0, 0.98, 0.25), Vector4(0.9, 1.0, 0.8, 1.15), Vector4(1.0, 1.0, 1.0, 0.9),
	Vector4(1.0, 1.0, 1.0, 0.8), Vector4(1.0, 0.94, 0.84, 0.55), Vector4(1.0, 1.0, 1.0, 0.9),
	Vector4(0.98, 0.99, 1.02, 1.0), Vector4(0.92, 1.03, 0.9, 1.05), Vector4(1.0, 0.98, 0.94, 0.85),
]

## Uniforms of terrain_fields.gdshaderinc, which other materials share.
const FIELD_PARAMS := ["near_height", "far_height", "near_control", "near_extra", "far_masks",
	"near_rect", "far_rect", "mask_rect", "water_level"]

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

var meta: Dictionary
var material := ShaderMaterial.new()
var water_level := 0.72
var near_image: Image
var far_image: Image
var near_origin := Vector2.ZERO
var near_cell := 0.5
var near_size := 2048
var far_origin := Vector2.ZERO
var far_cell := 8.0
var far_size := 2048
var selected_nodes := 0

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

func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(DATA + "terrain.json"))
	water_level = meta.water_level
	near_origin = Vector2(meta.near.origin[0], meta.near.origin[1])
	near_cell = meta.near.cell
	near_size = int(meta.near.size)
	far_origin = Vector2(meta.far.origin[0], meta.far.origin[1])
	far_cell = meta.far.cell
	far_size = int(meta.far.size)
	near_image = _load_height("near_height.bin", near_size)
	RockField.seat(near_image, near_origin, near_cell)
	WaterfallSystem.carve(near_image, near_origin, near_cell)
	preload("res://src/village/village_layout.gd").settle_ground(near_image, near_origin, near_cell)
	preload("res://src/tavern/tavern_ground.gd").settle(near_image, near_origin, near_cell)
	preload("res://src/village/village_buildings.gd").settle_ground(near_image, near_origin, near_cell)
	VillageBrook.carve(near_image, near_origin, near_cell, water_level)
	far_image = _load_height("far_height.bin", far_size)
	_load_minmax()
	for level in LEVELS:
		_ranges.append(lod_distance * LOD0_SIZE * pow(2.0, level))
	TerrainMaterial.setup(self)
	_full = _make_layer("TerrainPatches", PATCH_QUADS)
	_quad = _make_layer("TerrainQuadrants", PATCH_QUADS / 2)
	_full_buffer.resize(MAX_NODES * 16)
	_quad_buffer.resize(MAX_NODES * 16)
	if collision_enabled:
		TerrainCollision.build(self)

func _load_height(file_name: String, size: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(DATA + file_name)
	return Image.create_from_data(size, size, false, Image.FORMAT_RF, bytes)

func _load_minmax() -> void:
	var data := FileAccess.get_file_as_bytes(DATA + "far_minmax.bin").to_float32_array()
	_minmax_cell = meta.minmax.cell
	var size := int(meta.minmax.size)
	var offset := 0
	while size >= 1:
		_minmax.append(data.slice(offset, offset + size * size * 2))
		offset += size * size * 2
		size /= 2
	# The same expressions _bounds evaluated per node before.
	_minmax_levels.clear()
	_minmax_cells.resize(_minmax.size())
	_minmax_counts.resize(_minmax.size())
	var total := int(meta.minmax.size)
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
	var near_weight := _near_weight(Vector2(x, z))
	var far_h := _sample(far_image, far_origin, far_cell, far_size, x, z)
	if near_weight <= 0.0:
		return far_h
	return lerpf(far_h, _sample(near_image, near_origin, near_cell, near_size, x, z), near_weight)

## height_at(xs[i], zs[j]) for every pair, row by row (index j * xs.size() + i),
## stored as 32-bit floats (see terrain_heights.gd).
func heights_at_grid(xs: PackedFloat64Array, zs: PackedFloat64Array) -> PackedFloat32Array:
	return TerrainHeights.heights_at_grid(self, xs, zs)

func _near_weight(xz: Vector2) -> float:
	var local := (xz - near_origin) / near_cell
	var edge := minf(minf(local.x, local.y), minf(near_size - 1 - local.x, near_size - 1 - local.y)) * near_cell
	return clampf(edge / 40.0, 0.0, 1.0)

static func _sample(image: Image, origin: Vector2, cell: float, size: int, x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / cell, 0.0, size - 1.001)
	var fz := clampf((z - origin.y) / cell, 0.0, size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := image.get_pixel(ix, iz).r
	var b := image.get_pixel(ix + 1, iz).r
	var c := image.get_pixel(ix, iz + 1).r
	var d := image.get_pixel(ix + 1, iz + 1).r
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

func _process(_delta: float) -> void:
	var view := camera if camera != null else get_viewport().get_camera_3d()
	if view == null:
		return
	var eye := view.global_position
	material.set_shader_parameter("terrain_camera", eye)
	var planes: Array[Plane] = view.get_frustum()
	if _selection_valid and eye == _selection_eye and planes == _selection_planes \
			and far_origin == _selection_origin:
		return
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
	if not _visible(bounds, planes):
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
			if _visible(_bounds(child.x, child.y, half), planes):
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
	var count := int(meta.minmax.size)
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

## Lowest and highest terrain height over the square [x, x+size] x [z, z+size].
func height_bounds(x: float, z: float, size: float) -> Vector2:
	var box := _bounds(x, z, size)
	return Vector2(box.position.y + 2.0, box.end.y - 2.0)

func _bounds(x: float, z: float, size: float) -> AABB:
	var level: int = _minmax_levels.get(size, -1)
	if level < 0:
		level = clampi(int(round(log(maxf(size, _minmax_cell) / _minmax_cell) / log(2.0))), 0, _minmax.size() - 1)
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
