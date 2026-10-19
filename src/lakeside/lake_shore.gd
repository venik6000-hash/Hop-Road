class_name LakeShore
extends Node
const RdUtil = preload("res://src/common/rd_util.gd")
const SIZE := 512
## The square of the waves (LakePlan.shore_field): x, z of its corner, its
## side, 0. project.godot declares the global `lake_shore_region` empty: a
## region without a lake has no shore.
var field := Vector4.ZERO
var water: WaterSystem
var terrain: TerrainSystem
var activities: LakesideSystem
var texture := Texture2DRD.new()
var clock := 0.0
var amplitude := 0.10
var wakes := PackedVector4Array()
var _wake_index := 0
var _last_wake := Vector3.INF
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _height: RID
var _states: Array[RID] = []
var _display: RID
var _sets: Array[RID] = []
var _current := 0
var _ready_gpu := false

func _ready() -> void:
	# The lake's surface heights take the shore's waves while it stands.
	if water != null:
		water.shore = self
	wakes.resize(16)
	for i in wakes.size(): wakes[i] = Vector4(0, 0, -100, 0)
	RenderingServer.global_shader_parameter_set("lake_shore_region", field)
	# Cell centres, the same expressions as the former per-cell height_at calls;
	# heights_at_grid returns height_at for each pair in z-major order.
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	xs.resize(SIZE)
	zs.resize(SIZE)
	for x: int in SIZE:
		xs[x] = field.x + (x + 0.5) * field.z / SIZE
	for z: int in SIZE:
		zs[z] = field.y + (z + 0.5) * field.z / SIZE
	var heights := terrain.heights_at_grid(xs, zs)
	RenderingServer.call_on_render_thread(_create.bind(heights.to_byte_array()))

func _create(heights: PackedByteArray) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return
	var file := load("res://src/lakeside/shore_state.glsl") as RDShaderFile
	_shader = _rd.shader_create_from_spirv(file.get_spirv())
	_pipeline = _rd.compute_pipeline_create(_shader)
	_sampler = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_height = make_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, heights)
	var zeros := PackedByteArray()
	zeros.resize(SIZE * SIZE * 8)
	for i in 2: _states.append(make_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, zeros))
	_display = make_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, zeros)
	for i in 2:
		_sets.append(_rd.uniform_set_create([
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_sampler, _states[i]]),
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [_states[1-i]]),
			RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, _height]),
			RdUtil.image(3, _display)], _shader, 0))
	texture.texture_rd_rid = _display
	_publish.call_deferred()

func make_texture(format: int, bytes: PackedByteArray) -> RID:
	var spec := RDTextureFormat.new()
	spec.width = SIZE
	spec.height = SIZE
	spec.format = format
	spec.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return _rd.texture_create(spec, RDTextureView.new(), [bytes])

func _publish() -> void:
	RenderingServer.global_shader_parameter_set("lake_shore_state", texture)
	_ready_gpu = true

func _process(delta: float) -> void:
	clock += delta
	amplitude = clampf(water.ocean.wind_speed * 0.017, 0.035, 0.28)
	RenderingServer.global_shader_parameter_set("lake_shore_clock", Vector2(clock, amplitude))
	if _ready_gpu:
		RenderingServer.call_on_render_thread(_dispatch.bind(PackedFloat32Array([clock, minf(delta,0.1), water.water_level, amplitude, field.x, field.y, field.z, 0]).to_byte_array()))
	if activities != null:
		var boat := activities.boat
		if boat.velocity.length() > 0.25 and boat.position.distance_to(_last_wake) > 0.6:
			wakes[_wake_index] = Vector4(boat.position.x, boat.position.z, clock, clampf(boat.velocity.length() * 0.025, 0.01, 0.08))
			_wake_index = (_wake_index + 1) % wakes.size()
			_last_wake = boat.position
	water.material.set_shader_parameter("lake_wakes", wakes)

func _dispatch(params: PackedByteArray) -> void:
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, _sets[_current], 0)
	_rd.compute_list_set_push_constant(list, params, params.size())
	_rd.compute_list_dispatch(list, SIZE / 8, SIZE / 8, 1)
	_rd.compute_list_end()
	_current = 1 - _current

func height_at(point: Vector2) -> float:
	var uv := (point - Vector2(field.x, field.y)) / field.z
	var edge := smoothstep(0, 0.05, minf(minf(uv.x, uv.y), minf(1-uv.x,1-uv.y)))
	var depth := water.water_level - terrain.height_at(point.x, point.y)
	var result := sin(clock * 1.25 - depth * 3) * amplitude * exp(-absf(depth)*1.5) * edge
	for wake in wakes:
		var age := clock - wake.z
		if age < 0 or age > 8: continue
		var radius := point.distance_to(Vector2(wake.x, wake.y))
		var d := radius-age*1.3
		result += sin(d*9) * exp(-d*d*2) * wake.w * exp(-age*0.4)
	return result

func _exit_tree() -> void:
	if water != null and water.shore == self:
		water.shore = null
	RenderingServer.global_shader_parameter_set("lake_shore_state", null)
	texture.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_free)

func _free() -> void:
	if _rd == null: return
	RdUtil.free_rids(_rd, _sets + _states + [_height, _display, _sampler, _shader])
