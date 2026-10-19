extends RefCounted
## The builders of the level's land, water, sky and wild life (LevelParts):
## each takes what the steps before it built, adds its shared system
## (SharedSystems) or its part of the content (CellContent) and leaves it there
## for the steps after it. A content step puts what its part gives the shared
## systems in the registries of WorldContext (docs/LEVEL.md, «Реестры»).

const LEVEL_POST = preload("res://src/alpine/level_post.gd")
const DRAGON := "res://scenes/alpine/lake_dragon.tscn"

## The sky and the weather of the region's air (RegionDef.environment), the
## environment that draws them, and the rooms of every building (Interiors).
## The weather turns what the content gives the wind (WorldContext.wind_vanes).
static func sky(s: SharedSystems) -> void:
	var air := s.region.environment
	s.sky = SkySystem.new()
	s.sky.name = "Sky"
	s.sky.take(air)
	GameClock.begin(air.start_hour)
	s.sky.viewer = s.camera
	# The weather first: the sky then draws the state of the same frame.
	s.weather = WeatherSystem.new()
	s.weather.name = "Weather"
	s.weather.sky = s.sky
	s.weather.viewer = s.camera
	s.weather.vanes = s.world.wind_vanes
	s.add(s.weather)
	if air.start_weather != s.weather.kind:
		s.weather.set_weather(air.start_weather, true)
	s.add(s.sky)
	s.environment.environment = RealismEnvironment.build(s.sky.make_sky(), air)
	s.sky.environment = s.environment.environment
	s.world.interiors = Interiors.new()
	s.world.interiors.name = "Interiors"
	s.world.interiors.sky = s.sky
	s.add(s.world.interiors)

## The generated terrain and the mountains' shadows on it.
static func terrain(s: SharedSystems) -> void:
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

## The FFT lake; its ocean raises the sea of the weather's wind. The water
## lies wherever the ground is below its level; the region's lake (its bed,
## shore and mooring) is read here for the parts after it.
static func lake(s: SharedSystems) -> void:
	s.lake = LakePlan.read(s.region.lake)
	s.water = WaterSystem.new()
	s.water.name = "Lake"
	s.water.terrain = s.terrain
	s.add(s.water)
	# Before the ocean's first frame, in which it makes its waves.
	s.water.ocean.quality = QualityProfile.of(s.world).water
	s.weather.ocean = s.water.ocean
	s.weather.set_sea(s.region.environment.start_wind, true)

## The falls below the plateau with their spray, mist and the lake's foam.
static func falls(s: SharedSystems, c: CellContent) -> void:
	c.falls = WaterfallSystem.new()
	c.falls.name = "Waterfall"
	c.falls.map = c.map
	c.falls.water = s.water
	c.falls.falls_file = s.region.falls
	c.add(c.falls)

## The brook through the village, on the falls' water; before the rocks, whose
## Blender brook stones it drops. Its bed is in the baked masks.
static func brook(s: SharedSystems, c: CellContent) -> void:
	c.brook = VillageBrook.new()
	c.brook.name = "Brook"
	c.brook.map = c.map
	c.brook.terrain = s.terrain
	c.brook.falls = c.falls
	c.add(c.brook)

## The eye's adaptation to the light; after the tavern, whose rooms it reads.
static func eye(s: SharedSystems) -> void:
	s.eye_adaptation = EyeAdaptation.new()
	s.eye_adaptation.name = "EyeAdaptation"
	s.eye_adaptation.environment = s.environment.environment
	s.eye_adaptation.sky = s.sky
	s.eye_adaptation.weather = s.weather
	s.eye_adaptation.interiors = s.world.interiors
	s.add(s.eye_adaptation)

## Scanned boulders and cliff faces in place of the Blender blockout stones;
## before the vegetation, whose obstacle scan must see their colliders.
static func rocks(s: SharedSystems, c: CellContent) -> void:
	c.rocks = RockField.new()
	c.rocks.name = "Rocks"
	c.rocks.terrain = s.terrain
	c.rocks.map = c.map
	c.rocks.layout = s.region.rocks
	c.rocks.cliff = s.region.cliff
	c.add(c.rocks)
	s.world.interiors.watch_pieces(c.rocks)

