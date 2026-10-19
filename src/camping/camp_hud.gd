class_name CampHud
extends CanvasLayer
## The camp's part on the screen (CampSystem): the caption of what is said,
## under the speaker's name, and the line over the potato in the hand
## (CampFood fills it). The prompts at a seat by a fire are here too. The
## part reads no input.

var camp: CampSystem
var caption: Label
var caption_panel: PanelContainer
var food_hint: Label
## Seconds the caption still shows.
var caption_time := 0.0

func _ready() -> void:
	name = "CampConversation"
	caption_panel = PanelContainer.new()
	caption_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption_panel.offset_left = 36
	caption_panel.offset_right = -36
	caption_panel.offset_top = -205
	caption_panel.offset_bottom = -122
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.045, 0.028, 0.82)
	background.border_color = Color(0.71, 0.54, 0.32, 0.55)
	background.border_width_left = 3
	background.content_margin_left = 18
	background.content_margin_right = 18
	background.content_margin_top = 10
	background.content_margin_bottom = 10
	caption_panel.add_theme_stylebox_override("panel", background)
	add_child(caption_panel)
	caption = Label.new()
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	style(caption, 21)
	caption_panel.add_child(caption)
	caption_panel.visible = false
	food_hint = Label.new()
	food_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	food_hint.offset_left = 24
	food_hint.offset_right = -24
	food_hint.offset_top = 165
	food_hint.offset_bottom = 199
	food_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style(food_hint, 18)
	add_child(food_hint)

func _process(delta: float) -> void:
	caption_time = maxf(0.0, caption_time - delta)
	caption_panel.visible = camp.in_play() and caption_time > 0
	caption_panel.modulate.a = minf(1.0, caption_time)

## Shows `words` (a key of the table, a line of the people's sheets or words
## translated already) under the speaker's name, in the language of the game.
func say(actor: VillageNPC, words: String) -> void:
	if words.is_empty():
		return
	var said := tr(words)
	caption.text = InputActions.hint(said if actor == null else tr(actor.title) + ":  " + said)
	caption_time = Storyteller.caption_seconds(said)

## Whether a caption still shows: another one waits.
func speaking() -> bool:
	return caption_time > 0.0

## The keys of the mug and the food for the player on a seat by a fire, after
## the seat's own prompt; "" on any other seat.
func seated_text() -> String:
	if not camp.interactions.seated.get("camp", false):
		return ""
	if camp.food.holding():
		return tr(" · {drink_beer} — пиво · {camp_refill} — налить · {eat_potato} — есть · {camp_secondary} — поделиться")
	return tr(" · {drink_beer} — пиво · {camp_refill} — налить")

static func style(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff2d7"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
