extends RefCounted
## Шаг на ступень и прилипание к полу на спуске: пробные перемещения и лучи
## от тела игрока. Решают чистые функции player_motion.gd, здесь только замеры.
const MOTION = preload("res://src/player/player_motion.gd")

## Подъём на ступень. true — шаг сделан и тело уже перенесено.
##
## Приём стандартный для Godot 4 и состоит из трёх пробных перемещений, ни одно
## из которых тела не двигает: вверх на высоту шага, вперёд с поднятой высоты,
## вниз обратно. Слепо прибавлять к position.y нельзя — так игрок влезает в
## перекрытия и просачивается сквозь то, что должно его держать.
static func try_step(body: Player, wish: Vector3, delta: float) -> bool:
	# На весу шагать нечем — кроме случая, когда шаг начат в прошлом кадре и
	# ещё не доделан (см. _stepped).
	if not body.is_on_floor() and not body._stepped:
		body._stepped = false
		return false

	var ahead := MOTION.step_probe(wish, delta)
	if ahead == Vector3.ZERO:
		body._stepped = false
		return false

	var here := body.global_transform
	var blocked := body.test_move(here, ahead)
	# step_rise always rejects an unobstructed move; avoid the other probes.
	if not blocked:
		body._stepped = false
		return false

	# Замер над головой. Столкновение на подъёме — это низкая притолока, и
	# свободной высоты остаётся ровно столько, сколько капсула успела пройти.
	var headroom := MOTION.STEP_HEIGHT
	var above := KinematicCollision3D.new()
	if body.test_move(here, Vector3.UP * MOTION.STEP_HEIGHT, above):
		headroom = above.get_travel().y

	var raised := here.translated(Vector3.UP * MOTION.STEP_HEIGHT)
	var ahead_free := not body.test_move(raised, ahead)

	# Спуск на площадку. Начинаем из поднятой и продвинутой точки и опускаемся
	# ровно на высоту шага: не нашли опоры — ступать некуда.
	var landing_rise := -1.0
	var surface_rise := -1.0
	var surface_normal := Vector3.ZERO
	var down := KinematicCollision3D.new()
	if blocked and ahead_free \
			and body.test_move(raised.translated(ahead), Vector3.DOWN * MOTION.STEP_HEIGHT, down):
		# travel.y отрицателен: сколько не доопустились — на столько и поднялись.
		landing_rise = MOTION.STEP_HEIGHT + down.get_travel().y
		var surface := surface_at(body, down.get_position(), ahead)
		if not surface.is_empty():
			surface_rise = (surface["position"] as Vector3).y - here.origin.y
			surface_normal = surface["normal"]

	var lift := MOTION.step_rise(blocked, headroom, ahead_free, landing_rise,
		surface_rise, surface_normal, body.floor_max_angle)
	if lift <= 0.0:
		body._stepped = false
		return false

	body.global_position += ahead + Vector3.UP * lift
	# Вертикаль гасится: подъём совершён телом, а не падением, и остаточная
	# скорость вниз утащила бы игрока с только что занятой ступени.
	body.velocity.y = 0.0
	body.apply_floor_snap()
	body._stepped = true
	return true

## Спуск: притянуть игрока к полу, если пол под ногами есть.
##
## Штатный floor_snap_length делает это сам, но ровно до тех пор, пока капсуле не
## мешает её собственная форма. Сходя со ступени, капсула переваливается через
## ребро, и в тот кадр, когда нормаль ребра становится круче предельного угла
## пола, тело считается сорвавшимся; притянуть его вниз при этом нельзя — пробное
## перемещение упирается в то же ребро и не проходит ни сантиметра. Дальше
## включается гравитация, и сход с бордюра превращается в падение с набором
## скорости: замер на стенде давал 0.18 с полёта и 3.7 м/с при приземлении.
##
## Поэтому вертикаль гасится вручную, пока пол в пределах шага под ногами есть.
## Игрок при этом продолжает сползать по ребру — вбок его толкает скольжение
## вдоль стенки, — но не разгоняется вниз и приземляется без рывка.
static func stick_to_floor(body: Player, was_grounded: bool) -> bool:
	# Дешёвый отсев прежде луча: на ровном месте игрок стоит на полу каждый
	# кадр, и гонять зонд по земле незачем.
	if body.is_on_floor() or not was_grounded or body.velocity.y > 0.0:
		return false
	if not MOTION.should_stick(body.is_on_floor(), body.velocity.y, was_grounded, floor_gap(body)):
		return false
	body.velocity.y = 0.0
	body.apply_floor_snap()
	return true

## Сколько метров от подошвы до пола под ней. Отрицательное значение — пола в
## пределах шага нет либо он круче предельного угла: срываться с обрыва и
## съезжать по круче игрок обязан сам.
static func floor_gap(body: Player) -> float:
	var world := body.get_world_3d()
	if world == null:
		return -1.0
	var from := body.global_position + Vector3.UP * 0.01
	var query := PhysicsRayQueryParameters3D.create(from,
		body.global_position - Vector3.UP * MOTION.FLOOR_REACH)
	query.exclude = [body.get_rid()]
	# Опора — только мир и валуны: на жителя и зверя игрок не встаёт.
	query.collision_mask = PhysicsLayers.GROUND
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	if MOTION.is_too_steep(hit["normal"], body.floor_max_angle):
		return -1.0
	return body.global_position.y - (hit["position"] as Vector3).y

## Площадка за кромкой — тем самым лучом, о котором сказано у
## STEP_SURFACE_AHEAD. Пустой словарь означает, что площадки там нет.
static func surface_at(body: Player, contact: Vector3, ahead: Vector3) -> Dictionary:
	var world := body.get_world_3d()
	if world == null:
		return {}
	var point := contact + ahead.normalized() * MOTION.STEP_SURFACE_AHEAD
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * MOTION.STEP_HEIGHT,
		point - Vector3.UP * MOTION.STEP_SURFACE_BELOW)
	# Себя из выборки вон: луч выходит из точки касания, и без этого он с
	# половины ракурсов упирается в собственную капсулу.
	query.exclude = [body.get_rid()]
	query.collision_mask = PhysicsLayers.GROUND
	return world.direct_space_state.intersect_ray(query)
