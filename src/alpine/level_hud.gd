extends RefCounted
## The level's HUD: the controls help and the weather and time line. Both are
## out of sight until Tab asks for them (toggle_help); the game shows a word
## about Tab for its first seconds (ValleyLoop).
## The wind seas of the lake (the weather's own names are WeatherSystem.NAMES).
const WEATHER_NAMES := {"calm": "Штиль", "breeze": "Бриз", "choppy": "Свежий ветер", "storm": "Шторм"}

## Builds the "Controls" canvas on the level; returns the status label.
static func build(level: Node3D) -> Label:
	var canvas := CanvasLayer.new()
	canvas.name = "Controls"
	level.add_child(canvas)
	var label := Label.new()
	label.name = "Help"
	label.text = "ХМЕЛЬНАЯ ТРОПА   ·   Альпийская долина   ·   Tab — скрыть\nWASD — ходьба   ·   Shift — бег   ·   Мышь — обзор   ·   E — двери / сесть / лестница / позвать / поговорить   ·   Esc — курсор\nF9 — панорама   ·   R — к таверне   ·   B — на пляж   ·   F12 — снимок   ·   F10 — графика   ·   H — рука\nF1–F4 — ветер на озере   ·   F5 / F6 — погода   ·   F7 — погода сама   ·   [ ] — время суток   ·   Пробел / C — всплыть / нырнуть"
	label.position = Vector2(24, 22)
	style_label(label)
	label.text += "\nПивоварня: E — взять / поставить / к станку / книга   ·   у станка мышь — работа, колесо — другое дело, E — отойти"
	label.text += "\nK — костёр   ·   V — пиво   ·   X — налить у костра   ·   F — есть   ·   Q — поделиться / потушить / попрощаться   ·   G — любимое место спутника   ·   J — удочка   ·   Z — улов   ·   I — журнал улова"
	label.anchor_right = 1.0
	label.offset_right = -24
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.visible = false
	canvas.add_child(label)
	var status := Label.new()
	status.name = "Status"
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.offset_left = 24.0
	status.offset_top = -56.0
	style_label(status)
	status.visible = false
	canvas.add_child(status)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Tab — управление"
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 24.0
	hint.offset_top = -56.0
	style_label(hint)
	hint.add_theme_font_size_override("font_size", 18)
	hint.visible = false
	canvas.add_child(hint)
	return status

## Shows the controls help and the weather line, or puts them away again.
static func toggle_help(level: Node3D) -> void:
	var canvas := level.get_node_or_null("Controls")
	if canvas == null:
		return
	var help := canvas.get_node("Help") as Label
	help.visible = not help.visible
	(canvas.get_node("Status") as Label).visible = help.visible
	(canvas.get_node("Hint") as Label).visible = false

static func style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("fff5dc"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)

static func status_text(water: WaterSystem, sky_system: SkySystem, weather: WeatherSystem = null) -> String:
	var ocean := water.ocean
	var minutes := int(round(sky_system.time_of_day * 60.0)) % (24 * 60)
	var sky_line := ""
	if weather != null:
		sky_line = "%s%s   ·   " % [WeatherSystem.NAMES[weather.kind], " (сама)" if weather.auto else ""]
	return "%s%s   ·   волна %.1f м   ·   %02d:%02d" % [sky_line, WEATHER_NAMES[ocean.preset],
		ocean.significant_height(), minutes / 60, minutes % 60]
