class_name BeerFluid
extends Node3D
## Native GPU PBF. Rendering and simulation share a 3D density texture; no
## per-frame particle readback, no dependency on a browser or Three.js.
signal amount_changed(fraction: float)
const UNIT := 0.087
const FLOOR := 0.0158
const RIM := (0.24 - FLOOR) / UNIT
const RADIUS := 0.85
const SPACING := 0.22
const SMOOTHING := SPACING * 2.0
const STEP := 1.0 / 240.0
const FIELD_SIZE := Vector3i(96, 128, 96)
const FIELD_LOW := Vector3(-2.2, -2.0, -2.2)
const FIELD_EXTENT := Vector3(4.4, 6.4, 4.4)
const PARTICLE_FLOATS := 20
const SURFACE = preload("res://src/player/beer/beer_surface.gdshader")
## Head of foam: simulation units at a fresh pour and after settling, and the
## seconds the settling takes.
const HEAD_POURED := 0.22
const HEAD_SETTLED := 0.1
const HEAD_SETTLE_SECONDS := 150.0
const RdUtil = preload("res://src/common/rd_util.gd")

var material: ShaderMaterial
var field := Texture3DRD.new()
var ready_gpu := false
var fraction := 0.0
var escaped := 0
var head := 1.0
## The height of the head against the tavern's old beer (BeerViewmodel.beer_look).
var head_scale := 1.0
## Set by the hand while the lips are on the rim: beer reaching the rim is drunk.
var mouth := false
var capacity := 0
var _rd: RenderingDevice
var _buffer: RID
var _statistics: RID
var _neighbours: RID
var _tile_bins: RID
var _texture: RID
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []
var _sets: Array[RID] = []
var _initial := PackedByteArray()
var _generation := 0
var _accumulator := 0.0
var _force_sum := Vector3.ZERO
var _force_time := 0.0
var _read_timer := 0.0
var _read_pending := false
var _consume := 0
var _reset_pending := false
var _alive := true
var _simulation_active := true
var _empty_confirmed := false
var _surface: MeshInstance3D

static func seed_positions() -> PackedVector3Array:
	var points := PackedVector3Array()
	var y := 0.12
	while y < RIM - 0.14:
		for z in range(-4, 5):
			for x in range(-4, 5):
				var p := Vector3(float(x) * SPACING, y, float(z) * SPACING)
				if Vector2(p.x, p.z).length() < RADIUS - 0.025:
					points.append(p)
		y += SPACING
	return points

static func seed_data(level: float) -> PackedByteArray:
	var points := seed_positions()
	var values := PackedFloat32Array()
	values.resize(points.size() * PARTICLE_FLOATS)
	var count := roundi(points.size() * clampf(level, 0.0, 1.0))
	for i in points.size():
		var offset := i * PARTICLE_FLOATS
		values[offset] = points[i].x + sin(float(i) * 12.9898) * 0.008
		values[offset + 1] = points[i].y
		values[offset + 2] = points[i].z + cos(float(i) * 78.233) * 0.008
		values[offset + 3] = 1.0 if i < count else 0.0
	return values.to_byte_array()

func _ready() -> void:
	position = Vector3(0, FLOOR, 0)
	scale = Vector3.ONE * UNIT
	capacity = seed_positions().size()
	assert(capacity <= 512, "Density-field neighbour tiles support at most 512 particles.")
	material = ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("density_field", field)
	material.set_shader_parameter("field_low", FIELD_LOW)
	material.set_shader_parameter("field_extent", FIELD_EXTENT)
	_surface = MeshInstance3D.new()
	_surface.name = "BeerIsosurface"
	var box := BoxMesh.new()
	box.size = FIELD_EXTENT
	_surface.mesh = box
	_surface.position = FIELD_LOW + FIELD_EXTENT * 0.5
	# Shader vertices are in simulation space, including the box centre offset.
	var mesh := ArrayMesh.new()
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size(): vertices[i] += _surface.position
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.position = Vector3.ZERO
	_surface.mesh = mesh
	_surface.material_override = material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.visible = false
	add_child(_surface)
	if _initial.is_empty(): refill(0.86)
	RenderingServer.call_on_render_thread(_create)

func refill(level: float) -> void:
	_generation += 1
	fraction = clampf(level, 0.0, 1.0)
	escaped = 0
	_consume = 0
	_initial = seed_data(fraction)
	_reset_pending = true
	head = 1.0
	_empty_confirmed = false
	if _surface != null: _surface.visible = ready_gpu
	amount_changed.emit(fraction)

