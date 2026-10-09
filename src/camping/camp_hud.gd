extends RefCounted
## The camp's conversation caption and the food hint, on the "CampConversation"
## canvas of the camp node.

static func build(camp: CampSystem) -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "CampConversation"
	camp.add_child(canvas)
	camp.caption_panel = PanelContainer.new()
	camp.caption_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	camp.caption_panel.offset_left = 36
	camp.caption_panel.offset_right = -36
	camp.caption_panel.offset_top = -205
	camp.caption_panel.offset_bottom = -122
	camp.caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.045, 0.028, 0.82)
	background.border_color = Color(0.71, 0.54, 0.32, 0.55)
	background.border_width_left = 3
	background.content_margin_left = 18
	background.content_margin_right = 18
	background.content_margin_top = 10
	background.content_margin_bottom = 10
	camp.caption_panel.add_theme_stylebox_override("panel", background)
	canvas.add_child(camp.caption_panel)
	camp.caption = Label.new()
	camp.caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camp.caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	style(camp.caption, 21)
	camp.caption_panel.add_child(camp.caption)
	camp.caption_panel.visible = false
	camp.food_hint = Label.new()
	camp.food_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	camp.food_hint.offset_left = 24
	camp.food_hint.offset_right = -24
	camp.food_hint.offset_top = 165
	camp.food_hint.offset_bottom = 199
	camp.food_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style(camp.food_hint, 18)
	canvas.add_child(camp.food_hint)

static func style(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff2d7"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
