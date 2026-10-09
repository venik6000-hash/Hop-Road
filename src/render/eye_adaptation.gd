class_name EyeAdaptation
extends Node
## The exposure follows what the eye is in: open daylight keeps the look as it
## was authored, a room and the night open the exposure up. It closes fast on
## the way into the light and opens slowly on the way into the dark, as an eye
## (and a camera's metering) does.
##
## The scene is not metered on the GPU: where the eye stands and where the sun
## is are known, so the answer costs nothing and does not pump with the view.
## It is written to the environment's tonemap exposure, which the mug's own
## viewport copies every frame, so the hand and the world stay exposed alike.

## Gain over the authored exposure, by where the eye is.
const NIGHT_OUTDOORS := 1.45
const ROOM_BY_DAY := 1.5
const ROOM_BY_NIGHT := 1.9
## Under a storm's cloud by day, outdoors.
const STORM_OUTDOORS := 1.3
## Seconds for 63 % of the way: into the light, into the dark.
const CLOSE_SECONDS := 0.35
const OPEN_SECONDS := 1.6
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
## The authored exposure the gains multiply.
var base_exposure := 1.0
var gain := 1.0

var _eye := Vector3.INF

func _ready() -> void:
	if environment != null:
		base_exposure = environment.tonemap_exposure

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or environment == null or sky == null:
		return
	var eye := camera.global_position
	var wanted := target_gain(indoors(eye, rooms), darkness(sky.sun_direction.y),
		weather.gloom() if weather != null else 0.0)
	if _eye == Vector3.INF or eye.distance_to(_eye) > CUT_DISTANCE:
		gain = wanted
	else:
		gain = adapt(gain, wanted, delta)
	_eye = eye
	var exposure := base_exposure * gain
	if not is_equal_approx(environment.tonemap_exposure, exposure):
		environment.tonemap_exposure = exposure

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

## `gloom` is 0 under an open sky .. 1 under a storm (WeatherSystem.gloom).
static func target_gain(inside: float, dark: float, gloom := 0.0) -> float:
	var outdoors := lerpf(lerpf(1.0, STORM_OUTDOORS, gloom), NIGHT_OUTDOORS, dark)
	return lerpf(outdoors, lerpf(ROOM_BY_DAY, ROOM_BY_NIGHT, maxf(dark, gloom * 0.5)), inside)

## One step of `delta` seconds from `current` toward `wanted`, in stops.
static func adapt(current: float, wanted: float, delta: float) -> float:
	var seconds := CLOSE_SECONDS if wanted < current else OPEN_SECONDS
	var stops := log(wanted / current)
	return current * exp(stops * (1.0 - exp(-delta / seconds)))
