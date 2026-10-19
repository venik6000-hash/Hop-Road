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
##
## The near kilometre follows the eye (follow(), FieldWindow) from the
## region's near field. When it moves, the next build lays it at its new
## place: the near field alone, the far one holds for the same sun. A build
## is the whole field: the sun moves it again within a second of a running
## clock (REBUILD_DEG), so a strip kept from before would not live long.

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
## How far (m) along an axis the eye may stray from the middle of the near
## field before it moves (FieldWindow).
const REACH := 192.0
const GLOBALS := ["sun_shadow_near", "sun_shadow_far"]

var terrain: TerrainSystem
var sky: SkySystem
var near_field := Texture2DRD.new()
var far_field := Texture2DRD.new()
## Where the near field stands: it follows the eye from the region's near field.
var window: FieldWindow
## Builds so far, and those of the near field alone after a move (tools and
## tests read them).
var builds := 0
var moves := 0

var _rd: RenderingDevice
var _sampler: RID
var _shaders: Dictionary[String, RID] = {}
var _pipelines: Dictionary[String, RID] = {}
var _textures: Dictionary[String, RID] = {}
var _sets: Dictionary[String, RID] = {}
var _ready_for_frames := false
var _built_for := Vector3.ZERO
var _built_near := Vector4.ZERO
var _published := false

func _ready() -> void:
	window = FieldWindow.new(terrain.near_origin, SIZE * NEAR_CELL, REACH)
	var heights := PackedStringArray(["tile_heights", "far_height", "mid_height", "tile_slots"])
	var rids: Array[RID] = []
	for parameter: String in heights:
		var texture: Texture = terrain.material.get_shader_parameter(parameter)
		rids.append(texture.get_rid())
	RenderingServer.call_on_render_thread(_create_gpu_resources.bind(rids))
	# A tile come or gone changes the heights: build again at once.
	terrain.tiles_changed.connect(func() -> void: _built_for = Vector3.ZERO)

func _exit_tree() -> void:
	RenderingServer.call_on_render_thread(_free_gpu_resources)

## The near field follows the eye at `at` (world x, z); the level calls it
## every frame. The field moves at the next build.
func follow(at: Vector2) -> void:
	if window != null:
		window.offset = window.offset_for(at)

func _process(_delta: float) -> void:
	if not _ready_for_frames or sky == null:
		return
	var sun := sky.sun_direction
	if sun.y <= MIN_SUN_HEIGHT:
		return
	var near := near_rect()
	var whole := _built_for == Vector3.ZERO or _built_for.angle_to(sun) >= deg_to_rad(REBUILD_DEG)
	if not whole and near == _built_near:
		return
	if whole:
		_built_for = sun
		builds += 1
	else:
		moves += 1
	_built_near = near
	var heights: Array[Vector4] = []
	for parameter: String in ["tile_rect", "tile_cells", "mid_rect", "far_rect"]:
		heights.append(terrain.material.get_shader_parameter(parameter))
	RenderingServer.call_on_render_thread(_dispatch.bind(_built_for, near, far_rect(), heights, whole))
	# Queued after the build: the shaders read the new rect in the frame
	# whose fields it was built for.
	_publish(near, far_rect())

## Where the near field is built next: its corner follows the eye.
func near_rect() -> Vector4:
	var corner := window.corner() if window != null else terrain.near_origin
	return Vector4(corner.x, corner.y, NEAR_CELL, SIZE)

func far_rect() -> Vector4:
	return Vector4(terrain.far_origin.x, terrain.far_origin.y, FAR_CELL, SIZE)

## `heights`: the textures of the tiles' heights, the far and mid fields and
## the tiles' map, bound 0 to 3 (sun_shadow_common.glslinc).
func _create_gpu_resources(heights_rids: Array[RID]) -> void:
	_rd = RenderingServer.get_rendering_device()
	# No device in a headless run (the tests).
	if _rd == null:
		return
	_sampler = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	for pass_name: String in ["sweep", "resolve"]:
		var spirv := RdUtil.compute_spirv("res://src/terrain/sun_shadow_%s.glsl" % pass_name, "Sun shadow " + pass_name)
		if spirv == null:
			return
		_shaders[pass_name] = _rd.shader_create_from_spirv(spirv)
		_pipelines[pass_name] = _rd.compute_pipeline_create(_shaders[pass_name])
	_textures["a"] = _make_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
	_textures["b"] = _make_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
	_textures["near"] = _make_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	_textures["far"] = _make_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var heights := []
	for binding in heights_rids.size():
		heights.append(RdUtil.sampled(binding, _sampler, RenderingServer.texture_get_rd_texture(heights_rids[binding])))
	for pair: Array in [["ab", _textures["a"], _textures["b"]], ["ba", _textures["b"], _textures["a"]]]:
		var from: RID = pair[1]
		var to: RID = pair[2]
		_sets[str(pair[0])] = _rd.uniform_set_create(heights + [RdUtil.sampled(4, _sampler, from),
			RdUtil.sampled(5, _sampler, _textures["far"]), RdUtil.image(6, to)], _shaders["sweep"], 0)
	for field: String in ["near", "far"]:
		_sets[field] = _rd.uniform_set_create(heights + [RdUtil.sampled(4, _sampler, _textures["a"]),
			RdUtil.image(5, _textures[field])], _shaders["resolve"], 0)
	near_field.texture_rd_rid = _textures["near"]
	far_field.texture_rd_rid = _textures["far"]
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

## The far field first: the near one's sweeps run on into it. `heights` are
## the rects of the tiles, their cells, the mid and the far field. Without
## `whole` the far field is the one built for the same sun before.
func _dispatch(sun: Vector3, near: Vector4, far: Vector4, heights: Array[Vector4], whole: bool) -> void:
	if _pipelines.size() < 2:
		return
	var flat := Vector2(sun.x, sun.z).length()
	var heading := Vector2(sun.x, sun.z) / maxf(flat, 1e-5)
	var fields: Array[Array] = [["near", near, far]]
	if whole:
		fields.push_front(["far", far, Vector4.ZERO])
	var list := _rd.compute_list_begin()
	for field: Array in fields:
		var rect: Vector4 = field[1]
		var coarse: Vector4 = field[2]
		_rd.compute_list_bind_compute_pipeline(list, _pipelines["sweep"])
		_pass(list, _sets["ba"], heights, rect, coarse, Vector4.ZERO, 0.0, 0.0)
		for index in PASSES:
			var step := rect.z * pow(2.0, index)
			_pass(list, _sets["ab"] if index % 2 == 0 else _sets["ba"], heights, rect, coarse,
				Vector4(heading.x, heading.y, step, step * sun.y / maxf(flat, 1e-5)), 1.0, 1.0 / maxf(flat, 1e-5))
		_rd.compute_list_bind_compute_pipeline(list, _pipelines["resolve"])
		_pass(list, _sets[str(field[0])], heights, rect, coarse, Vector4.ZERO, 0.0, 0.0)
	_rd.compute_list_end()

func _pass(list: int, uniform_set: RID, heights: Array[Vector4], rect: Vector4, coarse: Vector4,
		sweep: Vector4, mode: float, path: float) -> void:
	var values := PackedFloat32Array()
	for vector: Vector4 in heights + [rect, coarse, sweep, Vector4(mode, path, 0.0, 0.0)]:
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
