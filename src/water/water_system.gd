class_name WaterSystem
extends Node3D
## The lake: FFT waves (OceanFFT) on a camera-centred CDLOD surface.
##
## The surface reuses the terrain's quadtree scheme but only where the ground
## dips below the lake level (the terrain's height bounds say where), so no
## water is drawn under mountains. Vertices are 12.5 cm apart at the camera.

const SHADER := preload("res://src/water/water.gdshader")
const PATCH_QUADS := 32
const LOD0_SIZE := 4.0
const LEVELS := 13
const MAX_NODES := 900
## Lake optics, shared by the surface shader and the underwater lens pass:
## pure-water absorption (1/m) and the colour of light the water body scatters.
const ABSORPTION := Vector3(0.42, 0.075, 0.036)
const SCATTER_COLOR := Color(0.035, 0.24, 0.26)
## Scattering (1/m): pure water plus fine suspended matter, which scatters a
## little more toward blue. Together with ABSORPTION it gives about 12 m of
## visibility in blue-green, as in a clear alpine lake.
const SCATTERING := Vector3(0.041, 0.046, 0.052)

@export var terrain: TerrainSystem
@export var camera: Camera3D
@export var lod_distance := 2.4

var shore: LakeShore
var ocean: OceanFFT
var material := ShaderMaterial.new()
var water_level := 0.72
var selected_nodes := 0
## World x/z points whose wave height callers want (the swimmer); read them
## back with surface_height(i) a few frames later.
var probe_points := PackedVector2Array()

var _macro: Image

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
var _selection_water_level := 0.0

func _ready() -> void:
	ocean = OceanFFT.new()
	ocean.name = "OceanFFT"
	add_child(ocean)
	water_level = terrain.water_level
	for level in LEVELS:
		_ranges.append(lod_distance * LOD0_SIZE * pow(2.0, level))
	material.shader = SHADER
	var terrain_material := terrain.material
	for parameter in ["near_height", "far_height", "near_rect", "far_rect", "macro_noise"]:
		material.set_shader_parameter(parameter, terrain_material.get_shader_parameter(parameter))
	material.set_shader_parameter("water_level", water_level)
	material.set_shader_parameter("absorption", ABSORPTION)
	material.set_shader_parameter("scatter_color", SCATTER_COLOR)
	material.set_shader_parameter("scattering", SCATTERING)
	terrain_material.set_shader_parameter("water_absorption", ABSORPTION)
	terrain_material.set_shader_parameter("water_scattering", SCATTERING)
	_macro = (terrain_material.get_shader_parameter("macro_noise") as Texture2D).get_image()
	_full = _make_layer("WaterPatches", PATCH_QUADS)
	_quad = _make_layer("WaterQuadrants", PATCH_QUADS / 2)
	_full_buffer.resize(MAX_NODES * 16)
	_quad_buffer.resize(MAX_NODES * 16)

func _make_layer(layer_name: String, quads: int) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = layer_name
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = TerrainSystem.patch_mesh(quads)
	multimesh.instance_count = MAX_NODES
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-20000, -60, -20000), Vector3(40000, 120, 40000))
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.extra_cull_margin = 4000.0
	add_child(instance)
	return instance

## Water surface height at probe_points[index] from the last GPU query, else
## the calm level.
func surface_height(index: int) -> float:
	if index < ocean.query_results.size():
		return water_level + ocean.query_results[index].x + (shore.height_at(probe_points[index]) if shore != null and index < probe_points.size() else 0.0)
	return water_level

## The surface shader's wave amplitude factor at x/z (water.gdshader vertex()):
## waves shrink over shallows and vary with gusts across the lake.
func wave_scale_at(x: float, z: float) -> float:
	var depth := water_level - terrain.height_at(x, z)
	var shore := lerpf(0.08, 1.0, smoothstep(0.0, 7.0, depth))
	return shore * (0.72 + 0.56 * _macro_red(x / 1700.0, z / 1700.0))

