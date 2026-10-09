class_name RefractionCapture
extends CompositorEffect
const RdUtil = preload("res://src/common/rd_util.gd")
var texture := Texture2DRD.new()
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _linear: RID
var _target: RID
const TARGET_SIZE := Vector2i(960, 540)
# The wrapper stays bound; only its RD allocation changes after a resize.
var match_source_size := true
var target_size := Vector2i.ZERO
var frames := 0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE
	RenderingServer.call_on_render_thread(_create)

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return
	var file := load("res://src/lakeside/refraction_capture.glsl") as RDShaderFile
	_shader = _rd.shader_create_from_spirv(file.get_spirv())
	_pipeline = _rd.compute_pipeline_create(_shader)
	_sampler = _rd.sampler_create(RDSamplerState.new())
	_linear = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)

## Sizes the target for a source of `source_size` before the frame that
## captures it is drawn; call it on the render thread when the source resizes.
## A resize frees the old allocation and with it the uniform set of every
## material that samples `texture`. Materials get a new set only as a frame
## begins, so after a resize inside the render callback they have none for the
## rest of that frame: the lake was not drawn, the log said "Uniforms supplied
## for set (3) ... are not the same format as required by the pipeline shader".
func prepare(source_size: Vector2i) -> void:
	if not _pipeline.is_valid() or source_size.x <= 0 or source_size.y <= 0: return
	_resize_target(source_size if match_source_size else TARGET_SIZE)

func _resize_target(size: Vector2i) -> void:
	if size == target_size: return
	var previous := _target
	var spec := RDTextureFormat.new()
	spec.width = size.x
	spec.height = size.y
	spec.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	spec.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_target = _rd.texture_create(spec, RDTextureView.new())
	texture.texture_rd_rid = _target
	target_size = size
	frames = 0
	if previous.is_valid(): _rd.free_rid(previous)

func _render_callback(_type: int, data: RenderData) -> void:
	if not _pipeline.is_valid(): return
	var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0: return
	# Only for a source nobody announced with prepare(): the first target, when
	# nothing samples it yet. See prepare() for what a resize here costs later.
	_resize_target(size if match_source_size else TARGET_SIZE)
	var uniforms: Array[RDUniform] = [
		RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,0,[_linear,buffers.get_color_layer(0)]),
		RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,1,[_sampler,buffers.get_depth_layer(0)]),
		RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,2,[_target])]
	var set := UniformSetCacheRD.get_cache(_shader,0,uniforms)
	var params := PackedFloat32Array()
	RdUtil.append_projection(params,data.get_render_scene_data().get_view_projection(0).inverse())
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_pipeline)
	_rd.compute_list_bind_uniform_set(list,set,0)
	_rd.compute_list_set_push_constant(list,params.to_byte_array(),64)
	_rd.compute_list_dispatch(list,ceili(target_size.x/8.0),ceili(target_size.y/8.0),1)
	_rd.compute_list_end()
	frames += 1

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		texture.texture_rd_rid = RID()
		RdUtil.free_rids(_rd, [_target,_sampler,_linear,_shader])
