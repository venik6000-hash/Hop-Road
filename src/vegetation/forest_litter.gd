class_name ForestLitter
extends Node3D
## What lies on a wood's floor: the dry branches, flakes of bark and cones
## its trees have shed, and small stones half sunk in the needles.
##
## Every tree that has a mesh sheds its own: a few branches under its crown,
## bark round its trunk, and a conifer its cones. What lies under a tree
## depends on the tree alone (shed(): a hash of where it stands), so the
## floor is the same whenever the player comes back to it. The stones lie in
## handfuls, a few to a tile, where the crowns close into a wood (strewn()).
##
## The pieces are meshes (assets/models/vegetation/litter.glb, built by
## tools/pipeline/vegetation/build_litter.py from scans the game draws
## heavier elsewhere, and a modelled cone), drawn in tiles round the eye: a
## tile holds the litter of the trees that stand in it and its own stones, a
## MultiMesh to a piece, and goes when the eye has left it behind.

const OutdoorScan = preload("res://src/render/outdoor_scan.gd")
const CanopyField = preload("res://src/vegetation/canopy_field.gd")
const MeshUtil = preload("res://src/common/mesh_util.gd")
const MODEL := "res://assets/models/vegetation/litter.glb"
## The kinds of piece, as the model's meshes are named (branch_a, bark_c,
## cone, stone_rock_07: a stone is named after its scan).
enum Kind { BRANCH, BARK, CONE, STONE }
const KINDS := ["branch", "bark", "cone", "stone"]
## The lake bed's models whose materials the branches and the bark wear: the
## pieces keep the unwrap of the same scans.
const DRESS := ["res://assets/models/lakebed/branches.glb", "res://assets/models/lakebed/bark_debris.glb"]
## A cone has no scan: a plain brown, lit scale by scale.
const CONE_COLOUR := Color(0.5, 0.36, 0.24)
## How much of the rain's film shines on dead wood (as on the forest's logs).
const WET_SHINE := 0.3
## Side of a tile, m.
const TILE := 16.0
## How far the pieces of a kind are drawn, m, and the stretch they fade over:
## a cone is a few pixels long by then.
const VIEW := [40.0, 26.0, 16.0, 34.0]
const VIEW_FADE := 5.0
## The eye must move this far before the tiles are looked over again, m.
const LOOK_STEP := 2.0
## A tile goes when it is this much farther than a piece can be seen, m.
const LEAVE := 12.0
## What a tree of its model's size has shed, by the look group of its kind
## (TreePlacer.SPECIES_GROUP: spruces, beeches, pines): branches, flakes of
## bark, cones. A tree `grown` times that size has shed grown squared of it.
const SHED := [Vector3(4.0, 2.0, 16.0), Vector3(2.5, 1.0, 0.0), Vector3(4.0, 2.5, 14.0)]
## Sizes of a piece against its model, by kind.
const SIZES := [Vector2(0.9, 1.8), Vector2(0.45, 0.9), Vector2(0.8, 1.15), Vector2(0.6, 1.5)]
## A pine's cone against a spruce's: rounder and half as long.
const PINE_CONE := Vector3(0.8, 0.8, 0.5)
## How deep a piece of size 1 settles into the ground, by kind, m. A stone
## settles by a share of its height instead (STONE_SUNK).
const SINK := [0.02, 0.012, 0.006, 0.0]
## Bark lies this near the trunk, m (for a tree of its model's size).
const BARK_REACH := Vector2(0.4, 2.0)
## Nothing lies under the lake's edge or on ground steeper than this (the
## normal's y).
const DRY := 0.3
const STEEPEST := 0.78
## Handfuls of stones a tile may hold and the odds that one of them is
## there; stones to a handful and how far from its middle they lie, m; one
## stone in five is this many times larger.
const HANDFULS := 3
const HANDFUL_ODDS := 0.55
const HANDFUL := Vector2i(3, 8)
const HANDFUL_SPREAD := 1.4
const LARGE_STONE := 1.9
## Stones lie where the stand round them closes this much of the sky
## (CanopyField.wooded_at): on a wood's floor.
const STONE_FLOOR := 0.12
## How bare of moss a wood's stone is (the boulders' material: lower is mossier).
const STONE_MOSS := Vector2(0.2, 0.5)
## A stone of size 1 is this long, m, whatever its scan's size, and this
## share of its height is in the ground.
const STONE_LENGTH := 0.22
const STONE_SUNK := 0.3
## Numbers to a piece in the rows of shed() and strewn(): kind, which mesh of
## the kind (0..1), x, z, turn (rad), size, and 1 for a pine's cone.
const ROW := 7

var terrain: TerrainSystem
## The trees that have a mesh.
var woods: TreeLodGrid
## Where their crowns close into a wood, and the boulders, whose material the
## stones wear (no stones without either).
var canopy: CanopyField
var rocks: RockField

var _shapes: Array[Array] = []
var _species := PackedVector2Array()
var _tiles := {}
var _wanted: Array[Vector2i] = []
var _eye := Vector3.INF

