class_name ViewmodelMotion
extends RefCounted
## Как шевелится кружка в руке. Чистые функции: проверяются тестами и не знают
## ни про сцену, ни про кадр.
##
## Всё меряется во внутренних пикселях кадра 480 × 270, а не в долях экрана:
## на этом разрешении разница между двумя и четырьмя пикселями — это разница
## между «предмет живёт» и «предмет мотает».
##
## Правило, которое важнее всех чисел: предмет качается сильнее камеры.
## Наоборот — и горизонт поедет, а от этого укачивает.

const WALK_BOB_X := 2.2          ## размах вбок при ходьбе
const WALK_BOB_Y := 3.2          ## размах вверх-вниз
const IDLE_AMPLITUDE := 0.5      ## дыхание стоя
const IDLE_FREQUENCY := 0.35     ## колебаний в секунду
const LOOK_LAG_MAX := 4.0        ## насколько кружка отстаёт от поворота
const LOOK_LAG_PER_PIXEL := 0.10
const STIFFNESS := 28.0
const DAMPING := 9.0

## Шаг: вбок по синусу, вверх-вниз вдвое чаще (нога опускается дважды за цикл).
static func walk_offset(phase: float, speed_ratio: float) -> Vector2:
	var amount := clampf(speed_ratio, 0.0, 1.0)
	return Vector2(
		sin(phase) * WALK_BOB_X,
		-absf(cos(phase)) * WALK_BOB_Y
	) * amount

## Дыхание на месте. Частоты по осям разные, иначе получается ровный круг
## и видно, что предмет ходит по орбите.
static func idle_offset(time: float) -> Vector2:
	var w := TAU * IDLE_FREQUENCY
	return Vector2(sin(w * time), sin(w * time * 0.73 + 1.1)) * IDLE_AMPLITUDE

## Отставание от поворота головы. Ограничено жёстко: без предела быстрый
## разворот мыши выбрасывает кружку за край экрана.
static func look_lag(look_delta: Vector2) -> Vector2:
	var lag := -look_delta * LOOK_LAG_PER_PIXEL
	if lag.length() > LOOK_LAG_MAX:
		lag = lag.normalized() * LOOK_LAG_MAX
	return lag

## Пружина с затуханием, шаг по времени. Возвращает [значение, скорость].
## Полуявная схема (сначала скорость, потом положение) не разносит систему
## на больших delta, в отличие от явной.
static func spring(current: float, velocity: float, target: float, delta: float) -> Array:
	var step := minf(delta, 0.05)
	var next_velocity := velocity + (STIFFNESS * (target - current) - DAMPING * velocity) * step
	return [current + next_velocity * step, next_velocity]

static func spring_vector(current: Vector2, velocity: Vector2, target: Vector2, delta: float) -> Array:
	var x := spring(current.x, velocity.x, target.x, delta)
	var y := spring(current.y, velocity.y, target.y, delta)
	return [Vector2(Values.real(x[0]), Values.real(y[0])), Vector2(Values.real(x[1]), Values.real(y[1]))]
