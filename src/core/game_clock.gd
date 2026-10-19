extends Node
## The game's time (autoload GameClock): game minutes since the midnight
## before the first day's dawn (DayClock.minutes_at). The day and the hour
## come from them (DayClock.day_of, hour_of). The sky draws the hour, the
## loop names the day, the save keeps the minutes, and what lives through time
## (the brewery) listens to `advanced`.
##
## Time is lived or set. Lived time (the running clock, pass_minutes: a night
## slept, the debug key "an hour on") goes through `advanced`. Set time
## (set_minutes, set_hour: a load, a new level, a tool, the debug key "an hour
## back") is not lived: nothing runs through the minutes it skips.

## `minutes` of game time went by from game minute `from`.
signal advanced(minutes: float, from: float)
## The minute the clock shows changed, lived or set.
signal changed

## Game minutes since the midnight before the first day's dawn.
var minutes := DayClock.minutes_at(1, 14.6)
## The clock goes by itself at DayClock's pace: the loop runs it, a level
## opened by a tool stands at the hour it was given.
var running := false
## The whole minute `changed` told last.
var _shown := -1

func _process(delta: float) -> void:
	if running:
		pass_minutes(DayClock.hours_after(hour(), delta) * 60.0)

## The day the clock is in, from 1; a day begins at dawn.
func day() -> int:
	return DayClock.day_of(minutes)

## The hour, 0..24.
func hour() -> float:
	return DayClock.hour_of(minutes)

## A new game's clock at `hour` of the first day, standing.
func begin(hour_of_day: float) -> void:
	running = false
	set_minutes(DayClock.minutes_at(1, hour_of_day))

## Lives `lived` game minutes forward (none for less than 0).
func pass_minutes(lived: float) -> void:
	if lived <= 0.0:
		return
	var from := minutes
	minutes += lived
	advanced.emit(lived, from)
	_tell(false)

func pass_hours(hours: float) -> void:
	pass_minutes(hours * 60.0)

## Sets the clock at game minute `value` (from 0) without living the way there.
func set_minutes(value: float) -> void:
	minutes = maxf(value, 0.0)
	_tell(true)

## Sets the clock at `hour_of_day` of the day it is in (an hour before dawn is
## that day's night), without living the way there.
func set_hour(hour_of_day: float) -> void:
	set_minutes(DayClock.minutes_at(day(), hour_of_day))

func _tell(always: bool) -> void:
	var shown := floori(minutes)
	if always or shown != _shown:
		_shown = shown
		changed.emit()
