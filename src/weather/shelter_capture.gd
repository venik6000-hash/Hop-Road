class_name ShelterCapture
extends CompositorEffect
## The GPU side of RainShelter (shelter_capture.glsl): turns each view its
## camera draws from above into heights of the map, and opens the map once
## every view is in.

const RdUtil = preload("res://src/common/rd_util.gd")
const SHADER := "res://src/weather/shelter_capture.glsl"
## A texel nothing was drawn over (the shader's NOTHING).
const NOTHING := -10000.0

## The map, once finish() has run.
var texture := Texture2DRD.new()
## Views taken so far (RainShelter waits for each).
var captured := 0
## Whether the map is opened and ready to be read.
var finished := false

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _nearest: RID
var _map: RID
var _scratch: RID
var _origin := Vector2.ZERO
var _cell := 1.0
var _cells := 0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE

## A map of `cells` x `cells` texels of `cell` metres whose corner is at
## `origin` (world x, z).
func configure(origin: Vector2, cell: float, cells: int) -> void:
	_origin = origin
	_cell = cell
	_cells = cells
	RenderingServer.call_on_render_thread(_create)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		texture.texture_rd_rid = RID()
		RdUtil.free_rids(_rd, [_shader, _nearest, _map, _scratch])

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	# No device in a headless run (the tests).
	if _rd == null:
		return
	var spirv := RdUtil.compute_spirv(SHADER, "Rain shelter")
	if spirv == null:
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	_nearest = _rd.sampler_create(RDSamplerState.new())
	_map = _make_map()
	_scratch = _make_map()

func _make_map() -> RID:
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.width = _cells
	format.height = _cells
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var empty := PackedFloat32Array()
	empty.resize(_cells * _cells)
	empty.fill(NOTHING)
	return _rd.texture_create(format, RDTextureView.new(), [empty.to_byte_array()])

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_OPAQUE or not _pipeline.is_valid() or finished:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var data := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or data == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var to_world := Projection(data.get_cam_transform()) * AtmosphereFog.image_projection(data.get_view_projection(0)).inverse()
	_run(buffers.get_depth_layer(0), _map, to_world, 0.0, size)
	captured += 1

## Opens the map and hands it out. Call on the render thread after the last
## view was taken.
func finish() -> void:
	if not _pipeline.is_valid() or finished:
		return
	var whole := Vector2i(_cells, _cells)
	_run(_map, _scratch, Projection.IDENTITY, 1.0, whole)
	_run(_scratch, _map, Projection.IDENTITY, 2.0, whole)
	texture.texture_rd_rid = _map
	finished = true

func _run(source: RID, target: RID, to_world: Projection, mode: float, size: Vector2i) -> void:
	var values := PackedFloat32Array()
	RdUtil.append_projection(values, to_world)
	values.append_array([_origin.x, _origin.y, _cell, mode])
	var push := values.to_byte_array()
	var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [RdUtil.sampled(0, _nearest, source), RdUtil.image(1, target)])
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()
