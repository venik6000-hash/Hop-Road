class_name BrewArms
extends Node3D
## The brewer's arms in this public copy: the game's arms carry a scanned hand
## that this copy leaves out, so here they are not drawn. The works go on as
## in the game: the shoulders stand where the game's arms have them, and
## BrewHouse checks the reach from them.
## The node stands in the eye's frame, turned with the look but kept upright.
## The player owns one (Player.arms); the doer that has the hands
## (BodyChannels) puts them on what it holds.

## Metres from the shoulder to the farthest bar a hand closes on.
const REACH := 0.56
## The right shoulder from the eye; the left one is its mirror.
const SHOULDER := Vector3(0.19, -0.21, 0.06)

## The hands now: BrewHands' {side, at, clip}.
var hands: Array[Dictionary] = []

func _ready() -> void:
	visible = false

## The hands to take (BrewHands' list).
func reach(taken: Array[Dictionary]) -> void:
	hands = taken

## Takes the hands away.
func drop() -> void:
	hands = []

## Opens the fingers that held something: nothing to open.
func let_go() -> void:
	hands = []

## Poses the arms for this frame: nothing to pose.
func pose(_delta: float) -> void:
	pass

## Shoulder `side`'s joint, world space.
func shoulder(side: int) -> Vector3:
	return global_transform * (SHOULDER * Vector3(1.0 if side == 0 else -1.0, 1.0, 1.0))
