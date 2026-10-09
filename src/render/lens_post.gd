class_name LensPost
extends CompositorEffect
## Camera-lens pass (lens_post.glsl) that the compositor runs on the HDR image
## after transparent geometry: underwater extinction and in-scattering, the
## meniscus where the lake surface crosses the lens, and cos^4 vignetting.
##
## The main thread hands over the water and sun state once a frame through
## set_water() / set_sun(); the render thread only reads that snapshot.

const RdUtil = preload("res://src/common/rd_util.gd")
const SHADER := "res://src/render/lens_post.glsl"
const PARAM_FLOATS := 64

## Share of the physical cos^4 falloff toward the corners (0 = none).
@export_range(0.0, 1.0) var vignette := 0.3
## Half width of the dark meniscus at the lens, metres (about 15 px at 720p).
@export var meniscus := 0.0012
## Debug output instead of the picture: 1 world checker, 2 raw depth,
## 3 view direction, 4 distance bands.
@export_range(0, 4) var debug_view := 0

var skyview: Texture2DRD
var transmittance: Texture2DRD
## The FFT displacement cascades (OceanFFT.displacement_texture).
var displacement: Texture2DArrayRD

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _above_shader: RID
var _above_pipeline: RID
var _nearest: RID
var _linear: RID
var _repeat: RID
var _params: RID
var _water := PackedFloat32Array([-1000.0, 250.0, 37.0, 7.3, 1.0, 1.0, 1.0, 0.0, 0.46, 0.12, 0.08,
	0.04, 0.045, 0.05, INF])
var _sun := PackedFloat32Array([0.0, 1.0, 0.0, 6360.75, 12.566, 12.566, 12.566])

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_create)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		# Freeing the shader also frees its pipeline.
		RdUtil.free_rids(_rd, [_shader, _above_shader, _nearest, _linear, _repeat, _params])

## The lake: calm level (m), FFT cascade tiles, cascade weights already scaled
## by the wave amplitude factor at the camera, and the extinction and
## scattering coefficients (1/m). `crest_bound` (m) must be a hard upper bound
## of the wave height above the calm level with these weights; while the lens
## stays well above level + crest_bound the pass skips the water work, which
## then changes nothing. INF (the default) never skips.
func set_water(level: float, tiles: Vector4, weights: Vector4, extinction: Vector3, scattering: Vector3,
		crest_bound: float = INF) -> void:
	_water = PackedFloat32Array([level, tiles.x, tiles.y, tiles.z, weights.x, weights.y, weights.z, weights.w,
		extinction.x, extinction.y, extinction.z, scattering.x, scattering.y, scattering.z, crest_bound])

func set_sun(direction: Vector3, radiance_scale: Vector3, viewer_radius_km: float) -> void:
	_sun = PackedFloat32Array([direction.x, direction.y, direction.z, viewer_radius_km,
		radiance_scale.x, radiance_scale.y, radiance_scale.z])

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	var spirv := RdUtil.compute_spirv(SHADER, "LensPost")
	if spirv == null:
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	var above_spirv := RdUtil.compute_spirv("res://src/render/lens_above.glsl", "Above-water lens")
	if above_spirv != null:
		_above_shader = _rd.shader_create_from_spirv(above_spirv)
		_above_pipeline = _rd.compute_pipeline_create(_above_shader)
	var state := RDSamplerState.new()
	_nearest = _rd.sampler_create(state)
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_linear = _rd.sampler_create(state)
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_repeat = _rd.sampler_create(state)
	var zero := PackedByteArray()
	zero.resize(PARAM_FLOATS * 4)
	_params = _rd.uniform_buffer_create(zero.size(), zero)

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _pipeline.is_valid():
		return
	for texture: Variant in [skyview, transmittance, displacement]:
		if texture == null or not texture.texture_rd_rid.is_valid():
			return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var data := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or data == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var camera := data.get_cam_transform()
	var near := data.get_cam_projection().get_z_near()
	var water := _water
	var sun := _sun
	var band := meniscus
	# The lens point is eye + dir * near with |dir| = 1, so it lies no lower
	# than eye.y - |near|. Where that clears the highest crest by 20 meniscus
	# half widths (plus 1 cm and 1 % of near for rounding), the shader's
	# `submerged` is below 0 and its meniscus factor is exactly 1.
	var clearance := camera.origin.y - absf(near) * 1.01 - 20.0 * maxf(band, 1e-5) - 0.01
	var skip_water := 1.0 if clearance > water[0] + water[14] else 0.0
	for view in buffers.get_view_count():
		# Already reversed Z in 0..1, so the raw depth inverts straight to view
		# space; only the image's top-down rows need flipping (in the shader).
		var projection := data.get_view_projection(view)
		var values := PackedFloat32Array()
		RdUtil.append_projection(values, projection.inverse())
		RdUtil.append_projection(values, Projection(camera))
		values.append_array([water[0], skip_water, 0.0, near])
		values.append_array([water[1], water[2], water[3], 1.0])
		values.append_array([water[4], water[5], water[6], water[7]])
		values.append_array([water[8], water[9], water[10], float(debug_view)])
		values.append_array([water[11], water[12], water[13], band])
		values.append_array([sun[0], sun[1], sun[2], sun[3]])
		values.append_array([sun[4], sun[5], sun[6], vignette])
		values.append_array([size.x, size.y, 1.0 / size.x, 1.0 / size.y])
		var bytes := values.to_byte_array()
		_rd.buffer_update(_params, 0, bytes.size(), bytes)
		var uniforms: Array[RDUniform] = [
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [buffers.get_color_layer(view)]),
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_nearest, buffers.get_depth_layer(view)]),
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_linear, skyview.texture_rd_rid]),
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_linear, transmittance.texture_rd_rid]),
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 4, [_params]),
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_repeat, displacement.texture_rd_rid]),
		]
		# The depth-free ray is equivalent for a conventional single-view
		# perspective camera. Orthographic, XR, custom projective translations,
		# underwater/waterline and every debug mode keep the general shader.
		var above_water := skip_water > 0.5 and debug_view == 0 and buffers.get_view_count() == 1 \
			and perspective_ray_is_depth_independent(projection) and _above_pipeline.is_valid()
		var active_shader := _above_shader if above_water else _shader
		var active_pipeline := _above_pipeline if above_water else _pipeline
		if above_water:
			uniforms = [uniforms[0], uniforms[4]]
		var uniform_set := UniformSetCacheRD.get_cache(active_shader, 0, uniforms)
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, active_pipeline)
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
		_rd.compute_list_end()

## Projection of rays from the view origin: clip.w depends only on view z,
## and clip.x/y have no translation. Off-axis/jittered perspective is valid.
static func perspective_ray_is_depth_independent(projection: Projection) -> bool:
	return projection.x.w == 0.0 and projection.y.w == 0.0 and projection.z.w != 0.0 \
		and projection.w.w == 0.0 and projection.w.x == 0.0 and projection.w.y == 0.0
