class_name Player
extends CharacterBody3D
## Спека §10.1: ходьба ~3 м/с, бег ~5 м/с, обзор мышью. В озере — вброд и вплавь.

## Константы и чистые функции движения — в player_motion.gd (там же разбор
## каждой цифры), шаг и прилипание — в player_stepper.gd. Здесь те из них,
## на которые ссылаются этот скрипт, тесты и инструменты.
const MOTION = preload("res://src/player/player_motion.gd")
const STEPPER = preload("res://src/player/player_stepper.gd")
const WALK_SPEED := MOTION.WALK_SPEED
const RUN_SPEED := MOTION.RUN_SPEED
const ACCELERATION := MOTION.ACCELERATION
const GRAVITY := MOTION.GRAVITY
const SWIM_DEPTH := MOTION.SWIM_DEPTH
const WADE_SLOWDOWN := MOTION.WADE_SLOWDOWN
const EYE_HEIGHT := MOTION.EYE_HEIGHT
const WATER_DRAG := MOTION.WATER_DRAG
const STEP_HEIGHT := MOTION.STEP_HEIGHT
const FLOOR_SNAP_LENGTH := MOTION.FLOOR_SNAP_LENGTH

@onready var rig: CameraRig = $CameraRig
@onready var viewmodel: BeerViewmodel = get_node_or_null("BeerViewmodel")

var movement_locked := false

var _previous_velocity := Vector3.ZERO
## Шагал ли игрок в прошлом кадре.
##
## Подъём на ступень — не один кадр, а несколько. Капсула вкатывается на ребро
## постепенно: пока её ось не перешла плоскость подступёнка, она опирается на
## кромку, и is_on_floor() там честно возвращает false — нормаль ребра круче
## предельного угла пола. Без этой памяти подъём обрывался бы на втором кадре и
## игрок скатывался обратно.
var _stepped := false
## Стоял ли игрок на опоре в прошлом кадре — своим ходом, шагом или прилипанием.
## Спуск начинается только с земли: падать в пропасть, сорвавшись с обрыва,
## игрок обязан честно.
var _grounded := false
## Высота поверхности воды над игроком, метров; -INF — воды нет.
var water_surface := -INF
var swimming := false
## Плывёт под водой: голова ниже поверхности или зажат спуск.
var diving := false

static func local_acceleration(world: Vector3, yaw_deg: float) -> Vector3:
	return MOTION.local_acceleration(world, yaw_deg)

static func wish_direction(input: Vector2, yaw_deg: float) -> Vector3:
	return MOTION.wish_direction(input, yaw_deg)

static func step_probe(wish: Vector3, delta: float) -> Vector3:
	return MOTION.step_probe(wish, delta)

static func is_too_steep(normal: Vector3, max_floor_angle: float) -> bool:
	return MOTION.is_too_steep(normal, max_floor_angle)

static func step_rise(blocked: bool, headroom: float, ahead_free: bool,
		landing_rise: float, surface_rise: float, surface_normal: Vector3,
		max_floor_angle: float) -> float:
	return MOTION.step_rise(blocked, headroom, ahead_free, landing_rise, surface_rise,
		surface_normal, max_floor_angle)

static func water_speed(dry_speed: float, depth: float, sprint: bool) -> float:
	return MOTION.water_speed(dry_speed, depth, sprint)

static func buoyant_velocity(vertical: float, feet_y: float, surface: float, delta: float) -> float:
	return MOTION.buoyant_velocity(vertical, feet_y, surface, delta)

static func dive_velocity(input: Vector2, forward: Vector3, right: Vector3,
		vertical_input: float, speed: float) -> Vector3:
	return MOTION.dive_velocity(input, forward, right, vertical_input, speed)

static func should_stick(on_floor: bool, vertical_speed: float,
		was_grounded: bool, floor_gap: float) -> bool:
	return MOTION.should_stick(on_floor, vertical_speed, was_grounded, floor_gap)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Прилипание к полу — свойство тела, и задаётся оно здесь, а не в сцене,
	# чтобы стоять рядом с высотой шага: эти две цифры связаны и врозь не имеют
	# смысла (см. FLOOR_SNAP_LENGTH).
	floor_snap_length = FLOOR_SNAP_LENGTH

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rig.apply_look(event.relative)
	elif event.is_action_pressed("interact") or event.is_action_pressed("drink_beer"):
		if viewmodel != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not event.is_echo():
			viewmodel.drink()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var depth := water_surface - global_position.y
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_back", "move_forward")
	)
	if movement_locked:
		input = Vector2.ZERO
	var sprint := Input.is_action_pressed("sprint") and not movement_locked
	var speed := water_speed(RUN_SPEED if sprint else WALK_SPEED, depth, sprint)
	var vertical_input := 0.0 if movement_locked else Input.get_axis("swim_down", "swim_up")
	swimming = depth > SWIM_DEPTH
	diving = swimming and (depth > EYE_HEIGHT + 0.05 or vertical_input < 0.0)
	var target := wish_direction(input, rotation_degrees.y) * speed
	if diving:
		var look := rig.global_basis
		target = dive_velocity(input, -look.z, look.x, vertical_input, speed)
		# Сопротивление, а не постоянное ускорение: прыжок с берега вода гасит
		# за метр-два, как и положено, а не тащит ныряльщика на семь метров.
		velocity = velocity.lerp(target, 1.0 - exp(-WATER_DRAG * delta))
	else:
		if swimming:
			velocity.y = buoyant_velocity(velocity.y, global_position.y, water_surface, delta)
		elif is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= GRAVITY * delta
		velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)

	var was_grounded := _grounded
	var stuck := false
	# Шаг заменяет собой move_and_slide за этот кадр, а не дополняет его:
	# горизонтальный перенос он делает сам, и второй вызов сдвинул бы игрока
	# вперёд дважды. Пловцу шагать не с чего, а прилипание к дну спорило бы
	# с плавучестью и дёргало его вверх-вниз у самого дна.
	if swimming:
		_stepped = false
		move_and_slide()
	elif not STEPPER.try_step(self, target, delta):
		move_and_slide()
		stuck = STEPPER.stick_to_floor(self, was_grounded)
	# Прилипание считается опорой наравне с полом. Иначе спуск обрывался бы на
	# втором кадре: прилипнув, игрок формально не «на полу» (капсула лежит на
	# ребре, а нормаль ребра круче предельного угла), и следующий кадр отпускал
	# бы его в свободное падение — ровно то, от чего прилипание и заведено.
	_grounded = not swimming and (is_on_floor() or _stepped or stuck)

	var horizontal := Vector2(velocity.x, velocity.z).length()
	rig.apply_bob(0.0 if swimming else horizontal / RUN_SPEED, delta)
	_drive_viewmodel(horizontal, delta)

func _drive_viewmodel(horizontal: float, delta: float) -> void:
	var acceleration := (velocity - _previous_velocity) / maxf(delta, 0.0001)
	_previous_velocity = velocity
	if viewmodel == null:
		return
	viewmodel.update_motion(
		horizontal / RUN_SPEED,
		rig.walk_phase,
		rig.last_look,
		local_acceleration(acceleration, rotation_degrees.y),
		delta
	)
	# Рывок мыши расходуется за один кадр: иначе кружка застревает
	# в отклонённом положении, пока мышь не двинут обратно.
	rig.last_look = Vector2.ZERO
