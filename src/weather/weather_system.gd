class_name WeatherSystem
extends Node
## The weather: one state that the clouds, the fog, the sun and the lake read.
##
## After Bauer, "Creating the Atmospheric World of Red Dead Redemption 2"
## (SIGGRAPH 2019): a few weather and time-of-day parameters place the clouds
## and the fog, and one weather turns into the next without a cut. A kind of
## weather is a preset of that state (WeatherTable). What draws reads the state, never the
## kind: SkySystem (cloud cover and type, cirrus, lightning inside the clouds,
## the share of the sun that reaches the ground), AtmosphereFog (haze, the
## mist over the lake, rain fog under the clouds, the fog in the woods, light
## shafts, the rainbow),
## LightningFx (the flash, the bolt, the thunder), and the surfaces' shaders
## (how wet the ground is and how full its puddles).
##
## The wind over the ground is the weather's too: each kind raises a sea on
## the lake (its row's "lake", OceanFFT.PRESETS), and the wind of that sea
## blows everywhere, lake or not (set_sea). Each kind turns it to a heading of
## its row's "heading" (pick_heading). It is written once, as the global
## shader parameter `wind` (pack_wind), which every plant reads, with the
## gusts' way `wind_drift`; the rain, the mist and the vanes take it from
## here. The lake's ocean takes its speed only: its waves keep their own
## heading (OceanFFT.WAVE_HEADING_DEG), the lake being the reference look.

signal weather_changed(kind: String)
## A lightning strike: {at: Vector3 (world, m), ground: bool, power: 0..1,
## seed: int, age: seconds}.
signal lightning_struck(strike: Dictionary)

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
const CLOUD_BASE := SkySystem.CLOUD_BASE_KM * 1000.0
## A strike's height against the base, m: low in the cloud, where its light
## still gets out through the base.
const STRIKE_HEIGHT := Vector2(-60.0, 260.0)
## Seconds between strikes at the height of a storm.
const STRIKE_PAUSE := Vector2(3.5, 11.0)
## Seconds the weather keeps a kind when it changes by itself: a quarter of an
## hour at most, against a day of 48 minutes. A storm passes sooner.
const DWELL_SECONDS := Vector2(360.0, 900.0)
const STORM_DWELL_SECONDS := Vector2(180.0, 300.0)
## Metres at which the gusts' way wraps (`wind_drift`): ten repeats of their
## field (wind.gdshaderinc, GUST_SCALE), whose finer octave repeats 2.7 times
## as often.
const GUST_WRAP := 1800.0

## Seconds one weather takes to turn into the next; the wind comes round to
## the new weather's heading as long.
@export var transition_seconds := 25.0
## Where the wind over the ground blows to, degrees from +X toward +Z: the
## authored one until a weather turns it.
@export var wind_heading_deg := 55.0
## The weather changes by itself.
@export var auto := false

var sky: SkySystem
var ocean: OceanFFT
var fog: AtmosphereFog
var viewer: Node3D
## What the content has for the wind to turn (WorldContext.wind_vanes):
## Callable(heading: float), the heading in radians. Null in a tool without it.
var vanes: ContentRegistry
var kind := "fair"
## The state now (WeatherTable.FIELDS).
var state: Dictionary = WeatherTable.state("fair")
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
## The sea the wind raises on the lake (OceanFFT.PRESETS).
var sea := "breeze"
## The wind over the ground, m/s: it turns to the wind of a new sea over
## OceanFFT.SEA_SECONDS, as the waves do.
var wind_speed := OceanFFT.sea_wind("breeze")
## Metres the gusts have gone downwind (x, z), wrapped at GUST_WRAP: the
## global `wind_drift`.
var gust_drift := Vector2.ZERO

