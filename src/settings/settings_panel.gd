class_name SettingsPanel
extends CanvasLayer
## The settings of the game: the language over three tabs of graphics,
## sound and controls. Labels hold keys of the table (Languages): they change
## language by themselves; the bindings and the notice are written anew.
## Entry: open(). The panel tells `closed` when it shuts. It needs no level,
## so any screen can make one and open it; the level makes one. The panel
## does not pause the game: GameFlow opens it on the action "settings" (F10)
## and holds the pause (docs/LOOP.md, «Состояния игры»). "ui_cancel" (Esc,
## pad B) shuts it. "toggle_hand" (H) shows or hides the hand, in play too.
signal closed

const GAME_SETTINGS = preload("res://src/settings/game_settings.gd")
const INPUT_ACTIONS = preload("res://src/core/input_actions.gd")
const VOLUME_TITLES: Dictionary[StringName, String] = {
	AudioBuses.MASTER: "Общая громкость",
	AudioBuses.MUSIC: "Музыка",
	AudioBuses.AMBIENCE: "Окружение",
	AudioBuses.EFFECTS: "Звуки",
	AudioBuses.VOICE: "Голоса",
	AudioBuses.UI: "Интерфейс",
}
const WAITING := "Нажмите…"

var settings: GAME_SETTINGS
var panel: PanelContainer
var language: OptionButton
var tabs: TabContainer
var quality: OptionButton
var hand: CheckButton
var hand_resolution: OptionButton
var sharpness: HSlider
var volumes: Dictionary[StringName, HSlider] = {}
## InputActions.binding_key -> the button that shows and takes the binding.
var bindings: Dictionary[String, Button] = {}
var mouse_sensitivity: HSlider
var invert_y: CheckButton
var pad_look_speed: HSlider
var stick_deadzone: HSlider
var notice: Label
## The binding the next input goes to: the action and the slot; empty when
## none waits.
var _capture_action := ""
var _capture_slot := &""
var _mouse_mode: Input.MouseMode

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = get_node("/root/GameSettings")
	settings.controls_changed.connect(_show_bindings)
	_build()
	hide()

## Shows the panel with the pointer free.
func open() -> void:
	if visible:
		return
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	tabs.get_tab_bar().grab_focus()

## Hides the panel; the pointer goes back as open() found it.
func close() -> void:
	if not visible:
		return
	_stop_capture()
	hide()
	Input.mouse_mode = _mouse_mode
	closed.emit()

func _input(event: InputEvent) -> void:
	if not _capture_action.is_empty():
		_capture(event)
		return
	if event.is_echo():
		return
	if visible and InputActions.pressed(event, "ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif InputActions.pressed(event, "toggle_hand") and (visible or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_hand_toggled(not settings.show_hand)
		hand.set_pressed_no_signal(settings.show_hand)
		get_viewport().set_input_as_handled()

# --- building -----------------------------------------------------------------

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.045, 0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	var theme := Theme.new()
	theme.default_font_size = 22
	panel.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182126")
	style.border_color = Color("627575")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -420
	panel.offset_bottom = 420
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var language_row := HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 12)
	column.add_child(language_row)
	_label(language_row, "Язык")
	language = OptionButton.new()
	for id: String in Languages.IDS:
		language.add_item(Languages.NAMES[id])
	language.select(Languages.IDS.find(settings.language))
	language.item_selected.connect(_language_selected)
	language_row.add_child(language)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	tabs.add_child(_graphics_tab())
	tabs.add_child(_sound_tab())
	tabs.add_child(_controls_tab())
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size = Vector2(700, 64)
	column.add_child(notice)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var restart := Button.new()
	restart.text = "Перезапустить игру"
	restart.pressed.connect(_restart)
	buttons.add_child(restart)
	var back := Button.new()
	back.text = "Продолжить"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(close)
	buttons.add_child(back)
	_update_notice()

func _tab(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.add_theme_constant_override("separation", 10)
	return page

func _label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)

