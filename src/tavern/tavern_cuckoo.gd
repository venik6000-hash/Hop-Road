class_name TavernCuckoo
extends Node
## The cuckoo clock in the hall keeps the game's time (GameClock).
## On the hour its door swings open, the bird comes out and calls the hour,
## on the half hour once; then it goes back in and the door shuts. The door
## and the bird are pieces of their own in the furnishing (`tav_cuckoo` in
## their extras): the door turns on its hinge (`tav_hinge`), the bird moves
## out of the wall (`tav_out`).

## Seconds the door takes to open, the bird to come out, and one call.
const OPEN_SECONDS := 0.45
const OUT_SECONDS := 0.35
const CALL_SECONDS := 0.9
## How far the door opens (radians) and the bird comes out (m); how much
## further it leans out on a call, as a share of that.
const OPEN_ANGLE := 1.66
const BIRD_REACH := 0.035
const CALL_LEAN := 0.3
## A step of the game's clock longer than this (hours) is a jump (a probe
## setting the time, a night slept through): the clock calls nothing for it.
const LONGEST_STEP := 0.25

var tavern: TavernSystem

var _door: MeshInstance3D
var _door_rest: Transform3D
var _hinge := Vector3.ZERO
var _bird: MeshInstance3D
var _bird_rest: Transform3D
var _out := Vector3.ZERO
var _hour := NAN
var _calls := 0
var _time := -1.0

## Takes the door or the bird the furnishing marked as `part`.
func add(part: String, item: MeshInstance3D, extras: Dictionary) -> void:
	match part:
		"door":
			_door = item
			_door_rest = item.global_transform
			var h: Array = extras.tav_hinge
			_hinge = tavern.to_global(Vector3(Values.real(h[0]), Values.real(h[2]), Values.real(-h[1])))
		"bird":
			_bird = item
			_bird_rest = item.global_transform
			var o: Array = extras.tav_out
			_out = (tavern.global_basis * Vector3(Values.real(o[0]), Values.real(o[2]), Values.real(-o[1]))).normalized()

func _process(delta: float) -> void:
	if tavern == null or tavern.sky_system == null or _door == null or _bird == null:
		return
	var hour := GameClock.hour()
	if not is_nan(_hour) and _time < 0.0:
		var step := wrapf(hour - _hour, -12.0, 12.0)
		var was := floori(fposmod(_hour, 24.0) * 2.0)
		var now := floori(fposmod(hour, 24.0) * 2.0)
		if step > 0.0 and step < LONGEST_STEP and now != was:
			_calls = calls_at(now)
			_time = 0.0
	_hour = hour
	if _time < 0.0:
		return
	_time += delta
	var at := pose(_time, _calls)
	_door.global_transform = Transform3D(Basis(Vector3.UP, OPEN_ANGLE * at.x), Vector3.ZERO) \
		.translated(_hinge) * Transform3D(Basis.IDENTITY, -_hinge) * _door_rest
	_bird.global_transform = _bird_rest.translated(_out * BIRD_REACH * at.y)
	if _time >= duration(_calls):
		_time = -1.0
		_door.global_transform = _door_rest
		_bird.global_transform = _bird_rest

## How many times the bird calls at the start of half hour `half` of the day
## (0 is midnight): the hour on a twelve-hour dial, once on the half hour.
static func calls_at(half: int) -> int:
	if half % 2 == 1:
		return 1
	var hour := floori(half / 2.0) % 12
	return 12 if hour == 0 else hour

## How long the door stands open for `calls` calls, s.
static func duration(calls: int) -> float:
	return 2.0 * (OPEN_SECONDS + OUT_SECONDS) + calls * CALL_SECONDS

## How far open the door is (x, 0 .. 1) and how far out the bird is (y, 0
## .. 1 + CALL_LEAN) `time` seconds after it began to call `calls` times.
static func pose(time: float, calls: int) -> Vector2:
	var length := duration(calls)
	if time <= 0.0 or time >= length:
		return Vector2.ZERO
	var door := smoothstep(0.0, OPEN_SECONDS, minf(time, length - time))
	var out := smoothstep(OPEN_SECONDS, OPEN_SECONDS + OUT_SECONDS, minf(time, length - time))
	var calling := time - OPEN_SECONDS - OUT_SECONDS
	if calling > 0.0 and calling < calls * CALL_SECONDS:
		# Each call: a lean out and back, quicker out than back.
		var beat := fposmod(calling, CALL_SECONDS) / CALL_SECONDS
		out += CALL_LEAN * sin(PI * pow(beat, 0.6))
	return Vector2(door, out)
