class_name SkySystem
extends Node3D
## Sun, moon, physically based sky and drifting clouds as one unit.
##
## The sun position comes from the solar-position formulae for a latitude and
## a day of the year, the sun lamp's colour from the same atmosphere that
## paints the sky, so a low sun turns the light and the sky orange together.
## World axes: -Z is north, +X is east, +Y is up.

signal time_changed(hours: float)

const SKY_SHADER := preload("res://src/sky/sky.gdshader")

@export_range(0.0, 24.0, 0.01) var time_of_day := 15.6:
	set(value):
		time_of_day = fposmod(value, 24.0)
		time_changed.emit(time_of_day)
## Real minutes the day (DayClock.DAY_START to DAY_END) and the night take;
## the clock stands while either is 0.
@export var day_minutes := 0.0
@export var night_minutes := 0.0
@export var latitude_deg := 47.0
@export var day_of_year := 200
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

func _ready() -> void:
	atmosphere = SkyAtmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	sun = _make_light("Sun", true)
	moon = _make_light("Moon", false)
	moon.light_color = Color(0.62, 0.72, 1.0)
	sky_material.shader = SKY_SHADER
	# Godot's array-reflection path overwrites the temporary quarter-res mip
	# before geometry consumes it. Keep the original pass in other backends
	# or the single-texture incremental path, where it can remain visible.
	sky_material.set_shader_parameter("skip_cubemap_quarter_pass",
		RenderingServer.get_current_rendering_method() == "forward_plus" and bool(
			ProjectSettings.get_setting_with_override("rendering/reflections/sky_reflections/texture_array_reflections")))
	sky_material.set_shader_parameter("cloud_shape", load("res://assets/generated/sky/cloud_shape.png"))
	sky_material.set_shader_parameter("cloud_detail", load("res://assets/generated/sky/cloud_detail.png"))
	sky_material.set_shader_parameter("cloud_weather", load("res://assets/generated/sky/cloud_weather.png"))
	sky_material.set_shader_parameter("cloud_cirrus", load("res://assets/generated/sky/cloud_cirrus.png"))
	_update(0.0)

func _make_light(light_name: String, casts: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = light_name
	light.shadow_enabled = casts
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 160.0
	light.directional_shadow_split_1 = 0.06
	light.directional_shadow_split_2 = 0.18
	light.directional_shadow_split_3 = 0.45
	light.directional_shadow_blend_splits = true
	light.directional_shadow_fade_start = 0.85
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 1.2
	light.light_angular_distance = 0.53
	light.light_specular = 1.0
	add_child(light)
	return light

func make_sky() -> Sky:
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	return sky

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	if day_minutes > 0.0 and night_minutes > 0.0:
		time_of_day += DayClock.hours_after(time_of_day, delta, day_minutes, night_minutes)
	sun_direction = solar_direction(time_of_day, latitude_deg, day_of_year)
	# The moon trails the sun by roughly half a day (a full moon night).
	moon_direction = solar_direction(time_of_day + 12.4, latitude_deg, day_of_year + 3)
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
	_set_global(7, &"weather_sky", Vector4(cirrus, cloud_glow, 0.0, 0.0))
	_set_global(8, &"lightning_a", lightning[0])
	_set_global(9, &"lightning_b", lightning[1])

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
