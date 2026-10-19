extends Node
## Builds the input map in code. An autoload: it runs before the scenes.
##
## An action has two slots: keyboard with mouse (KEYS) and gamepad (PAD). A
## binding is written as a code: "key:W", "mouse:1", "button:2", "axis:1-".
## Keys are physical_keycode, not keycode: WASD work on any layout. The
## player's own bindings live in GameSettings: a slot is replaced whole.
## Hints on the screen take their labels from here (hint): the player's last
## device decides whether a key or a gamepad button is shown.
##
## Input contexts (docs/PLAYER.md, «Контексты ввода»): a stack with GAME
## always at the bottom. A system puts its context on (push) and takes it off
## (pop). An action belongs to a context (CONTEXTS). An event goes from the
## top down: the first context with an action on that button takes it. A
## deaf context (blocks) lets no other event below it. Systems ask takes,
## releases and live instead of grabbing the mouse. The stack does not touch
## the mouse pointer: the windows that put their context on free it.

const KEYS := &"keys"
const PAD := &"pad"
const SLOTS: Array[StringName] = [KEYS, PAD]

## The actions in the order of the settings panel, with their labels.
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

## Keyboard.
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
## Mouse buttons.
const MOUSE_DEFAULTS: Dictionary[String, Array] = {
	"fish_cast": [MOUSE_BUTTON_LEFT],
	"fish_cancel": [MOUSE_BUTTON_RIGHT],
	"choice_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"choice_previous": [MOUSE_BUTTON_WHEEL_UP],
}
## Gamepad buttons. One button serves two actions only when they are of
## different contexts: a drink of beer (GAME) and the potato in the hand (FOOD).
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
## Gamepad axes: (axis, sign). Diving (GAME) and the line (ROD) are on the
## left trigger: while the rod is in the hands, the trigger reels the line in.
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
## The actions of the sticks: their dead zone is the player's setting.
const STICKS: Array[String] = ["move_forward", "move_back", "move_left", "move_right",
	"look_up", "look_down", "look_left", "look_right"]
const DEADZONE := 0.2
## The tilt of an axis that the settings panel takes as a choice of that axis.
const AXIS_PICK := 0.6

const PAD_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓", JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→",
}
## The label of an axis by its sign: "-" and "+".
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

## Input contexts.
## GAME: the player walks the world. FOOD: food in the hand; PLACE: the player
## picks the place of a campfire; ROD: the rod in the hands. These lie over
## GAME and take only their own buttons. STATION: a station of the brewery;
## BOOK: the brewer's book; JOURNAL: the catch journal; MENU: the pause.
## These are deaf.
const GAME := &"game"
const FOOD := &"food"
const PLACE := &"place"
const ROD := &"rod"
const STATION := &"station"
const BOOK := &"book"
const JOURNAL := &"journal"
const MENU := &"menu"
## A context: {actions: its actions, blocks: deaf, pointer: the window
## frees the pointer and closes the game (in_play)}.
const CONTEXTS: Dictionary[StringName, Dictionary] = {
	GAME: {"actions": ["move_forward", "move_back", "move_left", "move_right", "look_up", "look_down", "look_left",
		"look_right", "sprint", "swim_up", "swim_down", "interact", "drink_beer", "choice_next", "choice_previous",
		"place_camp", "camp_secondary", "guide_outing", "camp_refill", "fishing_rod", "fish_use", "fish_journal",
		"toggle_hand", "help", "screenshot", "settings", "pause"], "blocks": true, "pointer": false},
	FOOD: {"actions": ["eat_potato", "camp_secondary"], "blocks": false, "pointer": false},
	PLACE: {"actions": ["place_camp"], "blocks": false, "pointer": false},
	ROD: {"actions": ["fish_cast", "fish_cancel"], "blocks": false, "pointer": false},
	STATION: {"actions": ["look_up", "look_down", "look_left", "look_right", "interact", "choice_next", "choice_previous",
		"toggle_hand", "help", "screenshot", "settings", "pause"], "blocks": true, "pointer": false},
	BOOK: {"actions": ["move_left", "move_right", "interact", "toggle_hand", "help", "screenshot", "settings", "pause"],
		"blocks": true, "pointer": false},
	JOURNAL: {"actions": ["fish_journal", "screenshot", "settings", "pause"], "blocks": true, "pointer": true},
	MENU: {"actions": [], "blocks": true, "pointer": true},
}

## The player's last input came from a gamepad: hints name its buttons.
var pad_used := false
## The contexts over GAME, from the bottom up: {context, holder: the owner}.
var _stack: Array[Dictionary] = []

## Builds the map: the default bindings, with the player's `bindings` over
## them (GameSettings.bindings: binding_key -> codes). `deadzone` is for the sticks.
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

## The codes of slot `slot` of action `action`: the player's own or the defaults.
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

## Whether `event` presses action `action` now: a key or a button once, an
## axis once, when it leaves the dead zone. InputEventJoypadMotion comes while
## the axis moves, and is_action_pressed is true for each.
static func pressed(event: InputEvent, action: StringName) -> bool:
	return event.is_action_pressed(action) and (not event is InputEventJoypadMotion or Input.is_action_just_pressed(action))

## The slot of a code: KEYS for keys and the mouse, PAD for the gamepad.
static func slot_of(code: String) -> StringName:
	return KEYS if code.begins_with("key:") or code.begins_with("mouse:") else PAD

## The event of a code; null for a code that does not read.
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

