class_name BrewGuidePanel
extends CanvasLayer
## What BrewGuide shows (docs/plans/brewing.md, section 7.7): a small
## parchment at the bottom left with the order and its current task, a tick
## when the task is done; an arrow at the top of the screen to the task's place
## while the player is far from it; a mark over the station of the task in
## the room. BrewHouse feeds it each frame.

const PAPER := Color(0.87, 0.79, 0.62, 0.94)
const EDGE := Color(0.45, 0.31, 0.17)
const INK := Color(0.23, 0.15, 0.08)
const FADED := Color(0.23, 0.15, 0.08, 0.6)
const DONE_INK := Color(0.2, 0.36, 0.14)
const WARN_INK := Color(0.55, 0.12, 0.06)
const WIDTH := 380.0
## Seconds a ticked task stays before the next one comes in.
const TICK_SECONDS := 1.3
const FADE := 0.25

var _paper: PanelContainer
var _title: Label
var _count: Label
var _box: Tick
var _task: Label
var _note: Label
var _arrow: Arrow
var _arrow_words: Label
var _mark: Mark
## Tasks waiting behind the tick: [text, index, total].
var _queue: Array[Array] = []
var _ticking := 0.0

func _ready() -> void:
	layer = 2
	_paper = PanelContainer.new()
	_paper.anchor_top = 1.0
	_paper.anchor_bottom = 1.0
	_paper.offset_left = 24.0
	_paper.offset_right = 24.0 + WIDTH
	_paper.offset_bottom = -64.0
	_paper.offset_top = -64.0
	_paper.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(12.0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 6
	_paper.add_theme_stylebox_override("panel", style)
	add_child(_paper)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	_title = _label(17, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_count = _label(14, FADED)
	_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(_count)
	var rule := ColorRect.new()
	rule.color = Color(EDGE, 0.5)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(rule)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	column.add_child(line)
	_box = Tick.new()
	_box.custom_minimum_size = Vector2(18.0, 18.0)
	_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(_box)
	_task = _label(16, INK)
	_task.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_task)
	_note = _label(14, WARN_INK)
	_note.visible = false
	column.add_child(_note)
	_paper.visible = false

	_arrow = Arrow.new()
	_arrow.anchor_left = 0.5
	_arrow.anchor_right = 0.5
	_arrow.offset_left = -28.0
	_arrow.offset_right = 28.0
	_arrow.offset_top = 70.0
	_arrow.offset_bottom = 126.0
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	add_child(_arrow)
	_arrow_words = Label.new()
	_arrow_words.anchor_left = 0.5
	_arrow_words.anchor_right = 0.5
	_arrow_words.offset_left = -200.0
	_arrow_words.offset_right = 200.0
	_arrow_words.offset_top = 130.0
	_arrow_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow_words.add_theme_font_size_override("font_size", 17)
	_arrow_words.add_theme_color_override("font_color", PAPER)
	_arrow_words.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	_arrow_words.add_theme_constant_override("outline_size", 6)
	_arrow_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_words.visible = false
	add_child(_arrow_words)
	_mark = Mark.new()
	_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark)

func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _process(delta: float) -> void:
	if _ticking <= 0.0:
		return
	_ticking -= delta
	if _ticking <= 0.0 and not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_show_task(str(next[0]), Values.whole(next[1]), Values.whole(next[2]))

## The order taken: the parchment shows its heading.
func open(heading: String) -> void:
	_title.text = heading
	_paper.visible = true

## No order: the parchment, the arrow and the mark go.
func close() -> void:
	_paper.visible = false
	_queue.clear()
	_ticking = 0.0
	point(false, 0.0, "")
	mark(false, Vector2.ZERO)

## Task `index` of `total` now. Behind a tick, it waits for the tick to end.
func task(text: String, index: int, total: int) -> void:
	if _ticking > 0.0:
		_queue.append([text, index, total])
	else:
		_show_task(text, index, total)

## The task shown is done: the box is ticked for a while.
func tick() -> void:
	_box.ticked = true
	_box.queue_redraw()
	_task.add_theme_color_override("font_color", DONE_INK)
	_ticking = TICK_SECONDS

## Whether a tick is on the parchment now.
func ticking() -> bool:
	return _ticking > 0.0

## Whether the parchment is on the screen.
func is_open() -> bool:
	return _paper.visible

## The words of the task on the parchment now.
func task_text() -> String:
	return _task.text

## Whether the arrow is shown, and its words.
func is_pointing() -> bool:
	return _arrow.visible

func arrow_text() -> String:
	return _arrow_words.text

func _show_task(text: String, index: int, total: int) -> void:
	_box.ticked = false
	_box.queue_redraw()
	_task.add_theme_color_override("font_color", INK)
	_task.text = text
	_count.text = "%d / %d" % [index + 1, total]
	_task.modulate.a = 0.0
	create_tween().tween_property(_task, "modulate:a", 1.0, FADE)

## A warning under the task, hidden when "".
func note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""

## The arrow: shown or not, its turn (radians, 0 is straight ahead, positive
## to the right) and the words under it.
func point(shown: bool, angle: float, words: String) -> void:
	_arrow.visible = shown
	_arrow_words.visible = shown
	if shown:
		_arrow.angle = angle
		_arrow.queue_redraw()
		_arrow_words.text = words

## The mark over the task's station: shown or not, where on the screen.
func mark(shown: bool, at: Vector2) -> void:
	_mark.shown = shown
	_mark.at = at
	_mark.queue_redraw()

## The task's box, ticked or not.
class Tick extends Control:
	var ticked := false

	func _draw() -> void:
		var area := Rect2(Vector2(1.0, 2.0), size - Vector2(2.0, 2.0))
		draw_rect(area, EDGE, false, 2.0)
		if ticked:
			var a := area.position + area.size * Vector2(0.18, 0.5)
			var b := area.position + area.size * Vector2(0.42, 0.78)
			var c := area.position + area.size * Vector2(0.95, -0.05)
			draw_polyline(PackedVector2Array([a, b, c]), DONE_INK, 3.0, true)

## An arrow on a round parchment, turned to the place.
class Arrow extends Control:
	var angle := 0.0

	func _draw() -> void:
		var middle := size * 0.5
		var radius := minf(size.x, size.y) * 0.5
		draw_circle(middle, radius, PAPER)
		draw_arc(middle, radius - 1.0, 0.0, TAU, 40, EDGE, 2.0, true)
		var turn := Transform2D(angle, middle)
		var points := PackedVector2Array([Vector2(0.0, -radius * 0.72), Vector2(radius * 0.42, radius * 0.18),
			Vector2(radius * 0.13, radius * 0.08), Vector2(radius * 0.13, radius * 0.6), Vector2(-radius * 0.13, radius * 0.6),
			Vector2(-radius * 0.13, radius * 0.08), Vector2(-radius * 0.42, radius * 0.18)])
		draw_colored_polygon(turn * points, EDGE)

## A small arrow down over the task's station.
class Mark extends Control:
	var shown := false
	var at := Vector2.ZERO

	func _draw() -> void:
		if not shown:
			return
		var points := PackedVector2Array([at + Vector2(-9.0, -22.0), at + Vector2(9.0, -22.0), at + Vector2(0.0, -8.0)])
		draw_colored_polygon(points, PAPER)
		draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), EDGE, 2.0, true)
