class_name GrassClump
extends RefCounted
## What the grass shader draws (shaders/grass.gdshader): clumps of crossed
## cards and the atlas they show.
##
## A clump is one MultiMesh instance: a few cards that all show the same cell
## of the atlas baked by tools/pipeline/vegetation/make_grass_atlas.py from
## scanned plants, one plant or one slice of turf with every blade, seed head
## and leaf in the texture. Two triangles carry dozens of blades, so the
## grass costs the pixels its cards cover, not its geometry.
##
## The mesh is a clump one card wide and one high; the shader gives it the
## size of its cell, turns it and stands it on the ground. Per vertex:
##   VERTEX  the clump, its root at the origin
##   NORMAL  up, flaring outward toward the top of the clump
##   UV      across the card and down it (v = 1 at the root)
##   UV2     x: place across the card (-0.5 .. 0.5); y: the card's turn (radians)
##   COLOR   r: 1 on a card the shader turns to face the eye; g: 1 on the
##           mat; b: 1 on a flower

## The plants of the atlas: tall grass in seed, shorter green grass, low
## turf, leafy stalks (nettles and docks), ferns, small-leaved shrubs
## (bilberry-like twigs and dense bushes), flowers, and the loose low blades
## of the mat.
enum Kind { SEEDING, GREEN, TURF, LUSH, FERN, SHRUB, FLOWER, MAT }
const KINDS := ["seeding", "green", "turf", "lush", "fern", "shrub", "flower", "mat"]
## The flowers' cells, in the atlas's order.
enum Flower { KNAPWEED, BUTTERCUP, YARROW, BELLFLOWER, DANDELION, CELANDINE }

const DIR := "res://assets/models/vegetation/grass/"
const CARDS := DIR + "grass_cards.json"
## The shader's CELLS.
const MAX_CELLS := 32
## Per kind: how far the wind bends it; the share of the shader's alpha lift
## it takes (loose fine blades melt on the far mips and need it, dense tufts
## and broad leaves keep their coverage and would close up into slabs). The
## kinds' colours are graded in the bake (GRADE in make_grass_atlas.py).
const FLEX := [1.0, 0.9, 0.6, 0.45, 0.5, 0.25, 0.8, 0.6]
const LIFT := [0.6, 0.4, 0.2, 0.3, 0.3, 0.3, 1.0, 1.0]
## Cards, quads up a card, how far the tops lean outward and how far the
## cards stand off the middle, by level of detail: three bent cards near the
## eye, two flat ones farther out, then a single card that faces the eye.
const DETAIL := [[3, 3, 0.26, 0.07], [2, 1, 0.0, 0.0], [1, 1, 0.0, 0.0]]
const FACING := 2
## The mat: the low growth under and between the taller plants, which is all
## that is seen of the ground from above. Its clump, in DETAIL's terms, is
## three flat cards laid far outward, a rosette; their tops stand MAT_RISE
## of their length above the ground.
const MAT := [3, 1, 0.44, 0.0]
const MAT_RISE := 0.6
## Room round a clump's root for the widest and tallest plant as the shader
## grows it far away, its lean and its sway (m).
const REACH := 2.6

## The atlas's cells as the shader and the scatter need them.
class Sheet:
	## Per cell: u, v of its corner and its size in the atlas; its width and
	## height (m) and the share of the width the plant needs at its foot and
	## half way up; its kind's alpha lift; its kind's flex.
	var rects := PackedVector4Array()
	var shapes := PackedVector4Array()
	var lift := PackedFloat32Array()
	var flex := PackedFloat32Array()
	## The cells of each Kind.
	var cells: Array[PackedInt32Array] = []

static var _sheet: Sheet

