class_name DrinkMotion
extends RefCounted
## Глоток из кружки: поза запястья как функция времени. Чистые функции —
## проверяются тестами и не знают ни про сцену, ни про кадр.
##
## Кружка идёт по дуге ко рту, край ложится на губы, и кружка наклоняется
## вокруг губ ровно настолько, чтобы пиво дошло до края. Угол зависит от
## уровня: полную кружку наклоняют чуть-чуть, последний глоток пьют, держа
## кружку почти лёжа. Часть наклона берёт голова: она запрокидывается тем сильнее,
## чем меньше пива. Три глотка, потом кружка мягко садится обратно в руку.

const SECONDS := 2.6
const RAISE := Vector2(0.0, 0.55)       ## подъём ко рту, секунды от начала
const TIP_IN := Vector2(0.38, 0.8)      ## край на губах, наклон до пива
const SWALLOWS: Array[float] = [1.05, 1.45, 1.85]
const TIP_OUT := Vector2(1.95, 2.25)    ## кружка выпрямляется у губ
const LOWER := Vector2(2.05, 2.6)       ## обратно в руку
## Губы в пространстве камеры руки, метры: под глазами и чуть впереди.
const MOUTH := Vector3(0.0, -0.085, -0.06)
## Край кружки, который ложится на губы, в пространстве кружки: верх
## внешней кромки на стороне, обращённой к лицу.
const LIP := Vector3(0.0, 0.24, 0.108)
## Пока кружка подходит, край чуть ниже и дальше губ.
const APPROACH := Vector3(0.0, -0.012, -0.03)
const APPROACH_DEG := 12.0      ## наклон кружки, с которым она подходит к губам
const MOUTH_YAW_DEG := -8.0     ## ручка чуть к лицу: кисть у правой щеки
const FLOW_DEG := 2.0           ## сверх угла, при котором пиво доходит до края
const HEAD_MIN_DEG := 5.0
const HEAD_MAX_DEG := 35.0
## Доля наклона сверх полной кружки, которую берёт голова: донышко допивают,
## запрокинув голову, а не вывернув кисть.
const HEAD_SHARE := 0.5
## Дуга подъёма: кружка идёт вверх и к середине, а не напрямик в лицо.
const ARC := Vector3(-0.03, 0.06, 0.0)
## Модель уровня в единицах симуляции пива (BeerFluid.UNIT): высота полной
## кружки и радиус поверхности (центры частиц плюс их размер).
const FULL_HEIGHT := BeerFluid.RIM - 0.14
const SURFACE_RADIUS := BeerFluid.RADIUS + 0.07
const REACH_STEPS := 64

static var _reach_table := PackedFloat32Array()

## Насколько кружка у рта: 0 в руке, 1 у губ. Опускание — квинтика: у руки
## ни скорости, ни ускорения, кружка садится без толчка.
static func raise_weight(t: float) -> float:
	if t <= 0.0 or t >= SECONDS:
		return 0.0
	if t < LOWER.x:
		return smoothstep(RAISE.x, RAISE.y, t)
	var u := clampf((t - LOWER.x) / (LOWER.y - LOWER.x), 0.0, 1.0)
	return 1.0 - u * u * u * (u * (u * 6.0 - 15.0) + 10.0)

## Край на губах и кружка наклонена до пива: 0 — подходит, 1 — пьёт.
static func tip_weight(t: float) -> float:
	if t < TIP_OUT.x:
		return smoothstep(TIP_IN.x, TIP_IN.y, t)
	return 1.0 - smoothstep(TIP_OUT.x, TIP_OUT.y, t)

## Губы у края: пиво, дошедшее до края, выпито, а не пролито. Окно шире
## касания: кружка у рта и уходит от него, а пиво качнулось от рывка руки.
static func lips_on(t: float) -> bool:
	return t >= RAISE.y - 0.1 and t <= TIP_OUT.y + 0.05

## Доля пива, выпитая к моменту t, как её догоняет наклон. Глоток забирает
## пиво сразу, наклон доводит остаток до края за четверть секунды после:
## наклон раньше глотка вылил бы за край тот же глоток второй раз.
static func drunk(t: float, sip: float) -> float:
	var total := 0.0
	for at in SWALLOWS:
		total += smoothstep(at, at + 0.25, t)
	return sip * total / SWALLOWS.size()

## Сколько глотков уже сделано к моменту t.
static func swallows_done(t: float) -> int:
	var count := 0
	for at in SWALLOWS:
		if t >= at:
			count += 1
	return count

## Толчок горла: короткий бугор вокруг каждого глотка, только у губ.
static func swallow_pulse(t: float) -> float:
	var pulse := 0.0
	for at in SWALLOWS:
		var x := (t - at) / 0.08
		pulse += exp(-x * x)
	return pulse * tip_weight(t)

