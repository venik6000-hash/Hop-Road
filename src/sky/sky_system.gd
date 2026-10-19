class_name SkySystem
extends Node3D
## Sun, moon, physically based sky and drifting clouds as one unit.
##
## The sun position comes from the solar-position formulae for a latitude and
## a day of the year, the sun lamp's colour from the same atmosphere that
## paints the sky, so a low sun turns the light and the sky orange together.
## World axes: -Z is north, +X is east, +Y is up. The hour is the game's
## (GameClock): the sky draws it and does not keep one of its own.

const SKY_SHADER := preload("res://src/sky/sky.gdshader")
## The sky's weather map: the global `cloud_weather` (cloud_weather.gdshaderinc)
## that the clouds, their shadows and the wind's gusts read.
const WEATHER_MAP := "res://assets/generated/sky/cloud_weather.png"
## The cloud layer: its base above y = 0 and its thickness, km, and how many
## repeats of the weather map a km of it holds (cloud_layer()).
const CLOUD_BASE_KM := 1.7
const CLOUD_THICKNESS_KM := 3.2
const CLOUD_MAP_FREQUENCY := 0.016
## The lamp_dusk over which a lamp that is only on or off burns.
const LIT_DUSK := 0.01

## Where the region lies, the day of the year, the height of its ground
## (km, SkyAtmosphere) and the moon's light: the region's (take), set before
## the sky enters the tree.
@export var latitude_deg := 0.0
@export var day_of_year := 1
@export var ground_altitude_km := 0.0
@export var moon_colour := Color.WHITE
## Top-of-atmosphere sun intensity in Godot light units.
@export var sun_energy := 4.0
## The full moon's light at its height, in the same units: enough to walk by.
@export var moon_energy := 0.5
## The light a moonlit sky sends into the moon's shade, as a share of the
## moon's own: the air that scatters it is not in the sky's shader, so it is
## given to the environment's ambient colour (see `environment`).
@export var night_fill := 0.5
## The share of the sun's light on level ground that the lit land sends back
## into the shade, by channel: grass and earth return a warm light, and
## without it the shade has the sky's blue alone.
@export var ground_bounce := Vector3(0.2, 0.176, 0.104)
@export_range(0.0, 1.0) var cloud_coverage := 0.42
@export_range(0.1, 3.0) var cloud_density := 1.0
@export_range(-0.5, 0.5) var cloud_cumulus_bias := 0.1
## Wind at cloud altitude, metres per second (x east, y south).
@export var cloud_wind := Vector2(9.0, 3.5)
## What the weather adds (WeatherSystem writes these). 0 white fair-weather
## cloud .. 1 a storm's dark base.
var cloud_darkness := 0.0
## 0 a broken layer .. 1 a layer without a gap (WeatherSystem.closed_sky): a
## closed layer casts no patches of shadow.
var cloud_closed := 0.0
## The high ice cloud above the layer, 0 none .. 1 a streaked sky.
var cirrus := 0.0
## Light a closed layer passes down through its base: 0 broken or storm
## cloud .. 1 a pale overcast.
var cloud_glow := 0.0
## The clouds' speed over `cloud_wind`.
var wind_scale := 1.0
## The share of the sun's direct light a closed cloud layer lets through.
var sun_share := 1.0
## Strikes shining inside the clouds: x, z in km of world space, y in km above
## the layer's base, w the light now (0 none).
var lightning: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO]

var atmosphere: SkyAtmosphere
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material := ShaderMaterial.new()
var sun_direction := Vector3.UP
var moon_direction := Vector3.DOWN
## 0 by day .. 1 at night: how far the lamps are lit (dusk_of), the global
## `lamp_dusk` too. Every lamp, lantern and far light burns by it.
var lamp_dusk := 0.0
## The sun's and the moon's light at the viewer above the clouds, as pi times
## the irradiance in Godot light units (what the sky's LUTs are scaled by):
## the air between has taken its share, the weather has not.
var sun_irradiance := Vector3.ZERO
var moon_irradiance := Vector3.ZERO
var cloud_offset := Vector2(37.0, 12.0)
var viewer: Node3D
## The environment whose ambient colour takes the land's bounce by day and
## the moonlit sky's light by night (none: neither).
var environment: Environment
## The global shader parameter values _update last set (see _set_global).
var _globals_sent: Array = []
var _globals_valid := PackedByteArray()

