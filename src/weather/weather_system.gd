class_name WeatherSystem
extends Node
## The weather: one state that the clouds, the fog, the sun and the lake read.
##
## After Bauer, "Creating the Atmospheric World of Red Dead Redemption 2"
## (SIGGRAPH 2019): a few weather and time-of-day parameters place the clouds
## and the fog, and one weather turns into the next without a cut. A kind of
## weather is a preset of that state. What draws reads the state, never the
## kind: SkySystem (cloud cover and type, cirrus, lightning inside the clouds,
## the share of the sun that reaches the ground), AtmosphereFog (haze, the
## mist over the lake, rain fog under the clouds, the fog in the woods, light
## shafts, the rainbow),
## LightningFx (the flash, the bolt, the thunder), the lake's wind, and the
## surfaces' shaders (how wet the ground is and how full its puddles).

signal weather_changed(kind: String)
## A lightning strike: {at: Vector3 (world, m), ground: bool, power: 0..1,
## seed: int, age: seconds}.
signal lightning_struck(strike: Dictionary)

const KINDS: Array[String] = ["clear", "fair", "overcast", "mist", "rain", "storm"]
const NAMES := {"clear": "Ясно", "fair": "Облачно", "overcast": "Пасмурно", "mist": "Туман",
	"rain": "Дождь", "storm": "Гроза"}
## The numbers of a state. coverage, density, cumulus: the cloud layer, as
## SkySystem's exports. darkness: 0 white fair-weather cloud .. 1 a storm's
## dark base. cirrus: the high ice cloud. haze: fog everywhere, thinning with
## height. mist: the fog bank lying on the lake. rain: rain fog under the
## clouds and drops in the air. storm: lightning. wind: the clouds' speed over
## the authored one.
const FIELDS: Array[String] = ["coverage", "density", "cumulus", "darkness", "cirrus", "haze", "mist", "rain",
	"storm", "wind"]
## "fair" is the look the level was authored with: nothing of the weather is
## drawn in it. `lake` names the wind sea that goes with a kind (OceanFFT).
const PRESETS := {
	"clear": {"coverage": 0.16, "density": 0.9, "cumulus": 0.15, "darkness": 0.0, "cirrus": 0.7, "haze": 0.0,
		"mist": 0.0, "rain": 0.0, "storm": 0.0, "wind": 0.7, "lake": "calm"},
	"fair": {"coverage": 0.42, "density": 1.0, "cumulus": 0.1, "darkness": 0.0, "cirrus": 0.0, "haze": 0.0,
		"mist": 0.0, "rain": 0.0, "storm": 0.0, "wind": 1.0, "lake": "breeze"},
	"overcast": {"coverage": 0.9, "density": 1.3, "cumulus": -0.2, "darkness": 0.15, "cirrus": 0.0, "haze": 0.35,
		"mist": 0.1, "rain": 0.0, "storm": 0.0, "wind": 1.2, "lake": "breeze"},
	"mist": {"coverage": 0.3, "density": 0.9, "cumulus": 0.0, "darkness": 0.0, "cirrus": 0.35, "haze": 0.45,
		"mist": 1.0, "rain": 0.0, "storm": 0.0, "wind": 0.4, "lake": "calm"},
	"rain": {"coverage": 0.96, "density": 1.9, "cumulus": -0.1, "darkness": 0.6, "cirrus": 0.0, "haze": 0.6,
		"mist": 0.2, "rain": 1.0, "storm": 0.0, "wind": 1.6, "lake": "choppy"},
	"storm": {"coverage": 1.0, "density": 2.6, "cumulus": 0.35, "darkness": 1.0, "cirrus": 0.0, "haze": 0.7,
		"mist": 0.0, "rain": 1.0, "storm": 1.0, "wind": 2.6, "lake": "storm"},
}
## Where the weather may go by itself, with the odds.
const NEXT := {
	"clear": {"fair": 3, "mist": 1},
	"fair": {"clear": 2, "overcast": 2},
	"overcast": {"fair": 2, "rain": 2, "mist": 1},
	"mist": {"clear": 1, "fair": 2},
	"rain": {"overcast": 2, "storm": 1, "fair": 1},
	"storm": {"rain": 2, "overcast": 1},
}
## Seconds a strike's light lasts.
const FLASH_SECONDS := 0.7
## Seconds for the drops left in the air to thin to 37 %.
const DROPLET_SECONDS := 150.0
## Seconds a rain takes to wet the open ground through, and the ground to dry
## to 37 % after it; the puddles fill and go more slowly.
const SOAK_SECONDS := 40.0
const DRY_SECONDS := 260.0
const PUDDLE_FILL_SECONDS := 110.0
const PUDDLE_DRY_SECONDS := 600.0
## How damp a mist leaves what stands in it, against a rain's 1.
const MIST_DAMP := 0.3
## The fog a rain raises in the woods, against a mist's 1.
const WOOD_IN_RAIN := 0.7
## The clock the rings in the puddles run by wraps here, s: a whole number of
## both their periods (wetness.gdshaderinc).
const RING_CLOCK_WRAP := 900.0
## How far from the viewer a strike lands, m, and the clouds' base above it.
const STRIKE_RANGE := Vector2(1200.0, 8500.0)
const CLOUD_BASE := 1700.0
## A strike's height against the base, m: low in the cloud, where its light
## still gets out through the base.
const STRIKE_HEIGHT := Vector2(-60.0, 260.0)
## Seconds between strikes at the height of a storm.
const STRIKE_PAUSE := Vector2(3.5, 11.0)
## Seconds the weather keeps a kind when it changes by itself: a quarter of an
## hour at most, against a day of 48 minutes. A storm passes sooner.
const DWELL_SECONDS := Vector2(360.0, 900.0)
const STORM_DWELL_SECONDS := Vector2(180.0, 300.0)