## The atlas's cells, read once.
static func sheet() -> Sheet:
	if _sheet != null:
		return _sheet
	var parsed: Dictionary = DataFile.read(CARDS, WorldSchemas.grass_cards())
	var side: float = parsed.atlas_size[0]
	var result := Sheet.new()
	for kind in KINDS.size():
		result.cells.append(PackedInt32Array())
	for card: Dictionary in parsed.cards:
		var kind := KINDS.find(str(card.species))
		assert(kind >= 0, "grass_cards.json: unknown plant '%s'" % card.species)
		result.cells[kind].append(result.rects.size())
		result.rects.append(Vector4(Values.real(card.rect[0]), Values.real(card.rect[1]), Values.real(card.rect[2]), Values.real(card.rect[3])) / side)
		result.shapes.append(Vector4(Values.real(card.size[0]), Values.real(card.size[1]), Values.real(card.hull[0]), Values.real(card.hull[1])))
		result.lift.append(Values.real(LIFT[kind]))
		result.flex.append(Values.real(FLEX[kind]))
	assert(result.rects.size() <= MAX_CELLS, "grass_cards.json holds more cells than the shader")
	result.rects.resize(MAX_CELLS)
	result.shapes.resize(MAX_CELLS)
	result.lift.resize(MAX_CELLS)
	result.flex.resize(MAX_CELLS)
	_sheet = result
	return result

## Gives `material` (shaders/grass.gdshader) the atlas and its cells.
static func dress(material: ShaderMaterial) -> void:
	var cells := sheet()
	material.set_shader_parameter("atlas", load(DIR + "grass_albedo.png"))
	material.set_shader_parameter("atlas_normal", load(DIR + "grass_normal.png"))
	# Vector4 arrays: a PackedColorArray reaches a vec4 uniform array with 1 in
	# the fourth component.
	material.set_shader_parameter("cell_rect", cells.rects)
	material.set_shader_parameter("cell_shape", cells.shapes)
	material.set_shader_parameter("cell_lift", cells.lift)
	material.set_shader_parameter("cell_flex", cells.flex)

## The clump at level of detail `detail` (an index of DETAIL).
static func mesh(detail: int, flower := false) -> ArrayMesh:
	return _build(Values.list(DETAIL[detail]), 1.0, Color(1.0 if detail == FACING else 0.0, 0.0, 1.0 if flower else 0.0))

## The mat's clump.
static func mat_mesh() -> ArrayMesh:
	return _build(MAT, MAT_RISE, Color(0.0, 1.0, 0.0))

## A clump of `shape` (a row of DETAIL) whose cards' tops stand `rise` of
## their length above the root, every vertex marked `mark`.
static func _build(shape: Array, rise: float, mark: Color) -> ArrayMesh:
	var cards: int = shape[0]
	var segments: int = shape[1]
	var lean: float = shape[2]
	var spread: float = shape[3]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var places := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for card in cards:
		var turn := PI * card / cards + 0.2
		var axis := Vector3(cos(turn), 0.0, sin(turn))
		var face := Vector3(-sin(turn), 0.0, cos(turn)) * (1.0 if card % 2 == 0 else -1.0)
		var first := vertices.size()
		for level in segments + 1:
			var t := float(level) / segments
			var up := t * rise
			for column in 2:
				var across := float(column) - 0.5
				vertices.append(face * (spread + lean * t * t) + axis * across + Vector3.UP * up)
				normals.append((Vector3.UP + (axis * across * 0.9 + face * 0.5) * t).normalized())
				# Every other card shows its cell mirrored.
				uvs.append(Vector2(column if card % 2 == 0 else 1 - column, 1.0 - t))
				places.append(Vector2(across, turn))
				colors.append(mark)
		for level in segments:
			var corner := first + level * 2
			indices.append_array([corner, corner + 1, corner + 3, corner, corner + 3, corner + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = places
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader sizes the clump: this box holds any of them.
	result.custom_aabb = AABB(Vector3(-REACH, -0.5, -REACH), Vector3(2.0 * REACH, REACH + 0.5, 2.0 * REACH))
	return result
