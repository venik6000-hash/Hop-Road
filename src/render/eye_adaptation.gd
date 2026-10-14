class_name EyeAdaptation
extends Node
## The exposure follows what the eye is in and what it looks at. Where it
## stands gives the gain of the place: open daylight keeps the look as it was
## authored, a room, a wood and the night open the exposure up. What it sees
## moves the gain about that one: the picture is metered as a camera meters
## it (LightMeter), so a look into the shade opens the exposure further and a
## look at lamps or at the lit land from under a roof closes it. The eye
## closes within a second or two on the way into the light, which blinds it
## for that while, and opens over several seconds on the way into the dark.
## There it loses colour as well, and a closed sky's flat light takes a little
## of the colour and of the contrast by day.
##
## The haze of the valley's air (the environment's height fog) is laid over
## everything below its top by as much whatever the distance, so in a room it
## is a pale blue veil over every dark corner: it goes as the eye comes in.
## The rooms' reflection probes keep the air they were captured in, so it is
## also gone until they have captured their rooms the first time.
##
## The exposure is written to the environment's tonemap exposure, which the
## mug's own viewport copies every frame, so the hand and the world stay
## exposed alike.

const CanopyField = preload("res://src/vegetation/canopy_field.gd")

## Gain over the authored exposure, by where the eye is.
const NIGHT_OUTDOORS := 2.6
const ROOM_BY_DAY := 1.5
const ROOM_BY_NIGHT := 1.6
## Under a storm's cloud by day, outdoors.
const STORM_OUTDOORS := 1.3
## Under the closed crowns of a wood by day.
const WOOD_BY_DAY := 1.4
## The cover of the stand round the eye (CanopyField.wooded_at) between which
## it stands in the open and in a wood.
const WOOD_COVER := Vector2(0.25, 0.7)
## The eye takes a wood in over this far round it, m: a gap between two crowns
## is no clearing, and the gain must not follow every one of them on a walk.
const WOOD_REACH := 12.0
## The eye is under the crowns up to the first height above the ground, m,
## and clear of them at the second.
const CROWN_HEIGHT := Vector2(8.0, 16.0)
## The metered light (LightMeter.stops) of the open day the look was authored
## for, and the share of a difference from it that the eye makes up.
const KEY_STOPS := -2.9
const FOLLOW := 0.45
## Stops the gain may stand under and over the gain of the place for what the
## eye sees there.
const SEEN_STOPS := Vector2(-0.5, 1.6)
## In a room the gain stands no further over the room's than this, by day and
## by night: windows, candles and a hearth light their own corners and leave
## the rest dark, and a look into a dark corner does not turn it into a lit one.
const ROOM_DAY_OVER := 0.8
const ROOM_NIGHT_OVER := 0.4
## Seconds for 63 % of the way: into the light, into the dark.
const CLOSE_SECONDS := 0.9
const OPEN_SECONDS := 3.0
## After a cut the eye is where it is at once, for as long as the meter takes
## to read the new picture.
const SETTLE_SECONDS := 0.8
## What the eye keeps of the colour in the dark, between the stops of gain
## at which it begins and has done losing it; what a closed sky leaves of the
## colour and of the contrast.
const NIGHT_COLOUR := 0.5
const NIGHT_COLOUR_STOPS := Vector2(0.7, 1.6)
const CLOSED_SKY_COLOUR := 0.9
const CLOSED_SKY_CONTRAST := 0.97
## A doorway is this deep: the gain turns over it, half of it on each side of
## a room's wall face.
const DOORWAY := 1.2
## The eye moved further than a step can in a frame: a cut, not a walk.
const CUT_DISTANCE := 4.0

var environment: Environment
var sky: SkySystem
## The weather, if the level has one: a dark sky opens the exposure a little.
var weather: WeatherSystem
## The rooms, as boxes in world space.
var rooms: Array[AABB] = []
## Where the crowns close the sky, and the ground they stand on (none without
## either: the eye is then never in a wood).
var canopy: CanopyField
var terrain: TerrainSystem
## The tavern, if the level has one: its rooms' probes are captured in clear air.
var tavern: TavernSystem
## What meters the picture (none: the eye goes by the place alone).
var meter: LightMeter
## The authored exposure the gains multiply, and the authored colour.
var base_exposure := 1.0
var base_saturation := 1.0
var base_contrast := 1.0
var base_haze := 0.0
var gain := 1.0
## The light of the picture as last metered (NAN: not metered).
var seen := NAN

var _eye := Vector3.INF
var _settling := 0.0

func _ready() -> void:
	if environment != null:
		base_exposure = environment.tonemap_exposure
		base_saturation = environment.adjustment_saturation
		base_contrast = environment.adjustment_contrast
		base_haze = environment.fog_height_density

