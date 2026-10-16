extends Node
## Регистрирует карту управления кодом. Автозагрузка: выполняется до сцен.
##
## У действия два гнезда: клавиатура с мышью (KEYS) и геймпад (PAD). Привязка
## записана кодом: "key:W", "mouse:1", "button:2", "axis:1-". Клавиши —
## physical_keycode, а не keycode: WASD работают на любой раскладке. Свои
## привязки игрока хранит GameSettings: гнездо заменяется целиком.
## Подсказки на экране берут подписи отсюда (hint): последнее устройство
## игрока решает, показать клавишу или кнопку геймпада.

const KEYS := &"keys"
const PAD := &"pad"
const SLOTS: Array[StringName] = [KEYS, PAD]

## Действия в порядке панели настроек, с подписями.
const TITLES: Dictionary[String, String] = {
	"move_forward": "Вперёд",
	"move_back": "Назад",
	"move_left": "Влево",
	"move_right": "Вправо",
	"look_up": "Взгляд вверх",
	"look_down": "Взгляд вниз",
	"look_left": "Взгляд влево",
	"look_right": "Взгляд вправо",
	"sprint": "Бег",
	"swim_up": "Всплыть",
	"swim_down": "Нырнуть",
	"interact": "Действие",
	"drink_beer": "Пиво",
	"choice_next": "Следующий выбор",
	"choice_previous": "Предыдущий выбор",
	"place_camp": "Костёр",
	"eat_potato": "Есть",
	"camp_secondary": "Поделиться / потушить / попрощаться",
	"guide_outing": "Любимое место спутника",
	"camp_refill": "Налить у костра",
	"fishing_rod": "Удочка",
	"fish_cast": "Забросить / тянуть",
	"fish_cancel": "Смотать леску",
	"fish_use": "Улов",
	"fish_journal": "Журнал улова",
	"toggle_hand": "Рука с кружкой",
	"help": "Справка",
	"screenshot": "Снимок экрана",
	"settings": "Настройки",
	"pause": "Пауза",
}

