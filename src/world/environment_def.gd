@tool
class_name EnvironmentDef
extends Resource
## The air, the season and the look of the ground of a region
## (RegionDef.environment): where on the globe it lies and on which day the
## game starts, the weather it starts with, the fog of its air and the grade of
## its terrain's layers. The level gives them to the sky, the weather, the
## environment and the terrain as it builds them (LevelNature). A plain
## record: the tests load it with the region before the game's autoloads
## stand, so it names none of the systems that read it.

## The layers of the terrain's textures (terrain.gdshader: layer_tile,
## layer_grade).
const LAYERS := 15

@export_group("Sky")
## Where the region lies and the day of the year: the sun's and the moon's
## way across the sky (SkySystem.solar_direction).
@export var latitude_deg := 0.0
@export var day_of_year := 1
## The hour of the day a new game starts at (GameClock.begin).
@export var start_hour := 12.0
## The height of the region's y = 0 above the sea, km (SkyAtmosphere): high
## ground has thin air above it and a deep blue zenith.
@export var ground_altitude_km := 0.0
## The moon's light (SkySystem.moon).
@export var moon_colour := Color.WHITE

@export_group("Weather")
## The kind of weather a new game starts with (WeatherTable) and the wind on
## the water (OceanFFT.PRESETS).
@export var start_weather := "fair"
@export var start_wind := "calm"

@export_group("Fog")
## The fog of the region's air (RealismEnvironment.build): its density, its
## colour, how much of the sun it scatters, the height it thins out above
## and how fast it thins there.
@export var fog_density := 0.0
@export var fog_light_colour := Color.WHITE
@export var fog_sun_scatter := 0.0
@export var fog_height := 0.0
@export var fog_height_density := 0.0

@export_group("Ground")
## Metres to a repeat of each layer of the terrain (the L_* of
## terrain.gdshader), and the rgb tint and saturation of each (grade() of the
## shader). One entry per layer of the region's terrain textures
## (RegionDef.terrain_dir).
@export var layer_tiles := PackedFloat32Array()
@export var layer_grades: Array[Vector4] = []

## Gives `environment` the region's fog.
func apply_fog(environment: Environment) -> void:
	environment.fog_density = fog_density
	environment.fog_light_color = fog_light_colour
	environment.fog_sun_scatter = fog_sun_scatter
	environment.fog_height = fog_height
	environment.fog_height_density = fog_height_density

## What is wrong with these: a weather or a wind no table has, a layer
## without its repeat or its grade.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if not start_weather in WeatherTable.KINDS:
		found.append("no such weather: %s" % start_weather)
	if not OceanFFT.PRESETS.has(start_wind):
		found.append("no such wind: %s" % start_wind)
	if layer_tiles.size() != LAYERS or layer_grades.size() != LAYERS:
		found.append("%d layer repeats and %d layer grades for %d layers" % [layer_tiles.size(), layer_grades.size(), LAYERS])
	return found
