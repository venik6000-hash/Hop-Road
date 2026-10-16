extends Control
## The main menu (scenes/menu/main_menu.tscn, the project's main scene): go
## on with the slot saved last, a new game, a game in a slot of the player's
## choice, the settings and the way out. It asks GameFlow for a game through
## its signals; a new game over a save asks the player first. Buttons and
## headings hold keys of the table and change language by themselves; the
## lines about the slots are written anew (_write).

const MENU_LOOK = preload("res://src/flow/menu_look.gd")

## A game in slot `slot` is asked for: anew (`fresh`) or from its save.
signal play(slot: String, fresh: bool)
## The player leaves the game.
signal quit

## The slots the menu offers (SaveService slot names).
const SLOTS: Array[String] = ["1", "2", "3"]

var continue_button: Button
var new_button: Button
var pick_button: Button
var settings_button: Button
var quit_button: Button
## The rows of the slot page, one per SLOTS.
var slot_buttons: Array[Button] = []
## Starts the new game over the save of the slot asked about.
var confirm_button: Button
## The line under the buttons: why the last game did not start ("" for
## none). GameFlow sets it before the menu enters the tree.
var notice := ""
var settings: SettingsPanel
var _main: Control
var _slots: Control
var _confirm: Control
var _notice: Label
var _slots_title: Label
var _question: Label
## The slot page starts new games (true) or opens saves (false).
var _fresh := false
## The slot the confirmation is about.
var _asked := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = MENU_LOOK.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_main = _page()
	var rows := MENU_LOOK.column(_main, "Хмельная тропа")
	continue_button = MENU_LOOK.button(rows, "Продолжить", _continue)
	new_button = MENU_LOOK.button(rows, "Новая игра", _open_slots.bind(true))
	pick_button = MENU_LOOK.button(rows, "Выбрать ячейку", _open_slots.bind(false))
	settings_button = MENU_LOOK.button(rows, "Настройки", _open_settings)
	quit_button = MENU_LOOK.button(rows, "Выход", quit.emit)
	_notice = MENU_LOOK.notice(rows)
	_slots = _page()
	rows = MENU_LOOK.column(_slots, "")
	_slots_title = rows.get_child(0) as Label
	for slot: String in SLOTS:
		slot_buttons.append(MENU_LOOK.button(rows, "", _slot_chosen.bind(slot)))
	MENU_LOOK.button(rows, "Назад", _show.bind(_main))
	_confirm = _page()
	rows = MENU_LOOK.column(_confirm, "Новая игра")
	_question = MENU_LOOK.notice(rows)
	confirm_button = MENU_LOOK.button(rows, "Начать заново", _confirmed)
	MENU_LOOK.button(rows, "Назад", _show.bind(_slots))
	settings = SettingsPanel.new()
	settings.name = "Settings"
	add_child(settings)
	_show(_main)

func _page() -> Control:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	return page

func _show(page: Control) -> void:
	for each: Control in [_main, _slots, _confirm]:
		each.visible = each == page
	if page == _main:
		continue_button.disabled = SaveService.last_slot().is_empty()
		_notice.text = notice
		_notice.visible = not notice.is_empty()
	_write()
	_first_button(page).grab_focus()

## The lines about the slots, in the language of the game.
func _write() -> void:
	var last := SaveService.last_slot()
	continue_button.text = "Продолжить" if last.is_empty() else tr("Продолжить — %s") % describe(last)
	for index: int in SLOTS.size():
		slot_buttons[index].text = describe(SLOTS[index])
	if not _asked.is_empty():
		_question.text = tr("%s.\nНачать новую игру в этой ячейке? Сохранение будет заменено.") % describe(_asked)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _confirm != null:
		_write()

func _first_button(page: Control) -> Button:
	for found: Node in page.find_children("*", "Button", true, false):
		var button := found as Button
		if not button.disabled:
			return button
	return null

func _continue() -> void:
	var last := SaveService.last_slot()
	if not last.is_empty():
		play.emit(last, false)

func _open_slots(fresh: bool) -> void:
	_fresh = fresh
	_slots_title.text = "Новая игра" if fresh else "Выбрать ячейку"
	_show(_slots)

## A new game over a save waits for the player's word; an empty slot always
## starts anew.
func _slot_chosen(slot: String) -> void:
	var taken := not SaveService.slot_file(slot).is_empty()
	if not taken:
		play.emit(slot, true)
	elif not _fresh:
		play.emit(slot, false)
	else:
		_asked = slot
		_show(_confirm)

func _confirmed() -> void:
	play.emit(_asked, true)

func _open_settings() -> void:
	settings.open()

## The slot as the menu names it: its number and the day and hour of its save.
static func describe(slot: String) -> String:
	if SaveService.slot_file(slot).is_empty():
		return TranslationServer.translate("Ячейка %s — пуста") % slot
	var saved := SaveService.read_slot(slot)
	if saved.is_empty():
		return TranslationServer.translate("Ячейка %s — сохранение не читается") % slot
	var fields := ValleyLoop.unpack(saved)
	var hour: float = fields.hour
	if hour < 0.0:
		return TranslationServer.translate("Ячейка %s — день %d") % [slot, fields.day]
	return TranslationServer.translate("Ячейка %s — день %d, %02d:%02d") % [slot, fields.day, int(hour),
		int(fposmod(hour, 1.0) * 60.0)]

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _confirm.visible:
		_show(_slots)
	elif _slots.visible:
		_show(_main)
	else:
		return
	get_viewport().set_input_as_handled()