## Bilinear, wrapping lookup of the macro noise red channel at uv, as the
## shader's repeat sampler does.
func _macro_red(u: float, v: float) -> float:
	var width := _macro.get_width()
	var height := _macro.get_height()
	var fx := fposmod(u * width - 0.5, width)
	var fy := fposmod(v * height - 0.5, height)
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := (x0 + 1) % width
	var y1 := (y0 + 1) % height
	var top := lerpf(_macro.get_pixel(x0, y0).r, _macro.get_pixel(x1, y0).r, fx - x0)
	var bottom := lerpf(_macro.get_pixel(x0, y1).r, _macro.get_pixel(x1, y1).r, fx - x0)
	return lerpf(top, bottom, fy - y0)

func _request_heights() -> void:
	var scales := PackedFloat32Array()
	for point in probe_points:
		scales.append(wave_scale_at(point.x, point.y))
	ocean.query_points = probe_points
	ocean.query_scales = scales

func _process(_delta: float) -> void:
	var view := camera if camera != null else get_viewport().get_camera_3d()
	if view == null:
		return
	var eye := view.global_position
	if not _selection_valid or eye != _selection_eye:
		material.set_shader_parameter("surface_camera", eye)
	_request_heights()
	var planes: Array[Plane] = view.get_frustum()
	if _selection_valid and eye == _selection_eye and planes == _selection_planes \
			and terrain.far_origin == _selection_origin and water_level == _selection_water_level:
		return
	_selection_valid = true
	_selection_eye = eye
	_selection_planes = planes
	_selection_origin = terrain.far_origin
	_selection_water_level = water_level
	_full_count = 0
	_quad_count = 0
	var root_size := LOD0_SIZE * pow(2.0, LEVELS - 1)
	_visit(terrain.far_origin.x, terrain.far_origin.y, root_size, LEVELS - 1, eye, planes)
	_commit(_full, _full_buffer, _full_count)
	_commit(_quad, _quad_buffer, _quad_count)
	selected_nodes = _full_count + _quad_count

func _commit(instance: MultiMeshInstance3D, buffer: PackedFloat32Array, count: int) -> void:
	instance.multimesh.buffer = buffer
	instance.multimesh.visible_instance_count = count

func _has_water(x: float, z: float, size: float) -> bool:
	return terrain.height_bounds(x, z, size).x < water_level + 1.5

func _visit(x: float, z: float, size: float, level: int, eye: Vector3, planes: Array[Plane]) -> bool:
	var bounds := AABB(Vector3(x, water_level - 5.0, z), Vector3(size, 10.0, size))
	if not TerrainSystem._within(bounds, eye, _ranges[level]):
		return false
	if not _has_water(x, z, size) or not TerrainSystem._visible(bounds, planes):
		return true
	if level == 0 or not TerrainSystem._within(bounds, eye, _ranges[level - 1]):
		_emit(false, x, z, size, level)
		return true
	var half := size * 0.5
	for child in [Vector2(x, z), Vector2(x + half, z), Vector2(x, z + half), Vector2(x + half, z + half)]:
		if not _visit(child.x, child.y, half, level - 1, eye, planes):
			var child_bounds := AABB(Vector3(child.x, water_level - 5.0, child.y), Vector3(half, 10.0, half))
			if _has_water(child.x, child.y, half) and TerrainSystem._visible(child_bounds, planes):
				_emit(true, child.x, child.y, half, level)
	return true

func _emit(quadrant: bool, x: float, z: float, size: float, level: int) -> void:
	var end := _ranges[level]
	var start := lerpf(_ranges[level - 1] if level > 0 else 0.0, end, 0.55)
	var quads := PATCH_QUADS / 2 if quadrant else PATCH_QUADS
	var values := [size, 0.0, 0.0, x, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, size, z, start, end, float(quads), float(level)]
	if quadrant:
		if _quad_count >= MAX_NODES:
			return
		for i in 16:
			_quad_buffer[_quad_count * 16 + i] = values[i]
		_quad_count += 1
	else:
		if _full_count >= MAX_NODES:
			return
		for i in 16:
			_full_buffer[_full_count * 16 + i] = values[i]
		_full_count += 1