## Trees placed from the terrain masks, kept off the Blender buildings, and
## what they have shed onto the ground.
static func vegetation(s: SharedSystems, c: CellContent) -> void:
	c.vegetation = VegetationSystem.new()
	c.vegetation.name = "Vegetation"
	c.vegetation.terrain = s.terrain
	c.vegetation.world = s.world
	c.vegetation.map = c.map
	c.vegetation.scope = s.level
	# The rays that find the buildings' footprints pass the rocks: the village's
	# trees and the grass stand among them.
	c.vegetation.exclude = [s.player.get_rid()]
	if c.rocks != null:
		for body: CollisionObject3D in c.rocks.find_children("*", "CollisionObject3D", true, false):
			c.vegetation.exclude.append(body.get_rid())
	c.add(c.vegetation)
	if c.vegetation.grass.canopy != null:
		s.world.canopies.add(c.vegetation, c.vegetation.grass.canopy)
	var litter := ForestLitter.new()
	litter.name = "Litter"
	litter.terrain = s.terrain
	litter.woods = c.vegetation.grid
	litter.canopy = c.vegetation.grass.canopy
	litter.rocks = c.rocks
	c.add(litter)

## The compositor passes (level_post.gd), and what a storm adds to the land.
## The fog and the eye read the content's canopy (WorldContext.canopies).
static func post(s: SharedSystems) -> void:
	s.post = LEVEL_POST.new(s.sky, s.weather, s.terrain, s.water, s.sun_shadow, s.world, s.eye_adaptation,
		s.environment)
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
	s.rain_fall.world = s.world
	s.add(s.rain_fall)

## The wild animals, the birds and the fish; they are placed once the
## colliders stand (Level, step "placement").
static func wildlife(s: SharedSystems, c: CellContent) -> void:
	c.wildlife = WildlifeSystem.new()
	c.wildlife.name = "Wildlife"
	c.wildlife.wildlife = s.region.wildlife
	c.wildlife.auto_populate = false
	c.wildlife.terrain = s.terrain
	c.wildlife.player = s.player
	c.wildlife.water = s.water
	c.wildlife.lake = s.lake
	c.wildlife.rocks = c.rocks
	c.wildlife.interiors = s.world.interiors
	c.add(c.wildlife)
	s.world.animals.add(c.wildlife, c.wildlife)

## The dragon on its circuit (RegionDef.dragon).
static func dragon(s: SharedSystems, c: CellContent) -> void:
	var scene: PackedScene = load(DRAGON)
	c.dragon = scene.instantiate() as LakeDragon
	c.dragon.circuit = s.region.dragon
	c.add(c.dragon)

## The lake's activities (the boat, the rod, the swim), its sounds, and its
## shore's waves and wakes.
static func lakeside(s: SharedSystems, c: CellContent) -> void:
	c.lakeside = LakesideSystem.new()
	c.lakeside.plan = s.lake
	c.lakeside.player = s.player
	c.lakeside.terrain = s.terrain
	c.lakeside.water = s.water
	c.lakeside.interactions = s.interactions
	c.lakeside.camping = s.camping
	c.add(c.lakeside)
	s.world.water_probes.add(c.lakeside, c.lakeside.probe_points)
	var audio := LakeSoundscape.new()
	audio.player = s.player
	audio.water = s.water
	audio.terrain = s.terrain
	audio.activities = c.lakeside
	c.add(audio)
	c.lakeside.soundscape = audio
	var shore := LakeShore.new()
	shore.water = s.water
	shore.terrain = s.terrain
	shore.activities = c.lakeside
	shore.field = s.lake.shore_field
	c.add(shore)

## The view through the lake's surface; after the lakeside, whose shore it
## sees. It looks through the whole level (LakeRefraction.scope).
static func refraction(s: SharedSystems) -> void:
	s.refraction = LakeRefraction.new()
	s.refraction.water = s.water
	s.refraction.world = s.world
	s.refraction.scope = s.level
	s.refraction.environment = s.environment
	s.add(s.refraction)

## The map of where the rain falls (RainShelter) round the region's middle
## (RegionDef.shelter_centre). It is drawn once the content stands
## (WorldContext.shelters).
static func shelter(s: SharedSystems) -> void:
	s.rain_shelter = RainShelter.new()
	s.rain_shelter.terrain = s.terrain
	s.rain_shelter.centre = s.region.shelter_centre
	s.rain_shelter.interiors = s.world.interiors
	s.rain_shelter.world = s.world
	s.add(s.rain_shelter)
