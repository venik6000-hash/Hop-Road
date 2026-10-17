class_name AtmosphereFog
extends CompositorEffect
## The weather's fog as a compositor pass on the HDR image, after Bauer 2019,
## "Creating the Atmospheric World of Red Dead Redemption 2": haze, the mist
## bank on the lake and the lowland, rain fog under the clouds, the damp a
## wood holds under its crowns, the shafts the mountains' and the clouds'
## shadows cut into them, and the rainbow.
##
## fog_volume.glsl marches a small view-aligned grid (CELLS) once a frame and
## fog_apply.glsl lays it over the picture by each pixel's own depth. With no
## fog in the air (fair weather by day) neither runs.
##
## Two things come on top of the grid: the halo round every lamp that burns in
## the fog (the lights of the group LAMP_GROUP), and the fog between the lake
## and what it mirrors, which the grid marches along the mirrored ray. The
## lake's own shader knows nothing of either.
##
## WeatherSystem sets the amounts; the level calls prepare() once a frame on
## the main thread, and the render thread only reads that snapshot.

const RdUtil = preload("res://src/common/rd_util.gd")
const CanopyField = preload("res://src/vegetation/canopy_field.gd")
const VOLUME_SHADER := "res://src/weather/fog_volume.glsl"
const APPLY_SHADER := "res://src/weather/fog_apply.glsl"
## Columns, rows and depth slices of the grid.
const CELLS := Vector3i(160, 90, 48)
## Far edge of the first and of the last slice, m.
const NEAR_EDGE := 2.0
const FAR_EDGE := 24000.0
const PARAM_FLOATS := 236
## Lights in this group glow in the fog (lanterns, a campfire).
const LAMP_GROUP := &"fog_lamp"
## The nearest lamps that get a halo, and how far away one may be, m.
const MAX_LAMPS := 16
const LAMP_VIEW := 160.0
## What the fog's forward lobes send toward the eye of a lamp's light, against
## a fog that scatters alike all round: their mean along a ray past the lamp.
const LAMP_PHASE := 2.2
## The mist bank's mean thickness against its thickest (its clots).
const MIST_BANKS := 0.55
## The share of the rain fog that lies under a mean rain cloud.
const RAIN_COVER := 0.7
## Extinction (1/m) of each kind of fog at an amount of 1.
const HAZE_EXTINCTION := 0.0011
const MIST_EXTINCTION := 0.05
const RAIN_EXTINCTION := 0.0008
const DROP_EXTINCTION := 0.0003
## Height (m) over which the haze thins to 37 %.
const HAZE_HEIGHT := 420.0
## The mist bank: its top above the ground, the falloff above the top, and
## how high above the lake the ground may lie and still hold it, m.
const MIST_TOP := 5.0
const MIST_FALLOFF := 4.0
const MIST_REACH := 55.0
## The fog a wood holds under its crowns in mist and rain: trunks melt into it
## over 30-100 m. Its extinction (1/m) at an amount of 1, its top above the
## ground and the falloff above the top (m), and the share of the sun and the
## moon the crowns let into it.
const WOOD_EXTINCTION := 0.018
const WOOD_TOP := 11.0
const WOOD_FALLOFF := 7.0
const WOOD_SUN := 0.2
## The cover of a stand (CanopyField.wooded_at) between which it holds no fog
## and all of it. WOOD_COVER in fog_volume.glsl.
const WOOD_COVER := Vector2(0.1, 0.5)
## Metres a second the mist drifts with a wind of 1 m/s.
const MIST_DRIFT := 0.35
## Height (m) the clouds' shadow on the fog is taken at, as on the ground.
const CLOUD_SHADOW_HEIGHT := 3300.0
## Share of the sun a thick cloud takes from the fog under it.
const CLOUD_SHADOW := 0.85
## The rainbow's radiance against the sun's light.
const BOW_STRENGTH := 0.032
## Amounts below this draw nothing.
const SILENT := 0.002

## Debug output instead of the picture: 1 what is left of the light behind the
## fog, 2 the fog's own light, 3 the slice a pixel reads, 4 sunlit drops.
@export_range(0, 4) var debug_view := 0
## The halos round the lamps, and the fog in the lake's mirror (off for tools
## that compare).
@export var lamp_halos := true
@export var lake_mirror := true

## Amounts 0..1 and above (WeatherSystem writes them): fog everywhere, the
## mist bank, rain fog, the fog in the woods, the drops left in the air,
## lightning's light, and how much of the day the clouds take.
var haze := 0.0
var mist := 0.0
var rain := 0.0
var wood := 0.0
var droplets := 0.0
var flash := 0.0
var gloom := 0.0