## Клавиатура.
const KEY_DEFAULTS: Dictionary[String, Array] = {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"swim_up": [KEY_SPACE],
	"swim_down": [KEY_C, KEY_CTRL],
	"interact": [KEY_E],
	"drink_beer": [KEY_V],
	"place_camp": [KEY_K],
	"eat_potato": [KEY_F],
	"camp_secondary": [KEY_Q],
	"guide_outing": [KEY_G],
	"camp_refill": [KEY_X],
	"fishing_rod": [KEY_J],
	"fish_use": [KEY_Z],
	"fish_journal": [KEY_I],
	"toggle_hand": [KEY_H],
	"help": [KEY_TAB],
	"screenshot": [KEY_F12],
	"settings": [KEY_F10],
	"pause": [KEY_ESCAPE],
}
## Кнопки мыши.
const MOUSE_DEFAULTS: Dictionary[String, Array] = {
	"fish_cast": [MOUSE_BUTTON_LEFT],
	"fish_cancel": [MOUSE_BUTTON_RIGHT],
	"choice_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"choice_previous": [MOUSE_BUTTON_WHEEL_UP],
}
## Кнопки геймпада. Одна кнопка у двух действий — только там, где они не
## встречаются: глоток пива и картошка в руках (руки заняты одним).
const BUTTON_DEFAULTS: Dictionary[String, Array] = {
	"swim_up": [JOY_BUTTON_A],
	"camp_secondary": [JOY_BUTTON_B],
	"interact": [JOY_BUTTON_X],
	"drink_beer": [JOY_BUTTON_Y],
	"eat_potato": [JOY_BUTTON_Y],
	"fishing_rod": [JOY_BUTTON_LEFT_SHOULDER],
	"fish_use": [JOY_BUTTON_RIGHT_SHOULDER],
	"sprint": [JOY_BUTTON_LEFT_STICK],
	"guide_outing": [JOY_BUTTON_RIGHT_STICK],
	"place_camp": [JOY_BUTTON_DPAD_UP],
	"camp_refill": [JOY_BUTTON_DPAD_DOWN],
	"choice_previous": [JOY_BUTTON_DPAD_LEFT],
	"choice_next": [JOY_BUTTON_DPAD_RIGHT],
	"fish_journal": [JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
}
## Оси геймпада: (ось, знак). Нырок и леска — на левом курке: удочку в воде
## не достать (LakesideSystem.toggle_rod).
const AXIS_DEFAULTS: Dictionary[String, Array] = {
	"move_forward": [Vector2i(JOY_AXIS_LEFT_Y, -1)],
	"move_back": [Vector2i(JOY_AXIS_LEFT_Y, 1)],
	"move_left": [Vector2i(JOY_AXIS_LEFT_X, -1)],
	"move_right": [Vector2i(JOY_AXIS_LEFT_X, 1)],
	"look_up": [Vector2i(JOY_AXIS_RIGHT_Y, -1)],
	"look_down": [Vector2i(JOY_AXIS_RIGHT_Y, 1)],
	"look_left": [Vector2i(JOY_AXIS_RIGHT_X, -1)],
	"look_right": [Vector2i(JOY_AXIS_RIGHT_X, 1)],
	"swim_down": [Vector2i(JOY_AXIS_TRIGGER_LEFT, 1)],
	"fish_cancel": [Vector2i(JOY_AXIS_TRIGGER_LEFT, 1)],
	"fish_cast": [Vector2i(JOY_AXIS_TRIGGER_RIGHT, 1)],
}
## Действия стиков: их мёртвая зона — настройка игрока.
const STICKS: Array[String] = ["move_forward", "move_back", "move_left", "move_right",
	"look_up", "look_down", "look_left", "look_right"]
const DEADZONE := 0.2
## Отклонение оси, которое панель настроек принимает за выбор этой оси.
const AXIS_PICK := 0.6

const PAD_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓", JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→",
}
## Подпись оси по знаку: "-" и "+".
const AXIS_NAMES: Dictionary[int, Array] = {
	JOY_AXIS_LEFT_X: ["левый стик ←", "левый стик →"], JOY_AXIS_LEFT_Y: ["левый стик ↑", "левый стик ↓"],
	JOY_AXIS_RIGHT_X: ["правый стик ←", "правый стик →"], JOY_AXIS_RIGHT_Y: ["правый стик ↑", "правый стик ↓"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}
const KEY_NAMES: Dictionary[int, String] = {
	KEY_SPACE: "Пробел", KEY_ESCAPE: "Esc", KEY_CTRL: "Ctrl", KEY_SHIFT: "Shift",
	KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→",
}
const MOUSE_NAMES: Dictionary[int, String] = {
	MOUSE_BUTTON_LEFT: "ЛКМ", MOUSE_BUTTON_RIGHT: "ПКМ", MOUSE_BUTTON_MIDDLE: "СКМ",
	MOUSE_BUTTON_WHEEL_UP: "колесо вверх", MOUSE_BUTTON_WHEEL_DOWN: "колесо вниз",
}

## Последний ввод игрока был с геймпада: подсказки называют его кнопки.
var pad_used := false

## Строит карту: привязки по умолчанию, поверх них `bindings` игрока
## (GameSettings.bindings: binding_key -> коды). `deadzone` — для стиков.
static func setup(bindings: Dictionary = {}, deadzone := DEADZONE) -> void:
	for action: String in TITLES:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		InputMap.action_set_deadzone(action, deadzone if action in STICKS else DEADZONE)
		for slot: StringName in SLOTS:
			for code: String in bound(bindings, action, slot):
				var event := event_of(code)
				if event != null:
					InputMap.action_add_event(action, event)

## Коды гнезда `slot` действия `action`: свои игрока или по умолчанию.
static func bound(bindings: Dictionary, action: String, slot: StringName) -> PackedStringArray:
	var own: Variant = bindings.get(binding_key(action, slot))
	return own if own is PackedStringArray else defaults(action, slot)

static func binding_key(action: String, slot: StringName) -> String:
	return "%s/%s" % [action, slot]

static func defaults(action: String, slot: StringName) -> PackedStringArray:
	var codes := PackedStringArray()
	if slot == KEYS:
		for key: Key in KEY_DEFAULTS.get(action, []):
			codes.append("key:" + OS.get_keycode_string(key))
		for button: MouseButton in MOUSE_DEFAULTS.get(action, []):
			codes.append("mouse:%d" % button)
	else:
		for button: JoyButton in BUTTON_DEFAULTS.get(action, []):
			codes.append("button:%d" % button)
		for axis: Vector2i in AXIS_DEFAULTS.get(action, []):
			codes.append("axis:%d%s" % [axis.x, "+" if axis.y > 0 else "-"])
	return codes

## Нажимает ли `event` действие `action` сейчас: клавиша и кнопка — один раз,
## ось — один раз, когда выходит из мёртвой зоны. InputEventJoypadMotion
## приходит, пока ось движется, и is_action_pressed верен для каждого.
static func pressed(event: InputEvent, action: StringName) -> bool:
	return event.is_action_pressed(action) and (not event is InputEventJoypadMotion or Input.is_action_just_pressed(action))

## Гнездо кода: KEYS для клавиш и мыши, PAD для геймпада.
static func slot_of(code: String) -> StringName:
	return KEYS if code.begins_with("key:") or code.begins_with("mouse:") else PAD

## Событие по коду; null для кода, который не читается.
static func event_of(code: String) -> InputEvent:
	var kind := code.get_slice(":", 0)
	var value := code.trim_prefix(kind + ":")
	match kind:
		"key":
			var key := OS.find_keycode_from_string(value)
			if key == KEY_NONE:
				return null
			var key_event := InputEventKey.new()
			key_event.physical_keycode = key
			return key_event
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = value.to_int() as MouseButton
			return mouse if value.is_valid_int() else null
		"button":
			var button := InputEventJoypadButton.new()
			button.device = -1
			button.button_index = value.to_int() as JoyButton
			return button if value.is_valid_int() else null
		"axis":
			var axis := value.left(-1)
			if not axis.is_valid_int() or not value.right(1) in ["+", "-"]:
				return null
			var motion := InputEventJoypadMotion.new()
			motion.device = -1
			motion.axis = axis.to_int() as JoyAxis
			motion.axis_value = 1.0 if value.ends_with("+") else -1.0
			return motion
	return null

## Код события, которое игрок нажал в панели настроек; "" — не привязка.
static func code_of(event: InputEvent) -> String:
	var motion := event as InputEventJoypadMotion
	if motion != null and absf(motion.axis_value) < AXIS_PICK:
		return ""
	var key := event as InputEventKey
	if key != null and key.echo:
		return ""
	return code_for(event) if event.is_pressed() or motion != null else ""

## Код события карты; "" для события другого рода.
static func code_for(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var physical := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:" + OS.get_keycode_string(physical)
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return "mouse:%d" % mouse.button_index
	var button := event as InputEventJoypadButton
	if button != null:
		return "button:%d" % button.button_index
	var motion := event as InputEventJoypadMotion
	if motion != null:
		return "axis:%d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return ""

## Действие, которое осталось бы без привязки в своём гнезде, если дать
## `action` код `code`: у `action` в этом гнезде нечего отдать взамен, а у
## того действия код — единственный. "" — такого нет.
static func stranded(bindings: Dictionary, action: String, code: String) -> String:
	var slot := slot_of(code)
	if not bound(bindings, action, slot).is_empty():
		return ""
	for other: String in TITLES:
		if other != action and bound(bindings, other, slot) == PackedStringArray([code]):
			return other
	return ""

## Привязки после того, как действию `action` дали код `code`. Гнездо кода
## заменяется целиком. Если код был у другого действия, оно получает
## прежний первый код этого гнезда `action`: клавиши меняются местами.
## Сначала спросите stranded.
static func rebind(bindings: Dictionary, action: String, code: String) -> Dictionary:
	var slot := slot_of(code)
	var result := bindings.duplicate()
	var before := bound(bindings, action, slot)
	for other: String in TITLES:
		if other == action:
			continue
		var codes := bound(bindings, other, slot)
		var at := codes.find(code)
		if at < 0:
			continue
		if before.is_empty() or before[0] in codes:
			codes.remove_at(at)
		else:
			codes[at] = before[0]
		result[binding_key(other, slot)] = codes
	result[binding_key(action, slot)] = PackedStringArray([code])
	return result

## Подпись кода для панели и подсказок, на языке игры.
static func label(code: String) -> String:
	var kind := code.get_slice(":", 0)
	var value := code.trim_prefix(kind + ":")
	match kind:
		"key":
			return TranslationServer.translate(str(KEY_NAMES.get(OS.find_keycode_from_string(value), value)))
		"mouse":
			var mouse: String = MOUSE_NAMES.get(value.to_int(), "")
			return TranslationServer.translate(mouse) if not mouse.is_empty() else TranslationServer.translate("мышь %s") % value
		"button":
			return str(PAD_NAMES.get(value.to_int(), TranslationServer.translate("кнопка %s") % value))
		"axis":
			var names: Array = AXIS_NAMES.get(value.left(-1).to_int(), [])
			if names.size() != 2:
				return TranslationServer.translate("ось %s") % value
			return TranslationServer.translate(str(names[1 if value.ends_with("+") else 0]))
	return code

## Подпись действия по карте: первая привязка гнезда, которым игрок играет
## сейчас, иначе первая другого.
func prompt(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var other := ""
	for event: InputEvent in InputMap.action_get_events(action):
		var code := code_for(event)
		if (slot_of(code) == PAD) == pad_used:
			return label(code)
		if other.is_empty():
			other = code
	return label(other) if not other.is_empty() else "—"

## `text` (переведённый) с подписями вместо меток: {interact} — подпись
## действия, {move} — клавиши ходьбы или левый стик, {look} — мышь или
## правый стик, {choice} — колесо мыши или пара кнопок выбора.
func hint(text: String) -> String:
	if not "{" in text:
		return text
	var out := text.replace("{look}", tr("правый стик") if pad_used else tr("мышь"))
	if pad_used:
		out = out.replace("{move}", tr("левый стик"))
	else:
		out = out.replace("{move}", "".join([prompt("move_forward"), prompt("move_left"), prompt("move_back"), prompt("move_right")]))
	var previous := prompt("choice_previous")
	var next := prompt("choice_next")
	var wheel := previous == label("mouse:%d" % MOUSE_BUTTON_WHEEL_UP) and next == label("mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN)
	out = out.replace("{choice}", tr("колесо") if wheel else "%s / %s" % [previous, next])
	for action: String in TITLES:
		out = out.replace("{%s}" % action, prompt(action))
	return out

## GameSettings, загруженный раньше, уже построил карту со своими привязками.
## Устройство игрока окно сообщает до всех узлов: событие, которое съест
## узел, тоже переключает подсказки.
func _ready() -> void:
	if get_node_or_null("/root/GameSettings") == null:
		setup()
	get_tree().root.window_input.connect(_note_device)

func _note_device(event: InputEvent) -> void:
	var motion := event as InputEventJoypadMotion
	var mouse := event as InputEventMouseMotion
	if event is InputEventJoypadButton or (motion != null and absf(motion.axis_value) > InputMap.action_get_deadzone("look_left")):
		pad_used = true
	elif event is InputEventKey or event is InputEventMouseButton or (mouse != null and mouse.relative.length() > 2.0):
		pad_used = false
