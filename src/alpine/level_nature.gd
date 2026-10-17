extends RefCounted
## The builders of the level's land, water, sky and wild life (LevelParts):
## each takes what the steps before it built (LevelSystems), adds its system
## to the level and leaves it there for the steps after it.

const LEVEL_POST = preload("res://src/alpine/level_post.gd")
const CanopyField = preload("res://src/vegetation/canopy_field.gd")

## The sky and the weather, the environment that draws them, and the rooms of
## every building (Interiors); the old map's pieces outdoors are hidden from an
## eye in a room that sees none of them.
static func sky(s: LevelSystems) -> void:
	s.sky = SkySystem.new()
	s.sky.name = "Sky"
	s.sky.day_of_year = 225
	s.sky.time_of_day = 14.6
	s.sky.viewer = s.camera
	# The weather first: the sky then draws the state of the same frame.
	s.weather = WeatherSystem.new()
	s.weather.name = "Weather"
	s.weather.sky = s.sky
	s.weather.viewer = s.camera
	s.add(s.weather)
	s.add(s.sky)
	s.environment.environment = RealismEnvironment.build(s.sky.make_sky())
	s.sky.environment = s.environment.environment
	s.world.interiors = Interiors.new()
	s.world.interiors.name = "Interiors"
	s.world.interiors.sky = s.sky
	s.add(s.world.interiors)
	s.world.interiors.watch_pieces(s.map)

## The generated terrain and the mountains' shadows on it.
static func terrain(s: LevelSystems) -> void:
	s.terrain = TerrainSystem.new()
	s.terrain.name = "Terrain"
	s.terrain.world = s.world
	s.terrain.region = s.region
	s.add(s.terrain)
	s.sun_shadow = SunShadowField.new()
	s.sun_shadow.name = "SunShadowField"
	s.sun_shadow.terrain = s.terrain
	s.sun_shadow.sky = s.sky
	s.add(s.sun_shadow)

## The FFT lake; its ocean is the wind the weather blows.
static func lake(s: LevelSystems) -> void:
	s.water = WaterSystem.new()
	s.water.name = "Lake"
	s.water.terrain = s.terrain
	s.add(s.water)
	s.water.ocean.set_preset("breeze", true)
	s.weather.ocean = s.water.ocean

## The falls below the plateau with their spray, mist and the lake's foam.
static func falls(s: LevelSystems) -> void:
	s.falls = WaterfallSystem.new()
	s.falls.name = "Waterfall"
	s.falls.map = s.map
	s.falls.water = s.water
	s.falls.falls_file = s.region.falls
	s.add(s.falls)

## The brook through the village, on the falls' water; before the rocks, whose
## Blender brook stones it drops. Its bed is in the baked masks.
static func brook(s: LevelSystems) -> void:
	s.brook = VillageBrook.new()
	s.brook.name = "Brook"
	s.brook.map = s.map
	s.brook.terrain = s.terrain
	s.brook.falls = s.falls
	s.add(s.brook)

## The eye's adaptation to the light; after the tavern, whose rooms it reads.
static func eye(s: LevelSystems) -> void:
	s.eye_adaptation = EyeAdaptation.new()
	s.eye_adaptation.name = "EyeAdaptation"
	s.eye_adaptation.environment = s.environment.environment
	s.eye_adaptation.sky = s.sky
	s.eye_adaptation.weather = s.weather
	s.eye_adaptation.interiors = s.world.interiors
	s.add(s.eye_adaptation)

## Scanned boulders and cliff faces in place of the Blender blockout stones;
## before the vegetation, whose obstacle scan must see their colliders.
static func rocks(s: LevelSystems) -> void:
	s.rocks = RockField.new()
	s.rocks.name = "Rocks"
	s.rocks.terrain = s.terrain
	s.rocks.map = s.map
	s.rocks.layout = s.region.rocks
	s.rocks.cliff = s.region.cliff
	s.add(s.rocks)
	s.world.interiors.watch_pieces(s.rocks)