func _ready() -> void:
	_shapes = shapes()
	# TreeLodGrid.near() answers with a tree's size times x, and y: here the
	# tree's size itself and its species.
	for species in TreePlacer.SPECIES_NAMES.size():
		_species.append(Vector2(1.0, species))

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or terrain == null or woods == null:
		return
	var eye := camera.global_position
	if _eye == Vector3.INF or eye.distance_to(_eye) >= LOOK_STEP:
		_eye = eye
		_look_over(Vector2(eye.x, eye.z))
	# One tile a frame: a tile is a few hundred samples of the ground.
	if not _wanted.is_empty():
		var key: Vector2i = _wanted.pop_front()
		_tiles[key] = _lay_tile(key)

## The meshes of each Kind, dressed, in the order of their names.
static func shapes() -> Array[Array]:
	var worn: Array[ShaderMaterial] = []
	for path: String in DRESS:
		var dressed := (load(path) as PackedScene).instantiate()
		var first: MeshInstance3D = dressed.find_children("*", "MeshInstance3D", true, false)[0]
		worn.append(OutdoorScan.material(first.mesh.surface_get_material(0) as StandardMaterial3D, WET_SHINE))
		dressed.free()
	var plain := StandardMaterial3D.new()
	plain.albedo_color = CONE_COLOUR
	plain.roughness = 0.85
	worn.append(OutdoorScan.material(plain, WET_SHINE))
	var found: Array[Array] = [[], [], [], []]
	var scene := (load(MODEL) as PackedScene).instantiate()
	var names: Array[String] = []
	var meshes := {}
	for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		names.append(str(node.name))
		meshes[str(node.name)] = node.mesh
	names.sort()
	for piece: String in names:
		var kind := KINDS.find(piece.get_slice("_", 0))
		assert(kind >= 0, "litter.glb: unknown piece '%s'" % piece)
		var mesh := (meshes[piece] as ArrayMesh).duplicate() as ArrayMesh
		mesh.resource_name = piece
		# A stone is drawn with the boulders' material, which the tile gives it.
		if kind != Kind.STONE:
			mesh.surface_set_material(0, worn[kind])
		found[kind].append(mesh)
	scene.free()
	return found

## What the tree at (x, z) of `species`, `grown` times its model's size, has
## shed: ROW numbers a piece, one piece after another. A sapling has shed
## nothing yet.
static func shed(x: float, z: float, grown: float, species: int) -> PackedFloat32Array:
	var pieces := PackedFloat32Array()
	if species == TreePlacer.FIR_YOUNG:
		return pieces
	var group: int = TreePlacer.SPECIES_GROUP[species]
	var crown: float = TreePlacer.SPECIES_CROWN[species] * grown
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(x * 8.0), roundi(z * 8.0)))
	var means: Vector3 = SHED[group]
	for kind: int in [Kind.BRANCH, Kind.BARK, Kind.CONE]:
		var sizes: Vector2 = SIZES[kind]
		for _piece in int(means[kind] * grown * grown + rng.randf()):
			var away := crown * sqrt(rng.randf()) * 1.1
			if kind == Kind.BARK:
				away = rng.randf_range(BARK_REACH.x, BARK_REACH.y) * grown
			elif kind == Kind.CONE:
				# Cones drop from the outer branches more than by the trunk.
				away = crown * (0.25 + 0.7 * sqrt(rng.randf()))
			var bearing := rng.randf() * TAU
			pieces.append_array([kind, rng.randf(), x + cos(bearing) * away, z + sin(bearing) * away, rng.randf() * TAU,
				rng.randf_range(sizes.x, sizes.y), 1.0 if kind == Kind.CONE and group == 2 else 0.0])
	return pieces

## The stones of tile `key`, in shed()'s rows: handfuls of them, each stone
## where a hash of the tile says.
static func strewn(key: Vector2i) -> PackedFloat32Array:
	var pieces := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key * 7919 + Vector2i(13, 71))
	var sizes: Vector2 = SIZES[Kind.STONE]
	for _handful in HANDFULS:
		var middle := (Vector2(key) + Vector2(rng.randf(), rng.randf())) * TILE
		var count := rng.randi_range(HANDFUL.x, HANDFUL.y)
		if rng.randf() > HANDFUL_ODDS:
			continue
		for _stone in count:
			var off := Vector2.from_angle(rng.randf() * TAU) * (HANDFUL_SPREAD * sqrt(rng.randf()))
			var size := rng.randf_range(sizes.x, sizes.y) * (LARGE_STONE if rng.randf() < 0.2 else 1.0)
			pieces.append_array([Kind.STONE, rng.randf(), middle.x + off.x, middle.y + off.y, rng.randf() * TAU, size, 0.0])
	return pieces

