extends RefCounted
## Save version 5 to 6 (SaveService.MIGRATIONS). Version 6 keeps the game's
## time as one number, "minutes" (GameClock.minutes: game minutes since the
## midnight before the first day's dawn). Version 5 kept the day ("day", from
## 1, begun at dawn) and the hour ("hour", 0..24) apart. A save with a day and
## no hour takes the day's dawn; a save with neither keeps no time.

const DAY := "day"
const HOUR := "hour"
const MINUTES := "minutes"

## `saved` (version 5) as version 6.
static func apply(saved: Dictionary, _path: String) -> Dictionary:
	var day: Variant = saved.get(DAY)
	var hour: Variant = saved.get(HOUR)
	var has_day := day is float or day is int
	var has_hour := hour is float or hour is int
	if has_day or has_hour:
		var of_day := maxi(1, int(Values.number(day, 1.0, 1.0, 1e9)))
		var at := Values.number(hour, DayClock.DAY_START, 0.0, 24.0)
		saved[MINUTES] = DayClock.minutes_at(of_day, at)
	saved.erase(DAY)
	saved.erase(HOUR)
	return saved
