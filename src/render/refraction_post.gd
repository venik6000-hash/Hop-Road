class_name RefractionPost
extends CompositorEffect
## Bends the finished picture where light is bent on its way to the eye
## (refraction_post.glsl), after the transparent geometry and before the fog:
##  - the hot air over the fires (HearthFire.heating) shimmers;
##  - the rain's drops leave rings on the lake.
## Both are done on the picture because nothing else can do them: a material
## reads the scene without the transparent things already drawn (the lake, the
## flames, the smoke), and the lake's own shader stays as it is.
##
## The level calls prepare() once a frame on the main thread; the render
## thread only reads that snapshot. With no fire in sight and no rain on a
## lake nearby the pass does not run.

const RdUtil = preload("res://src/common/rd_util.gd")
const SHADER := "res://src/render/refraction_post.glsl"
const PARAM_FLOATS := 128
const MAX_FIRES := 8
## How far away (m) a fire's air still shows, and the rings on the lake.
const HEAT_VIEW := 32.0
const RING_VIEW := 28.0
## The rings' clock wraps here, s: a whole number of both their periods.
const RING_CLOCK_WRAP := 900.0
## The shimmer's clock wraps here, s.
const AIR_CLOCK_WRAP := 3600.0
## What a pixel shows may lie this far (m) above the lake's level and still be
## the lake, plus this share of its waves' significant height.
const WAVE_REACH := Vector2(0.15, 0.8)

## Off for tools that compare.
@export var heat := true
@export var rings := true
## Debug output instead of the picture: 1 how far the hot air moves it (red
## across, green up and down, pixels / 2) and, on the lake, the pixels a ring
## fetches from (red), the spray (green) and the rings' slopes (blue).
@export_range(0, 1) var debug_view := 0

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _nearest: RID
var _linear: RID
var _params: RID
var _fires := PackedFloat32Array()
var _fire_boxes: Array[AABB] = []
var _rain := 0.0
var _lake := false
var _level := 0.0
var _waves := 0.0
var _ring_clock := 0.0
var _air_clock := 0.0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_create)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		RdUtil.free_rids(_rd, [_shader, _nearest, _linear, _params])

## Takes this frame's state for the render thread. `fires` are the fires
## whose air shimmers (HearthFire.heating), `rain` the share of the drops that fall (RainFall.amount),
## `lake_level` the lake's level, `lake_near` whether its water lies within
## RING_VIEW of the eye, and `wave_height` its waves' significant height (m).
func prepare(delta: float, eye: Vector3, fires: Array, rain: float, lake_level: float, lake_near: bool,
		wave_height := 0.0) -> void:
	_air_clock = fposmod(_air_clock + delta, AIR_CLOCK_WRAP)
	_ring_clock = fposmod(_ring_clock + delta, RING_CLOCK_WRAP)
	_level = lake_level
	_waves = wave_reach(wave_height)
	_rain = rain if rings else 0.0
	_lake = lake_near and eye.y > lake_level
	var rows := PackedFloat32Array()
	var boxes: Array[AABB] = []
	if heat:
		var near: Array[Array] = []
		for fire: HearthFire in fires:
			if not is_instance_valid(fire) or not fire.is_visible_in_tree():
				continue
			var away := eye.distance_to(fire.global_position)
			if away < HEAT_VIEW:
				near.append([away, fire])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for entry: Array in near.slice(0, MAX_FIRES):
			var fire: HearthFire = entry[1]
			var foot := fire.haze_foot()
			rows.append_array([foot.x, foot.y, foot.z, fire.haze_radius, fire.haze_height, fire.haze_strength, 0.0, 0.0])
			boxes.append(column_box(foot, fire.haze_radius, fire.haze_height))
	_fires = rows
	_fire_boxes = boxes

## How far above its level the lake's waves reach, m, for waves of a
## significant height of `wave_height`.
static func wave_reach(wave_height: float) -> float:
	return WAVE_REACH.x + WAVE_REACH.y * wave_height

## The box a fire's column of hot air stays in: it widens to 2.3 radii.
static func column_box(foot: Vector3, radius: float, height: float) -> AABB:
	var reach := radius * 2.3
	return AABB(foot - Vector3(reach, 0.0, reach), Vector3(reach * 2.0, height, reach * 2.0))

