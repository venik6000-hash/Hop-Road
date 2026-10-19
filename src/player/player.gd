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
const GAME_SETTINGS = preload("res://src/settings/game_settings.gd")

@onready var rig: CameraRig = $CameraRig
## The eye of the rig, which the systems that look where the player looks use.
@onready var camera: Camera3D = $CameraRig/Camera3D
## The capsule the body stands in.
@onready var collision: CollisionShape3D = $Collision
@onready var viewmodel: BeerViewmodel = get_node_or_null("BeerViewmodel")

## The player's modes (docs/PLAYER.md, «Режимы игрока»). One system owns the
## mode at a time: it asks for it with enter() and gives it back with leave().
## WALK: the feet walk and swim by the controls. SEATED, LADDER, BOAT: a seat,
## the ladder or the boat carries the body (CARRIED). STATION, SLEEP, MENU:
## the feet stand still, the body falls and floats as it does on foot (a
## brewery's station; the sleep; the brewer's book or the catch's journal).
const WALK := &"walk"
const SEATED := &"seated"
const LADDER := &"ladder"
const BOAT := &"boat"
const STATION := &"station"
const SLEEP := &"sleep"
const MENU := &"menu"
const MODES: Array[StringName] = [WALK, SEATED, LADDER, BOAT, STATION, SLEEP, MENU]
## The modes where something carries the body: its physics and its capsule
## are off.
const CARRIED: Array[StringName] = [SEATED, LADDER, BOAT]
## The modes where the player stands on their own feet.
const ON_FEET: Array[StringName] = [WALK, STATION, MENU]
## The mode the player is in now (MODES). Read it; change it with enter() and
## leave().
var mode := WALK
## The system that owns the mode; null in WALK.
var _mode_owner: Object = null
## The feet stand still: the player is in a mode other than WALK.
var movement_locked: bool:
	get:
		return mode != WALK
## What the player has: the coins, the mug, the food in the hand, the place
## they stood (PlayerState). The save keeps it.
var state := PlayerState.new()
## The right stick does not turn the view: a doer reads it (BrewHouse at a
## station takes it as the mouse).
var look_held := false
## Who has the hands and the mouth (BodyChannels); the mug shows while it
## is in the right hand.
var hands := BodyChannels.new()
## The first-person picture (the mug and its hand) is on. It is off while
## another camera is the eye (the overview) or a tool shoots a frame without it.
var first_person := true
## The player's place in each frame's processing: after all others, so that
## the guard of the hands sees each doer's release of this frame.
const GUARD_LAST := 1000
## A breach the guard of the hands put right (guard_hands), in words.
signal hands_breached(what: String)
## The part of a free step left by what the hands carry (BrewCarry.pace).
var pace := 1.0
## The player's arms (the brewer's arms, BrewArms): the doer that has the
## hands puts them on what it holds, the mug's own hand aside.
var arms: BrewArms
## The doer that put the arms on its thing with hold(), &"" for none.
var _arms_doer := &""

var _previous_velocity := Vector3.ZERO
## CameraRig.sensitivity as the scene sets it, before the settings scale it.
## stick_gesture divides by it: it is taken as the body enters the tree, also
## for a player whose own _ready does not call this one (the tools' player).
@onready var _base_sensitivity: float = rig.sensitivity
var _settings: GAME_SETTINGS
## Шагал ли игрок в прошлом кадре.
##
## Подъём на ступень — не один кадр, а несколько. Капсула вкатывается на ребро
## постепенно: пока её ось не перешла плоскость подступёнка, она опирается на
## кромку, и is_on_floor() там честно возвращает false — нормаль ребра круче
## предельного угла пола. Без этой памяти подъём обрывался бы на втором кадре и
## игрок скатывался обратно.
var stepped := false
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

static func water_speed(dry_speed: float, depth: float, sprint: bool) -> float:
	return MOTION.water_speed(dry_speed, depth, sprint)

static func buoyant_velocity(vertical: float, feet_y: float, surface: float, delta: float) -> float:
	return MOTION.buoyant_velocity(vertical, feet_y, surface, delta)

static func dive_velocity(input: Vector2, forward: Vector3, right: Vector3,
		vertical_input: float, speed: float) -> Vector3:
	return MOTION.dive_velocity(input, forward, right, vertical_input, speed)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_up_body()
	_join_hands()
	_settings = get_node_or_null("/root/GameSettings")
	if _settings != null:
		_settings.controls_changed.connect(_apply_look_settings)
		_apply_look_settings()
		_settings.fov_changed.connect(_set_fov)
		_set_fov(_settings.fov)

## Switches the capsule of the body on and off: off while a seat or a
## ladder carries the player.
func set_body_enabled(enabled: bool) -> void:
	collision.disabled = not enabled

