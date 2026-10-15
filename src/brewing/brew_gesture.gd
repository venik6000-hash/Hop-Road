class_name BrewGesture
extends RefCounted
## What the mouse does at a brewing station (docs/plans/brewing.md, section 7):
## seven gestures, each written here once. feed() takes the mouse's travel in
## pixels; a heavier thing (`weight`) needs more travel for the same move.
##
## - tilt: push the mouse away to tip a sack, a bucket or a dipper; `amount`
##   is how far it is tipped, flow() how fast it pours.
## - circle: turn the mouse round a point (a paddle, a millstone, a windlass);
##   `turns` counts the turns, signed, taken by take_turns().
## - rock: pull the mouse down and push it up (a pump handle); `count` is the
##   full strokes.
## - draw: drag the mouse along `along` (a tap key, a damper chain); `amount`
##   is how far it is open.
## - stripe: drag along `along` in long passes (a shovel, a rake); `count` is
##   the passes as long as PASS made without a turn back.
## - strike: pull the mouse down to lift, then push it up hard (a mallet);
##   `count` is the blows, `force` the last one's.
## - throw: pull the mouse down to swing back, then fling it up (a log, hops);
##   `count` is the throws, `force` the last one's.

const KINDS: Array[String] = ["tilt", "circle", "rock", "draw", "stripe", "strike", "throw"]
## Pixels of mouse travel for the whole of a move of a thing of weight 1.
const PIXELS := 400.0
## A tipped thing pours from this tilt on, fully when tipped all the way.
const POUR_FROM := 0.35
## The circle counts only away from its middle, past this part of its radius.
const HUB := 0.35
## A rock stroke: the handle at the top above TOP, at the bottom below BOTTOM.
const TOP := 0.9
const BOTTOM := 0.1
## Length of a pass of a stripe, in moves.
const PASS := 0.8
## A blow or a throw: the least wind-up, and the speed (moves a second) of the
## swing that makes one; twice SWING is the full force.
const WIND_UP := 0.4
## Below this the arm is back at rest: the blow or the throw is over.
const REST := 0.05
const SWING := 4.0

var kind := "tilt"
var weight := 1.0
## The direction a draw or a stripe goes along, in screen pixels (y down).
var along := Vector2.RIGHT
## Tilt, draw: how far 0..1. Rock: the handle 0 (up) .. 1 (down). Strike,
## throw: the wind-up 0..1. Circle: the angle of the hand, radians.
var amount := 0.0
var count := 0
var turns := 0.0
var force := 0.0

var _hand := Vector2(0.0, -1.0)
var _taken := 0
var _was_top := true
var _pass := 0.0
var _speed := 0.0
var _wound := 0.0

static func make(gesture_kind: String, gesture_weight := 1.0) -> BrewGesture:
	var gesture := BrewGesture.new()
	gesture.kind = gesture_kind
	gesture.weight = gesture_weight
	return gesture

## The mouse moved `motion` pixels in `delta` seconds.
func feed(motion: Vector2, delta: float) -> void:
	var move := motion / (PIXELS * maxf(weight, 0.01))
	match kind:
		"tilt":
			amount = clampf(amount - move.y, 0.0, 1.0)
		"draw":
			amount = clampf(amount + move.dot(along.normalized()), 0.0, 1.0)
		"circle":
			_circle(move)
		"rock":
			amount = clampf(amount + move.y * 2.0, 0.0, 1.0)
			if amount <= BOTTOM:
				_was_top = true
			elif amount >= TOP and _was_top:
				_was_top = false
				count += 1
		"stripe":
			var step := move.dot(along.normalized())
			_pass = _pass + step if signf(step) == signf(_pass) or _pass == 0.0 else step
			if absf(_pass) >= PASS:
				count += 1
				_pass = 0.0
		"strike", "throw":
			_swing(move.y, delta)

## How fast a tipped thing pours, 0..1.
func flow() -> float:
	return smoothstep(POUR_FROM, 1.0, amount) if kind == "tilt" else 0.0

## How far along its pass a stripe is, -1..1 (signed by the way it goes).
func pass_part() -> float:
	return clampf(_pass / PASS, -1.0, 1.0) if kind == "stripe" else 0.0

## Whole turns made since the last call, signed.
func take_turns() -> int:
	var whole := int(turns) if turns >= 0.0 else -int(-turns)
	var made := whole - _taken
	_taken = whole
	return made

func _circle(move: Vector2) -> void:
	var before := _hand
	_hand = (_hand + move * 2.0).limit_length(1.0)
	amount = _hand.angle()
	if before.length() >= HUB and _hand.length() >= HUB:
		turns += angle_difference(before.angle(), _hand.angle()) / TAU

## A blow and a throw: wind up by pulling down, let fly by pushing up fast.
func _swing(down: float, delta: float) -> void:
	var before := amount
	amount = clampf(amount + down, 0.0, 1.0)
	var speed := (before - amount) / maxf(delta, 0.001)
	_speed = maxf(_speed, speed) if down < 0.0 else 0.0
	if down < 0.0 and amount <= REST and before > REST:
		var wound := _wound
		_wound = 0.0
		if wound >= WIND_UP and _speed >= SWING:
			count += 1
			force = clampf(wound * _speed / (2.0 * SWING), 0.0, 1.0)
		_speed = 0.0
	elif down > 0.0:
		_wound = maxf(_wound, amount)
