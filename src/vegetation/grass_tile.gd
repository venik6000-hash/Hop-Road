class_name GrassTile
extends RefCounted
## One tile of GrassField as the renderer holds it: what its job made, as a
## MultiMesh a piece, and what each piece draws. A piece draws the clumps
## that stand at its distance, the first rows of what it holds, with the mesh
## that distance asks for: three bent cards a clump near the eye, two flat
## ones farther out, a single card that faces the eye far away. For an eye in
## the tavern's rooms the pieces no opening shows are not drawn
## (InteriorSight).

const TileJob = preload("res://src/vegetation/grass_tile_job.gd")
## A piece's clumps are GrassClump.DETAIL's first mesh within NEAR_REACH
## metres, its second to FAR_REACH, its last beyond. Flowers, thin as they
## are, take the second and the last.
const NEAR_REACH := 14.0
const FAR_REACH := 50.0

## How the tiles are seen now, and the meshes they are drawn with; the field
## keeps one and every tile reads it.
class View:
	## The eye, and the fades of the grass and of the mat
	## (GrassScatter.fade_of, mat_fade_of), as the tiles were last looked over.
	var eye := Vector3.ZERO
	var fade := Vector4.ZERO
	var mat_fade := Vector2.ZERO
	## What an eye in the tavern's rooms sees of the outdoors (null: all of it).
	var sight: InteriorSight.Sight
	## GrassClump.DETAIL's meshes for the grass and for the flowers, and the mat's.
	var grass: Array[ArrayMesh] = []
	var flowers: Array[ArrayMesh] = []
	var mat: ArrayMesh

	## The meshes, all drawn with `material`.
	func _init(material: ShaderMaterial) -> void:
		for detail in GrassClump.DETAIL.size():
			grass.append(GrassClump.mesh(detail))
			flowers.append(GrassClump.mesh(detail, true))
		mat = GrassClump.mat_mesh()
		for mesh: ArrayMesh in grass + flowers + [mat]:
			mesh.surface_set_material(0, material)

var key := Vector2i.ZERO
var rect := Rect2()
## Lowest and highest ground under it (TerrainSystem.height_range).
var span := Vector2.ZERO
## False where nothing can grow (under the lake, off the near field).
var grows := true
## The level it holds, -1 while it holds nothing.
var level := -1
## Side (m) of the pieces it is held as: the tile's or a patch's.
var piece := 0.0
## Its clumps by piece (GrassScatter.split's keys), the rows each piece
## was filled from and their ranks in their order.
var pieces := {}
var piece_rows := {}
var piece_ranks := {}
var flowers: MultiMeshInstance3D
var flower_rows := PackedFloat32Array()
var flower_ranks := PackedFloat32Array()
## Whether it holds the mat, and the mat by square of `mat_piece` metres
## with each square's ranks.
var matted := false
var mat_piece := 0.0
var mats := {}
var mat_ranks := {}
## The job being worked on for it and its WorkerThreadPool task, or -1.
var job: TileJob
var task := -1
## Left the field while its job was still running.
var dropped := false

## The tile `at` of the grid of `side` metres, held in one piece.
func _init(at: Vector2i, side: float) -> void:
	key = at
	rect = Rect2(Vector2(at) * side, Vector2(side, side))
	piece = side

## Whether a piece with the bounds `box` is drawn for an eye that sees the
## outdoors as `sight` has it (null: all of it).
static func seen(sight: InteriorSight.Sight, box: AABB) -> bool:
	return sight == null or sight.sees_box(box)

## Distance from `eye` to the nearest point of the box over `area` between the
## heights `heights`.
static func distance_to_tile(eye: Vector3, area: Rect2, heights: Vector2) -> float:
	var nearest := Vector3(clampf(eye.x, area.position.x, area.end.x), clampf(eye.y, heights.x, heights.y),
		clampf(eye.z, area.position.y, area.end.y))
	return nearest.distance_to(eye)

## The mesh (an index of GrassClump.DETAIL) a piece `distance` metres away is drawn with.
static func detail_for(distance: float) -> int:
	return 0 if distance <= NEAR_REACH else (1 if distance <= FAR_REACH else 2)

## Puts what `made` made in place of what the tile showed, as children of
## `parent`.
func show_job(made: TileJob, parent: Node3D, view: View) -> void:
	empty()
	level = made.level
	piece = made.piece
	piece_rows = made.pieces
	piece_ranks = made.piece_ranks
	flower_rows = made.flowers
	flower_ranks = made.flower_ranks
	matted = made.mat_total > 0
	mat_piece = made.mat_piece
	mat_ranks = made.mat_ranks
	var height := maxf(made.high - made.low, 0.0)
	for at: Vector2i in made.pieces:
		var square := Rect2(Vector2(at) * made.piece, Vector2(made.piece, made.piece))
		var box := AABB(Vector3(square.position.x, made.low, square.position.y), Vector3(made.piece, height, made.piece))
		var rows: PackedFloat32Array = made.pieces[at]
		pieces[at] = _make(parent, "Clumps_%d_%d_%d" % [int(made.piece), at.x, at.y], rows,
			view.grass[detail_for(distance_to_tile(view.eye, square, span))], box.grow(GrassClump.REACH))
	if not made.flowers.is_empty():
		var box := AABB(Vector3(rect.position.x, made.low, rect.position.y), Vector3(rect.size.x, height, rect.size.y))
		flowers = _make(parent, "Flowers_%d_%d" % [key.x, key.y], made.flowers,
			view.flowers[maxi(detail_for(distance_to_tile(view.eye, rect, span)), 1)], box.grow(GrassClump.REACH))
	for at: Vector2i in made.mats:
		var box := AABB(Vector3(at.x * mat_piece, made.low, at.y * mat_piece), Vector3(mat_piece, height, mat_piece))
		var rows: PackedFloat32Array = made.mats[at]
		mats[at] = _make(parent, "Mat_%d_%d" % [at.x, at.y], rows, view.mat, box.grow(GrassClump.REACH))
	trim(view)

