extends CanvasLayer
## The line at the top of the screen that tells the player of a trouble with
## the save (GameEvents.save_trouble): the file did not read and its .bak was
## taken, the game started anew, a save was not written. GameFlow owns it.
## Its time runs (`ticking`) only while the game or the main menu is shown
## (GameEvents.game_state_changed): a trouble found while the level loads
## waits for the game. A save written after one that was not takes the line
## of that one away (GameEvents.game_saved). The line holds a key of the
## table and changes language by itself.

const SAVE_SERVICE = preload("res://src/save/save_service.gd")
const GAME_FLOW = preload("res://src/flow/game_flow.gd")

## Seconds the line stays, and the last of them in which it fades.
const SECONDS := 12.0
const FADE := 2.0
const TEXTS: Dictionary[StringName, String] = {
	SAVE_SERVICE.FROM_BACKUP: "Сохранение повреждено. Игра продолжена из прошлой копии.",
	SAVE_SERVICE.STARTED_ANEW: "Сохранение не читается. Игра начата заново, старый файл отложен рядом.",
	SAVE_SERVICE.NOT_SAVED: "Игра не сохранилась: файл не записан. Прежнее сохранение цело.",
}

var label: Label
## The line's time runs out.
var ticking := false
var _panel: PanelContainer
var _left := 0.0
## The trouble whose line shows.
var _trouble := &""

func _ready() -> void:
	# Over the pause menu and the settings panel.
	layer = 110
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.1, 0.9)
	style.border_color = Color("c9a25c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = 32.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(640.0, 0.0)
	label.add_theme_font_size_override("font_size", 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(label)
	add_child(_panel)
	_panel.visible = false
	GameEvents.save_trouble.connect(tell)
	GameEvents.game_saved.connect(_saved)
	GameEvents.game_state_changed.connect(_moved)

## Shows the line of `trouble` (SaveService) for SECONDS of the game.
func tell(trouble: StringName, _slot := "") -> void:
	if not TEXTS.has(trouble):
		return
	label.text = TEXTS[trouble]
	_trouble = trouble
	_left = SECONDS
	_panel.modulate.a = 1.0
	_panel.visible = true

## A save is written: the line of one that was not goes away.
func _saved(_slot: String) -> void:
	if _trouble == SAVE_SERVICE.NOT_SAVED:
		_panel.visible = false
		_trouble = &""

## The game moved to `state`: the line's time runs in the game and the menu.
func _moved(state: StringName, _previous: StringName) -> void:
	ticking = state == GAME_FLOW.PLAYING or state == GAME_FLOW.MENU

## The line is on the screen.
func shown() -> bool:
	return _panel.visible

func _process(delta: float) -> void:
	if not _panel.visible or not ticking:
		return
	_left -= delta
	_panel.modulate.a = clampf(_left / FADE, 0.0, 1.0)
	if _left <= 0.0:
		_panel.visible = false
		_trouble = &""
