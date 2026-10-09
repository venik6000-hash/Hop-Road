class_name OceanFFT
extends Node
## GPU FFT ocean (Tessendorf 2001) with three cascades of 256^2.
##
## Tile sizes are mutually irrational (250 / 37 / 7.3 m) so no two cascades
## repeat together, and each cascade owns a band of wavenumbers so no wave is
## counted twice. Every frame: spectrum -> h(k, t) for four packed complex
## signals -> 256-point Stockham IFFT along rows then columns -> assemble
## displacement, derivatives and persistent foam -> box mip chain.
##
## Published as global shader parameters `water_displacement` and
## `water_derivatives` (Texture2DArrayRD) with `water_tiles` and
## `water_cascade_weights`. Surface heights at arbitrary points are available
## one frame late through `query_points` / `query_results`.

signal weather_changed(preset: String)

const RdUtil = preload("res://src/common/rd_util.gd")
const SIZE := 256
const CASCADES := 3
const MIPS := 9
const MAX_QUERIES := 64
const GRAVITY := 9.81
## RenderingDevice.TEXTURE_SLICE_2D_ARRAY exists in the engine but is not
## exported to GDScript in 4.6; the value is accepted by the binding.
const SLICE_2D_ARRAY := 3
## name: [wind m/s, fetch km, choppiness, swell, foam, spread blend]
const PRESETS := {
	"calm": [2.4, 4.0, 0.85, 0.0, 0.0, 0.25],
	"breeze": [6.0, 9.0, 1.0, 0.0, 0.25, 0.12],
	"choppy": [12.0, 35.0, 1.15, 0.15, 0.8, 0.06],
	"storm": [20.0, 140.0, 1.3, 0.55, 1.0, 0.04],
}

@export var tiles := Vector4(250.0, 37.0, 7.3, 1.0)
@export var wind_direction_deg := 55.0
@export var swell_direction_deg := 30.0
## Seconds to blend from one weather preset to the next.
@export var transition_time := 6.0
@export var depth := 60.0

var wind_speed := 6.0
var fetch_km := 9.0
var choppiness := 1.0
var swell := 0.0
var foam_amount := 0.25
var spread_blend := 0.12
var preset := "breeze"
var time := 0.0
var cascade_weights := Vector4(1.0, 1.0, 1.0, 0.0)

var displacement_texture := Texture2DArrayRD.new()
var derivatives_texture := Texture2DArrayRD.new()
var query_points := PackedVector2Array()
## Wave amplitude factor per query point (shallows, gusts); missing = 1.
var query_scales := PackedFloat32Array()
var query_results := PackedVector4Array()

var _target := {}
var _blend_from := {}
var _blend_t := 1.0
var _spectrum_dirty := true
var _ready_for_frames := false
var _rd: RenderingDevice
var _shaders := {}
var _pipelines := {}
var _textures := {}
var _views := {}
var _sets := {}
var _sampler: RID
var _query_buffer: RID
var _result_buffer: RID
var _pending_read := false
var _async_read := false

func _ready() -> void:
	set_preset(preset, true)
	_async_read = ClassDB.class_has_method("RenderingDevice", "buffer_get_data_async")
	RenderingServer.call_on_render_thread(_create_gpu_resources)

func _exit_tree() -> void:
	for global_name: String in ["water_displacement", "water_derivatives"]:
		RenderingServer.global_shader_parameter_set(global_name, null)
	displacement_texture.texture_rd_rid = RID()
	derivatives_texture.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_free_gpu_resources)

func set_preset(preset_name: String, instant := false) -> void:
	if not PRESETS.has(preset_name):
		return
	preset = preset_name
	var values: Array = PRESETS[preset_name]
	_blend_from = _current()
	_target = {"wind": values[0], "fetch": values[1], "chop": values[2], "swell": values[3],
		"foam": values[4], "spread": values[5]}
	_blend_t = 1.0 if instant else 0.0
	_apply(_target if instant else _blend_from)
	_spectrum_dirty = true
	weather_changed.emit(preset_name)