var _from: Dictionary = state
## The state of `kind` the transition goes to (WeatherTable.state), taken once
## at set_weather.
var _to: Dictionary = state
var _blend := 1.0
var _dwell := 0.0
var _strike_in := 0.0
var _ring_clock := 0.0
var _wet_sent := Vector4(-1.0, 0.0, 0.0, 0.0)
var _wind_from := wind_speed
var _wind_to := wind_speed
var _wind_blend := 1.0
var _heading_from := wind_heading_deg
var _heading_to := wind_heading_deg
var _heading_blend := 1.0
## The wind last written; NaN never compares equal, so the first is.
var _wind_sent := Vector4(NAN, NAN, NAN, NAN)
## The heading the vanes last turned to; NaN turns them at the next frame.
var _vanes_heading := NAN
## The weather's own chance: the kinds it goes to by itself, how long each
## stays, the strikes and the wind's headings. Seeded at random as the weather
## comes into the tree; a test seeds it to draw the same weather again.
var dice := RandomNumberGenerator.new()

func _ready() -> void:
	dice.randomize()
	_dwell = _keep(kind)
	if vanes != null:
		vanes.added.connect(_vane_added)
	apply()

## A vane came: every vane is turned to the wind at the next frame.
func _vane_added(_vane: Variant) -> void:
	_vanes_heading = NAN

func set_weather(new_kind: String, instant := false) -> void:
	if not WeatherTable.rows().has(new_kind):
		return
	kind = new_kind
	_from = state
	_to = WeatherTable.state(kind)
	_blend = 1.0 if instant else 0.0
	if instant:
		state = _to.duplicate()
		droplets = state.rain
		wetness = damp(Values.real(state.rain), Values.real(state.mist))
		puddles = state.rain
		strikes.clear()
	set_sea(str(WeatherTable.row(kind).get("lake", "breeze")), instant)
	turn_wind(pick_heading(kind, dice), instant)
	_dwell = _keep(kind)
	apply()
	weather_changed.emit(kind)

## The wind of the sea `sea_name` (OceanFFT.PRESETS) blows, at once or over
## OceanFFT.SEA_SECONDS; the lake raises that sea where there is one.
func set_sea(sea_name: String, instant := false) -> void:
	if not OceanFFT.PRESETS.has(sea_name):
		return
	sea = sea_name
	_wind_from = wind_speed
	_wind_to = OceanFFT.sea_wind(sea_name)
	_wind_blend = 1.0 if instant else 0.0
	if instant:
		wind_speed = _wind_to
	if ocean != null:
		ocean.set_preset(sea_name, instant)
	_blow()

## The weather `seconds` on, without the turns between: what a sleeper wakes
## to. Weather that stands still stays as it is.
func skip(seconds: float) -> void:
	if not auto:
		return
	var later := after(kind, _dwell, seconds, dice)
	if later.kind != kind:
		set_weather(str(later.kind), true)
	_dwell = later.dwell

## The wind comes round to `heading_deg`, at once or over transition_seconds,
## the short way.
func turn_wind(heading_deg: float, instant := false) -> void:
	_heading_from = wind_heading_deg
	_heading_to = heading_deg
	_heading_blend = 1.0 if instant else 0.0
	if instant:
		wind_heading_deg = heading_deg

## A heading, degrees 0..360, for the wind of the weather `of_kind`: one of its
## row's "heading" range (WeatherTable.headings), drawn by `rng`.
static func pick_heading(of_kind: String, rng: RandomNumberGenerator) -> float:
	var span := WeatherTable.headings(of_kind)
	return fposmod(rng.randf_range(span.x, span.y), 360.0)

## The heading `t` (0..1) of the way from `from_deg` round to `to_deg`, the
## short way, degrees 0..360.
static func turned(from_deg: float, to_deg: float, t: float) -> float:
	return fposmod(rad_to_deg(lerp_angle(deg_to_rad(from_deg), deg_to_rad(to_deg), t)), 360.0)

func _keep(of_kind: String) -> float:
	var keeps := dwell_range(of_kind)
	return dice.randf_range(keeps.x, keeps.y)