## Seconds one weather takes to turn into the next.
@export var transition_seconds := 25.0
## The weather changes by itself.
@export var auto := false

var sky: SkySystem
var ocean: OceanFFT
var fog: AtmosphereFog
var viewer: Node3D
var kind := "fair"
## The state now (see FIELDS).
var state: Dictionary = _fields(PRESETS.fair)
## Drops still in the air, 0..1: full under rain, thinning after it.
var droplets := 0.0
## How wet the open ground is, 0..1, and how full its puddles are: the
## surfaces' shaders read both as the global `weather_wet`.
var wetness := 0.0
var puddles := 0.0
## The strikes still shining; each as lightning_struck sends it.
var strikes: Array[Dictionary] = []
## The light of all the strikes on the ground at the viewer, 0..1.
var flash_light := 0.0

var _from: Dictionary = state
var _blend := 1.0
var _dwell := 0.0
var _strike_in := 0.0
var _rng := RandomNumberGenerator.new()
var _ring_clock := 0.0
var _wet_sent := Vector4(-1.0, 0.0, 0.0, 0.0)

func _ready() -> void:
	_rng.randomize()
	_dwell = _keep(kind)
	_apply()

func set_weather(new_kind: String, instant := false) -> void:
	if not PRESETS.has(new_kind):
		return
	kind = new_kind
	_from = state
	_blend = 1.0 if instant else 0.0
	if instant:
		state = _fields(PRESETS[kind])
		droplets = state.rain
		wetness = damp(state.rain, state.mist)
		puddles = state.rain
		strikes.clear()
	if ocean != null:
		ocean.set_preset(PRESETS[kind].lake, instant)
	_dwell = _keep(kind)
	_apply()
	weather_changed.emit(kind)

## The weather `seconds` on, without the turns between: what a sleeper wakes
## to. Weather that stands still stays as it is.
func skip(seconds: float) -> void:
	if not auto:
		return
	var later := after(kind, _dwell, seconds, _rng)
	if later.kind != kind:
		set_weather(later.kind, true)
	_dwell = later.dwell

func _keep(of_kind: String) -> float:
	var keeps := dwell_range(of_kind)
	return _rng.randf_range(keeps.x, keeps.y)

## The next (`step` 1) or the previous (-1) kind of the list.
func cycle(step: int) -> void:
	set_weather(KINDS[posmod(KINDS.find(kind) + step, KINDS.size())])

func _process(delta: float) -> void:
	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(transition_seconds, 0.01), 1.0)
		state = blend_states(_from, _fields(PRESETS[kind]), smoothstep(0.0, 1.0, _blend))
	if auto:
		_dwell -= delta
		if _dwell <= 0.0:
			set_weather(pick_next(kind, _rng))
	droplets = settle_droplets(droplets, state.rain, delta)
	wetness = soak(wetness, damp(state.rain, state.mist), delta, SOAK_SECONDS, DRY_SECONDS)
	puddles = soak(puddles, state.rain, delta, PUDDLE_FILL_SECONDS, PUDDLE_DRY_SECONDS)
	_ring_clock = fposmod(_ring_clock + delta, RING_CLOCK_WRAP)
	_strike(delta)
	_apply()

