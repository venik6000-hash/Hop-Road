class_name SkyAtmosphere
extends Node
## Physically based sky LUTs (Hillaire 2020) computed on the GPU.
##
## Transmittance and multiple scattering depend only on the air itself and are
## rebuilt when the tunables change; the sky-view LUT follows the sun and the
## viewer altitude whenever those inputs change (a 192x108 dispatch).
## Transmittance and the sky view are published as the global shader
## parameters `atmo_transmittance` and `atmo_skyview`, so the sky, water and
## terrain shaders all see the same air.

const RdUtil = preload("res://src/common/rd_util.gd")
const TRANSMITTANCE_SIZE := Vector2i(256, 64)
const MULTISCATTER_SIZE := Vector2i(32, 32)
const SKYVIEW_SIZE := Vector2i(192, 108)
const R_GROUND := 6360.0
const R_TOP := 6460.0
const RAYLEIGH_SCATTERING := Vector3(5.802, 13.558, 33.1) * 1e-3
const MIE_SCATTERING := 3.996e-3
const MIE_ABSORPTION := 0.444e-3
const OZONE_ABSORPTION := Vector3(0.650, 1.881, 0.085) * 1e-3

## Multiplies Rayleigh scattering: sky blueness and sunset redness.
@export var rayleigh_scale := 1.0
## Multiplies aerosol scattering: haze around the sun, milky horizon.
@export var mie_scale := 1.0
@export var ozone_scale := 1.0
## Altitude of world y = 0 above sea level, km. An alpine lake sits high,
## which thins the air above it and deepens the blue of the zenith.
@export var ground_altitude_km := 0.75

var sun_direction := Vector3(0.3, 0.6, 0.4).normalized()
var viewer_height_m := 0.0

var transmittance_lut := Texture2DRD.new()
var skyview_lut := Texture2DRD.new()

var _rd: RenderingDevice
var _sampler: RID
var _shaders: Dictionary[String, RID] = {}
var _pipelines: Dictionary[String, RID] = {}
var _textures: Dictionary[String, RID] = {}
var _sets: Dictionary[String, RID] = {}
var _built_tune := Vector4(-1, -1, -1, -1)
var _ready_for_frames := false
var _built_view := Vector2(INF, INF)
var _transmittance_key: Array = []
var _transmittance_value := Vector3.ZERO

func _ready() -> void:
	RenderingServer.call_on_render_thread(_create_gpu_resources)

func _exit_tree() -> void:
	RenderingServer.call_on_render_thread(_free_gpu_resources)

func tune() -> Vector4:
	return Vector4(rayleigh_scale, mie_scale, ozone_scale, 0.0)

func viewer_radius_km() -> float:
	return R_GROUND + ground_altitude_km + viewer_height_m * 0.001

func _process(_delta: float) -> void:
	if not _ready_for_frames:
		return
	var current := tune()
	var rebuild := current != _built_tune
	var view := Vector2(sun_direction.y, viewer_radius_km())
	if not rebuild and view == _built_view:
		return
	_built_tune = current
	_built_view = view
	RenderingServer.call_on_render_thread(_dispatch.bind(view.x, view.y, current, rebuild))

func _create_gpu_resources() -> void:
	_rd = RenderingServer.get_rendering_device()
	# No device in a headless run (the tests).
	if _rd == null:
		return
	_sampler = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	for pass_name: String in ["transmittance", "multiscatter", "skyview"]:
		var spirv := RdUtil.compute_spirv("res://src/sky/atmosphere_%s.glsl" % pass_name, "Atmosphere " + pass_name)
		if spirv == null:
			return
		_shaders[pass_name] = _rd.shader_create_from_spirv(spirv)
		_pipelines[pass_name] = _rd.compute_pipeline_create(_shaders[pass_name])
	_textures["transmittance"] = _make_texture(TRANSMITTANCE_SIZE)
	_textures["multiscatter"] = _make_texture(MULTISCATTER_SIZE)
	_textures["skyview"] = _make_texture(SKYVIEW_SIZE)
	_sets["transmittance"] = _rd.uniform_set_create([RdUtil.image(0, _textures["transmittance"])], _shaders["transmittance"], 0)
	_sets["multiscatter"] = _rd.uniform_set_create([
		RdUtil.sampled(0, _sampler, _textures["transmittance"]), RdUtil.image(1, _textures["multiscatter"])], _shaders["multiscatter"], 0)
	_sets["skyview"] = _rd.uniform_set_create([
		RdUtil.sampled(0, _sampler, _textures["transmittance"]), RdUtil.sampled(1, _sampler, _textures["multiscatter"]),
		RdUtil.image(2, _textures["skyview"])], _shaders["skyview"], 0)
	transmittance_lut.texture_rd_rid = _textures["transmittance"]
	skyview_lut.texture_rd_rid = _textures["skyview"]
	_publish.call_deferred()

