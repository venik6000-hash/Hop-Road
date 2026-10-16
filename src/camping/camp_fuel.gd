class_name CampFuel
extends RefCounted
## The logs in a campfire (docs/PLAYER.md, «Костёр»): a log thrown in burns
## LOG_SECONDS; the fire holds MAX_LOGS at most and goes out when the last
## one has burnt.
const LOG_SECONDS := 300.0
const MAX_LOGS := 4
## Seconds of its last log in which a fire burns lower.
const LOW_SECONDS := 60.0
var seconds := 0.0

## A log thrown in; false when the fire holds as many as it takes.
func add_log() -> bool:
	if seconds > (MAX_LOGS - 1) * LOG_SECONDS:
		return false
	seconds += LOG_SECONDS
	return true

func empty() -> bool:
	return seconds <= 0.0

## `delta` seconds of burning; true when the last log has just burnt.
func burn(delta: float) -> bool:
	if seconds <= 0.0:
		return false
	seconds = maxf(0.0, seconds - maxf(0.0, delta))
	return seconds <= 0.0

## How strong the fire burns: 1, lower over the last log's last minute.
func strength() -> float:
	return clampf(seconds / LOW_SECONDS, 0.3, 1.0)

## Whole logs as the eye counts them in the fire, the one burning included.
func logs() -> int:
	return ceili(seconds / LOG_SECONDS)
