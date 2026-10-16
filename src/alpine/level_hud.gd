extends RefCounted
## The level's HUD: the controls help, the weather and time line, the dot at
## the screen's middle. The help and the line are out of sight until the
## action "help" asks for them (toggle_help); the game shows a word about it
## for its first seconds (ValleyLoop). The help names the player's own
## bindings (InputActions.hint) in the language of the game, and is written
## anew when the language changes (Canvas).
## The wind seas of the lake (the weather's own names are WeatherSystem.NAMES).
const WEATHER_NAMES := {"calm": "Штиль", "breeze": "Бриз", "choppy": "Свежий ветер", "storm": "Шторм"}
## The actions of the game, a line for each part of it.
const PLAYER_HELP := ["ХМЕЛЬНАЯ ТРОПА   ·   Альпийская долина   ·   {help} — скрыть",
	"{move} — ходьба   ·   {sprint} — бег   ·   {look} — обзор   ·   {interact} — двери / сесть / лестница / позвать / поговорить   ·   {pause} — курсор",
	"{swim_up} / {swim_down} — всплыть / нырнуть   ·   {screenshot} — снимок   ·   {settings} — настройки   ·   {toggle_hand} — рука",
	"Пивоварня: {interact} — взять / поставить / к станку / книга   ·   у станка {look} — работа, {choice} — другое дело, {interact} — отойти   ·   доска заказов: {interact} — взять заказ, {choice} — другой",
	"{place_camp} — костёр   ·   {drink_beer} — пиво   ·   {camp_refill} — налить у костра   ·   {eat_potato} — есть   ·   {camp_secondary} — поделиться / потушить / попрощаться   ·   {guide_outing} — любимое место спутника   ·   {fishing_rod} — удочка   ·   {fish_use} — улов   ·   {fish_journal} — журнал улова"]
## The debug keys (level_controls.gd), shown only where they work.
const DEBUG_HELP := "Отладка: F9 — панорама   ·   R — к таверне   ·   B — на пляж   ·   F1–F4 — ветер на озере   ·   F5 / F6 — погода   ·   F7 — погода сама   ·   [ ] — время суток"

## Builds the "Controls" canvas on the level, its help with the debug keys
## when `debug`; returns the status label.
static func build(level: Node3D, debug: bool) -> Label:
	var canvas := Canvas.new()
	canvas.name = "Controls"
	canvas.debug = debug
	level.add_child(canvas)
	var label := Label.new()
	label.name = "Help"
	label.position = Vector2(24, 22)
	style_label(label)
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
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 24.0
	hint.offset_top = -56.0
	style_label(hint)
	hint.add_theme_font_size_override("font_size", 18)
	hint.visible = false
	canvas.add_child(hint)
	var dot := Dot.new()
	dot.name = "Dot"
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(dot)
	canvas.write()
	return status

## The controls help, translated; the debug keys only with `debug`.
static func help_text(debug: bool) -> String:
	var lines := PackedStringArray()
	for line: String in PLAYER_HELP:
		lines.append(TranslationServer.translate(line))
	if debug:
		lines.append(TranslationServer.translate(DEBUG_HELP))
	return "\n".join(lines)

## The "Controls" canvas: writes its help and its hint in the language of the
## game, again when the language changes.
class Canvas extends CanvasLayer:
	const LEVEL_HUD = preload("res://src/alpine/level_hud.gd")
	var debug := false

	func write() -> void:
		(get_node("Help") as Label).text = InputActions.hint(LEVEL_HUD.help_text(debug))
		(get_node("Hint") as Label).text = InputActions.hint(tr("{help} — управление"))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSLATION_CHANGED and has_node("Hint"):
			write()

## A small dot at the screen's middle: where the eye looks. It shows only
## while the mouse looks around (the cursor hidden).
class Dot extends Control:
	const RADIUS := 2.5

	func _process(_delta: float) -> void:
		var shown := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if shown != visible:
			visible = shown

	func _draw() -> void:
		draw_circle(Vector2.ZERO, RADIUS + 1.2, Color(0.0, 0.0, 0.0, 0.55))
		draw_circle(Vector2.ZERO, RADIUS, Color("fff5dc"))

## Shows the controls help and the weather line, or puts them away again.
## Shows or hides the help, with the debug keys when `debug`.
static func toggle_help(level: Node3D, debug: bool) -> void:
	var canvas := level.get_node_or_null("Controls")
	if canvas == null:
		return
	var help := canvas.get_node("Help") as Label
	help.text = InputActions.hint(help_text(debug))
	help.visible = not help.visible
	(canvas.get_node("Status") as Label).visible = help.visible
	(canvas.get_node("Hint") as Label).visible = false

static func style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("fff5dc"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)

## The weather, the lake's sea and the hour, translated.
static func status_text(water: WaterSystem, sky_system: SkySystem, weather: WeatherSystem = null) -> String:
	var ocean := water.ocean
	var minutes := int(round(sky_system.time_of_day * 60.0)) % (24 * 60)
	var parts := PackedStringArray()
	if weather != null:
		var sky := TranslationServer.translate(WeatherSystem.NAMES[weather.kind])
		parts.append(TranslationServer.translate("%s (сама)") % sky if weather.auto else sky)
	parts.append(TranslationServer.translate(WEATHER_NAMES[ocean.preset]))
	parts.append(TranslationServer.translate("волна %.1f м") % ocean.significant_height())
	parts.append("%02d:%02d" % [minutes / 60, minutes % 60])
	return "   ·   ".join(parts)
