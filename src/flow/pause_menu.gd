extends CanvasLayer
## The pause menu (Esc in the game): go on, the level's settings panel, a
## save into the open slot, back to the main menu, out of the game. GameFlow
## owns it and shows it while the game stands; it runs in the pause
## (GameFlow's process_mode). Its buttons hold keys of the table and change
## language by themselves; the notice of a save goes with a change of language.

const MENU_LOOK = preload("res://src/flow/menu_look.gd")
const UI_SOUNDS = preload("res://src/flow/ui_sounds.gd")

## The player goes on with the game.
signal resume
## The player goes back to the main menu.
signal leave
## The player leaves the game.
signal quit

var resume_button: Button
var settings_button: Button
var save_button: Button
var menu_button: Button
var quit_button: Button
## The level's settings panel; null for a level without one.
var settings: SettingsPanel
var _notice: Label

func _ready() -> void:
	# Under the settings panel, which opens over the pause.
	layer = 90
	var shade := ColorRect.new()
	shade.color = MENU_LOOK.SHADE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var rows := MENU_LOOK.column(shade, "Пауза")
	resume_button = MENU_LOOK.button(rows, "Продолжить   [Esc]", resume.emit)
	settings_button = MENU_LOOK.button(rows, "Настройки", open_settings)
	save_button = MENU_LOOK.button(rows, "Сохранить", _save)
	menu_button = MENU_LOOK.button(rows, "Выйти в меню", leave.emit)
	quit_button = MENU_LOOK.button(rows, "Выйти из игры", quit.emit)
	_notice = MENU_LOOK.notice(rows)
	UI_SOUNDS.wire(self)
	hide()

## Shows the menu over the stopped game; `panel` is the level's settings
## panel (null for none).
func open(panel: SettingsPanel) -> void:
	settings = panel
	settings_button.disabled = panel == null
	save_button.disabled = SaveService.path.is_empty()
	_notice.text = ""
	UI_SOUNDS.play(UI_SOUNDS.OPEN)
	show()
	UI_SOUNDS.focus(resume_button)

func _save() -> void:
	if SaveService.save():
		_notice.text = tr("Сохранено в ячейку %s.") % SaveService.slot
	else:
		_notice.text = "Не удалось сохранить."

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _notice != null:
		_notice.text = ""

## Opens the panel in place of the menu: the menu comes back when it shuts,
## or with `then_resume` the game goes on.
func open_settings(then_resume := false) -> void:
	hide()
	settings.closed.connect(_settings_closed.bind(then_resume), CONNECT_ONE_SHOT)
	settings.open()

func _settings_closed(then_resume: bool) -> void:
	if then_resume:
		resume.emit()
		return
	show()
	UI_SOUNDS.focus(settings_button)