## Takes the latitude, the day, the height of the ground and the moon's light
## of the region's environment `air`; before the sky enters the tree.
func take(air: EnvironmentDef) -> void:
	latitude_deg = air.latitude_deg
	day_of_year = air.day_of_year
	ground_altitude_km = air.ground_altitude_km
	moon_colour = air.moon_colour

func _ready() -> void:
	atmosphere = SkyAtmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.ground_altitude_km = ground_altitude_km
	add_child(atmosphere)
	sun = _make_light("Sun", true)
	moon = _make_light("Moon", false)
	# The authored shadows until RenderQuality applies the level's profile.
	apply_shadows(QualityProfile.named(QualityProfile.AUTHORED).shadows)
	moon.light_color = moon_colour
	sky_material.shader = SKY_SHADER
	# Godot's array-reflection path overwrites the temporary quarter-res mip
	# before geometry consumes it. Keep the original pass in other backends
	# or the single-texture incremental path, where it can remain visible.
	sky_material.set_shader_parameter("skip_cubemap_quarter_pass",
		RenderingServer.get_current_rendering_method() == "forward_plus" and Values.flag(
			ProjectSettings.get_setting_with_override("rendering/reflections/sky_reflections/texture_array_reflections")))
	sky_material.set_shader_parameter("cloud_shape", load("res://assets/generated/sky/cloud_shape.png"))
	sky_material.set_shader_parameter("cloud_detail", load("res://assets/generated/sky/cloud_detail.png"))
	# A texture global is set once (docs/PERFORMANCE.md, rule 11).
	RenderingServer.global_shader_parameter_set(&"cloud_weather", load(WEATHER_MAP))
	sky_material.set_shader_parameter("cloud_cirrus", load("res://assets/generated/sky/cloud_cirrus.png"))
	_update(0.0)

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"cloud_weather", null)