func _current() -> Dictionary:
	return {"wind": wind_speed, "fetch": fetch_km, "chop": choppiness, "swell": swell,
		"foam": foam_amount, "spread": spread_blend}

func _apply(values: Dictionary) -> void:
	wind_speed = values.wind
	fetch_km = values.fetch
	choppiness = values.chop
	swell = values.swell
	foam_amount = values.foam
	spread_blend = values.spread

## Significant wave height (m) of the current wind sea, from the fetch-limited
## JONSWAP relation; the HUD shows it with the preset name.
func significant_height() -> float:
	var dimensionless := sqrt(GRAVITY * fetch_km * 1000.0 / (wind_speed * wind_speed))
	return 0.0016 * dimensionless * wind_speed * wind_speed / GRAVITY + swell * 0.9

func _process(delta: float) -> void:
	time += delta
	if _blend_t < 1.0:
		_blend_t = minf(_blend_t + delta / transition_time, 1.0)
		var t := smoothstep(0.0, 1.0, _blend_t)
		var mixed := {}
		for key: String in _target:
			mixed[key] = lerpf(_blend_from[key], _target[key], t)
		_apply(mixed)
		_spectrum_dirty = true
	if not _ready_for_frames:
		return
	var spectrum := PackedFloat32Array()
	if _spectrum_dirty:
		spectrum = _spectrum_params()
		_spectrum_dirty = false
	var assemble := PackedFloat32Array([choppiness, choppiness, choppiness * 0.9, 0.0,
		0.6 * foam_amount, 1.0 * foam_amount, 0.7 * foam_amount, 0.0,
		lerpf(0.35, 0.72, clampf(foam_amount, 0.0, 1.0)), 2.2, 0.55, delta])
	var queries := PackedFloat32Array()
	for i in query_points.size():
		var point := query_points[i]
		queries.append_array([point.x, point.y, query_scales[i] if i < query_scales.size() else 1.0, 0.0])
	RenderingServer.call_on_render_thread(_dispatch.bind(time, spectrum, assemble, queries))

func _spectrum_params() -> PackedFloat32Array:
	var boundary_1 := TAU / tiles.y * 6.0
	var boundary_2 := TAU / tiles.z * 6.0
	var bands := [Vector2(TAU / tiles.x * 0.9, boundary_1), Vector2(boundary_1, boundary_2), Vector2(boundary_2, 9999.0)]
	var data := PackedFloat32Array()
	for c in CASCADES:
		var band: Vector2 = bands[c]
		data.append_array([tiles[c], band.x, band.y, maxf(wind_speed, 0.3), fetch_km * 1000.0,
			deg_to_rad(wind_direction_deg), spread_blend, swell, depth, 3.3, 0.006, 1.0])
		# cascade index travels as a float-typed slot reinterpreted as uint
		data.append(0.0)
		data.append_array([GRAVITY, deg_to_rad(swell_direction_deg), 0.0])
	return data