var sky: SkySystem
var terrain: TerrainSystem
var sun_shadow: SunShadowField
## Where the crowns close the sky: the woods that hold their own fog (none
## without it).
var canopy: CanopyField
## The sky's weather map (assets/generated/sky/cloud_weather.png).
var weather_map: Texture2D
## The rooms the fog stays out of, as one box (none while its size is zero):
## the nearest building's (Interiors.fog_box), set every frame.
var building := AABB()
## The level's rooms: seen from inside one, no lamp outdoors has a halo (the
## fog is not in the room, and a lantern on the other side of a wall would
## glow through it). Null: the eye is never in a room.
var interiors: Interiors
## Wind over the lake, m/s (x east, y south): the mist drifts with it.
var wind := Vector2.ZERO
## The significant height of the lake's waves, m: what a pixel shows is the
## lake up to their reach above its level.
var wave_height := 0.0

var _rd: RenderingDevice
var _volume_shader: RID
var _volume_pipeline: RID
var _apply_shader: RID
var _apply_pipeline: RID
var _nearest: RID
var _linear: RID
var _repeat: RID
var _params: RID
var _fog_volume: RID
var _bow_volume: RID
var _mirror_fog: RID
var _frame := PackedFloat32Array()
var _drift := Vector2.ZERO
var _level := 0.0
var _weather_texture: RID
var _height_texture: RID
var _canopy_texture: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_create)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		# Freeing a shader also frees its pipeline.
		RdUtil.free_rids(_rd, [_volume_shader, _apply_shader, _nearest, _linear, _repeat, _params, _fog_volume, _bow_volume,
			_mirror_fog])

## Whether there is anything in the air to draw.
func active() -> bool:
	return haze > SILENT or mist > SILENT or rain > SILENT or wood > SILENT or droplets > SILENT

## Takes this frame's state for the render thread. Call once a frame, with
## the eye's place and the lights that may glow in the fog.
func prepare(delta: float, eye := Vector3.ZERO, lamps: Array = []) -> void:
	if sky == null or terrain == null or not active():
		_frame = PackedFloat32Array()
		return
	_drift += wind * MIST_DRIFT * delta
	_level = terrain.water_level
	_weather_texture = weather_map.get_rid() if weather_map != null else RID()
	var far_height: Texture2D = terrain.material.get_shader_parameter("far_height")
	_height_texture = far_height.get_rid()
	var crowns := canopy.rect() if canopy != null and canopy.texture != null else Vector4.ZERO
	_canopy_texture = canopy.texture.get_rid() if crowns.w > 0.0 else RID()
	var sun := sky.sun_direction
	var moon := sky.moon_direction
	# A closed sky lets no beam through: what it passes is in the sky's light.
	var sun_light := sky.sun_irradiance * sky.sun_share
	var moon_light := sky.moon_irradiance * sky.sun_share
	var radiance := sky.sun_energy * PI
	var shadows := Vector4.ZERO
	if sun_shadow != null and sun_shadow.builds > 0 and sun.y > SunShadowField.MIN_SUN_HEIGHT:
		shadows = sun_shadow.far_rect()
	var values := PackedFloat32Array([
		sun.x, sun.y, sun.z, _level,
		sun_light.x, sun_light.y, sun_light.z, CLOUD_SHADOW,
		moon.x, moon.y, moon.z, CLOUD_SHADOW_HEIGHT,
		moon_light.x, moon_light.y, moon_light.z, flash,
		radiance, radiance, radiance, sky.atmosphere.viewer_radius_km(),
		haze * HAZE_EXTINCTION, HAZE_HEIGHT, gloom, BOW_STRENGTH,
		mist * MIST_EXTINCTION, MIST_TOP, MIST_FALLOFF, MIST_REACH,
		rain * RAIN_EXTINCTION, WeatherSystem.CLOUD_BASE, droplets, droplets * DROP_EXTINCTION,
		sky.cloud_coverage, sky.cloud_density, sky.cloud_cumulus_bias, sky.cloud_darkness,
		sky.cloud_offset.x, sky.cloud_offset.y, _drift.x, _drift.y,
		shadows.x, shadows.y, shadows.z, shadows.w,
		terrain.far_origin.x, terrain.far_origin.y, terrain.far_cell, terrain.far_size,
		building.position.x, building.position.y, building.position.z, 1.0 if building.has_volume() else 0.0,
		building.end.x, building.end.y, building.end.z, float(debug_view),
		wood * WOOD_EXTINCTION, WOOD_TOP, WOOD_FALLOFF, WOOD_SUN,
		crowns.x, crowns.y, crowns.z, crowns.w,
	])
	var outdoors := 1.0 - interiors.inside(eye) if interiors != null else 1.0
	var rows := lamp_rows(eye, lamps, outdoors) if lamp_halos and outdoors > 0.01 else PackedFloat32Array()
	values.append_array([rows.size() / 8, 1.0 if lake_mirror else 0.0, RefractionPost.wave_reach(wave_height), 0.0])
	values.append_array(rows)
	# The render thread adds the two matrices and two rows ahead of these.
	values.resize(PARAM_FLOATS - 40)
	_frame = values