func _publish() -> void:
	RenderingServer.global_shader_parameter_set("atmo_transmittance", transmittance_lut)
	RenderingServer.global_shader_parameter_set("atmo_skyview", skyview_lut)
	_ready_for_frames = true

func _make_texture(size: Vector2i) -> RID:
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.width = size.x
	format.height = size.y
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return _rd.texture_create(format, RDTextureView.new())

func _push(values: Array[float]) -> PackedByteArray:
	var data := PackedFloat32Array(values)
	while data.size() % 4 != 0:
		data.append(0.0)
	return data.to_byte_array()

func _dispatch(sun_zenith_cos: float, radius_km: float, air: Vector4, rebuild: bool) -> void:
	if _pipelines.size() < 3:
		return
	var list := _rd.compute_list_begin()
	if rebuild:
		var push := _push([air.x, air.y, air.z, air.w,
			TRANSMITTANCE_SIZE.x, TRANSMITTANCE_SIZE.y, 0.0, 0.0])
		_rd.compute_list_bind_compute_pipeline(list, _pipelines["transmittance"])
		_rd.compute_list_bind_uniform_set(list, _sets["transmittance"], 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, TRANSMITTANCE_SIZE.x / 8, TRANSMITTANCE_SIZE.y / 8, 1)
		_rd.compute_list_add_barrier(list)
		push = _push([air.x, air.y, air.z, air.w, MULTISCATTER_SIZE.x, MULTISCATTER_SIZE.y, 0.0, 0.0])
		_rd.compute_list_bind_compute_pipeline(list, _pipelines["multiscatter"])
		_rd.compute_list_bind_uniform_set(list, _sets["multiscatter"], 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, MULTISCATTER_SIZE.x, MULTISCATTER_SIZE.y, 1)
		_rd.compute_list_add_barrier(list)
	var view_push := _push([air.x, air.y, air.z, air.w, SKYVIEW_SIZE.x, SKYVIEW_SIZE.y, 0.0, 0.0,
		sun_zenith_cos, radius_km, 0.0, 0.0])
	_rd.compute_list_bind_compute_pipeline(list, _pipelines["skyview"])
	_rd.compute_list_bind_uniform_set(list, _sets["skyview"], 0)
	_rd.compute_list_set_push_constant(list, view_push, view_push.size())
	_rd.compute_list_dispatch(list, ceili(SKYVIEW_SIZE.x / 8.0), ceili(SKYVIEW_SIZE.y / 8.0), 1)
	_rd.compute_list_end()

func _free_gpu_resources() -> void:
	if _rd == null:
		return
	# Materials must stop referencing the LUTs before their RIDs die.
	for global_name: String in ["atmo_transmittance", "atmo_skyview"]:
		RenderingServer.global_shader_parameter_set(global_name, null)
	for lut: Texture2DRD in [transmittance_lut, skyview_lut]:
		lut.texture_rd_rid = RID()
	for key: String in _textures:
		_rd.free_rid(_textures[key])
	for key: String in _shaders:
		_rd.free_rid(_shaders[key])
	if _sampler.is_valid():
		_rd.free_rid(_sampler)
	_textures.clear()
	_shaders.clear()

## Sunlight transmittance from the viewer to space along `direction`, the same
## integral as the transmittance LUT but on the CPU: it colours the sun lamp.
func transmittance_toward(direction: Vector3) -> Vector3:
	var key: Array = [direction, viewer_radius_km(), tune()]
	if key != _transmittance_key:
		_transmittance_key = key
		_transmittance_value = _integrate_transmittance(direction)
	return _transmittance_value

func _integrate_transmittance(direction: Vector3) -> Vector3:
	var radius := viewer_radius_km()
	var origin := Vector3(0.0, radius, 0.0)
	var dir := direction.normalized()
	if _ray_sphere(origin, dir, R_GROUND) >= 0.0:
		return Vector3.ZERO
	var t_max := _ray_sphere(origin, dir, R_TOP)
	var steps := 64
	var dt := t_max / steps
	var depth := Vector3.ZERO
	var air := tune()
	for i in steps:
		var h := (origin + dir * (i + 0.5) * dt).length() - R_GROUND
		var rayleigh := exp(-h / 8.0)
		var mie := exp(-h / 1.2)
		var ozone := maxf(0.0, 1.0 - absf(h - 25.0) / 15.0)
		depth += (RAYLEIGH_SCATTERING * rayleigh * air.x
			+ Vector3.ONE * (MIE_SCATTERING + MIE_ABSORPTION) * mie * air.y
			+ OZONE_ABSORPTION * ozone * air.z) * dt
	return Vector3(exp(-depth.x), exp(-depth.y), exp(-depth.z))

static func _ray_sphere(origin: Vector3, dir: Vector3, radius: float) -> float:
	var b := origin.dot(dir)
	var c := origin.dot(origin) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var s := sqrt(disc)
	if -b - s >= 0.0:
		return -b - s
	if -b + s >= 0.0:
		return -b + s
	return -1.0