func _create_gpu_resources() -> void:
	_rd = RenderingServer.get_rendering_device()
	for pass_name: String in ["spectrum", "evolve", "ifft", "assemble", "mips", "query"]:
		var spirv := RdUtil.compute_spirv("res://src/water/fft_%s.glsl" % pass_name, "Ocean " + pass_name)
		if spirv == null:
			return
		_shaders[pass_name] = _rd.shader_create_from_spirv(spirv)
		_pipelines[pass_name] = _rd.compute_pipeline_create(_shaders[pass_name])
	_textures.h0 = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, CASCADES, 1)
	_textures.signals = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, CASCADES * 2, 1)
	_textures.displacement = _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, CASCADES, MIPS)
	_textures.derivatives = _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, CASCADES, MIPS)
	for key: String in ["displacement", "derivatives"]:
		var levels := []
		for level in MIPS:
			levels.append(_rd.texture_create_shared_from_slice(RDTextureView.new(), _textures[key], 0, level, 1,
				SLICE_2D_ARRAY))
		_views[key] = levels
	_sampler = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT)
	var zero := PackedByteArray()
	zero.resize(MAX_QUERIES * 16)
	_query_buffer = _rd.storage_buffer_create(MAX_QUERIES * 16, zero)
	_result_buffer = _rd.storage_buffer_create(MAX_QUERIES * 16, zero)

	_sets.spectrum = _rd.uniform_set_create([RdUtil.image(0, _textures.h0)], _shaders.spectrum, 0)
	_sets.evolve = _rd.uniform_set_create([RdUtil.image(0, _textures.h0), RdUtil.image(1, _textures.signals)], _shaders.evolve, 0)
	_sets.ifft = _rd.uniform_set_create([RdUtil.image(0, _textures.signals)], _shaders.ifft, 0)
	_sets.assemble = _rd.uniform_set_create([RdUtil.image(0, _textures.signals), RdUtil.image(1, _views.displacement[0]),
		RdUtil.image(2, _views.derivatives[0])], _shaders.assemble, 0)
	var mip_sets := []
	for level in MIPS - 1:
		mip_sets.append(_rd.uniform_set_create([
			RdUtil.image(0, _views.displacement[level]), RdUtil.image(1, _views.displacement[level + 1]),
			RdUtil.image(2, _views.derivatives[level]), RdUtil.image(3, _views.derivatives[level + 1])],
			_shaders.mips, 0))
	_sets.mips = mip_sets
	var sampled := RdUtil.sampled(0, _sampler, _textures.displacement)
	_sets.query = _rd.uniform_set_create([sampled, RdUtil.storage(1, _query_buffer), RdUtil.storage(2, _result_buffer)], _shaders.query, 0)

	displacement_texture.texture_rd_rid = _textures.displacement
	derivatives_texture.texture_rd_rid = _textures.derivatives
	_publish.call_deferred()

func _publish() -> void:
	RenderingServer.global_shader_parameter_set("water_displacement", displacement_texture)
	RenderingServer.global_shader_parameter_set("water_derivatives", derivatives_texture)
	RenderingServer.global_shader_parameter_set("water_tiles", tiles)
	RenderingServer.global_shader_parameter_set("water_cascade_weights", cascade_weights)
	_ready_for_frames = true

func _texture(format: int, layers: int, mips: int) -> RID:
	var spec := RDTextureFormat.new()
	spec.format = format
	spec.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	spec.width = SIZE
	spec.height = SIZE
	spec.array_layers = layers
	spec.mipmaps = mips
	spec.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var data := []
	for layer in layers:
		for level in mips:
			var bytes := PackedByteArray()
			var side := maxi(SIZE >> level, 1)
			var texel := 16 if format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT else 8
			bytes.resize(side * side * texel)
			data.append(bytes)
	return _rd.texture_create(spec, RDTextureView.new(), _layer_data(data, layers, mips))

static func _layer_data(data: Array, layers: int, mips: int) -> Array:
	# RD expects one PackedByteArray per layer holding all its mip levels.
	var result := []
	for layer in layers:
		var joined := PackedByteArray()
		for level in mips:
			joined.append_array(data[layer * mips + level])
		result.append(joined)
	return result