func _make_light(light_name: String, casts: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = light_name
	light.shadow_enabled = casts
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.light_angular_distance = 0.53
	light.light_specular = 1.0
	add_child(light)
	return light

## Gives the sun and the moon the cascades, the reach and the biases of
## `shadows` (a level of the profile's shadow group). The level's reach
## follows from WorldContext.set_shadow_reach, which takes less in a room.
func apply_shadows(shadows: QualityShadows) -> void:
	for light: DirectionalLight3D in [sun, moon]:
		light.directional_shadow_max_distance = shadows.distance
		light.directional_shadow_split_1 = shadows.splits.x
		light.directional_shadow_split_2 = shadows.splits.y
		light.directional_shadow_split_3 = shadows.splits.z
		light.directional_shadow_blend_splits = shadows.blend
		light.directional_shadow_fade_start = shadows.fade_start
		light.shadow_bias = shadows.bias
		light.shadow_normal_bias = shadows.normal_bias

func make_sky() -> Sky:
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	return sky

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	var hour := GameClock.hour()
	sun_direction = solar_direction(hour, latitude_deg, day_of_year)
	# The moon trails the sun by roughly half a day (a full moon night).
	moon_direction = solar_direction(hour + 12.4, latitude_deg, day_of_year + 3)
	cloud_offset += cloud_wind * 0.001 * delta * wind_scale
	if viewer != null:
		atmosphere.viewer_height_m = viewer.global_position.y
	atmosphere.sun_direction = sun_direction

	var through := atmosphere.transmittance_toward(sun_direction)
	var peak := maxf(through.x, maxf(through.y, through.z))
	# Fade the lamp through the last half degree instead of popping off.
	var horizon := smoothstep(-0.01, 0.02, sun_direction.y)
	_aim(sun, sun_direction)
	var tint := through / maxf(peak, 1e-4)
	sun.light_color = Color(tint.x, tint.y, tint.z)
	sun.light_energy = sun_energy * peak * horizon * sun_share
	sun.visible = sun.light_energy > 0.001
	sun_irradiance = through * (sun_energy * PI * horizon)

	lamp_dusk = dusk_of(sun_direction.y)
	var night := 1.0 - smoothstep(-0.12, 0.02, sun_direction.y)
	_aim(moon, moon_direction)
	var moonlight := moon_energy * night * smoothstep(0.0, 0.1, moon_direction.y)
	moon.light_energy = moonlight * sun_share
	moon.visible = moon.light_energy > 0.001
	moon_irradiance = Vector3(moon.light_color.r, moon.light_color.g, moon.light_color.b) * (moonlight * PI)
	moon.shadow_enabled = not sun.visible
	if environment != null:
		# A closed sky spreads the moon's light and keeps half of it.
		var by_moon := moon.light_color.srgb_to_linear() * (moon_energy * night_fill * night * lerpf(0.5, 1.0, sun_share))
		var by_sun := sun.light_color.srgb_to_linear() * (sun.light_energy * maxf(sun_direction.y, 0.0))
		# The environment takes its colours in sRGB.
		var colour := Color(by_moon.r + by_sun.r * ground_bounce.x, by_moon.g + by_sun.g * ground_bounce.y,
			by_moon.b + by_sun.b * ground_bounce.z).linear_to_srgb()
		if not environment.ambient_light_color.is_equal_approx(colour):
			environment.ambient_light_color = colour

	var radiance := Vector3.ONE * sun_energy * PI
	_set_global(0, &"sun_direction", sun_direction)
	_set_global(1, &"sun_radiance_scale", radiance)
	_set_global(2, &"atmo_view_radius", atmosphere.viewer_radius_km())
	_set_global(3, &"moon_direction", moon_direction)
	_set_global(4, &"night_factor", night)
	_set_global(5, &"cloud_params", Vector4(cloud_coverage, cloud_density, cloud_cumulus_bias, cloud_darkness))
	_set_global(6, &"cloud_offset", cloud_offset)
	_set_global(7, &"weather_sky", Vector4(cirrus, cloud_glow, cloud_closed, 0.0))
	_set_global(8, &"lightning_a", lightning[0])
	_set_global(9, &"lightning_b", lightning[1])
	_set_global(10, &"lamp_dusk", lamp_dusk)
	_set_global(11, &"cloud_layer", cloud_layer())

## The global `cloud_layer` (cloud_weather.gdshaderinc): x the layer's base,
## km; y its thickness, km; z the weather map's repeats a km; w the height of
## its middle, m, where the ground and the fog take the clouds' shadows.
static func cloud_layer() -> Vector4:
	return Vector4(CLOUD_BASE_KM, CLOUD_THICKNESS_KM, CLOUD_MAP_FREQUENCY, (CLOUD_BASE_KM + CLOUD_THICKNESS_KM * 0.5) * 1000.0)

## Sets a global shader parameter unless this node already set it to the same
## value (only SkySystem writes these globals). `slot` indexes _globals_sent.
func _set_global(slot: int, parameter: StringName, value: Variant) -> void:
	if _globals_sent.size() <= slot:
		_globals_sent.resize(slot + 1)
		_globals_valid.resize(slot + 1)
	if _globals_valid[slot] and typeof(_globals_sent[slot]) == typeof(value) and _globals_sent[slot] == value:
		return
	RenderingServer.global_shader_parameter_set(parameter, value)
	_globals_sent[slot] = value
	_globals_valid[slot] = 1

func _aim(light: DirectionalLight3D, toward: Vector3) -> void:
	var up := Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD
	light.global_transform = Transform3D(Basis.looking_at(-toward, up), light.global_position)

## How far the lamps are lit with the sun at `sun_height` (its direction's
## y): none with the sun 10 degrees up, all of them once it has set. The
## lamps are lit by the sun, not by the hour (the owner's rule): the dusk
## comes at its own hour in each season and latitude.
static func dusk_of(sun_height: float) -> float:
	return 1.0 - smoothstep(-0.02, 0.18, sun_height)

## Unit vector toward the sun for local solar time `hours`.
static func solar_direction(hours: float, latitude: float, day: int) -> Vector3:
	var declination := deg_to_rad(23.44) * sin(TAU * (284.0 + day) / 365.0)
	var hour_angle := deg_to_rad(15.0 * (hours - 12.0))
	var lat := deg_to_rad(latitude)
	var elevation := asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hour_angle))
	var azimuth := atan2(sin(hour_angle), cos(hour_angle) * sin(lat) - tan(declination) * cos(lat))
	# azimuth measured from south, positive toward west; convert to world axes.
	var flat := cos(elevation)
	return Vector3(-flat * sin(azimuth), sin(elevation), flat * cos(azimuth)).normalized()