func consume(level: float) -> void:
	_consume += roundi(maxf(level, 0.0) * capacity)
	fraction = maxf(fraction - level, 0.0)
	# A sip brings beer to the rim and stirs the head.
	head = maxf(head, 0.45)
	# Invalidate an in-flight statistics response from before the sip.
	_generation += 1
	amount_changed.emit(fraction)

func set_simulation_active(value: bool) -> void:
	_simulation_active = value
	set_process(value)
	if not value:
		_clear_pending_time()

func _clear_pending_time() -> void:
	_accumulator = 0.0
	_force_sum = Vector3.ZERO
	_force_time = 0.0
	_read_timer = 0.0

func advance(delta: float, acceleration: Vector3) -> void:
	if not ready_gpu or not _alive or not _simulation_active or _empty_confirmed: return
	var duration := maxf(delta, 0.0)
	_accumulator = minf(_accumulator + duration, STEP * 12)
	_force_sum += acceleration.limit_length(1800.0) * duration
	_force_time += duration
	_read_timer += duration

func _process(delta: float) -> void:
	if not ready_gpu or not _alive or not _simulation_active or _empty_confirmed: return
	head = maxf(head - delta / HEAD_SETTLE_SECONDS, 0.0)
	material.set_shader_parameter("foam_head", lerpf(HEAD_SETTLED, HEAD_POURED, head) * head_scale)
	# Several physics ticks can precede one rendered frame. Reconstruct the
	# surface only once, and bound catch-up work to avoid a GPU feedback spiral.
	var steps := mini(int(_accumulator / STEP), 12)
	if steps == 0: return
	_accumulator -= steps * STEP
	var acceleration := _force_sum / maxf(_force_time, 0.000001)
	_force_sum = Vector3.ZERO
	_force_time = 0.0
	var read_stats := _read_timer >= 0.25 and not _read_pending
	if read_stats:
		_read_pending = true
		_read_timer = 0.0
	var reset := _initial if _reset_pending else PackedByteArray()
	_reset_pending = false
	var drink_count := _consume
	_consume = 0
	RenderingServer.call_on_render_thread(_dispatch.bind(steps, acceleration,
		drink_count, _generation, reset, read_stats, 1.0 if mouth else 0.0))

func _uniform(kind: int, binding: int, rid: RID) -> RDUniform:
	return RdUtil.uniform(kind, binding, [rid])

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_failed.call_deferred("Beer simulation requires Godot Forward+ or Mobile rendering.")
		return
	_buffer = _rd.storage_buffer_create(_initial.size(), _initial)
	var zeros := PackedByteArray()
	zeros.resize(16)
	_statistics = _rd.storage_buffer_create(16, zeros)
	_neighbours = _rd.storage_buffer_create(capacity * (capacity + 1) * 4)
	# One 512-bit membership mask per 4³ tile; ordered bit scans make the
	# density sum deterministic and avoid scanning all particles at every tile.
	_tile_bins = _rd.storage_buffer_create(_tile_bin_bytes())
	var spec := RDTextureFormat.new()
	spec.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	spec.width = FIELD_SIZE.x
	spec.height = FIELD_SIZE.y
	spec.depth = FIELD_SIZE.z
	spec.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var compact_field := _rd.texture_is_format_supported_for_usage(
		RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, spec.usage_bits) and _rd.sampler_is_format_supported_for_filter(
		RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, RenderingDevice.SAMPLER_FILTER_LINEAR)
	spec.format = RenderingDevice.DATA_FORMAT_R16G16_SFLOAT if compact_field else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	_texture = _rd.texture_create(spec, RDTextureView.new())
	if compact_field and not _texture.is_valid():
		compact_field = false
		spec.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		_texture = _rd.texture_create(spec, RDTextureView.new())
	if not _texture.is_valid():
		_failed.call_deferred("Cannot create the beer density texture.")
		return
	for name in ["particle_fluid", "density_binned" if compact_field else "density_binned_rgba", "density_bins"]:
		var source := load("res://src/player/beer/%s.glsl" % name) as RDShaderFile
		if source == null or not source.get_spirv().compile_error_compute.is_empty():
			_failed.call_deferred("Cannot compile beer shader: " + name)
			return
		var shader := _rd.shader_create_from_spirv(source.get_spirv())
		_shaders.append(shader)
		_pipelines.append(_rd.compute_pipeline_create(shader))
	_sets.append(_rd.uniform_set_create([
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, _buffer),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, _statistics),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, _neighbours)], _shaders[0], 0))
	_sets.append(_rd.uniform_set_create([
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, _buffer),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, _texture),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, _tile_bins)], _shaders[1], 0))
	_sets.append(_rd.uniform_set_create([
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, _buffer),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, _tile_bins)], _shaders[2], 0))
	field.texture_rd_rid = _texture
	_publish.call_deferred()

