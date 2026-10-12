class_name SunShadowField
extends Node
## Where the mountains shadow the valley, as a field the shaders look up.
##
## The terrain keeps out of the sun's shadow map (see TerrainSystem), so
## nothing that stands on it knew when a ridge took its sun: at a low sun the
## trees, the grass and the houses stayed lit on a slope already in shadow.
## This is the baked top-down light map of large open-world games, built from
## the heightfields on the GPU whenever the sun has moved: per texel, how far
## the shadow stands above the ground, how far away its caster is (the
## penumbra widens with it), and the ground's height.
##
## Two fields, as the heights have: 1 m over the near kilometre, 16 m over the
## 16 km around it. They are published as the global shader parameters
## `sun_shadow_near`, `sun_shadow_far` and their rects (origin x, origin z,
## cell, samples); src/terrain/sun_shadow.gdshaderinc reads them.

const RdUtil = preload("res://src/common/rd_util.gd")
const SIZE := 1024
## Sweeps per field; each doubles the reach, so 2^PASSES cells are crossed.
## Even, so the last sweep lands in the texture the resolve reads.
const PASSES := 10
const NEAR_CELL := 1.0
const FAR_CELL := 16.0
## Below this height of the sun (its direction's y) its light is nearly gone
## and the shaders stop asking.
const MIN_SUN_HEIGHT := 0.02
## The sun moved by more than this angle: build again.
const REBUILD_DEG := 0.05
const GLOBALS := ["sun_shadow_near", "sun_shadow_far"]

var terrain: TerrainSystem
var sky: SkySystem
var near_field := Texture2DRD.new()
var far_field := Texture2DRD.new()
## Builds so far (tools and tests read it).
var builds := 0

var _rd: RenderingDevice
var _sampler: RID
var _shaders := {}
var _pipelines := {}
var _textures := {}
var _sets := {}
var _ready_for_frames := false
var _built_for := Vector3.ZERO
var _published := false

func _ready() -> void:
	RenderingServer.call_on_render_thread(_create_gpu_resources.bind(
		terrain.material.get_shader_parameter("near_height").get_rid(),
		terrain.material.get_shader_parameter("far_height").get_rid()))

func _exit_tree() -> void:
	RenderingServer.call_on_render_thread(_free_gpu_resources)

func _process(_delta: float) -> void:
	if not _ready_for_frames or sky == null:
		return
	var sun := sky.sun_direction
	if sun.y <= MIN_SUN_HEIGHT:
		return
	if _built_for != Vector3.ZERO and _built_for.angle_to(sun) < deg_to_rad(REBUILD_DEG):
		return
	_built_for = sun
	builds += 1
	RenderingServer.call_on_render_thread(_dispatch.bind(sun, near_rect(), far_rect(),
		Vector4(terrain.near_origin.x, terrain.near_origin.y, terrain.near_cell, terrain.near_size),
		Vector4(terrain.far_origin.x, terrain.far_origin.y, terrain.far_cell, terrain.far_size)))

func near_rect() -> Vector4:
	return Vector4(terrain.near_origin.x, terrain.near_origin.y, NEAR_CELL, SIZE)

func far_rect() -> Vector4:
	return Vector4(terrain.far_origin.x, terrain.far_origin.y, FAR_CELL, SIZE)

func _create_gpu_resources(near_height: RID, far_height: RID) -> void:
	_rd = RenderingServer.get_rendering_device()
	_sampler = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	for pass_name: String in ["sweep", "resolve"]:
		var spirv := RdUtil.compute_spirv("res://src/terrain/sun_shadow_%s.glsl" % pass_name, "Sun shadow " + pass_name)
		if spirv == null:
			return
		_shaders[pass_name] = _rd.shader_create_from_spirv(spirv)
		_pipelines[pass_name] = _rd.compute_pipeline_create(_shaders[pass_name])
	_textures.a = _make_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
	_textures.b = _make_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
	_textures.near = _make_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	_textures.far = _make_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var heights := [RdUtil.sampled(0, _sampler, RenderingServer.texture_get_rd_texture(near_height)),
		RdUtil.sampled(1, _sampler, RenderingServer.texture_get_rd_texture(far_height))]
	for pair: Array in [["ab", _textures.a, _textures.b], ["ba", _textures.b, _textures.a]]:
		_sets[pair[0]] = _rd.uniform_set_create(heights + [RdUtil.sampled(2, _sampler, pair[1]),
			RdUtil.sampled(3, _sampler, _textures.far), RdUtil.image(4, pair[2])], _shaders.sweep, 0)
	for field: String in ["near", "far"]:
		_sets[field] = _rd.uniform_set_create(heights + [RdUtil.sampled(2, _sampler, _textures.a),
			RdUtil.image(3, _textures[field])], _shaders.resolve, 0)
	near_field.texture_rd_rid = _textures.near
	far_field.texture_rd_rid = _textures.far
	_start.call_deferred()

