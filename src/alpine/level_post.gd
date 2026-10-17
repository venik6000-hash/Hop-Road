extends RefCounted
## The level's compositor passes, for every camera: the contact shadows of the
## rooms' lamps on the opaque picture (Interiors.contact); then, after the transparent things,
## the hot air and the rain's rings, the weather's fog, the eye's light meter,
## and the underwater view, waterline and vignette. The level gives it the
## frame's inputs from its _process (update).

## Height above the lake level that no wave crest reaches: five times the
## storm preset's significant height at the largest local wave scale. An eye
## above it lets the lens pass skip its water block.
const LENS_CREST_BOUND := 30.0
const CanopyField = preload("res://src/vegetation/canopy_field.gd")

var fog: AtmosphereFog
var _interiors: Interiors
var refraction: RefractionPost
var lens: LensPost
var _sky: SkySystem
var _weather: WeatherSystem
var _terrain: TerrainSystem
var _water: WaterSystem
# Inputs of the last lens updates.
var _water_valid := false
var _level := 0.0
var _tiles := Vector4.ZERO
var _weights := Vector4.ZERO
var _eye_x := 0.0
var _eye_z := 0.0
var _sun_valid := false
var _sun_direction := Vector3.ZERO
var _sun_radiance := Vector3.ZERO
var _viewer_radius := 0.0

## After the vegetation, whose canopy the fog reads.
func _init(sky: SkySystem, weather: WeatherSystem, terrain: TerrainSystem, water: WaterSystem, sun_shadow: SunShadowField,
		interiors: Interiors, eye_adaptation: EyeAdaptation, canopy: CanopyField, environment: WorldEnvironment) -> void:
	_sky = sky
	_weather = weather
	_terrain = terrain
	_water = water
	fog = AtmosphereFog.new()
	fog.sky = _sky
	fog.terrain = _terrain
	fog.sun_shadow = sun_shadow
	fog.canopy = canopy
	fog.weather_map = load("res://assets/generated/sky/cloud_weather.png")
	_interiors = interiors
	fog.interiors = interiors
	_weather.fog = fog
	lens = LensPost.new()
	lens.skyview = _sky.atmosphere.skyview_lut
	lens.transmittance = _sky.atmosphere.transmittance_lut
	lens.displacement = _water.ocean.displacement_texture
	# First what bends the picture itself (hot air, the rain's rings on the
	# lake), then the fog that lies before it all, then the lens.
	refraction = RefractionPost.new()
	# The eye meters the picture as the air leaves it, before the lens darkens
	# its corners.
	eye_adaptation.meter = LightMeter.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [interiors.contact, refraction, fog, eye_adaptation.meter, lens]
	environment.compositor = compositor

## The inputs of this frame's passes, seen from `eye`.
func update(delta: float, eye: Vector3, tree: SceneTree) -> void:
	var ocean := _water.ocean
	var wind_heading := deg_to_rad(ocean.wind_direction_deg)
	fog.wind = Vector2(cos(wind_heading), sin(wind_heading)) * ocean.wind_speed
	fog.wave_height = ocean.significant_height()
	fog.building = _interiors.fog_box(eye)
	fog.prepare(delta, eye, tree.get_nodes_in_group(AtmosphereFog.LAMP_GROUP) if fog.active() else [])
	var falling := RainFall.amount(Values.real(_weather.state.rain), Values.real(_weather.state.storm))
	# The lake lies within the rings' view where the ground dips under its level.
	var lake_near := falling > 0.0 and _terrain.height_range(Rect2(eye.x - RefractionPost.RING_VIEW, eye.z - RefractionPost.RING_VIEW,
		RefractionPost.RING_VIEW * 2.0, RefractionPost.RING_VIEW * 2.0)).x < _water.water_level
	refraction.prepare(delta, eye, tree.get_nodes_in_group(RefractionPost.HEAT_GROUP), falling, _water.water_level, lake_near,
		fog.wave_height)
	# The lens only takes new values when an input changed: the same inputs
	# give the same packed parameters. wave_scale_at() depends on the eye's
	# x/z, the lake level and fixed fields.
	if not _water_valid or _water.water_level != _level or ocean.tiles != _tiles \
			or ocean.cascade_weights != _weights or eye.x != _eye_x or eye.z != _eye_z:
		_water_valid = true
		_level = _water.water_level
		_tiles = ocean.tiles
		_weights = ocean.cascade_weights
		_eye_x = eye.x
		_eye_z = eye.z
		lens.set_water(_water.water_level, ocean.tiles, ocean.cascade_weights * _water.wave_scale_at(eye.x, eye.z),
			WaterSystem.ABSORPTION + WaterSystem.SCATTERING, WaterSystem.SCATTERING, LENS_CREST_BOUND)
	var sun_radiance := Vector3.ONE * _sky.sun_energy * PI
	var viewer_radius := _sky.atmosphere.viewer_radius_km()
	if not _sun_valid or _sky.sun_direction != _sun_direction \
			or sun_radiance != _sun_radiance or viewer_radius != _viewer_radius:
		_sun_valid = true
		_sun_direction = _sky.sun_direction
		_sun_radiance = sun_radiance
		_viewer_radius = viewer_radius
		lens.set_sun(_sky.sun_direction, sun_radiance, viewer_radius)