## New strikes while the storm lasts, and the light of those still shining.
func _strike(delta: float) -> void:
	if state.storm > 0.05 and viewer != null:
		_strike_in -= delta * state.storm
		if _strike_in <= 0.0:
			_strike_in = _rng.randf_range(STRIKE_PAUSE.x, STRIKE_PAUSE.y)
			var strike := make_strike(viewer.global_position, _rng)
			strikes.append(strike)
			lightning_struck.emit(strike)
	flash_light = 0.0
	for strike: Dictionary in strikes:
		strike.age += delta
		if viewer != null:
			var away: float = Vector2(strike.at.x - viewer.global_position.x, strike.at.z - viewer.global_position.z).length()
			flash_light += strike_light(strike) / (1.0 + pow(away / 2500.0, 2.0))
	var shining: Array[Dictionary] = []
	for strike: Dictionary in strikes:
		if strike.age < FLASH_SECONDS:
			shining.append(strike)
	strikes = shining
	flash_light = minf(flash_light, 1.0)

## Hands the state to what draws it.
func _apply() -> void:
	if sky != null:
		sky.cloud_coverage = state.coverage
		sky.cloud_density = state.density
		sky.cloud_cumulus_bias = state.cumulus
		sky.cloud_darkness = state.darkness
		sky.cirrus = state.cirrus
		sky.wind_scale = state.wind
		sky.sun_share = sun_share(state.coverage, state.density, state.darkness)
		sky.cloud_glow = cloud_glow(state.coverage, state.density, state.darkness)
		for index in sky.lightning.size():
			sky.lightning[index] = Vector4.ZERO
		for index in mini(strikes.size(), sky.lightning.size()):
			var strike: Dictionary = strikes[strikes.size() - 1 - index]
			# The sky marches the clouds in km, heights from the layer's base.
			sky.lightning[index] = Vector4(strike.at.x * 0.001, (strike.at.y - CLOUD_BASE) * 0.001, strike.at.z * 0.001,
				strike_light(strike))
	if fog != null:
		fog.haze = haze()
		fog.mist = mist()
		fog.rain = state.rain
		fog.wood = wood_fog(mist(), state.rain, droplets)
		fog.droplets = droplets
		fog.flash = flash_light
		fog.gloom = gloom()
	# The clock only runs while drops fall: dry ground sends nothing.
	var wet := Vector4(wetness if wetness > 0.002 else 0.0, puddles if puddles > 0.002 else 0.0, state.rain,
		_ring_clock if state.rain > 0.01 else 0.0)
	if wet != _wet_sent:
		_wet_sent = wet
		RenderingServer.global_shader_parameter_set(&"weather_wet", wet)

## Fog everywhere: the weather's own and the haze of a low sun.
func haze() -> float:
	return state.haze + (low_sun_haze(sky.sun_direction.y) if sky != null else 0.0)

## The fog bank on the lake: the weather's own, and the morning's in calm,
## dry, open weather.
func mist() -> float:
	if sky == null:
		return state.mist
	var calm: float = (1.0 - smoothstep(0.55, 0.85, state.coverage)) * (1.0 - state.rain) \
		* (1.0 - smoothstep(0.9, 1.6, state.wind))
	return maxf(state.mist, 0.7 * calm * dawn_mist(sky.sun_direction.y, sky.time_of_day))

## The fog a wood holds under its crowns, 0..1: all of it in a mist, most of
## it under rain and for as long after it as the drops hang in the air.
static func wood_fog(mist_bank: float, rain: float, drops: float) -> float:
	return clampf(maxf(mist_bank, WOOD_IN_RAIN * maxf(rain, drops)), 0.0, 1.0)

## 0 open sky .. 1 the dark under a storm: what the clouds take of the day.
func gloom() -> float:
	return (1.0 - sun_share(state.coverage, state.density, state.darkness)) * state.darkness

## The light of `strike` now, 0..1.
static func strike_light(strike: Dictionary) -> float:
	return flash(strike.age, strike.seed) * strike.power

static func _fields(preset: Dictionary) -> Dictionary:
	var values := {}
	for field: String in FIELDS:
		values[field] = float(preset[field])
	return values

