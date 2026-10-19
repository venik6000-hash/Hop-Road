class_name LightMeter
extends CompositorEffect
## Meters the light of the picture as a camera does. light_meter.glsl takes
## the mean log2 luminance of the HDR image, before exposure, in each cell of
## a coarse grid; the grid is read back a few frames later, without waiting
## for the GPU, and weighed into one number (stops()). EyeAdaptation turns it
## into an exposure.

const RdUtil = preload("res://src/common/rd_util.gd")
const SHADER := "res://src/render/light_meter.glsl"
## Cells of the grid.
const GRID := Vector2i(32, 18)
## The weight of the picture's top rows, where the sky stands, against the
## rest, and what the sides lose against the middle.
const SKY_WEIGHT := 0.35
const SIDE_LOSS := 0.4
## The shares of the weight left out at the dark and at the bright end: a
## black doorway, a lamp and the sun's glare are no measure of a scene.
const DARK_CUT := 0.1
const BRIGHT_CUT := 0.15

## A reading is asked for once in this many frames: the profile's
## (QualityPost.meter_every), fixed when the pass is made.
var every := 0

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _image: RID
var _frame := 0
var _waiting := false
var _mutex := Mutex.new()
var _cells := PackedFloat32Array()
var _readings := 0
var _weighed := 0
var _stops := NAN

## `post`: the post passes of the level's quality profile (the authored ones
## without it).
func _init(post: QualityPost = null) -> void:
	every = (post if post != null else QualityProfile.named(QualityProfile.AUTHORED).post).meter_every
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_create)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		# Freeing the shader also frees its pipeline.
		RdUtil.free_rids(_rd, [_shader, _image])

## The light of the picture last read, log2 of its luminance; NAN before the
## first reading.
func stops() -> float:
	_mutex.lock()
	if _weighed != _readings:
		_stops = metered(_cells, GRID)
		_weighed = _readings
	_mutex.unlock()
	return _stops

## One number for a grid of log2 luminances (rows from the top of the
## picture): the mean of the middle of its light, the lower middle of the
## picture counting most. NAN for a grid of another size.
static func metered(cells: PackedFloat32Array, grid: Vector2i) -> float:
	if cells.size() != grid.x * grid.y or cells.is_empty():
		return NAN
	var weighed: Array[Vector2] = []
	var total := 0.0
	for row in grid.y:
		var down := smoothstep(0.15, 0.6, (row + 0.5) / grid.y)
		for column in grid.x:
			var aside := (column + 0.5) / grid.x * 2.0 - 1.0
			var weight := lerpf(SKY_WEIGHT, 1.0, down) * (1.0 - SIDE_LOSS * aside * aside)
			weighed.append(Vector2(cells[row * grid.x + column], weight))
			total += weight
	# By light, x; cells of one light may stand in any order.
	weighed.sort()
	var low := total * DARK_CUT
	var high := total * (1.0 - BRIGHT_CUT)
	var passed := 0.0
	var sum := 0.0
	for one: Vector2 in weighed:
		var share := minf(passed + one.y, high) - maxf(passed, low)
		if share > 0.0:
			sum += one.x * share
		passed += one.y
	return sum / (high - low)

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var spirv := RdUtil.compute_spirv(SHADER, "LightMeter")
	if spirv == null:
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.width = GRID.x
	format.height = GRID.y
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_image = _rd.texture_create(format, RDTextureView.new())

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _pipeline.is_valid():
		return
	_frame += 1
	if _waiting or _frame % every != 0:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var uniforms: Array[RDUniform] = [RdUtil.image(0, buffers.get_color_layer(0)), RdUtil.image(1, _image)]
	var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, uniforms)
	var push := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(GRID.x / 8.0), ceili(GRID.y / 8.0), 1)
	_rd.compute_list_end()
	_waiting = _rd.texture_get_data_async(_image, 0, _arrived) == OK

func _arrived(data: PackedByteArray) -> void:
	_mutex.lock()
	_cells = data.to_float32_array()
	_readings += 1
	_mutex.unlock()
	_waiting = false