## The next (`step` 1) or the previous (-1) kind of the list.
func cycle(step: int) -> void:
	set_weather(WeatherTable.KINDS[posmod(WeatherTable.KINDS.find(kind) + step, WeatherTable.KINDS.size())])

func _process(delta: float) -> void:
	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(transition_seconds, 0.01), 1.0)
		state = blend_states(_from, _to, smoothstep(0.0, 1.0, _blend))
	if _wind_blend < 1.0:
		_wind_blend = minf(_wind_blend + delta / OceanFFT.SEA_SECONDS, 1.0)
		wind_speed = lerpf(_wind_from, _wind_to, smoothstep(0.0, 1.0, _wind_blend))
	if _heading_blend < 1.0:
		_heading_blend = minf(_heading_blend + delta / maxf(transition_seconds, 0.01), 1.0)
		wind_heading_deg = turned(_heading_from, _heading_to, smoothstep(0.0, 1.0, _heading_blend))
	gust_drift = (gust_drift + wind_over_ground() * delta).posmod(GUST_WRAP)
	RenderingServer.global_shader_parameter_set(&"wind_drift", gust_drift)
	if auto:
		_dwell -= delta
		if _dwell <= 0.0:
			set_weather(pick_next(kind, dice))
	droplets = settle_droplets(droplets, Values.real(state.rain), delta)
	wetness = soak(wetness, damp(Values.real(state.rain), Values.real(state.mist)), delta, SOAK_SECONDS, DRY_SECONDS)
	puddles = soak(puddles, Values.real(state.rain), delta, PUDDLE_FILL_SECONDS, PUDDLE_DRY_SECONDS)
	_ring_clock = fposmod(_ring_clock + delta, RING_CLOCK_WRAP)
	_strike(delta)
	apply()

## New strikes while the storm lasts, and the light of those still shining.
func _strike(delta: float) -> void:
	if state.storm > 0.05 and viewer != null:
		_strike_in -= delta * state.storm
		if _strike_in <= 0.0:
			_strike_in = dice.randf_range(STRIKE_PAUSE.x, STRIKE_PAUSE.y)
			var strike := make_strike(viewer.global_position, dice)
			strikes.append(strike)
			lightning_struck.emit(strike)
	flash_light = 0.0
	for strike: Dictionary in strikes:
		strike.age += delta
		if viewer != null:
			var away: float = Vector2(Values.real(strike.at.x - viewer.global_position.x), Values.real(strike.at.z - viewer.global_position.z)).length()
			flash_light += strike_light(strike) / (1.0 + pow(away / 2500.0, 2.0))
	var shining: Array[Dictionary] = []
	for strike: Dictionary in strikes:
		if strike.age < FLASH_SECONDS:
			shining.append(strike)
	strikes = shining
	flash_light = minf(flash_light, 1.0)

## Hands the state to what draws it. A caller that changes `state`,
## `wetness`, `puddles` or the strikes by hand calls it to show them at once.
func apply() -> void:
	if sky != null:
		sky.cloud_coverage = state.coverage
		sky.cloud_density = state.density
		sky.cloud_cumulus_bias = state.cumulus
		sky.cloud_darkness = state.darkness
		sky.cirrus = state.cirrus
		sky.wind_scale = state.wind
		sky.sun_share = sun_share(Values.real(state.coverage), Values.real(state.density), Values.real(state.darkness))
		sky.cloud_glow = cloud_glow(Values.real(state.coverage), Values.real(state.density), Values.real(state.darkness))
		sky.cloud_closed = closed_sky(Values.real(state.coverage), Values.real(state.density))
		for index in sky.lightning.size():
			sky.lightning[index] = Vector4.ZERO
		for index in mini(strikes.size(), sky.lightning.size()):
			var strike: Dictionary = strikes[strikes.size() - 1 - index]
			# The sky marches the clouds in km, heights from the layer's base.
			sky.lightning[index] = Vector4(Values.real(strike.at.x * 0.001), Values.real((strike.at.y - CLOUD_BASE) * 0.001), Values.real(strike.at.z * 0.001),
				strike_light(strike))
	if fog != null:
		fog.haze = haze()
		fog.mist = mist()
		fog.rain = state.rain
		fog.wood = wood_fog(mist(), Values.real(state.rain), droplets)
		fog.droplets = droplets
		fog.flash = flash_light
		fog.gloom = gloom()
	# The clock only runs while drops fall: dry ground sends nothing.
	var wet := Vector4(wetness if wetness > 0.002 else 0.0, puddles if puddles > 0.002 else 0.0, Values.real(state.rain),
		_ring_clock if state.rain > 0.01 else 0.0)
	if wet != _wet_sent:
		_wet_sent = wet
		RenderingServer.global_shader_parameter_set(&"weather_wet", wet)
	_blow()

