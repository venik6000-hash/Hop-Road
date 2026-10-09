extends CanvasLayer
## F10 pauses play and opens graphics options. H toggles only the hand preference.
const RenderQuality = preload("res://src/render/render_quality.gd")
var level: Node3D
var settings: Node
var panel: PanelContainer
var quality: OptionButton
var render: OptionButton
var hand: CheckButton
var hand_resolution: OptionButton
var notice: Label
var _mouse_mode: Input.MouseMode
var _was_paused := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = get_node("/root/GameSettings")
	settings.hand_visibility_changed.connect(_apply_hand)
	_apply_hand(settings.show_hand)
	_build()
	hide()

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.045, 0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	var theme := Theme.new()
	theme.default_font_size = 24
	panel.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182126")
	style.border_color = Color("627575")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -350
	panel.offset_right = 350
	panel.offset_top = -390
	panel.offset_bottom = 390
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Графика"
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	var render_label := Label.new()
	render_label.text = "Качество изображения"
	column.add_child(render_label)
	render = OptionButton.new()
	render.add_item("Быстрое — меньше пикселей, короче тени")
	render.add_item("Сбалансированное — рекомендуется")
	render.add_item("Максимальное — каждый пиксель окна")
	render.select(RenderQuality.TIERS.find(settings.render_quality))
	render.item_selected.connect(_render_selected)
	column.add_child(render)
	var label := Label.new()
	label.text = "Качество текстур"
	column.add_child(label)
	quality = OptionButton.new()
	quality.add_item("Максимальное — текущие оригиналы")
	quality.add_item("Среднее — сжатые, до 1024 px")
	quality.add_item("Низкое — сжатые, до 512 px")
	quality.select(settings.TIERS.find(settings.texture_quality))
	quality.item_selected.connect(_quality_selected)
	column.add_child(quality)
	hand = CheckButton.new()
	hand.text = "Показывать руку с кружкой   [H]"
	hand.button_pressed = settings.show_hand
	hand.toggled.connect(_hand_toggled)
	column.add_child(hand)
	var hand_label := Label.new()
	hand_label.text = "Чёткость руки с кружкой"
	column.add_child(hand_label)
	hand_resolution = OptionButton.new()
	hand_resolution.add_item("По размеру окна")
	hand_resolution.add_item("Максимальная")
	hand_resolution.select(settings.HAND_RESOLUTIONS.find(settings.hand_resolution))
	hand_resolution.item_selected.connect(_hand_resolution_selected)
	column.add_child(hand_resolution)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size = Vector2(600, 96)
	column.add_child(notice)
	var restart := Button.new()
	restart.text = "Перезапустить игру"
	restart.pressed.connect(_restart)
	column.add_child(restart)
	var close := Button.new()
	close.text = "Продолжить   [F10 / Esc]"
	close.pressed.connect(_close)
	column.add_child(close)
	_update_notice()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F10:
			if visible:
				_close()
			else:
				_open()
			get_viewport().set_input_as_handled()
		elif visible and event.physical_keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_H and (visible or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
			_hand_toggled(not settings.show_hand)
			hand.set_pressed_no_signal(settings.show_hand)
			get_viewport().set_input_as_handled()

func _open() -> void:
	if level.lakeside != null and level.lakeside.panel.visible:
		return
	_mouse_mode = Input.mouse_mode
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	quality.grab_focus()

func _close() -> void:
	if not visible:
		return
	hide()
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode

func _apply_hand(shown: bool) -> void:
	level.player.viewmodel.set_hand_visible(shown)

func _hand_toggled(shown: bool) -> void:
	var err: Error = settings.set_hand_visible(shown)
	_update_notice(err)

func _hand_resolution_selected(index: int) -> void:
	var err: Error = settings.set_hand_resolution(settings.HAND_RESOLUTIONS[index])
	_update_notice(err)

func _render_selected(index: int) -> void:
	var err: Error = settings.set_render_quality(RenderQuality.TIERS[index])
	_update_notice(err)

func _quality_selected(index: int) -> void:
	var err: Error = settings.set_texture_quality(settings.TIERS[index])
	_update_notice(err)

func _update_notice(err: Error = OK) -> void:
	if err != OK:
		notice.text = "Не удалось сохранить настройки: " + error_string(err)
	elif not settings.texture_error.is_empty():
		notice.text = settings.texture_error
	elif settings.restart_required():
		notice.text = "Сохранено. Текстуры изменятся после перезапуска. Прогулка начнётся у таверны."
	else:
		notice.text = "Текстуры меняются после перезапуска. Качество изображения и рука меняются сразу."

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
