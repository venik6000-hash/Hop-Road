extends RefCounted
## The level's HUD: the controls help and the weather and time line.
## The wind seas of the lake (the weather's own names are WeatherSystem.NAMES).
const WEATHER_NAMES := {"calm": "Штиль", "breeze": "Бриз", "choppy": "Свежий ветер", "storm": "Шторм"}

## Builds the "Controls" canvas on the level; returns the status label.
static func build(level: Node3D) -> Label:
	var canvas := CanvasLayer.new()
	canvas.name = "Controls"
	level.add_child(canvas)
	var label := Label.new()
	label.text = "ХМЕЛЬНАЯ ТРОПА   ·   Альпийская долина\nWASD — ходьба   ·   Shift — бег   ·   Мышь — обзор   ·   E — двери / сесть / лестница   ·   Esc — курсор\nF9 — панорама   ·   R — к таверне   ·   B — на пляж   ·   F12 — снимок   ·   F10 — графика   ·   H — рука\nF1–F4 — ветер на озере   ·   F5 / F6 — погода   ·   F7 — погода сама   ·   [ ] — время суток   ·   Пробел / C — всплыть / нырнуть"
	label.position = Vector2(24, 22)
	style_label(label)
	label.text += "\nK — костёр   ·   V — пиво   ·   X — налить у костра   ·   F — есть   ·   Q — поделиться / потушить / попрощаться   ·   G — прогулка   ·   T — разговор"
	label.anchor_right = 1.0
	label.offset_right = -24
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(label)
	var status := Label.new()
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.offset_left = 24.0
	status.offset_top = -56.0
	style_label(status)
	canvas.add_child(status)
	return status

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
