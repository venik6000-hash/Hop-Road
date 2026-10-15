class_name CameraRig
extends Node3D
## Держит углы взгляда. Тангаж применяет к себе, рыскание — к родителю
## (телу игрока), чтобы движение шло по горизонтали независимо от наклона.

const PITCH_LIMIT_DEG := 89.0
## Метров. Камера качается заметно меньше предмета в руке (см.
## ViewmodelMotion): если наоборот, вместе с камерой ездит горизонт,
## а от едущего горизонта укачивает.
const BOB_AMPLITUDE := 0.020
const BOB_FREQUENCY := 8.0       ## колебаний в секунду на полной скорости

## Градусов поворота на пиксель движения мыши.
## Внутри SubViewportContainer со stretch_shrink = 5 движок делит relative
## на пять, поэтому значение впятеро больше привычных 0.12.
@export var sensitivity := 0.6
@export var invert_y := false

## Начальный взгляд задаётся сценой, а не подразумевается нулевым.
##
## Раньше это были обычные поля. Игрок появлялся смотрящим на север, куда бы
## ни был развёрнут его узел в сцене, и — что хуже — первое же движение мыши
## рвало взгляд туда же: apply_look пересчитывает поворот тела из yaw_deg, а
## тот всё ещё был нулём. Поворот в сцене и поворот в рыскании обязаны сойтись
## в одном месте, и это место — здесь.
@export var yaw_deg := 0.0
@export var pitch_deg := 0.0

## Фаза шага и последний рывок мыши: их читает кружка в руке.
## Фаза, а не время: предмету нужно попадать в такт шагу, а не в секунды.
var walk_phase := 0.0
var last_look := Vector2.ZERO
## Метров, на сколько опущен глаз: игрок присел у низкой работы (BrewHouse).
var crouch := 0.0

var _base_y := 0.0

func _ready() -> void:
	_base_y = position.y
	# Начальный взгляд применяется сразу, а не ждёт первого движения мыши.
	apply_look(Vector2.ZERO)

func apply_look(mouse_delta: Vector2) -> void:
	last_look = mouse_delta
	yaw_deg = wrapf(yaw_deg - mouse_delta.x * sensitivity, -180.0, 180.0)
	var delta_pitch := mouse_delta.y * sensitivity
	if invert_y:
		delta_pitch = -delta_pitch
	pitch_deg = clampf(pitch_deg - delta_pitch, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)

	rotation.x = deg_to_rad(pitch_deg)
	var body := get_parent() as Node3D
	if body != null:
		body.rotation.y = deg_to_rad(yaw_deg)

## Запрокидывание головы при глотке, радианы вверх. Слой поверх тангажа:
## взгляд игрока (pitch_deg) не меняется, и после глотка камера возвращается
## сама. За предел тангажа голова не уходит. Возвращает наклон, который
## камера получила.
func set_drink_tilt(radians: float) -> float:
	var applied := minf(radians, deg_to_rad(PITCH_LIMIT_DEG - pitch_deg))
	var camera := get_node_or_null("Camera3D") as Node3D
	if camera != null:
		camera.rotation.x = applied
	return applied

## speed_ratio — доля от максимальной скорости, 0.0 стоя и 1.0 на бегу.
func apply_bob(speed_ratio: float, delta: float) -> void:
	walk_phase += delta * BOB_FREQUENCY * clampf(speed_ratio, 0.0, 1.0)
	position.y = _base_y - crouch + bob_offset(walk_phase, speed_ratio)

static func bob_offset(time: float, speed_ratio: float) -> float:
	return sin(time) * BOB_AMPLITUDE * clampf(speed_ratio, 0.0, 1.0)
