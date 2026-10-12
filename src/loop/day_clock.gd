class_name DayClock
extends RefCounted
## The valley's day: how fast the hours go by day and by night, which part of
## the day an hour belongs to, when a new day begins and when a sleeper wakes.
## Hours are the sky's (SkySystem.time_of_day, 0..24).

## The day runs from DAY_START to DAY_END, the night the rest of the way round.
const DAY_START := 6.0
const DAY_END := 21.0
## Real minutes the day and the night take: 48 for the two. The night goes
## faster, so that a third of the game is not spent in the dark.
const DAY_MINUTES := 36.0
const NIGHT_MINUTES := 12.0
## A bed takes the sleeper to this hour of the next morning.
const WAKE_HOUR := 6.5
## Where the morning turns into the day and the day into the evening.
const NOON_START := 11.0
const EVENING_START := 17.0
## The least step of the clock, hours: keeps a sum of steps moving when a
## rounding error leaves it a hair short of a turn of pace.
const LEAST_STEP := 1e-6

static func is_day(hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	return h >= DAY_START and h < DAY_END

## Game hours one real second adds at `hour`.
static func pace(hour: float, day_minutes := DAY_MINUTES, night_minutes := NIGHT_MINUTES) -> float:
	if is_day(hour):
		return (DAY_END - DAY_START) / (day_minutes * 60.0)
	return (24.0 - DAY_END + DAY_START) / (night_minutes * 60.0)

## Hours from `hour` to the next turn of pace (dusk by day, dawn by night).
static func _to_turn(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var ahead := DAY_END - h if is_day(h) else fposmod(DAY_START - h, 24.0)
	return maxf(ahead, LEAST_STEP)

## Game hours that `seconds` of real time add to the clock at `hour`.
static func hours_after(hour: float, seconds: float, day_minutes := DAY_MINUTES, night_minutes := NIGHT_MINUTES) -> float:
	var passed := 0.0
	var left := seconds
	# A frame crosses one turn of pace at most, a skipped night a few.
	while left > 0.0:
		var rate := pace(hour + passed, day_minutes, night_minutes)
		var reach := _to_turn(hour + passed)
		if left * rate < reach:
			return passed + left * rate
		passed += reach
		left -= reach / rate
	return passed

## Real seconds the clock takes to go `hours` forward from `hour`.
static func seconds_for(hour: float, hours: float, day_minutes := DAY_MINUTES, night_minutes := NIGHT_MINUTES) -> float:
	var seconds := 0.0
	var gone := 0.0
	while gone < hours:
		var reach := minf(_to_turn(hour + gone), hours - gone)
		seconds += reach / pace(hour + gone, day_minutes, night_minutes)
		gone += reach
	return seconds

## Dawns (DAY_START) the clock reaches going `hours` forward from `hour`: the
## days that begin on the way. A clock standing at dawn has begun its day.
static func dawns_passed(hour: float, hours: float) -> int:
	if hours <= 0.0:
		return 0
	var to_dawn := fposmod(DAY_START - fposmod(hour, 24.0), 24.0)
	if to_dawn == 0.0:
		to_dawn = 24.0
	if hours < to_dawn:
		return 0
	return 1 + int(floor((hours - to_dawn) / 24.0))

## The day the clock is in after it went from hour `was` to hour `now`. A step
## forward of up to half a day counts the dawns it passed; anything else is
## the clock being set back, and no day begins.
static func day_after(day: int, was: float, now: float) -> int:
	var forward := fposmod(now - was, 24.0)
	if forward > 12.0:
		return day
	return day + dawns_passed(was, forward)

## Hours from `hour` to the next WAKE_HOUR: a whole day for one who lies down
## at that very hour.
static func hours_until_wake(hour: float) -> float:
	var ahead := fposmod(WAKE_HOUR - fposmod(hour, 24.0), 24.0)
	return ahead if ahead > 0.0 else 24.0

## "morning", "day", "evening" or "night".
static func part(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if not is_day(h):
		return "night"
	if h < NOON_START:
		return "morning"
	if h < EVENING_START:
		return "day"
	return "evening"