func _start() -> void:
	_ready_for_frames = true

func _make_texture(data_format: int) -> RID:
	var format := RDTextureFormat.new()
	format.format = data_format
	format.width = SIZE
	format.height = SIZE
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return _rd.texture_create(format, RDTextureView.new())

## The far field first: the near one's sweeps run on into it.
func _dispatch(sun: Vector3, near: Vector4, far: Vector4, near_heights: Vector4, far_heights: Vector4) -> void:
	if _pipelines.size() < 2:
		return
	var flat := Vector2(sun.x, sun.z).length()
	var heading := Vector2(sun.x, sun.z) / maxf(flat, 1e-5)
	var list := _rd.compute_list_begin()
	for field: Array in [["far", far, Vector4.ZERO], ["near", near, far]]:
		var rect: Vector4 = field[1]
		_rd.compute_list_bind_compute_pipeline(list, _pipelines.sweep)
		_pass(list, _sets.ba, near_heights, far_heights, rect, field[2], Vector4.ZERO, 0.0, 0.0)
		for index in PASSES:
			var step := rect.z * pow(2.0, index)
			_pass(list, _sets.ab if index % 2 == 0 else _sets.ba, near_heights, far_heights, rect, field[2],
				Vector4(heading.x, heading.y, step, step * sun.y / maxf(flat, 1e-5)), 1.0, 1.0 / maxf(flat, 1e-5))
		_rd.compute_list_bind_compute_pipeline(list, _pipelines.resolve)
		_pass(list, _sets[field[0]], near_heights, far_heights, rect, field[2], Vector4.ZERO, 0.0, 0.0)
	_rd.compute_list_end()
	_publish.call_deferred(near, far)

func _pass(list: int, uniform_set: RID, near_heights: Vector4, far_heights: Vector4, rect: Vector4, coarse: Vector4,
		sweep: Vector4, mode: float, path: float) -> void:
	var values := PackedFloat32Array()
	for vector: Vector4 in [near_heights, far_heights, rect, coarse, sweep, Vector4(mode, path, 0.0, 0.0)]:
		values.append_array([vector.x, vector.y, vector.z, vector.w])
	var push := values.to_byte_array()
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, SIZE / 8, SIZE / 8, 1)
	_rd.compute_list_add_barrier(list)

## The fields are named once: a build fills the same two textures, and a
## texture global set again makes every material that reads it rebuild its
## uniform set, which also redraws the shadows of the lamps around.
func _publish(near: Vector4, far: Vector4) -> void:
	if not _published:
		_published = true
		RenderingServer.global_shader_parameter_set("sun_shadow_near", near_field)
		RenderingServer.global_shader_parameter_set("sun_shadow_far", far_field)
	RenderingServer.global_shader_parameter_set("sun_shadow_near_rect", near)
	RenderingServer.global_shader_parameter_set("sun_shadow_far_rect", far)

func _free_gpu_resources() -> void:
	if _rd == null:
		return
	# Materials must stop referencing the fields before their RIDs die.
	for global_name: String in GLOBALS:
		RenderingServer.global_shader_parameter_set(global_name, null)
	for global_name: String in GLOBALS:
		RenderingServer.global_shader_parameter_set(global_name + "_rect", Vector4.ZERO)
	near_field.texture_rd_rid = RID()
	far_field.texture_rd_rid = RID()
	RdUtil.free_rids(_rd, _textures.values() + _shaders.values() + [_sampler])
	_textures.clear()
	_shaders.clear()
	_pipelines.clear()