func _publish() -> void:
	if not _alive: return
	ready_gpu = true
	_surface.visible = true

func _failed(reason: String) -> void:
	push_error(reason)

func _pass(list: int, phase: int, acceleration: Vector3, consume_count: int, generation: int,
		lips: float = 0.0) -> void:
	var data := PackedFloat32Array([acceleration.x, acceleration.y, acceleration.z, STEP,
		RADIUS, RIM, SPACING, SMOOTHING, capacity, phase, consume_count, generation,
		lips, 0, 0, 0]).to_byte_array()
	_rd.compute_list_set_push_constant(list, data, data.size())
	_rd.compute_list_dispatch(list, ceili(capacity / 64.0), 1, 1)
	_rd.compute_list_add_barrier(list)

func _tile_bin_bytes() -> int:
	return (FIELD_SIZE.x / 4) * (FIELD_SIZE.y / 4) * (FIELD_SIZE.z / 4) * 16 * 4

func _dispatch(steps: int, acceleration: Vector3, consume_count: int, generation: int,
		reset: PackedByteArray, read_stats: bool, lips: float) -> void:
	if _pipelines.size() != 3: return
	if not reset.is_empty(): _rd.buffer_update(_buffer, 0, reset.size(), reset)
	_rd.buffer_clear(_tile_bins, 0, _tile_bin_bytes())
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[0])
	_rd.compute_list_bind_uniform_set(list, _sets[0], 0)
	if not reset.is_empty():
		for relaxation in 64:
			for phase in [0, 1, 2, 3, 8]:
				_pass(list, phase, Vector3.ZERO, 0, generation)
	for step in steps:
		# Apply the previous viscosity correction with the next prediction. The
		# last constraint correction and velocity update are also particle-local.
		_pass(list, 0 if step == 0 else 10, acceleration, 0, generation)
		for iteration in 3:
			for phase in [1, 2, 9 if iteration == 2 else 3]:
				_pass(list, phase, acceleration, 0, generation, lips)
		_pass(list, 5, acceleration, 0, generation)
	if steps > 0: _pass(list, 6, acceleration, 0, generation)
	_pass(list, 7, acceleration, consume_count, generation)
	var params := PackedFloat32Array([FIELD_LOW.x, FIELD_LOW.y, FIELD_LOW.z, FIELD_SIZE.x,
		FIELD_EXTENT.x, FIELD_EXTENT.y, FIELD_EXTENT.z, FIELD_SIZE.y,
		capacity, SPACING * 2.1, FIELD_SIZE.z, 0]).to_byte_array()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[2])
	_rd.compute_list_bind_uniform_set(list, _sets[2], 0)
	_rd.compute_list_set_push_constant(list, params, params.size())
	_rd.compute_list_dispatch(list, ceili(capacity / 64.0), 1, 1)
	_rd.compute_list_add_barrier(list)
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[1])
	_rd.compute_list_bind_uniform_set(list, _sets[1], 0)
	_rd.compute_list_set_push_constant(list, params, params.size())
	_rd.compute_list_dispatch(list, FIELD_SIZE.x / 4, FIELD_SIZE.y / 4, FIELD_SIZE.z / 4)
	_rd.compute_list_end()
	if read_stats: _rd.buffer_get_data_async(_statistics, _receive_stats)

func _receive_stats(bytes: PackedByteArray) -> void:
	_accept_stats.call_deferred(bytes)

func _accept_stats(bytes: PackedByteArray) -> void:
	_read_pending = false
	if not _alive or bytes.size() < 16: return
	var values := bytes.to_float32_array()
	if roundi(values[2]) != _generation: return
	fraction = clampf(values[0] / capacity, 0.0, 1.0)
	escaped = roundi(values[1])
	# Only GPU-confirmed emptiness may suspend the fluid: spilled drops can
	# outlive the last sip. The generation check above rejects pre-refill data.
	if values[0] == 0.0 and escaped == 0:
		_empty_confirmed = true
		_clear_pending_time()
		if _surface != null: _surface.visible = false
	amount_changed.emit(fraction)

## Debug-only readback for numerical integration tests, never used by gameplay.
func inspect_particles(callback: Callable) -> void:
	RenderingServer.call_on_render_thread(func():
		_rd.buffer_get_data_async(_buffer, func(bytes: PackedByteArray): callback.call_deferred(bytes)))

func _exit_tree() -> void:
	_alive = false
	ready_gpu = false
	if material != null: material.set_shader_parameter("density_field", null)
	field.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_free)

func _free() -> void:
	if _rd == null: return
	RdUtil.free_rids(_rd, _sets + _pipelines + _shaders + [_buffer, _statistics, _neighbours, _tile_bins, _texture])
