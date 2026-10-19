class_name FieldWindow
extends RefCounted
## Where a field that follows the eye stands: the square it covers with the
## eye at home (the region's own placement of it), moved by whole steps of
## STEP metres along x and z.
##
## The field stays put while the eye is within `reach` of its middle along
## both axes. When the eye goes past, the field moves by as few steps as bring
## it back within reach: walking on, one step every STEP metres; walking back
## over the line, nothing until the eye is STEP metres back past it again
## (2 * reach - STEP of play). A reach under STEP / 2 would move it back and
## forth.

const STEP := 128.0

## The corner of least x and z with the eye at home, and the side (m).
var home := Vector2.ZERO
var side := 0.0
## How far (m) along an axis the eye may be from the middle before it moves.
var reach := 0.0
## Steps from home along x and z where the field stands now.
var offset := Vector2i.ZERO
## The land the field's data is known for (world x, z); the field does not
## leave it. Empty: no bounds.
var bounds := Rect2()

func _init(home_corner: Vector2, field_side: float, field_reach: float) -> void:
	home = home_corner
	side = field_side
	reach = maxf(field_reach, STEP * 0.5)

## The corner of least x and z where the field stands now.
func corner() -> Vector2:
	return home + Vector2(offset) * STEP

func middle() -> Vector2:
	return corner() + Vector2.ONE * side * 0.5

## The steps from home the field takes for the eye at `at` (world x, z).
func offset_for(at: Vector2) -> Vector2i:
	var result := offset
	var away := at - middle()
	for axis in 2:
		var beyond := absf(away[axis]) - reach
		if beyond > 0.0:
			result[axis] += (1 if away[axis] > 0.0 else -1) * ceili(beyond / STEP)
	if bounds.has_area():
		var least := ((bounds.position - home) / STEP).ceil()
		var most := ((bounds.end - Vector2.ONE * side - home) / STEP).floor()
		for axis in 2:
			result[axis] = 0 if least[axis] > most[axis] else clampi(result[axis], int(least[axis]), int(most[axis]))
	return result

## The corner the field would have at `steps` from home.
func corner_at(steps: Vector2i) -> Vector2:
	return home + Vector2(steps) * STEP
