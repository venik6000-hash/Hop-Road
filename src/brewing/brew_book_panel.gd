class_name BrewBookPanel
extends CanvasLayer
## The brewer's book open on the desk: two pages of BrewBook.pages at a time.

const PAPER := Color(0.86, 0.8, 0.66)
const INK := Color(0.2, 0.14, 0.09)

var pages := PackedStringArray()
## The left page of the spread.
var first := 0

var _left: Label
var _right: Label

func _ready() -> void:
	layer = 20
	var sheet := PanelContainer.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sheet.custom_minimum_size = Vector2(980.0, 620.0)
	sheet.position = -sheet.custom_minimum_size * 0.5
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.set_corner_radius_all(6)
	paper.set_content_margin_all(36.0)
	paper.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	paper.shadow_size = 18
	sheet.add_theme_stylebox_override("panel", paper)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 56)
	sheet.add_child(spread)
	_left = _page(spread)
	_right = _page(spread)
	visible = false

func _page(spread: HBoxContainer) -> Label:
	var page := Label.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_theme_color_override("font_color", INK)
	page.add_theme_font_size_override("font_size", 20)
	spread.add_child(page)
	return page

func open(book_pages: PackedStringArray) -> void:
	pages = book_pages
	first = clampi(first, 0, maxi(0, pages.size() - 1) & ~1)
	visible = true
	_show()

## Turns the spread forward (1) or back (-1).
func turn(step: int) -> void:
	first = clampi(first + step * 2, 0, maxi(0, pages.size() - 1) & ~1)
	_show()

func _show() -> void:
	_left.text = pages[first] if first < pages.size() else ""
	_right.text = pages[first + 1] if first + 1 < pages.size() else ""