## The code of the event the player pressed in the settings panel; "" when it is no binding.
static func code_of(event: InputEvent) -> String:
	var motion := event as InputEventJoypadMotion
	if motion != null and absf(motion.axis_value) < AXIS_PICK:
		return ""
	var key := event as InputEventKey
	if key != null and key.echo:
		return ""
	return code_for(event) if event.is_pressed() or motion != null else ""

## The code of a map event; "" for an event of another kind.
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

## The action that would be left without a binding in its slot if `action`
## got code `code`: `action` has nothing in this slot to give in exchange, and
## that action's code is its only one. "" when there is none.
static func stranded(bindings: Dictionary, action: String, code: String) -> String:
	var slot := slot_of(code)
	if not bound(bindings, action, slot).is_empty():
		return ""
	for other: String in TITLES:
		if other != action and bound(bindings, other, slot) == PackedStringArray([code]):
			return other
	return ""

## The bindings after action `action` got code `code`. The slot of the code
## is replaced whole. If another action had the code, it gets the former
## first code of this slot of `action`: the keys swap places. Ask stranded
## first.
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

## The label of a code for the panel and the hints, in the game's language.
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

## The label of an action by the map: the first binding of the slot the
## player plays with now, else the first of the other.
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

## `text` (translated) with labels in place of marks: {interact} is the
## action's label, {move} the walking keys or the left stick, {look} the mouse
## or the right stick, {choice} the mouse wheel or the pair of choice buttons.
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

# ---- Input contexts ------------------------------------------------------------

## `holder` puts context `context` (CONTEXTS) on top of the stack. Another
## push of the same holder and context brings it to the top.
func push(context: StringName, holder: Object) -> void:
	if context == GAME or not CONTEXTS.has(context) or holder == null:
		push_error("InputActions.push: no context %s for %s" % [context, holder])
		return
	pop(holder, context)
	_stack.append({"context": context, "holder": holder})

## `holder` takes its context `context` off, wherever it lies; without
## `context`, all its contexts.
func pop(holder: Object, context := &"") -> void:
	for index in range(_stack.size() - 1, -1, -1):
		var entry: Dictionary = _stack[index]
		if entry.holder == holder and (context.is_empty() or entry.context == context):
			_stack.remove_at(index)

## The contexts from the top down, GAME last. The context of a holder that
## is gone is taken off.
func contexts() -> Array[StringName]:
	var result: Array[StringName] = []
	for index in range(_stack.size() - 1, -1, -1):
		var entry: Dictionary = _stack[index]
		if not is_instance_valid(entry.holder):
			_stack.remove_at(index)
			continue
		result.append(entry.context)
	result.append(GAME)
	return result

## The top context.
func current() -> StringName:
	return contexts()[0]

## The game is seen and played: no window of the stack has freed the
## pointer (the catch journal, the pause).
func in_play() -> bool:
	for context: StringName in contexts():
		if CONTEXTS[context].pointer:
			return false
	return true

## `event` presses `action` (pressed), and the button reaches the context
## of that action.
func takes(event: InputEvent, action: StringName) -> bool:
	return pressed(event, action) and routes(event, action)

## `event` presses `action` of context `context`: the button reaches that
## context, and no context above it has taken the button for its own action.
## So a part of a system reads only its own context (CampSystem).
func takes_in(event: InputEvent, action: StringName, context: StringName) -> bool:
	return pressed(event, action) and reaches(event, action, context)

## The button `event` of action `action` reaches context `context`, and
## that context has the action.
func reaches(event: InputEvent, action: StringName, context: StringName) -> bool:
	for each: StringName in contexts():
		var own: Array = CONTEXTS[each].actions
		if each == context:
			return own.has(String(action))
		if own.has(String(action)):
			return false
		for other: String in own:
			if InputMap.has_action(other) and event.is_action(other):
				return false
		if CONTEXTS[each].blocks:
			return false
	return false

## `event` releases `action`, and the button reaches the context of that action.
func releases(event: InputEvent, action: StringName) -> bool:
	return event.is_action_released(action) and routes(event, action)

## The button `event` reaches the context of action `action`: no context
## above it has taken the button for its own action or held it back.
func routes(event: InputEvent, action: StringName) -> bool:
	for context: StringName in contexts():
		var own: Array = CONTEXTS[context].actions
		if own.has(String(action)):
			return true
		for other: String in own:
			if InputMap.has_action(other) and event.is_action(other):
				return false
		if CONTEXTS[context].blocks:
			return false
	return false

## Action `action`, which the game polls each frame (walking, looking,
## diving), is live: its context can be reached, and no action above it is on
## the same buttons.
func live(action: StringName) -> bool:
	for context: StringName in contexts():
		var own: Array = CONTEXTS[context].actions
		if own.has(String(action)):
			return true
		for other: String in own:
			if shares_binding(other, action):
				return false
		if CONTEXTS[context].blocks:
			return false
	return false

## The strength of action `action` (Input.get_action_strength); 0 while it is not live.
func strength(action: StringName) -> float:
	return Input.get_action_strength(action) if live(action) else 0.0

## The axis of two actions (Input.get_axis): the live one of them gives its strength.
func axis(negative: StringName, positive: StringName) -> float:
	return strength(positive) - strength(negative)

## Actions `one` and `other` share a button.
static func shares_binding(one: StringName, other: StringName) -> bool:
	if one == other or not InputMap.has_action(one) or not InputMap.has_action(other):
		return false
	for event: InputEvent in InputMap.action_get_events(one):
		for theirs: InputEvent in InputMap.action_get_events(other):
			if event.is_match(theirs):
				return true
	return false

## GameSettings, loaded earlier, has already built the map with its
## bindings. The window tells the player's device before all nodes: an event
## that a node eats switches the hints too.
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