## queries: x, z, wave scale, unused per point.
func _dispatch(now: float, spectrum: PackedFloat32Array, assemble: PackedFloat32Array, queries: PackedFloat32Array) -> void:
	if _pipelines.size() < 6:
		return
	var groups := SIZE / 16
	var count := mini(queries.size() / 4, MAX_QUERIES)
	var run_query := count > 0 and not _pending_read
	if run_query:
		# Buffers may not be written while a compute list is open.
		var points := queries.slice(0, count * 4)
		_rd.buffer_update(_query_buffer, 0, points.size() * 4, points.to_byte_array())
	var list := _rd.compute_list_begin()
	if not spectrum.is_empty():
		_rd.compute_list_bind_compute_pipeline(list, _pipelines.spectrum)
		_rd.compute_list_bind_uniform_set(list, _sets.spectrum, 0)
		for c in CASCADES:
			var bytes := spectrum.slice(c * 16, c * 16 + 16).to_byte_array()
			bytes.encode_u32(12 * 4, c)
			_rd.compute_list_set_push_constant(list, bytes, bytes.size())
			_rd.compute_list_dispatch(list, groups, groups, 1)
		_rd.compute_list_add_barrier(list)
	var evolve := PackedFloat32Array([tiles.x, tiles.y, tiles.z, tiles.w, now, GRAVITY, depth, 0.0]).to_byte_array()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines.evolve)
	_rd.compute_list_bind_uniform_set(list, _sets.evolve, 0)
	_rd.compute_list_set_push_constant(list, evolve, evolve.size())
	_rd.compute_list_dispatch(list, groups, groups, CASCADES)
	_rd.compute_list_add_barrier(list)
	_rd.compute_list_bind_compute_pipeline(list, _pipelines.ifft)
	_rd.compute_list_bind_uniform_set(list, _sets.ifft, 0)
	for vertical in [0, 1]:
		var push := PackedInt32Array([vertical, 0, 0, 0]).to_byte_array()
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, SIZE, CASCADES * 2, 1)
		_rd.compute_list_add_barrier(list)
	var assemble_bytes := assemble.to_byte_array()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines.assemble)
	_rd.compute_list_bind_uniform_set(list, _sets.assemble, 0)
	_rd.compute_list_set_push_constant(list, assemble_bytes, assemble_bytes.size())
	_rd.compute_list_dispatch(list, groups, groups, CASCADES)
	_rd.compute_list_add_barrier(list)
	_rd.compute_list_bind_compute_pipeline(list, _pipelines.mips)
	for level in MIPS - 1:
		var side := maxi(SIZE >> (level + 1), 1)
		var push := PackedInt32Array([side, 0, 0, 0]).to_byte_array()
		_rd.compute_list_bind_uniform_set(list, _sets.mips[level], 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, maxi(ceili(side / 8.0), 1), maxi(ceili(side / 8.0), 1), CASCADES)
		_rd.compute_list_add_barrier(list)
	if run_query:
		var push := PackedFloat32Array([tiles.x, tiles.y, tiles.z, tiles.w,
			cascade_weights.x, cascade_weights.y, cascade_weights.z, cascade_weights.w]).to_byte_array()
		var tail := PackedInt32Array([count, 0, 0, 0]).to_byte_array()
		push.append_array(tail)
		_rd.compute_list_bind_compute_pipeline(list, _pipelines.query)
		_rd.compute_list_bind_uniform_set(list, _sets.query, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, 1, 1, 1)
	_rd.compute_list_end()
	if run_query:
		if _async_read:
			_pending_read = true
			_rd.buffer_get_data_async(_result_buffer, _on_results.bind(count), 0, count * 16)
		else:
			_on_results(_rd.buffer_get_data(_result_buffer, 0, count * 16), count)

func _on_results(bytes: PackedByteArray, count: int) -> void:
	var floats := bytes.to_float32_array()
	var values := PackedVector4Array()
	values.resize(count)
	for i in count:
		values[i] = Vector4(floats[i * 4], floats[i * 4 + 1], floats[i * 4 + 2], floats[i * 4 + 3])
	_store_results.call_deferred(values)

func _store_results(values: PackedVector4Array) -> void:
	query_results = values
	_pending_read = false

func _free_gpu_resources() -> void:
	if _rd == null:
		return
	for key: String in _textures:
		_rd.free_rid(_textures[key])
	for key: String in _shaders:
		_rd.free_rid(_shaders[key])
	RdUtil.free_rids(_rd, [_query_buffer, _result_buffer, _sampler])
	_textures.clear()
	_shaders.clear()