func _slider(parent: Control, low: float, high: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	parent.add_child(slider)
	return slider

func _graphics_tab() -> Control:
	var page := _tab("Графика")
	_label(page, "Качество")
	quality = OptionButton.new()
	for id: StringName in QualityProfile.IDS:
		quality.add_item(QualityProfile.named(id).title)
	quality.select(QualityProfile.IDS.find(settings.quality))
	quality.item_selected.connect(_quality_selected)
	page.add_child(quality)
	hand = CheckButton.new()
	hand.text = "Показывать руку с кружкой"
	hand.button_pressed = settings.show_hand
	hand.toggled.connect(_hand_toggled)
	page.add_child(hand)
	_label(page, "Чёткость руки с кружкой")
	hand_resolution = OptionButton.new()
	hand_resolution.add_item("По размеру окна")
	hand_resolution.add_item("Максимальная")
	hand_resolution.select(settings.HAND_RESOLUTIONS.find(settings.hand_resolution))
	hand_resolution.item_selected.connect(_hand_resolution_selected)
	page.add_child(hand_resolution)
	_label(page, "Резкость картинки")
	sharpness = _slider(page, 0.0, 1.0, 0.05, settings.sharpness)
	sharpness.value_changed.connect(_sharpness_changed)
	return page

func _sound_tab() -> Control:
	var page := _tab("Звук")
	for bus: StringName in AudioBuses.VOLUMES:
		_label(page, VOLUME_TITLES[bus])
		var slider := _slider(page, 0.0, 1.0, 0.05, settings.volumes[bus])
		slider.value_changed.connect(_volume_changed.bind(bus))
		volumes[bus] = slider
	return page

func _controls_tab() -> Control:
	var page := _tab("Управление")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	list.add_child(grid)
	for heading: String in ["", "Клавиатура и мышь", "Геймпад"]:
		_label(grid, heading)
	for action: String in INPUT_ACTIONS.TITLES:
		var title := Label.new()
		title.text = INPUT_ACTIONS.TITLES[action]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(title)
		for slot: StringName in INPUT_ACTIONS.SLOTS:
			var button := Button.new()
			button.custom_minimum_size = Vector2(170, 0)
			button.pressed.connect(_start_capture.bind(action, slot))
			grid.add_child(button)
			bindings[INPUT_ACTIONS.binding_key(action, slot)] = button
	_label(list, "Чувствительность мыши")
	mouse_sensitivity = _slider(list, settings.MOUSE_SENSITIVITY.x, settings.MOUSE_SENSITIVITY.y, 0.05, settings.mouse_sensitivity)
	mouse_sensitivity.value_changed.connect(_look_changed.bind(&"mouse_sensitivity"))
	invert_y = CheckButton.new()
	invert_y.text = "Обратный взгляд по вертикали"
	invert_y.button_pressed = settings.invert_y
	invert_y.toggled.connect(_invert_toggled)
	list.add_child(invert_y)
	_label(list, "Скорость взгляда стиком, градусов в секунду")
	pad_look_speed = _slider(list, settings.PAD_LOOK_SPEED.x, settings.PAD_LOOK_SPEED.y, 5.0, settings.pad_look_speed)
	pad_look_speed.value_changed.connect(_look_changed.bind(&"pad_look_speed"))
	_label(list, "Мёртвая зона стиков")
	stick_deadzone = _slider(list, settings.STICK_DEADZONE.x, settings.STICK_DEADZONE.y, 0.01, settings.stick_deadzone)
	stick_deadzone.value_changed.connect(_look_changed.bind(&"stick_deadzone"))
	var reset := Button.new()
	reset.text = "Сбросить управление"
	reset.pressed.connect(_reset_controls)
	list.add_child(reset)
	_show_bindings()
	return page

# --- controls -----------------------------------------------------------------

func _show_bindings() -> void:
	for key: String in bindings:
		var action := key.get_slice("/", 0)
		var slot := StringName(key.get_slice("/", 1))
		var labels := PackedStringArray()
		for code: String in INPUT_ACTIONS.bound(settings.bindings, action, slot):
			labels.append(INPUT_ACTIONS.label(code))
		bindings[key].text = " / ".join(labels) if not labels.is_empty() else "—"
	if mouse_sensitivity != null:
		mouse_sensitivity.set_value_no_signal(settings.mouse_sensitivity)
		invert_y.set_pressed_no_signal(settings.invert_y)
		pad_look_speed.set_value_no_signal(settings.pad_look_speed)
		stick_deadzone.set_value_no_signal(settings.stick_deadzone)

func _start_capture(action: String, slot: StringName) -> void:
	_stop_capture()
	_capture_action = action
	_capture_slot = slot
	bindings[INPUT_ACTIONS.binding_key(action, slot)].text = WAITING

func _stop_capture() -> void:
	_capture_action = ""
	_capture_slot = &""
	_show_bindings()

## The next input of the slot that waits becomes its binding. Esc, an input
## of the other device or a click away from the waiting button gives up, and
## the panel takes that input as ever. The wheel scrolls the list, unless a
## choice waits for it.
func _capture(event: InputEvent) -> void:
	var code := INPUT_ACTIONS.code_of(event)
	if code.is_empty():
		return
	var key := event as InputEventKey
	if (key != null and key.physical_keycode == KEY_ESCAPE) or INPUT_ACTIONS.slot_of(code) != _capture_slot:
		_stop_capture()
		if key != null:
			get_viewport().set_input_as_handled()
		return
	var mouse := event as InputEventMouseButton
	if mouse != null:
		var wheel := mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if wheel and not _capture_action.begins_with("choice_"):
			return
		var waiting := bindings[INPUT_ACTIONS.binding_key(_capture_action, _capture_slot)]
		if not wheel and not waiting.get_global_rect().has_point(mouse.position):
			_stop_capture()
			return
	get_viewport().set_input_as_handled()
	var action := _capture_action
	_capture_action = ""
	_capture_slot = &""
	var taken := INPUT_ACTIONS.stranded(settings.bindings, action, code)
	var err := settings.set_binding(action, code)
	_show_bindings()
	if err == ERR_ALREADY_IN_USE:
		notice.text = tr("«%s» — единственная привязка действия «%s». Сначала дайте ему другую.") % [
			INPUT_ACTIONS.label(code), tr(INPUT_ACTIONS.TITLES[taken])]
	else:
		_update_notice(err)

func _look_changed(value: float, setting: StringName) -> void:
	var err: Error = OK
	match setting:
		&"mouse_sensitivity":
			err = settings.set_mouse_sensitivity(value)
		&"pad_look_speed":
			err = settings.set_pad_look_speed(value)
		&"stick_deadzone":
			err = settings.set_stick_deadzone(value)
	_update_notice(err)

func _invert_toggled(inverted: bool) -> void:
	_update_notice(settings.set_invert_y(inverted))

func _reset_controls() -> void:
	_update_notice(settings.reset_controls())

# --- language, sound and graphics ---------------------------------------------

func _language_selected(index: int) -> void:
	_update_notice(settings.set_language(Languages.IDS[index]))

## The labels follow the language by themselves; the texts built here not.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and notice != null:
		_show_bindings()
		_update_notice()


func _volume_changed(value: float, bus: StringName) -> void:
	_update_notice(settings.set_volume(bus, value))

func _sharpness_changed(strength: float) -> void:
	_update_notice(settings.set_sharpness(strength))

func _hand_toggled(shown: bool) -> void:
	_update_notice(settings.set_hand_visible(shown))

func _hand_resolution_selected(index: int) -> void:
	_update_notice(settings.set_hand_resolution(settings.HAND_RESOLUTIONS[index]))

func _quality_selected(index: int) -> void:
	_update_notice(settings.set_quality(QualityProfile.IDS[index]))

func _update_notice(err: Error = OK) -> void:
	if err != OK:
		notice.text = tr("Не удалось сохранить настройки: %s") % error_string(err)
	elif not settings.texture_error.is_empty():
		notice.text = settings.texture_error
	elif settings.restart_required():
		notice.text = "Сохранено. Текстуры и дальность деревьев изменятся после перезапуска. Прогулка начнётся у таверны."
	else:
		notice.text = "Картинка, тени, трава, звук и управление меняются сразу. Текстуры и деревья — после перезапуска."

func _restart() -> void:
	var err: Error = settings.save_preferences()
	if err != OK:
		_update_notice(err)
		return
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	OS.set_restart_on_exit(true, args)
	get_tree().quit()