## The fog's extinction (1/m) around `at`: the shader's haze, mist bank, rain
## fog and the fog of a wood, without their clots.
func density_at(at: Vector3) -> float:
	var above := at.y - terrain.water_level
	var density := haze * HAZE_EXTINCTION * exp(-maxf(above, 0.0) / HAZE_HEIGHT)
	if mist > SILENT:
		var ground := terrain.height_at(at.x, at.z) - terrain.water_level
		var low := lerpf(1.0, 0.45, smoothstep(0.2, 2.5, ground)) * (1.0 - smoothstep(MIST_REACH * 0.35, MIST_REACH, ground))
		var top := maxf(ground, 0.0) + MIST_TOP
		density += mist * MIST_EXTINCTION * low * MIST_BANKS * (1.0 if above <= top else exp(-(above - top) / MIST_FALLOFF))
	if at.y < WeatherSystem.CLOUD_BASE:
		density += rain * RAIN_EXTINCTION * RAIN_COVER
	if wood > SILENT and canopy != null:
		var crown_top := terrain.height_at(at.x, at.z) + WOOD_TOP
		density += wood * WOOD_EXTINCTION * wood_share(canopy.wooded_at(at.x, at.z)) \
			* (1.0 if at.y <= crown_top else exp(-(at.y - crown_top) / WOOD_FALLOFF))
	return density

## How much of its fog a stand holds, 0..1, by how much of the sky its crowns
## close.
static func wood_share(cover: float) -> float:
	return smoothstep(WOOD_COVER.x, WOOD_COVER.y, cover)

## The parameter rows of the lamps that glow in the fog, the nearest to `eye`
## first, eight numbers a lamp: where it is and the fog's scattering there,
## then what a metre of that fog sends on of its light (times `share`) and how
## far it reaches.
func lamp_rows(eye: Vector3, lamps: Array, share := 1.0) -> PackedFloat32Array:
	var lit: Array[Array] = []
	for lamp: Light3D in lamps:
		if not is_instance_valid(lamp) or not lamp.is_visible_in_tree() or lamp.light_energy < 0.01:
			continue
		var away := eye.distance_to(lamp.global_position)
		if away < LAMP_VIEW:
			lit.append([away, lamp])
	lit.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var rows := PackedFloat32Array()
	for entry: Array in lit.slice(0, MAX_LAMPS):
		var lamp: Light3D = entry[1]
		var at := lamp.global_position
		var light := lamp_light(lamp.light_color, lamp.light_energy) * share
		rows.append_array([at.x, at.y, at.z, density_at(at), light.x, light.y, light.z, lamp_reach(lamp)])
	return rows

## What a metre of fog of unit scattering sends toward the eye of a lamp's
## light, a metre from it. The renderer lights a white wall a metre from a
## lamp of energy 1 to a radiance of 1: an irradiance of pi.
static func lamp_light(color: Color, energy: float) -> Vector3:
	var linear := color.srgb_to_linear()
	return Vector3(linear.r, linear.g, linear.b) * (energy * LAMP_PHASE / 4.0)

