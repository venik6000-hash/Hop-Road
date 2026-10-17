extends RefCounted
## The watchdog of a loading stage (WorldLoader). A new engine build has Metal
## compile every shader on first use, and the frame that needs them waits, for
## minutes at worst. That is progress the loader cannot see, so the watch
## counts the frames that do arrive: a stage fails only when they keep coming
## and it stands still.

## Seconds of frames that keep coming which one stage may take.
const STALL_SECONDS := 180.0
## The most one frame adds to that: a frame held up by the graphics driver is
## slow, not stalled.
const STALL_STEP := 0.25

## Seconds of frames the stage has stood still.
var idle := 0.0

## A new stage begins: its count starts from nothing.
func begin() -> void:
	idle = 0.0

## A frame of `delta` seconds has come; true once the stage has stood still
## for too long.
func tick(delta: float) -> bool:
	idle += minf(delta, STALL_STEP)
	return idle > STALL_SECONDS