## The eye has been where it is for a while: the next frames take the gain of
## the place and the view at once (a probe that sets a view calls this).
func settle() -> void:
	_settling = SETTLE_SECONDS

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or environment == null or sky == null:
		return
	var eye := camera.global_position
	var dark := darkness(sky.sun_direction.y)
	seen = meter.stops() if meter != null else NAN
	var inside := indoors(eye, rooms)
	var wanted := seen_gain(target_gain(inside, dark, weather.gloom() if weather != null else 0.0,
		under_crowns(eye)), seen, lerpf(SEEN_STOPS.y, lerpf(ROOM_DAY_OVER, ROOM_NIGHT_OVER, dark), inside))
	if _eye == Vector3.INF or eye.distance_to(_eye) > CUT_DISTANCE:
		_settling = SETTLE_SECONDS
	_eye = eye
	if _settling > 0.0:
		_settling -= delta
		gain = wanted
	else:
		gain = adapt(gain, wanted, delta)
	var exposure := base_exposure * gain
	if not is_equal_approx(environment.tonemap_exposure, exposure):
		environment.tonemap_exposure = exposure
	var air := haze(base_haze, inside if tavern == null or tavern.probes_captured() else 1.0)
	if not is_equal_approx(environment.fog_height_density, air):
		environment.fog_height_density = air
	var look := colour(gain, dark, 1.0 - sky.sun_share, inside)
	if not is_equal_approx(environment.adjustment_saturation, base_saturation * look.x):
		environment.adjustment_saturation = base_saturation * look.x
	if not is_equal_approx(environment.adjustment_contrast, base_contrast * look.y):
		environment.adjustment_contrast = base_contrast * look.y

## 0 in daylight .. 1 at night, by the sun's height (its direction's y).
static func darkness(sun_height: float) -> float:
	return 1.0 - smoothstep(-0.1, 0.12, sun_height)

## 0 outdoors .. 1 inside a room, turning over a doorway's depth.
static func indoors(eye: Vector3, boxes: Array[AABB]) -> float:
	var deepest := -INF
	for box: AABB in boxes:
		var low := eye - box.position
		var high := box.end - eye
		deepest = maxf(deepest, minf(minf(low.x, high.x), minf(minf(low.y, high.y), minf(low.z, high.z))))
	return smoothstep(-DOORWAY * 0.5, DOORWAY * 0.5, deepest)

## 0 under the open sky .. 1 under the closed crowns of a wood.
func under_crowns(eye: Vector3) -> float:
	if canopy == null or terrain == null:
		return 0.0
	var cover := canopy.wooded_at(eye.x, eye.z)
	for corner: Vector2 in [Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]:
		cover += canopy.wooded_at(eye.x + corner.x * WOOD_REACH, eye.z + corner.y * WOOD_REACH)
	return wooded(cover / 5.0, eye.y - terrain.height_at(eye.x, eye.z))

## The same from the cover of the stand round the eye and the eye's height
## above the ground, m.
static func wooded(cover: float, above: float) -> float:
	return smoothstep(WOOD_COVER.x, WOOD_COVER.y, cover) * (1.0 - smoothstep(CROWN_HEIGHT.x, CROWN_HEIGHT.y, above))

## `gloom` is 0 under an open sky .. 1 under a storm (WeatherSystem.gloom),
## `wood` 0 in the open .. 1 under closed crowns. A dark day in a wood is
## still no darker than the night.
static func target_gain(inside: float, dark: float, gloom := 0.0, wood := 0.0) -> float:
	var day := minf(lerpf(1.0, STORM_OUTDOORS, gloom) * lerpf(1.0, WOOD_BY_DAY, wood), NIGHT_OUTDOORS)
	var outdoors := lerpf(day, NIGHT_OUTDOORS, dark)
	return lerpf(outdoors, lerpf(ROOM_BY_DAY, ROOM_BY_NIGHT, maxf(dark, gloom * 0.5)), inside)

## The gain for a place whose own gain is `place` when the picture meters
## `stops` (LightMeter.stops; NAN: not metered): the eye makes up a share of
## what the picture lacks of the authored day's light, within a reach of the
## place's gain: `over` stops above it at the most.
static func seen_gain(place: float, stops: float, over := SEEN_STOPS.y) -> float:
	if is_nan(stops):
		return place
	var of_place := log(place) / log(2.0)
	return pow(2.0, clampf((KEY_STOPS - stops) * FOLLOW, of_place + SEEN_STOPS.x, of_place + over))

## What the eye keeps of the colour (x) and of the contrast (y) at `gain`,
## with `dark` 0 by day .. 1 at night and `closed` 0 under an open sky .. 1
## under a closed one. By the fires of a room (`inside` 1) the eye loses none
## of the colour to the dark.
static func colour(gain: float, dark: float, closed: float, inside := 0.0) -> Vector2:
	var dim := dark * (1.0 - inside) * smoothstep(NIGHT_COLOUR_STOPS.x, NIGHT_COLOUR_STOPS.y, log(maxf(gain, 0.01)) / log(2.0))
	return Vector2(lerpf(1.0, NIGHT_COLOUR, dim) * lerpf(1.0, CLOSED_SKY_COLOUR, closed), lerpf(1.0, CLOSED_SKY_CONTRAST, closed))

## The valley's haze of density `authored` as the eye sees it `inside` (0
## outdoors .. 1 in a room): none between a room's walls.
static func haze(authored: float, inside: float) -> float:
	return authored * (1.0 - inside)

## One step of `delta` seconds from `current` toward `wanted`, in stops.
static func adapt(current: float, wanted: float, delta: float) -> float:
	var seconds := CLOSE_SECONDS if wanted < current else OPEN_SECONDS
	var stops := log(wanted / current)
	return current * exp(stops * (1.0 - exp(-delta / seconds)))
