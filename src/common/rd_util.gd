extends RefCounted
## RenderingDevice boilerplate the compute passes share (sky LUTs, ocean FFT,
## lens pass, lake shore, refraction capture, beer fluid): compiled shader
## code, samplers, uniforms, freeing and the std140 matrix layout.

## The SPIR-V of the compute shader at `path`, or null after reporting
## "`label`: <compile error>".
static func compute_spirv(path: String, label: String) -> RDShaderSPIRV:
	var file := load(path) as RDShaderFile
	var spirv := file.get_spirv()
	if spirv.compile_error_compute != "":
		push_error(label + ": " + spirv.compile_error_compute)
		return null
	return spirv

## A linearly filtered sampler with `repeat` (a SamplerRepeatMode) in u and v.
static func linear_sampler(rd: RenderingDevice, repeat: int) -> RID:
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = repeat
	state.repeat_v = repeat
	return rd.sampler_create(state)

static func uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var value := RDUniform.new()
	value.uniform_type = type
	value.binding = binding
	for id: RID in ids:
		value.add_id(id)
	return value

static func image(binding: int, texture: RID) -> RDUniform:
	return uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, binding, [texture])

static func sampled(binding: int, sampler: RID, texture: RID) -> RDUniform:
	return uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, binding, [sampler, texture])

static func storage(binding: int, buffer: RID) -> RDUniform:
	return uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, binding, [buffer])

## Frees every valid RID of `rids`, in order.
static func free_rids(rd: RenderingDevice, rids: Array) -> void:
	for rid: RID in rids:
		if rid.is_valid():
			rd.free_rid(rid)

## Column-major, as std140 mat4 expects.
static func append_projection(values: PackedFloat32Array, matrix: Projection) -> void:
	for column: Vector4 in [matrix.x, matrix.y, matrix.z, matrix.w]:
		values.append_array([column.x, column.y, column.z, column.w])