## Trees placed from the terrain masks, kept off the Blender buildings, and
## what they have shed onto the ground.
static func vegetation(s: LevelSystems) -> void:
	s.vegetation = VegetationSystem.new()
	s.vegetation.name = "Vegetation"
	s.vegetation.terrain = s.terrain
	s.vegetation.world = s.world
	s.vegetation.map = s.map
	# The rays that find the buildings' footprints pass the rocks: the village's
	# trees and the grass stand among them. Named here because a physics engine
	# may or may not answer for bodies added in this same frame.
	s.vegetation.exclude = [s.player.get_rid()]
	if s.rocks != null:
		for body: CollisionObject3D in s.rocks.find_children("*", "CollisionObject3D", true, false):
			s.vegetation.exclude.append(body.get_rid())
	s.add(s.vegetation)
	var litter := ForestLitter.new()
	litter.name = "Litter"
	litter.terrain = s.terrain
	litter.woods = s.vegetation.grid
	litter.canopy = s.vegetation.grass.canopy
	litter.rocks = s.rocks
	s.add(litter)

## The compositor passes (level_post.gd), and what a storm adds to the land;
## after the vegetation, whose canopy the fog and the eye read.
static func post(s: LevelSystems) -> void:
	var canopy: CanopyField = s.vegetation.grass.canopy if s.vegetation != null else null
	s.post = LEVEL_POST.new(s.sky, s.weather, s.terrain, s.water, s.sun_shadow, s.world.interiors, s.eye_adaptation,
		canopy, s.environment)
	s.eye_adaptation.canopy = canopy
	s.eye_adaptation.terrain = s.terrain
	var lightning := LightningFx.new()
	lightning.name = "Lightning"
	lightning.weather = s.weather
	lightning.terrain = s.terrain
	lightning.environment = s.environment.environment
	lightning.interiors = s.world.interiors
	s.add(lightning)
	var sound := WeatherSound.new()
	sound.name = "WeatherSound"
	sound.weather = s.weather
	sound.interiors = s.world.interiors
	s.add(sound)
	s.rain_fall = RainFall.new()
	s.rain_fall.weather = s.weather
	s.rain_fall.water_level = s.terrain.water_level
	s.add(s.rain_fall)

## The wild animals, the birds and the fish; they are placed once the
## colliders stand (Level, step "placement").
static func wildlife(s: LevelSystems) -> void:
	s.wildlife = WildlifeSystem.new()
	s.wildlife.name = "Wildlife"
	s.wildlife.wildlife = s.region.wildlife
	s.wildlife.auto_populate = false
	s.wildlife.terrain = s.terrain
	s.wildlife.player = s.player
	s.wildlife.sky = s.sky
	s.wildlife.water = s.water
	s.wildlife.rocks = s.rocks
	s.wildlife.interiors = s.world.interiors
	s.add(s.wildlife)

## The lake's activities (the boat, the rod, the swim), its sounds, its shore's
## waves and wakes, and the view through its surface.
static func lakeside(s: LevelSystems) -> void:
	s.lakeside = LakesideSystem.new()
	s.lakeside.player = s.player
	s.lakeside.terrain = s.terrain
	s.lakeside.water = s.water
	s.lakeside.sky = s.sky
	s.lakeside.interactions = s.interactions
	s.lakeside.camping = s.camping
	s.add(s.lakeside)
	var audio := LakeSoundscape.new()
	audio.player = s.player
	audio.water = s.water
	audio.terrain = s.terrain
	audio.sky = s.sky
	audio.activities = s.lakeside
	s.add(audio)
	s.lakeside.soundscape = audio
	var shore := LakeShore.new()
	shore.water = s.water
	shore.terrain = s.terrain
	shore.activities = s.lakeside
	s.water.shore = shore
	s.add(shore)
	var refraction := LakeRefraction.new()
	refraction.water = s.water
	refraction.world = s.world
	s.add(refraction)

## The map of where the rain falls (RainShelter) round the region's middle
## (RegionDef.shelter_centre); last: it is drawn from what stands by now.
static func shelter(s: LevelSystems) -> void:
	var rain_shelter := RainShelter.new()
	rain_shelter.terrain = s.terrain
	rain_shelter.centre = s.region.shelter_centre
	rain_shelter.interiors = s.world.interiors
	s.add(rain_shelter)