## How far a lamp's light reaches, m.
static func lamp_reach(lamp: Light3D) -> float:
	if lamp is OmniLight3D:
		return (lamp as OmniLight3D).omni_range
	if lamp is SpotLight3D:
		return (lamp as SpotLight3D).spot_range
	return 0.0

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	# No device in a headless run (the tests).
	if _rd == null:
		return
	var volume_spirv := RdUtil.compute_spirv(VOLUME_SHADER, "Fog volume")
	var apply_spirv := RdUtil.compute_spirv(APPLY_SHADER, "Fog apply")
	if volume_spirv == null or apply_spirv == null:
		return
	_volume_shader = _rd.shader_create_from_spirv(volume_spirv)
	_volume_pipeline = _rd.compute_pipeline_create(_volume_shader)
	_apply_shader = _rd.shader_create_from_spirv(apply_spirv)
	_apply_pipeline = _rd.compute_pipeline_create(_apply_shader)
	_nearest = _rd.sampler_create(RDSamplerState.new())
	_linear = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_repeat = RdUtil.linear_sampler(_rd, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT)
	var zero := PackedByteArray()
	zero.resize(PARAM_FLOATS * 4)
	_params = _rd.uniform_buffer_create(zero.size(), zero)
	_fog_volume = _make_volume(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	_bow_volume = _make_volume(RenderingDevice.DATA_FORMAT_R16_SFLOAT)
	var flat := RDTextureFormat.new()
	flat.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	flat.width = CELLS.x
	flat.height = CELLS.y
	flat.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_mirror_fog = _rd.texture_create(flat, RDTextureView.new())

## `projection` with its y turned so that -1 is the image's top row, whether
## the renderer hands it over that way already (Godot 4.7 does) or not.
static func image_projection(projection: Projection) -> Projection:
	if projection.y.y > 0.0:
		projection.x.y = -projection.x.y
		projection.y.y = -projection.y.y
		projection.z.y = -projection.z.y
		projection.w.y = -projection.w.y
	return projection

func _make_volume(data_format: int) -> RID:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	format.format = data_format
	format.width = CELLS.x
	format.height = CELLS.y
	format.depth = CELLS.z
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return _rd.texture_create(format, RDTextureView.new())

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	var frame := _frame
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or frame.is_empty() or not _apply_pipeline.is_valid():
		return
	if not _weather_texture.is_valid() or not sky.atmosphere.skyview_lut.texture_rd_rid.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var data := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or data == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var camera := data.get_cam_transform()
	# Under the lake the lens pass draws the water; the fog is the air's.
	if camera.origin.y < _level:
		return
	var weather := RenderingServer.texture_get_rd_texture(_weather_texture)
	var heights := RenderingServer.texture_get_rd_texture(_height_texture)
	# Before the first field is built its rect says "none" and the texture is
	# not read, but a texture must be bound all the same.
	var shadows := sun_shadow.far_field.texture_rd_rid if sun_shadow != null else RID()
	if not shadows.is_valid():
		shadows = heights
	# The same for the crowns' field: its rect says "none" without it.
	var crowns := heights
	if _canopy_texture.is_valid():
		crowns = RenderingServer.texture_get_rd_texture(_canopy_texture)
		if not crowns.is_valid():
			return
	for view in buffers.get_view_count():
		var values := PackedFloat32Array()
		var projection := image_projection(data.get_view_projection(view))
		RdUtil.append_projection(values, projection.inverse())
		RdUtil.append_projection(values, Projection(camera))
		# Reversed depth of a perspective view: raw = z.w / depth - z.z.
		values.append_array([size.x, size.y, projection.w.z, projection.z.z])
		values.append_array([NEAR_EDGE, FAR_EDGE, CELLS.z, (Engine.get_frames_drawn() % 64) / 64.0])
		values.append_array(frame)
		var bytes := values.to_byte_array()
		_rd.buffer_update(_params, 0, bytes.size(), bytes)
		var params := RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_params])
		var volume_set := UniformSetCacheRD.get_cache(_volume_shader, 0, [params,
			RdUtil.image(1, _fog_volume), RdUtil.image(2, _bow_volume),
			RdUtil.sampled(3, _linear, shadows), RdUtil.sampled(4, _repeat, weather),
			RdUtil.sampled(5, _linear, sky.atmosphere.skyview_lut.texture_rd_rid), RdUtil.sampled(6, _linear, heights),
			RdUtil.image(7, _mirror_fog), RdUtil.sampled(8, _linear, crowns)])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _volume_pipeline)
		_rd.compute_list_bind_uniform_set(list, volume_set, 0)
		_rd.compute_list_dispatch(list, ceili(CELLS.x / 8.0), ceili(CELLS.y / 8.0), 1)
		_rd.compute_list_end()
		var apply_set := UniformSetCacheRD.get_cache(_apply_shader, 0, [params,
			RdUtil.image(1, buffers.get_color_layer(view)), RdUtil.sampled(2, _nearest, buffers.get_depth_layer(view)),
			RdUtil.sampled(3, _linear, _fog_volume), RdUtil.sampled(4, _linear, _bow_volume),
			RdUtil.sampled(5, _linear, _mirror_fog)])
		list = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _apply_pipeline)
		_rd.compute_list_bind_uniform_set(list, apply_set, 0)
		_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
		_rd.compute_list_end()