## The pixels `box` (world space) covers in an image of `size`, or an empty
## rectangle when it is out of sight. `to_clip` takes world space to the
## image's NDC. A box that reaches behind the eye covers the whole image.
static func screen_rect(box: AABB, to_clip: Projection, size: Vector2i) -> Rect2i:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in 8:
		var clip := to_clip * Vector4(box.position.x + box.size.x * (corner & 1), box.position.y + box.size.y * ((corner >> 1) & 1),
			box.position.z + box.size.z * ((corner >> 2) & 1), 1.0)
		if clip.w <= 0.01:
			return Rect2i(Vector2i.ZERO, size)
		var at := (Vector2(clip.x, clip.y) / clip.w * 0.5 + Vector2(0.5, 0.5)) * Vector2(size)
		low = low.min(at)
		high = high.max(at)
	var from := Vector2i(low.floor()).clamp(Vector2i.ZERO, size)
	var to := Vector2i(high.ceil()).clamp(Vector2i.ZERO, size)
	return Rect2i(from, to - from)

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	# No device in a headless run (the tests).
	if _rd == null:
		return
	var spirv := RdUtil.compute_spirv(SHADER, "Refraction post")
	if spirv == null:
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	_nearest = _rd.sampler_create(RDSamplerState.new())
	_linear = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	var zero := PackedByteArray()
	zero.resize(PARAM_FLOATS * 4)
	_params = _rd.uniform_buffer_create(zero.size(), zero)

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	var fires := _fires
	var boxes := _fire_boxes
	var rain := _rain
	var with_rings := rain > 0.004 and _lake
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _pipeline.is_valid() or (fires.is_empty() and not with_rings):
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var data := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or data == null or buffers.get_view_count() != 1:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var camera := data.get_cam_transform()
	var projection := AtmosphereFog.image_projection(data.get_view_projection(0))
	var to_clip := projection * Projection(camera.affine_inverse())
	# The rectangle of the fires in sight, and the one of the lake's rings:
	# everything below the highest point of the ring of water RING_VIEW away.
	var air := Rect2i()
	for box in boxes:
		var covered := screen_rect(box, to_clip, size)
		if covered.has_area():
			air = covered if not air.has_area() else air.merge(covered)
	var water := Rect2i()
	if with_rings and camera.origin.y > _level:
		var top := float(size.y)
		for step in 24:
			var bearing := TAU * step / 24.0
			var clip := to_clip * Vector4(camera.origin.x + cos(bearing) * RING_VIEW, _level, camera.origin.z + sin(bearing) * RING_VIEW, 1.0)
			if clip.w > 0.01:
				top = minf(top, (clip.y / clip.w * 0.5 + 0.5) * size.y)
		var first := clampi(floori(top) - 2, 0, size.y)
		water = Rect2i(0, first, size.x, size.y - first)
	if not air.has_area() and not water.has_area():
		return
	var values := PackedFloat32Array()
	RdUtil.append_projection(values, projection.inverse())
	RdUtil.append_projection(values, projection)
	RdUtil.append_projection(values, Projection(camera))
	# Reversed depth of a perspective view: raw = z.w / depth - z.z.
	values.append_array([size.x, size.y, projection.w.z, projection.z.z])
	values.append_array([rain, _ring_clock, _level, RING_VIEW])
	values.append_array([_air_clock, fires.size() / 8, _waves, (Engine.get_frames_drawn() % 64) / 64.0])
	values.append_array([float(debug_view), 0.0, 0.0, 0.0])
	values.append_array(fires)
	values.resize(PARAM_FLOATS)
	var bytes := values.to_byte_array()
	_rd.buffer_update(_params, 0, bytes.size(), bytes)
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.width = size.x
	format.height = size.y
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var scratch := buffers.create_texture_from_format(&"refraction_post", &"scratch", format, RDTextureView.new(), true) \
		if not buffers.has_texture(&"refraction_post", &"scratch") else buffers.get_texture(&"refraction_post", &"scratch")
	var color := buffers.get_color_layer(0)
	var params := RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_params])
	var depth := RdUtil.sampled(2, _nearest, buffers.get_depth_layer(0))
	var bend := UniformSetCacheRD.get_cache(_shader, 0, [params, RdUtil.sampled(1, _linear, color), depth, RdUtil.image(3, scratch)])
	var back := UniformSetCacheRD.get_cache(_shader, 0, [params, RdUtil.sampled(1, _nearest, scratch), depth, RdUtil.image(3, color)])
	for job: Array in [[air, 1, 0], [water, 0, 1]]:
		var rect: Rect2i = job[0]
		if not rect.has_area():
			continue
		_run(bend, rect, 0, Values.whole(job[1]), Values.whole(job[2]))
		_run(back, rect, 1, 0, 0)

func _run(uniform_set: RID, rect: Rect2i, job: int, with_air: int, with_rings: int) -> void:
	var push := PackedInt32Array([rect.position.x, rect.position.y, rect.size.x, rect.size.y, job, with_air, with_rings, 0]).to_byte_array()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(rect.size.x / 8.0), ceili(rect.size.y / 8.0), 1)
	_rd.compute_list_end()
