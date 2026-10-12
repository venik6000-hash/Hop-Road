extends Node
## Регистрирует карту управления кодом. Автозагрузка: выполняется до сцен.
## physical_keycode, а не keycode: WASD должны работать на любой раскладке.

const ACTIONS := {
	"fishing_rod": [KEY_J],
	"fish_journal": [KEY_I],
	"fish_use": [KEY_Z],
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
	"release_mouse": [KEY_ESCAPE],
}

static func setup() -> void:
	for action_name in ACTIONS:
		if InputMap.has_action(action_name):
			InputMap.action_erase_events(action_name)
		else:
			InputMap.add_action(action_name)
		for keycode in ACTIONS[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action_name, event)

func _ready() -> void:
	setup()
