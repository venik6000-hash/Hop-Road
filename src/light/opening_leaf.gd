class_name OpeningLeaf
extends RefCounted
## A leaf that stands in an opening of a building and shuts it as it closes:
## a door on its hinge (docs/LEVEL.md, «Свет помещений»). The light of the
## rooms (Daylight, InteriorSight) knows a door by this alone. The node that
## turns the leaf is the building's door, which gives its `leaf` (Building.leaves).

## The node that turns: its place is the hinge in the building's frame, and it
## turns about its up axis.
var pivot: Node3D
## Its turn shut and open, radians.
var closed_angle := 0.0
var open_angle := 0.0
## Its width and the height of its top in the building's frame, m.
var measure := Vector2.ZERO

func _init(turning: Node3D, shut: float, open: float, size: Vector2) -> void:
	pivot = turning
	closed_angle = shut
	open_angle = open
	measure = size

## The hinge, in the building's frame.
func hinge() -> Vector3:
	return pivot.position

## 0 shut .. 1 open.
func openness() -> float:
	var swing := absf(open_angle - closed_angle)
	return clampf(absf(pivot.rotation.y - closed_angle) / maxf(swing, 0.001), 0.0, 1.0)