static func _make(parent: Node3D, item_name: String, rows: PackedFloat32Array, mesh: ArrayMesh,
		box: AABB) -> MultiMeshInstance3D:
	var item := MultiMeshInstance3D.new()
	item.name = item_name
	item.multimesh = _fill(rows, mesh)
	item.custom_aabb = box
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	item.layers = VegetationSystem.VISUAL_LAYER
	parent.add_child(item)
	return item

## Draws of every piece the clumps that stand at the piece's distance, the
## first rows of what it holds, with the mesh that distance asks for.
func trim(view: View) -> void:
	if out_of_sight(view.sight):
		return
	var eye := view.eye
	var fade := view.fade
	var sight := view.sight
	var meshes := view.grass
	# A tile in one piece is seen as the tile is.
	var whole := piece == rect.size.x
	for at: Vector2i in pieces:
		var item: MultiMeshInstance3D = pieces[at]
		var distance := distance_to_tile(eye, Rect2(Vector2(at) * piece, Vector2(piece, piece)), span)
		var rows: PackedFloat32Array = piece_rows[at]
		var ranks: PackedFloat32Array = piece_ranks[at]
		_limit(item, rows, ranks,
			GrassScatter.share(maxf(distance - GrassField.REFRESH_STEP, 0.0), fade), meshes[detail_for(distance)],
			whole or seen(sight, item.custom_aabb))
	if flowers != null:
		var distance := distance_to_tile(eye, rect, span)
		_limit(flowers, flower_rows, flower_ranks,
			GrassScatter.share(maxf(distance - GrassField.REFRESH_STEP, 0.0), fade, true),
			view.flowers[maxi(detail_for(distance), 1)], true)
	# The mat has one mesh, so its rows are never asked for again.
	for at: Vector2i in mats:
		var item: MultiMeshInstance3D = mats[at]
		var distance := distance_to_tile(eye, Rect2(Vector2(at) * mat_piece, Vector2(mat_piece, mat_piece)), span)
		var ranks: PackedFloat32Array = mat_ranks[at]
		_limit(item, PackedFloat32Array(), ranks,
			GrassScatter.mat_share(maxf(distance - GrassField.REFRESH_STEP, 0.0), view.mat_fade), view.mat,
			seen(sight, item.custom_aabb))

## True, with all it holds hidden unasked, for a tile no opening of the
## tavern shows (`sight`, null: all is seen); it is trimmed when it is seen
## again.
func out_of_sight(sight: InteriorSight.Sight) -> bool:
	if seen(sight, AABB(Vector3(rect.position.x, span.x, rect.position.y),
			Vector3(rect.size.x, span.y - span.x, rect.size.y)).grow(GrassClump.REACH)):
		return false
	for item: MultiMeshInstance3D in pieces.values() + mats.values():
		item.visible = false
	if flowers != null:
		flowers.visible = false
	return true

## After the sight has changed and the eye has not: hides what of the tile
## has gone out of sight, and trims the tile again when anything of it has
## come back into sight.
func resee(view: View) -> void:
	if out_of_sight(view.sight):
		return
	var back := false
	var whole := piece == rect.size.x
	var asked: Array = mats.values() if whole else pieces.values() + mats.values()
	for item: MultiMeshInstance3D in asked:
		if seen(view.sight, item.custom_aabb):
			back = back or not item.visible
		elif item.visible:
			item.visible = false
	if whole:
		for item: MultiMeshInstance3D in pieces.values():
			back = back or not item.visible
	if back or (flowers != null and not flowers.visible):
		trim(view)

static func _limit(item: MultiMeshInstance3D, rows: PackedFloat32Array, ranks: PackedFloat32Array, share: float,
		mesh: ArrayMesh, in_sight: bool) -> void:
	# A piece out of sight keeps what it had: it is asked again when seen.
	if not in_sight:
		if item.visible:
			item.visible = false
		return
	# Another mesh means another MultiMesh, filled from the rows again: giving
	# a filled one a new mesh makes the renderer read its instances back from
	# the GPU, which waits for every frame under way.
	if item.multimesh.mesh != mesh:
		item.multimesh = _fill(rows, mesh)
	var count := ranks.bsearch(share)
	if item.multimesh.visible_instance_count != count:
		item.multimesh.visible_instance_count = count
	if item.visible != (count > 0):
		item.visible = count > 0

static func _fill(rows: PackedFloat32Array, mesh: ArrayMesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = rows.size() / GrassScatter.STRIDE
	multimesh.buffer = rows
	return multimesh

## Takes away what the tile shows; a job under way for it is left to finish.
func empty() -> void:
	for item: MultiMeshInstance3D in pieces.values():
		item.free()
	pieces = {}
	piece_rows = {}
	piece_ranks = {}
	if flowers != null:
		flowers.free()
		flowers = null
	flower_rows = PackedFloat32Array()
	for item: MultiMeshInstance3D in mats.values():
		item.free()
	mats = {}
	mat_ranks = {}
	matted = false
	level = -1
