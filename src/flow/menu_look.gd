extends RefCounted
## The look the main menu and the pause menu share: a dark panel in the
## middle of the screen with a column of buttons, as the settings panel has.

const BACKGROUND := Color("101d20")
const SHADE := Color(0.025, 0.035, 0.045, 0.83)

## A panel in the middle of `parent`, `width` px wide, with the title
## `title`; returns the column to put the buttons in.
static func column(parent: Node, title: String, width := 520.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	var theme := Theme.new()
	theme.default_font_size = 24
	panel.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182126")
	style.border_color = Color("627575")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(width, 0.0)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	margin.add_child(rows)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 36)
	rows.add_child(heading)
	return rows

## A button `text` at the end of `rows` that calls `action` when pressed.
static func button(rows: Container, text: String, action: Callable) -> Button:
	var made := Button.new()
	made.text = text
	made.pressed.connect(action)
	rows.add_child(made)
	return made

## A line of text at the end of `rows`, for news and questions.
static func notice(rows: Container) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	rows.add_child(label)
	return label
