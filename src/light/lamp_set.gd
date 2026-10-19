class_name LampSet
extends RefCounted
## What a building gives the lamps registry (WorldContext.lamps, docs/LEVEL.md,
## «Реестры»): its lanterns outdoors for LampShadowGuard and its glows from
## far away for FarLights. The building makes it once (lamps_for()) and puts
## a glow out or lights it again here (set_lit).

## Told when the glow `index` goes out or is lit again.
signal lit_changed(lamps: LampSet, index: int, lit: bool)

## The lanterns outdoors whose shadow maps LampShadowGuard keeps.
var lanterns: Array[Light3D] = []
## The glows in world space: {at, color, radius, facing, lit}. `facing` is the
## way a window looks; a lamp, seen from all round, leaves it zero.
var glows: Array[Dictionary] = []

## Adds a glow of `radius` metres at `at` and returns its index.
func add_glow(at: Vector3, color: Color, radius: float, facing := Vector3.ZERO, lit := true) -> int:
	glows.append({"at": at, "color": color, "radius": radius, "facing": facing, "lit": lit})
	return glows.size() - 1

## Puts the glow `index` out, or lights it again: a fire that burns for a
## part of the day only.
func set_lit(index: int, lit: bool) -> void:
	glows[index].lit = lit
	lit_changed.emit(self, index, lit)