static func blend_states(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var values := {}
	for field: String in FIELDS:
		values[field] = lerpf(from[field], to[field], t)
	return values

## The share of the sun's direct light that a cloud layer lets to the ground:
## all of it under broken cloud, little under a closed and dark one. Under
## broken cloud the shaders of the ground shade it in patches
## (cloud_shadow.gdshaderinc); a closed layer has no patches, and what they
## took on average is part of this share, which dims the sun's lamp for every
## material alike.
static func sun_share(coverage: float, density: float, darkness: float) -> float:
	return 1.0 - closed_sky(coverage, density) * lerpf(0.92, 0.97, darkness)

## 0 broken cloud .. 1 a layer without a gap.
static func closed_sky(coverage: float, density: float) -> float:
	return smoothstep(0.62, 0.95, coverage) * clampf(density, 0.0, 1.0)

## The light a closed layer passes down through its base: much of it under
## a pale overcast, none under a storm.
static func cloud_glow(coverage: float, density: float, darkness: float) -> float:
	return closed_sky(coverage, density) * (1.0 - darkness)

## 0..1: mist of a morning, by the sun's height (its direction's y) and the
## hour. It stands from before sunrise and burns off as the sun climbs.
static func dawn_mist(sun_height: float, hours: float) -> float:
	if hours >= 12.0:
		return 0.0
	return smoothstep(-0.3, -0.08, sun_height) * (1.0 - smoothstep(0.2, 0.5, sun_height))

## Haze that shows the shafts of a sun near the horizon.
static func low_sun_haze(sun_height: float) -> float:
	return 0.3 * smoothstep(-0.08, 0.04, sun_height) * (1.0 - smoothstep(0.18, 0.42, sun_height))

## 0..1: a strike's light `age` seconds after it began. A strike is two to
## four return strokes, each a fast decay; `seed` sets their number and times.
static func flash(age: float, seed: int) -> float:
	if age < 0.0 or age >= FLASH_SECONDS:
		return 0.0
	var light := 0.0
	var at := 0.0
	var strokes := 2 + posmod(seed, 3)
	for stroke in strokes:
		var chance := _hash(seed * 31 + stroke * 17)
		if age >= at:
			var level := 1.0 if stroke == 0 else lerpf(0.35, 0.9, chance)
			light = maxf(light, level * exp(-(age - at) / 0.055))
		at += lerpf(0.06, 0.16, _hash(seed * 13 + stroke * 7))
	# The last of it fades out instead of being cut at the end of its life.
	return light * (1.0 - smoothstep(FLASH_SECONDS * 0.7, FLASH_SECONDS, age))

static func _hash(value: int) -> float:
	return fposmod(sin(float(value) * 12.9898) * 43758.5453, 1.0)

## The drops in the air `delta` seconds on: at once as wet as the rain,
## drying slowly after it.
static func settle_droplets(current: float, rain: float, delta: float) -> float:
	return maxf(rain, current * exp(-delta / DROPLET_SECONDS))

## What the weather wets the open ground to, 0..1: a rain all the way, a mist
## a little.
static func damp(rain: float, mist_bank: float) -> float:
	return clampf(maxf(rain, mist_bank * MIST_DAMP), 0.0, 1.0)

## A wetness `delta` seconds on: it rises toward `target` over `fill_seconds`
## and falls toward it over `dry_seconds` (each to within 37 %).
static func soak(current: float, target: float, delta: float, fill_seconds: float, dry_seconds: float) -> float:
	var seconds := fill_seconds if target > current else dry_seconds
	return target + (current - target) * exp(-delta / seconds)

## Seconds a kind is kept for when the weather changes by itself (least, most).
static func dwell_range(of_kind: String) -> Vector2:
	return STORM_DWELL_SECONDS if of_kind == "storm" else DWELL_SECONDS

## The kind the weather has come to `seconds` after `from` had `dwell` seconds
## left, changing by itself, and the seconds that kind still has: {kind, dwell}.
static func after(from: String, dwell: float, seconds: float, rng: RandomNumberGenerator) -> Dictionary:
	var now := from
	var left := dwell - seconds
	while left <= 0.0:
		now = pick_next(now, rng)
		var keeps := dwell_range(now)
		left += rng.randf_range(keeps.x, keeps.y)
	return {"kind": now, "dwell": left}

static func pick_next(from: String, rng: RandomNumberGenerator) -> String:
	var odds: Dictionary = NEXT[from]
	var total := 0
	for next: String in odds:
		total += odds[next]
	var roll := rng.randi_range(1, total)
	for next: String in odds:
		roll -= odds[next]
		if roll <= 0:
			return next
	return odds.keys()[0]

## A strike at the clouds' base somewhere around `eye`. Four in ten of the near
## ones reach the ground.
static func make_strike(eye: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var bearing := rng.randf() * TAU
	var away := rng.randf_range(STRIKE_RANGE.x, STRIKE_RANGE.y)
	return {
		"at": Vector3(eye.x + cos(bearing) * away, CLOUD_BASE + rng.randf_range(STRIKE_HEIGHT.x, STRIKE_HEIGHT.y),
			eye.z + sin(bearing) * away),
		"ground": away < 6000.0 and rng.randf() < 0.4,
		"power": rng.randf_range(0.55, 1.0),
		"seed": rng.randi_range(0, 1 << 20),
		"age": 0.0,
	}
