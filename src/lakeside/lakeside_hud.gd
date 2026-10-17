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
	for edge: String in ["left", "top", "right", "bottom"]:
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
			"idle": text = "{fish_cast}: удерживай и отпусти для заброса · {fishing_rod} — убрать · {fish_journal} — журнал"
			"charging": text = "Отпусти {fish_cast} — забросить · {fish_cancel} — отмена"
			"waiting": text = "Смотри на поплавок… · {fish_cancel} — смотать леску"
			"bite": text = "Клюёт! Нажми {fish_cast}, чтобы подсечь"
			"fight": text = TranslationServer.translate("{fish_cast} — тяни; отпускай, когда натяжение растёт · Улов %d%%") % int(lake.progress * 100)
	elif not lake.cooking.is_empty():
		text = "Рыба готовится у костра…" if lake.cooking_fire.burning else "Рыба ждёт: разожги костёр"
	else:
		text = "{fishing_rod} — удочка · {fish_journal} — журнал улова · {fish_use} — приготовить / угостить / поесть" if lake.player.global_position.y < lake.water.water_level + 4 else ""

	text = InputActions.hint(TranslationServer.translate(text))
	if lake.hud.text != text:
		lake.hud.text = text

## The journal page, translated: every species with its record, then the basket.
static func journal(fishing: FishingState) -> String:
	var text := TranslationServer.translate("РЫБЫ НАШЕГО ОЗЕРА") + "\n\n"
	for species: String in FishingState.species_table():
		var record: Dictionary = fishing.journal.get(species, {})
		var title := TranslationServer.translate(FishingState.title(species))
		if record.is_empty():
			text += TranslationServer.translate("%s — ещё не встречалась") % title + "\n"
		else:
			var count := Values.whole(record.count)
			text += TranslationServer.translate_plural("%s — %d улов · рекорд %.1f см", "%s — %d улова · рекорд %.1f см",
				count) % [title, count, Values.real(record.best_cm)] + "\n"
	text += "\n" + TranslationServer.translate("В КОРЗИНЕ: %d / %d") % [fishing.bag.size(), FishingState.CAPACITY] + "\n"
	for fish in fishing.bag:
		var title := TranslationServer.translate(FishingState.title(str(fish.species)))
		var words := TranslationServer.translate("%s · %.2f кг · приготовлена") if fish.cooked else TranslationServer.translate("%s · %.2f кг")
		text += words % [title, fish.kg] + "\n"
	text += "\n" + TranslationServer.translate("{fish_use} — приготовить / угостить / поесть\n{fish_journal} или {pause} — закрыть")
	return text