## Угол от вертикали (радианы), при котором пиво этого уровня доходит до края.
## У рта его спрашивают несколько раз за кадр: таблица строится один раз.
static func reach_tilt(fill: float) -> float:
	if _reach_table.is_empty():
		for i in REACH_STEPS + 1:
			_reach_table.append(_solve_reach(float(i) / REACH_STEPS))
	var x := clampf(fill, 0.0, 1.0) * REACH_STEPS
	var i := mini(int(x), REACH_STEPS - 1)
	return lerpf(_reach_table[i], _reach_table[i + 1], x - float(i))

static func _solve_reach(fill: float) -> float:
	var level := clampf(fill, 0.0, 1.0) * FULL_HEIGHT
	var low := 0.0
	var high := deg_to_rad(88.0)
	for i in 24:
		var middle := (low + high) * 0.5
		if held_height(middle) > level:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5

## Сколько пива (как высота в стоячей кружке) держит кружка при наклоне,
## не переливаясь через край. Цилиндр: пока поверхность не касается дна,
## это высота у оси; дальше клин, объём считается по хордам.
static func held_height(tilt: float) -> float:
	var slope := tan(tilt)
	if BeerFluid.RIM - 2.0 * SURFACE_RADIUS * slope >= 0.0:
		return BeerFluid.RIM - SURFACE_RADIUS * slope
	var steps := 48
	var width := 2.0 * SURFACE_RADIUS / steps
	var volume := 0.0
	for i in steps:
		var x := -SURFACE_RADIUS + (float(i) + 0.5) * width
		var height := maxf(BeerFluid.RIM - (SURFACE_RADIUS - x) * slope, 0.0)
		volume += 2.0 * sqrt(SURFACE_RADIUS * SURFACE_RADIUS - x * x) * height * width
	return volume / (PI * SURFACE_RADIUS * SURFACE_RADIUS)

## Наклон кружки от вертикали мира: пиво у края и чуть сверх того.
static func beer_tilt(t: float, fill: float, sip: float) -> float:
	var left := maxf(fill - drunk(t, sip), 0.0)
	return reach_tilt(left) + deg_to_rad(FLOW_DEG)

## Запрокидывание головы, радианы вверх. Голова берёт часть наклона.
static func head_tilt(t: float, fill: float, sip: float) -> float:
	var tilt := rad_to_deg(beer_tilt(t, fill, sip))
	var head := clampf(HEAD_MIN_DEG + (tilt - 30.0) * HEAD_SHARE, HEAD_MIN_DEG, HEAD_MAX_DEG)
	return deg_to_rad(head) * tip_weight(t) + deg_to_rad(1.2) * swallow_pulse(t)

## Поза кружки у рта, в пространстве камеры руки.
static func mouth_pose(t: float, fill: float, sip: float) -> Transform3D:
	var tip := tip_weight(t)
	var tilt := lerpf(deg_to_rad(APPROACH_DEG), beer_tilt(t, fill, sip) - head_tilt(t, fill, sip), tip)
	tilt += deg_to_rad(1.5) * swallow_pulse(t)
	var basis := Basis(Vector3.UP, deg_to_rad(MOUTH_YAW_DEG)) * Basis(Vector3.RIGHT, tilt)
	var lip := MOUTH + APPROACH * (1.0 - tip) + Vector3(0.0, 0.0, 0.003) * swallow_pulse(t)
	return Transform3D(basis, lip - basis * LIP)

## Поза запястья в момент t: из покоя (вместе с качанием шага) ко рту и обратно.
## fill — уровень в начале глотка, sip — сколько выпить за глоток.
static func pose(t: float, rest: Transform3D, fill: float, sip: float) -> Transform3D:
	var raise := raise_weight(t)
	if raise == 0.0:
		return rest
	var mouth := mouth_pose(t, fill, sip)
	var weight := clampf(raise, 0.0, 1.0)
	var origin := rest.origin.lerp(mouth.origin, raise) + ARC * 4.0 * weight * (1.0 - weight)
	var turn := rest.basis.get_rotation_quaternion().slerp(mouth.basis.get_rotation_quaternion(), weight)
	return Transform3D(Basis(turn), origin)

## Ускорение кружки от самого глотка (подъём, наклон, опускание), м/с².
## Считается по позе, а не по кадрам: шаг физики и шаг кадра не совпадают.
static func lift_acceleration(t: float, rest: Transform3D, fill: float, sip: float) -> Vector3:
	if t <= 0.0:
		return Vector3.ZERO
	var h := 1.0 / 60.0
	var before := pose(t - h, rest, fill, sip).origin
	var now := pose(t, rest, fill, sip).origin
	var after := pose(t + h, rest, fill, sip).origin
	return (after - 2.0 * now + before) / (h * h)

