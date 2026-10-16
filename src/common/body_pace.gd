extends RefCounted
## Paces a kinematic body that only populates the world (a villager, an
## animal). A motion test against the level's triangle colliders is the
## dearest thing a physics tick does: thousands of faces lie under a body on
## the cobbles. So such a body
##   - takes no test while it stands on the ground: nothing would move it;
##   - far from the viewer covers several ticks in one step, as long as the
##     step stays about two pixels of the view.
## In the body's _physics_process:
##   delta = pace.begin(delta)   # 0.0: this tick is not the body's
##   ... set velocity from `delta` ...
##   pace.slide(self, delta)     # in place of move_and_slide()
## A body that does not reach slide() answers on every tick.
## A step never moves the body as far as `max_step` over the ground
## (docs/LEVEL.md, «Шаг тела»).

## Ticks one step covers at most (15 steps a second at 60 ticks).
const MAX_TICKS := 4
## Within this distance, m, a standing body still answers on every tick: its
## first step is then as short as the ones that follow.
const NEAR := 12.0
## The longest step, as an angle at the viewer's eye, rad.
const STEP_ANGLE := 0.0018
## A standing body checks the ground under it this often, s.
const FLOOR_CHECK_SECONDS := 0.5

## Bodies made one after another take their steps and their ground checks on
## different ticks, so no tick carries them all.
static var _made := 0
var _wait := 0
var _elapsed := 0.0
var _count := 0
var _covered := 1
var _floor_clock := 0.0
## Half the body's smallest thickness, m: no step moves the body that far, or
## it could pass through a thin wall or another body. 0.0: no bound.
var max_step := 0.0

func _init() -> void:
	_wait = _made % MAX_TICKS
	_floor_clock = FLOOR_CHECK_SECONDS * (_made % 8) / 8.0
	_made += 1

## The time the body's step covers, or 0.0 while it waits for its tick.
func begin(delta: float) -> float:
	_elapsed += delta
	_count += 1
	_wait -= 1
	if _wait > 0:
		return 0.0
	var covered := _elapsed
	_covered = _count
	_elapsed = 0.0
	_count = 0
	return covered

## move_and_slide over the ticks the step covers; nothing for a body that
## stands on the ground, but for the check of that ground.
func slide(body: CharacterBody3D, delta: float) -> void:
	_wait = _ticks(body)
	if body.velocity.x == 0.0 and body.velocity.z == 0.0 and body.is_on_floor():
		_floor_clock -= delta
		if _floor_clock > 0.0:
			return
		_floor_clock = FLOOR_CHECK_SECONDS
	# A body that stood far away and now walks may have waited longer than
	# its speed allows one step to cover: it loses the rest of that time.
	var covered := mini(_covered, longest_ticks(_per_tick(body), max_step))
	if covered <= 1:
		body.move_and_slide()
		return
	# move_and_slide moves by the velocity over one tick.
	body.velocity *= covered
	body.move_and_slide()
	body.velocity /= covered

## Ticks the next step may cover: by the body's speed and its distance.
func _ticks(body: CharacterBody3D) -> int:
	var camera := body.get_viewport().get_camera_3d()
	if camera == null:
		return 1
	var distance := camera.global_position.distance_to(body.global_position)
	var per_tick := _per_tick(body)
	if per_tick < 0.0001:
		return 1 if distance < NEAR else MAX_TICKS
	return clampi(int(STEP_ANGLE * distance / per_tick), 1, longest_ticks(per_tick, max_step))

## The ground the body covers in one tick at its velocity, m.
static func _per_tick(body: CharacterBody3D) -> float:
	return Vector2(body.velocity.x, body.velocity.z).length() / Engine.physics_ticks_per_second

## The most ticks one step may cover, `per_tick` m each, and stay shorter than
## `max_step` (0.0: no bound). One tick at least, however fast.
static func longest_ticks(per_tick: float, max_step: float) -> int:
	if max_step <= 0.0 or per_tick <= 0.0:
		return MAX_TICKS
	var ticks := mini(int(max_step / per_tick), MAX_TICKS)
	while ticks > 1 and ticks * per_tick >= max_step:
		ticks -= 1
	return maxi(ticks, 1)