## Прилипание к полу — свойство тела, и задаётся оно здесь, а не в сцене,
## чтобы стоять рядом с высотой шага: эти две цифры связаны и врозь не имеют
## смысла (см. FLOOR_SNAP_LENGTH). Слой и маска — из PhysicsLayers: сцена чисел
## слоёв не держит.
func _set_up_body() -> void:
	floor_snap_length = FLOOR_SNAP_LENGTH
	collision_layer = PhysicsLayers.PLAYER
	collision_mask = PhysicsLayers.mask_of(PhysicsLayers.PLAYER)

## The mug follows the hands: it shows while it is in the right hand. The
## guard runs last of all in each frame, after every doer's own release.
func _join_hands() -> void:
	process_priority = GUARD_LAST
	arms = BrewArms.new()
	arms.name = "Arms"
	arms.top_level = true
	add_child(arms)
	hands.leaked.connect(_leaked)
	if viewmodel != null:
		viewmodel.channels = hands
		viewmodel.use_state(state)
		hands.changed.connect(_show_mug)
		hands.claim(BodyChannels.MUG, viewmodel.is_inside_tree)

func _show_mug() -> void:
	viewmodel.visible = _mug_shown()

## The mug shows: it is in the right hand and the first-person picture is on.
func _mug_shown() -> bool:
	return first_person and hands.mug_in_hand()

## Turns the first-person picture on or off (first_person); the mug still
## follows the hands.
func set_first_person(shown: bool) -> void:
	first_person = shown
	if viewmodel != null:
		_show_mug()

func _process(delta: float) -> void:
	var turn := stick_look(delta)
	if turn != Vector2.ZERO and not look_held and camera.current and InputActions.live(&"look_left"):
		rig.apply_look(turn)
	guard_hands()

## The turn of the right stick in this frame, as the mouse's motion in pixels
## (CameraRig.apply_look): GameSettings.pad_look_speed degrees a second at
## full tilt.
func stick_look(delta: float) -> Vector2:
	return _stick_degrees(delta) / rig.sensitivity

## The right stick as the mouse's motion for a station's gesture (BrewHouse):
## the same pixels whatever the mouse's sensitivity.
func stick_gesture(delta: float) -> Vector2:
	return _stick_degrees(delta) / _base_sensitivity

func _stick_degrees(delta: float) -> Vector2:
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	var speed := _settings.pad_look_speed if _settings != null else GAME_SETTINGS.DEFAULT_PAD_LOOK_SPEED
	return stick * speed * delta

## The mouse's sensitivity and the vertical inversion from the settings.
func _apply_look_settings() -> void:
	rig.sensitivity = _base_sensitivity * _settings.mouse_sensitivity
	rig.invert_y = _settings.invert_y

## The field of view of the eye, vertical degrees (GameSettings.fov).
func _set_fov(degrees: float) -> void:
	(rig.get_node("Camera3D") as Camera3D).fov = degrees

## The guard of the hands, each frame: no claim outlives its doer, and
## the mug is where the right hand says. A breach is put right and reported.
func guard_hands() -> void:
	hands.audit()
	if viewmodel != null and viewmodel.visible != _mug_shown():
		var what := "the mug was %s past the hands" % ("shown" if viewmodel.visible else "hidden")
		push_error("BodyChannels: " + what)
		hands_breached.emit(what)
		_show_mug()
	if arms.visible and not hands.arms_held():
		var what := "the arms showed with no doer at the hands"
		push_error("BodyChannels: " + what)
		hands_breached.emit(what)
		arms.drop()
		_arms_doer = &""

## The eye's frame turned with the look about the vertical, kept upright:
## where the arms stand.
func eye_frame() -> Transform3D:
	var camera := rig.get_node("Camera3D") as Camera3D
	var ahead := -camera.global_basis.z
	return Transform3D(Basis(Vector3.UP, atan2(-ahead.x, -ahead.z)), camera.global_position)

## Stands the arms in the eye's frame; gives their shoulders, world space
## (BrewHands' RIGHT, LEFT).
func stand_arms() -> Array[Vector3]:
	arms.global_transform = eye_frame()
	return [arms.shoulder(BrewHands.RIGHT), arms.shoulder(BrewHands.LEFT)]

## Puts the arms on `taken` (BrewHands' hands) for `doer`, which has its
## parts (BodyChannels); with nothing taken, or the parts gone, takes away
## the arms this doer showed. Called each frame after stand_arms().
func hold(doer: StringName, taken: Array[Dictionary], delta: float) -> void:
	if taken.is_empty() or not hands.has(doer):
		if _arms_doer == doer:
			arms.drop()
			_arms_doer = &""
		return
	_arms_doer = doer
	arms.reach(taken)
	arms.pose(delta)