## The tiles that have ground nearer than `reach` metres to `eye` (x, z), the
## nearest first.
static func tiles_round(eye: Vector2, reach: float) -> Array[Vector2i]:
	var near: Array[Vector2i] = []
	var first := Vector2i(((eye - Vector2(reach, reach)) / TILE).floor())
	var last := Vector2i(((eye + Vector2(reach, reach)) / TILE).floor())
	for row in range(first.y, last.y + 1):
		for column in range(first.x, last.x + 1):
			if away_from(eye, Vector2i(column, row)) < reach:
				near.append(Vector2i(column, row))
	near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return away_from(eye, a) < away_from(eye, b))
	return near

## Metres from `eye` (x, z) to the nearest ground of a tile.
static func away_from(eye: Vector2, key: Vector2i) -> float:
	var corner := Vector2(key) * TILE
	return (eye - eye.clamp(corner, corner + Vector2(TILE, TILE))).length()

## How a piece lies at (x, z) on ground of height `y` with the normal
## `normal`: turned by `turn` about the normal, `size` times its model
## (`shape` stretches it besides), settled `sink` metres in.
static func pose(x: float, y: float, z: float, normal: Vector3, turn: float, size: float, shape: Vector3, sink: float) -> Transform3D:
	var along := Vector3(cos(turn), 0.0, sin(turn))
	var side := normal.cross(along).normalized()
	along = side.cross(normal)
	return Transform3D(Basis(side * (size * shape.x), normal * (size * shape.y), along * (size * shape.z)),
		Vector3(x, y, z) - normal * (sink * size))

func _look_over(eye: Vector2) -> void:
	var reach: float = VIEW[Kind.BRANCH] + VIEW_FADE
	for key: Vector2i in _tiles.keys():
		if away_from(eye, key) > reach + LEAVE:
			for item: MultiMeshInstance3D in _tiles[key]:
				item.queue_free()
			_tiles.erase(key)
	_wanted.clear()
	for key: Vector2i in tiles_round(eye, reach):
		if not _tiles.has(key):
			_wanted.append(key)

## The litter of the trees that stand in tile `key` and the tile's stones: a
## MultiMesh to a piece.
func _lay_tile(key: Vector2i) -> Array[MultiMeshInstance3D]:
	var corner := Vector2(key) * TILE
	var rect := Rect2(corner, Vector2(TILE, TILE))
	var origin := Vector3(corner.x, 0.0, corner.y)
	var pieces := PackedFloat32Array()
	var trees := woods.near(rect, _species)
	for at in range(0, trees.size(), 4):
		if rect.has_point(Vector2(trees[at], trees[at + 1])):
			pieces.append_array(shed(trees[at], trees[at + 1], trees[at + 2], int(trees[at + 3])))
	if canopy != null and rocks != null:
		pieces.append_array(strewn(key))
	# Per mesh: its kind, the transforms of its pieces and what the boulders'
	# material is told of each (a stone's scan, moss and tone).
	var laid := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for row in range(0, pieces.size(), ROW):
		var kind := int(pieces[row])
		var x := pieces[row + 2]
		var z := pieces[row + 3]
		if kind == Kind.STONE and canopy.wooded_at(x, z) < STONE_FLOOR:
			continue
		var y := terrain.height_at(x, z)
		if y < terrain.water_level + DRY:
			continue
		var normal := Vector3(y - terrain.height_at(x + 0.4, z), 0.4, y - terrain.height_at(x, z + 0.4)).normalized()
		if normal.y < STEEPEST:
			continue
		var meshes: Array = _shapes[kind]
		var mesh: ArrayMesh = meshes[mini(int(pieces[row + 1] * meshes.size()), meshes.size() - 1)]
		var size := pieces[row + 5]
		var sink: float = SINK[kind]
		if kind == Kind.STONE:
			var box := mesh.get_aabb().size
			size *= STONE_LENGTH / maxf(box.x, box.z)
			sink = STONE_SUNK * box.y
		var lying := pose(x, y, z, normal, pieces[row + 4], size, PINE_CONE if pieces[row + 6] > 0.5 else Vector3.ONE, sink)
		lying.origin -= origin
		if not laid.has(mesh):
			laid[mesh] = {"kind": kind, "poses": [], "customs": []}
		laid[mesh].poses.append(lying)
		var told := Color()
		if kind == Kind.STONE:
			told = Color(RockField.BOULDER_SCANS.find(mesh.resource_name.trim_prefix("stone_")),
				rng.randf_range(STONE_MOSS.x, STONE_MOSS.y), rng.randf(), 0.0)
		laid[mesh].customs.append(told)
	var items: Array[MultiMeshInstance3D] = []
	for mesh: ArrayMesh in laid:
		var kind: int = laid[mesh].kind
		var item := MultiMeshInstance3D.new()
		item.multimesh = MeshUtil.custom_multimesh(mesh, laid[mesh].poses, laid[mesh].customs)
		if kind == Kind.STONE:
			item.material_override = rocks.boulder_material()
		item.position = origin
		item.visibility_range_end = VIEW[kind]
		item.visibility_range_end_margin = VIEW_FADE
		item.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(item)
		items.append(item)
	return items
