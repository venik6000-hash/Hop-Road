extends RefCounted
## The lake's HUD on its own canvas (layer 6): the hint line, the cast and
## line-tension gauge and the fish journal panel.

static func build(lake: LakesideSystem) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 6
	lake.add_child(canvas)
	lake.hud = Label.new()
	lake.hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lake.hud.anchor_left = 0
	lake.hud.anchor_right = 1
	lake.hud.offset_left = 24
	lake.hud.offset_right = -24
	lake.hud.offset_top = -210
	lake.hud.offset_bottom = -130
	lake.hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lake.hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lake.hud.add_theme_font_size_override("font_size", 22)
	lake.hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	lake.hud.add_theme_constant_override("shadow_offset_x", 2)
	lake.hud.add_theme_constant_override("shadow_offset_y", 2)
	lake.hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(lake.hud)
	lake.gauge = ProgressBar.new()
	lake.gauge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lake.gauge.offset_left = -150
	lake.gauge.offset_right = 150
	lake.gauge.offset_top = -238
	lake.gauge.offset_bottom = -220
	lake.gauge.show_percentage = false
	canvas.add_child(lake.gauge)
	lake.panel = PanelContainer.new()
	lake.panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lake.panel.offset_left = -300
	lake.panel.offset_right = 300
	lake.panel.offset_top = -230
	lake.panel.offset_bottom = 230
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	lake.panel.add_child(margin)
	lake.journal_text = Label.new()
	lake.journal_text.add_theme_font_size_override("font_size", 21)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 390)
	margin.add_child(scroll)
	scroll.add_child(lake.journal_text)
	canvas.add_child(lake.panel)
	lake.panel.hide()

static func update(lake: LakesideSystem) -> void:
	lake.hud.visible = lake.interactions.camera.current and not lake.panel.visible
	lake.gauge.visible = lake.hud.visible and lake.phase in ["fight", "charging"]
	lake.gauge.value = lake.tension * 100 if lake.phase == "fight" else lake.charge / 1.4 * 100
	lake.gauge.modulate = Color("ed936e") if lake.tension > 0.8 else Color("99d5ac")
	var text := lake.hud.text
	if lake.message_time > 0:
		text = lake.message
	elif lake.rod_out:
		match lake.phase:
			"idle": text = "ЛКМ: удерживай и отпусти для заброса · J — убрать · I — журнал"
			"charging": text = "Отпусти ЛКМ — забросить · ПКМ — отмена"
			"waiting": text = "Смотри на поплавок… · ПКМ — смотать леску"
			"bite": text = "Клюёт! Нажми ЛКМ, чтобы подсечь"
			"fight": text = "ЛКМ — тяни; отпускай, когда натяжение растёт · Улов %d%%" % int(lake.progress * 100)
	elif not lake.cooking.is_empty():
		text = "Рыба готовится у костра…" if lake.cooking_fire.burning else "Рыба ждёт: разожги костёр"
	else:
		text = "J — удочка · I — журнал улова · Z — приготовить / угостить / поесть" if lake.player.global_position.y < lake.water.water_level + 4 else ""

	if lake.hud.text != text:
		lake.hud.text = text

## The journal page: every species with its record, then the basket.
static func journal(fishing: FishingState) -> String:
	var text := "РЫБЫ НАШЕГО ОЗЕРА\n\n"
	for species: String in FishingState.SPECIES:
		var record: Dictionary = fishing.journal.get(species, {})
		text += "%s — %s\n" % [FishingState.SPECIES[species].title,
			"ещё не встречалась" if record.is_empty() else "%d уловов · рекорд %.1f см" % [record.count, record.best_cm]]
	text += "\nВ КОРЗИНЕ: %d / %d\n" % [fishing.bag.size(), FishingState.CAPACITY]
	for fish in fishing.bag:
		text += "%s · %.2f кг%s\n" % [FishingState.SPECIES[fish.species].title, fish.kg, " · приготовлена" if fish.cooked else ""]
	text += "\nZ — приготовить / угостить / поесть\nI или Esc — закрыть"
	return text