func _leaked(doer: StringName) -> void:
	var what := "%s kept the hands after it was done" % doer
	push_error("BodyChannels: " + what)
	hands_breached.emit(what)

## The mouse turns the view while the pointer is captured and the look is the
## game's (InputActions.live); E with nothing to act on, or V, sips from the
## mug; a click takes the pointer back.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and InputActions.live(&"look_left"):
			rig.apply_look((event as InputEventMouseMotion).relative)
	elif InputActions.takes(event, &"interact") or InputActions.takes(event, &"drink_beer"):
		if viewmodel != null and viewmodel.visible and not event.is_echo():
			viewmodel.drink()
	elif (event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed() \
			and InputActions.in_play():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## `holder` takes the player into `to` (MODES, not WALK). Only from WALK: a
## mode another system owns is not taken over. True when the player is in
## `to` for `holder` now (also when it was already).
func enter(to: StringName, holder: Object) -> bool:
	if to == WALK or not MODES.has(to) or holder == null:
		push_error("Player.enter: no mode %s for %s" % [to, holder])
		return false
	if mode != WALK:
		return mode == to and _mode_owner == holder
	_mode_owner = holder
	_set_mode(to)
	return true

## `holder` gives its mode back: the player walks again. Nothing happens when
## another system owns the mode.
func leave(holder: Object) -> void:
	if mode == WALK or _mode_owner != holder:
		return
	_mode_owner = null
	_set_mode(WALK)

## The system that owns the mode now; null in WALK.
func mode_owner() -> Object:
	return _mode_owner

## The player stands on their own feet: not carried and not asleep (ON_FEET).
func on_feet() -> bool:
	return ON_FEET.has(mode)

## Puts the body as `to` wants it: a carried body stops and lets go of the
## floor; it walks again when the mode ends.
func _set_mode(to: StringName) -> void:
	var previous := mode
	mode = to
	var carried := CARRIED.has(to)
	if carried != CARRIED.has(previous):
		velocity = Vector3.ZERO
		set_body_enabled(not carried)
		set_physics_process(not carried)

func _physics_process(delta: float) -> void:
	var depth := water_surface - global_position.y
	# The feet answer the controls in WALK only, and only while the game's
	# context has the walk (InputActions.live).
	var input := Vector2(
		InputActions.axis(&"move_left", &"move_right"),
		InputActions.axis(&"move_back", &"move_forward")
	)
	if movement_locked:
		input = Vector2.ZERO
	var sprint := not movement_locked and InputActions.live(&"sprint") and Input.is_action_pressed(&"sprint")
	var speed := water_speed((RUN_SPEED if sprint else WALK_SPEED) * pace, depth, sprint)
	var vertical_input := 0.0 if movement_locked else InputActions.axis(&"swim_down", &"swim_up")
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
	var pushed := velocity
	var slid := false
	# Шаг заменяет собой move_and_slide за этот кадр, а не дополняет его:
	# горизонтальный перенос он делает сам, и второй вызов сдвинул бы игрока
	# вперёд дважды. Пловцу шагать не с чего, а прилипание к дну спорило бы
	# с плавучестью и дёргало его вверх-вниз у самого дна.
	if swimming:
		stepped = false
		move_and_slide()
	elif not STEPPER.try_step(self, target, delta):
		move_and_slide()
		slid = true
		stuck = STEPPER.stick_to_floor(self, was_grounded)
	if slid:
		_bump_villagers(pushed)
	# Прилипание считается опорой наравне с полом. Иначе спуск обрывался бы на
	# втором кадре: прилипнув, игрок формально не «на полу» (капсула лежит на
	# ребре, а нормаль ребра круче предельного угла), и следующий кадр отпускал
	# бы его в свободное падение — ровно то, от чего прилипание и заведено.
	_grounded = not swimming and (is_on_floor() or stepped or stuck)

	var horizontal := Vector2(velocity.x, velocity.z).length()
	rig.apply_bob(0.0 if swimming else horizontal / RUN_SPEED, delta)
	_drive_viewmodel(horizontal, delta)

## A villager the player ran into faster than NpcStumble.BUMP_SPEED stumbles
## (docs/LIFE.md, «Толчок»).
func _bump_villagers(pushed: Vector3) -> void:
	for index in get_slide_collision_count():
		var met := get_slide_collision(index)
		var villager := met.get_collider() as VillageNPC
		if villager == null:
			continue
		var speed := NpcStumble.bump_speed(pushed, met.get_normal())
		if speed >= NpcStumble.BUMP_SPEED:
			var normal := met.get_normal()
			villager.poses.bump(-Vector3(normal.x, 0.0, normal.z).normalized() * speed, global_position)

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
