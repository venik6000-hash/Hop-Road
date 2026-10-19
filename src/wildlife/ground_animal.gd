class_name GroundAnimal
extends CharacterBody3D
## Quiet foraging, physical wandering and a bounded retreat from the player.
const SceneUtil = preload("res://src/common/scene_util.gd")
const BodyPace = preload("res://src/common/body_pace.gd")
## The body capsule, m: Vector2(radius, height), by kind; SMALL for the rest.
const SHAPES := {"deer": Vector2(0.3, 1.1)}
const SMALL_SHAPE := Vector2(0.16, 0.4)
## Ground speed, m/s: Vector2(walking, fleeing), by kind; SMALL for the rest.
const SPEEDS := {"deer": Vector2(0.85, 3.4), "fox": Vector2(0.65, 2.4)}
const SMALL_SPEED := Vector2(0.38, 1.3)
## What the animal does: grazes, stands, watches the player, runs away.
enum State {GRAZE, IDLE, ALERT, FLEE}
## The clip the animal plays while it waits in a state.
const CLIPS: Dictionary[State, String] = {State.GRAZE: "graze", State.IDLE: "idle", State.ALERT: "alert", State.FLEE: "flee"}
var kind := "deer"
var habitat: WildlifeSystem
var home := Vector3.ZERO
var home_radius := 16.0
var rng := RandomNumberGenerator.new()
var animation: AnimationPlayer
var target := Vector3.ZERO
var state := State.GRAZE
var _wait := 0.0
var _blocked := 0.0
var _decision := 0.0
var active := true
var _pace := BodyPace.new()

func _ready() -> void:
	collision_layer = PhysicsLayers.ANIMALS
	collision_mask = PhysicsLayers.mask_of(PhysicsLayers.ANIMALS)
	floor_snap_length = 0.7
	floor_max_angle = deg_to_rad(42.0)
	var size: Vector2 = SHAPES.get(kind, SMALL_SHAPE)
	var shape := CapsuleShape3D.new()
	shape.radius = size.x
	shape.height = size.y
	_pace.max_step = size.x
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position.y = shape.height * 0.5 + 0.03
	add_child(holder)
	var model := WildlifeModel.instantiate(kind, 120.0)
	add_child(model)
	animation = SceneUtil.animation_player(model)
	target = position
	_wait = rng.randf_range(1.0, 7.0)
	WildlifeModel.play(animation, "graze")
	animation.seek(rng.randf_range(0.0, animation.current_animation_length), true)

func set_active(value: bool) -> void:
	active = value
	set_physics_process(value)
	animation.set_active(value)

func _physics_process(delta: float) -> void:
	delta = _pace.begin(delta)
	if delta == 0.0:
		return
	velocity.y = -0.4 if is_on_floor() else velocity.y - 18.0 * delta
	velocity.x = 0.0
	velocity.z = 0.0
	_decision -= delta
	if _decision <= 0.0:
		_decision = 0.3
		react()
	_wait = maxf(0.0, _wait - delta)
	var offset := target - global_position
	offset.y = 0.0
	if _wait > 0.0:
		WildlifeModel.play(animation, CLIPS[state])
	elif offset.length() < 0.65:
		state = State.GRAZE if rng.randf() < 0.65 else State.IDLE
		_wait = rng.randf_range(3.0, 9.0)
		target = habitat.ground_target(home, home_radius, kind, rng)
		WildlifeModel.play(animation, CLIPS[state])
	else:
		var direction := offset.normalized()
		var ahead := global_position + direction * 1.4
		if not habitat.ground_safe(ahead, kind):
			_replan()
		else:
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 4.0, 1.0))
			var speed := _speed()
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
			# The doe's source has a run clip but no walk; slow the same gait.
			var clip := "run" if state == State.FLEE or kind == "deer" else "walk"
			WildlifeModel.play(animation, clip, 0.48 if kind == "deer" and state != State.FLEE else 1.0)
	var before := global_position
	_pace.slide(self, delta)
	if _wait <= 0.0 and offset.length() > 0.65:
		_blocked = _blocked + delta if global_position.distance_to(before) < delta * 0.12 else 0.0
		if _blocked > 1.4:
			_replan()

func _speed() -> float:
	var speeds: Vector2 = SPEEDS.get(kind, SMALL_SPEED)
	return speeds.y if state == State.FLEE else speeds.x

func _replan() -> void:
	_blocked = 0.0
	_wait = 1.5
	state = State.IDLE
	target = habitat.ground_target(home, home_radius, kind, rng)

## Runs to `point` at once.
func flee_to(point: Vector3) -> void:
	target = point
	_wait = 0.0
	state = State.FLEE

## Minds the player: flees from one too near by the first clear way, or
## stands alert; calms down once the run is over.
func react() -> void:
	if habitat.player == null:
		return
	var away := global_position - habitat.player.global_position
	away.y = 0.0
	var scare := 6.5 if kind == "deer" else 5.0 if kind == "fox" else 2.3
	if away.length() >= scare or away.length() < 0.01:
		if state == State.FLEE and global_position.distance_to(target) < 1.0:
			state = State.IDLE
		return
	# Try a fan of escape paths so a tree or a cliff does not suppress fear.
	for turn: float in [0.0, 0.45, -0.45, 0.9, -0.9, 1.25, -1.25]:
		var direction := away.normalized().rotated(Vector3.UP, turn)
		var retreat := global_position + direction * scare * 1.5
		var from_home := retreat - home
		from_home.y = 0.0
		if from_home.length() > home_radius * 1.6:
			retreat = home + from_home.normalized() * home_radius * 1.6
		var safe := true
		for step in range(1, 5):
			if not habitat.ground_safe(global_position.lerp(retreat, float(step) / 4.0), kind):
				safe = false
				break
		if safe:
			flee_to(retreat)
			return
	state = State.ALERT if kind == "deer" else State.IDLE
	_wait = 0.8