## Gives the wind's speed to the lake's ocean, the wind to the global `wind`
## when it has changed, and to the vanes when it has turned.
func _blow() -> void:
	if ocean != null:
		ocean.blow(wind_speed)
	var blowing := pack_wind(wind_heading_deg, wind_speed)
	if blowing != _wind_sent:
		_wind_sent = blowing
		RenderingServer.global_shader_parameter_set(&"wind", blowing)
	if vanes != null and wind_heading_deg != _vanes_heading:
		_vanes_heading = wind_heading_deg
		for vane: Variant in vanes.entries():
			var turn: Callable = vane
			turn.call(deg_to_rad(wind_heading_deg))

## The wind over the ground, m/s along x and z.
func wind_over_ground() -> Vector2:
	var heading := deg_to_rad(wind_heading_deg)
	return Vector2(cos(heading), sin(heading)) * wind_speed

## The wind as the global `wind` holds it: (x, z of the way it blows to, unit
## length; strength, 0 calm .. 1 a fresh breeze .. 2.2 a storm; speed m/s).
## Pressure grows with the square of the speed: a storm bends hard.
static func pack_wind(heading_deg: float, speed: float) -> Vector4:
	var heading := deg_to_rad(heading_deg)
	return Vector4(cos(heading), sin(heading), minf(pow(speed / 9.0, 1.6), 2.2), speed)

## Fog everywhere: the weather's own and the haze of a low sun.
func haze() -> float:
	return state.haze + (low_sun_haze(sky.sun_direction.y) if sky != null else 0.0)

## The fog bank on the lake: the weather's own, and the morning's in calm,
## dry, open weather.
func mist() -> float:
	if sky == null:
		return state.mist
	var calm: float = (1.0 - smoothstep(0.55, 0.85, Values.real(state.coverage))) * (1.0 - state.rain) \
		* (1.0 - smoothstep(0.9, 1.6, Values.real(state.wind)))
	return maxf(Values.real(state.mist), 0.7 * calm * dawn_mist(sky.sun_direction.y, GameClock.hour()))

## The fog a wood holds under its crowns, 0..1: all of it in a mist, most of
## it under rain and for as long after it as the drops hang in the air.
static func wood_fog(mist_bank: float, rain: float, drops: float) -> float:
	return clampf(maxf(mist_bank, WOOD_IN_RAIN * maxf(rain, drops)), 0.0, 1.0)

## 0 open sky .. 1 the dark under a storm: what the clouds take of the day.
func gloom() -> float:
	return (1.0 - sun_share(Values.real(state.coverage), Values.real(state.density), Values.real(state.darkness))) * state.darkness

## The light of `strike` now, 0..1.
static func strike_light(strike: Dictionary) -> float:
	return flash(Values.real(strike.age), Values.whole(strike.seed)) * strike.power

static func blend_states(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var values := {}
	for field: String in WeatherTable.FIELDS:
		values[field] = lerpf(Values.real(from[field]), Values.real(to[field]), t)
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
	var odds: Dictionary = WeatherTable.row(from).get("next", {})
	if odds.is_empty():
		return from
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
