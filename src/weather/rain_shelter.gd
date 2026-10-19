class_name RainShelter
extends Node
## What the rain cannot reach: a map, drawn once from straight above, of the
## height of the highest roof, awning, bridge or rock over each point of the
## built-up land. The drops end on it (rain_fall.gdshader) and what lies under
## it stays dry (wetness.gdshaderinc); both read the global shader parameters
## `rain_shelter` and `rain_shelter_rect`.
##
## The land is drawn tile by tile, a frame each, with the camera low enough
## over a tile to stay inside the props' visibility ranges. Plants are left
## out, as rain comes through a crown, and so is whatever is too thin to
## shelter anything (ShelterCapture opens the map). The terrain is left out
## too: its patches are those the main camera sees, so one place would give
## another map with every look of the eye.
##
## The map is drawn when a cell of the content stands (WorldContext.shelters,
## CellContent.stand) and put away when one goes. A tool without a level's
## context draws it at once.
##
## The map follows the eye (follow(), FieldWindow) from its place round the
## region's middle. When it moves, the part both places share is kept and
## only the tiles of the rest are drawn again, a frame each; the shaders read
## the old map until the new one is opened, and its rect in the same frame.

## Side of the map, m. Its texels along a side are the profile's
## (QualityEffects.shelter_cells).
const SIDE := 256.0
## Texels along a side of the tile one frame draws.
const TILE := 256
## The camera's height above the lowest ground of its tile, m: over the
## tavern's ridge, under the props' shortest useful range.
const HEADROOM := 60.0
const GLOBALS := ["rain_shelter", "rain_shelter_rect"]
## The render layers the map is drawn from: not the plants, not the lake
## refraction's private copies, and not the terrain, whose patches are the
## ones the main camera's quadtree picked (the ground is under the drops
## anyway).
const SEEN := 0xFFFFF & ~VegetationSystem.VISUAL_LAYER & ~LakeRefraction.LAYER & ~TerrainSystem.VISUAL_LAYER
## How far (m) along an axis the eye may stray from the middle of the map
## before it moves (FieldWindow): the map's edge stays 48 m or more away.
const REACH := 80.0

var terrain: TerrainSystem
## The level's context: its quality profile gives the texels of the map
## (the authored ones without it).
var world: WorldContext
## The level's rooms: nothing outdoors is hidden from an eye in a room while
## the map is drawn (Interiors.hold_sight). Null in a level without rooms.
var interiors: Interiors
## The middle of the map with the eye at home (world x, z).
var centre := Vector2.ZERO
## Steps (FieldWindow.STEP) from there to where the map stands.
var steps := Vector2i.ZERO
var capture := ShelterCapture.new()
## Whether the map is drawn and the shaders read it.
var drawn := false
## Texels along a side of the map, fixed when the node enters the tree.
var cells := 0

var _viewport: SubViewport
var _camera: Camera3D
## The tiles still to draw, and whether they redraw part of a moved map.
var _todo := PackedInt32Array()
var _moving := false
var _asked := 0
var _eye := Vector2.ZERO
var _has_eye := false

func _ready() -> void:
	name = "RainShelter"
	cells = QualityProfile.of(world).effects.shelter_cells
	if world == null:
		_draw_map()
		return
	world.shelters.added.connect(_cell_stands)
	world.shelters.removed.connect(_cell_goes)
	if not world.shelters.is_empty():
		_draw_map()

func _cell_stands(_cell: Variant) -> void:
	redraw()

func _cell_goes(_cell: Variant) -> void:
	clear()

## Draws the map again: a cell of the content it is drawn from came.
func redraw() -> void:
	clear()
	capture = ShelterCapture.new()
	_asked = 0
	_draw_map()

## Puts the map away: a cell it was drawn from goes. Nothing is sheltered
## until redraw().
func clear() -> void:
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
	if interiors != null:
		interiors.release_sight(self)
	drawn = false
	_moving = false
	_todo.clear()
	set_process(false)
	_put_globals_away()

## The map follows the eye at `at` (world x, z); the level calls it every
## frame. A map being drawn moves once it is done.
func follow(at: Vector2) -> void:
	_eye = at
	_has_eye = true
	if _viewport != null:
		return
	var window := FieldWindow.new(home_corner(), SIDE, REACH)
	window.offset = steps
	var to := window.offset_for(at)
	if to == steps:
		return
	# Nothing drawn, nothing to keep: the next map is drawn at the new place.
	if not drawn:
		steps = to
		return
	_move(to)

## Keeps the tiles the old and the new place share, draws the others.
func _move(to: Vector2i) -> void:
	var before := Rect2(corner(), Vector2.ONE * SIDE)
	steps = to
	_todo = exposed_tiles(before)
	_moving = true
	capture.shift(corner())
	_open_view()

## The tiles of the map where it stands that lie outside `before` (world x,
## z): those a move to here draws again.
func exposed_tiles(before: Rect2) -> PackedInt32Array:
	var tiles := PackedInt32Array()
	for index in tiles_per_side() * tiles_per_side():
		if not before.encloses(tile_rect(index)):
			tiles.append(index)
	return tiles

func _draw_map() -> void:
	# No device in a headless run (the tests): no map, and nothing is sheltered.
	if RenderingServer.get_rendering_device() == null:
		set_process(false)
		return
	capture.configure(corner(), cell(), cells)
	_todo.clear()
	for index in tiles_per_side() * tiles_per_side():
		_todo.append(index)
	_moving = false
	_open_view()

func _open_view() -> void:
	set_process(true)
	_viewport = SubViewport.new()
	_viewport.name = "ShelterView"
	_viewport.size = Vector2i(TILE, TILE)
	_viewport.world_3d = (get_parent() as Node3D).get_world_3d()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = TILE * cell()
	_camera.near = 0.1
	_camera.cull_mask = SEEN
	# Only the depth is read: no sky, no fog, no lens.
	var plain := Environment.new()
	plain.background_mode = Environment.BG_COLOR
	plain.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_camera.environment = plain
	var compositor := Compositor.new()
	compositor.compositor_effects = [capture]
	_camera.compositor = compositor
	_viewport.add_child(_camera)
	_camera.current = true
	if interiors != null:
		interiors.hold_sight(self)

func _exit_tree() -> void:
	if interiors != null:
		interiors.release_sight(self)
	_put_globals_away()

func _put_globals_away() -> void:
	for global_name: String in GLOBALS:
		RenderingServer.global_shader_parameter_set(global_name, Vector4.ZERO if global_name.ends_with("_rect") else null)

func _process(_delta: float) -> void:
	# A covered window draws nothing: each tile waits for its own frame.
	if capture.captured < _asked:
		return
	if not _todo.is_empty():
		_aim(_todo[0])
		_todo.remove_at(0)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_asked += 1
		return
	if _moving:
		# The texture is the one the shaders read already: its rect goes
		# with the opening, in the same frame.
		RenderingServer.call_on_render_thread(capture.finish)
		RenderingServer.global_shader_parameter_set("rain_shelter_rect", rect())
		_moving = false
	elif not capture.finished:
		RenderingServer.call_on_render_thread(capture.finish)
		return
	else:
		RenderingServer.global_shader_parameter_set("rain_shelter", capture.texture)
		RenderingServer.global_shader_parameter_set("rain_shelter_rect", rect())
		drawn = true
	_viewport.queue_free()
	_viewport = null
	set_process(false)
	if interiors != null:
		interiors.release_sight(self)
	# The eye may have gone on while the map was drawn.
	if _has_eye:
		follow(_eye)

## The camera over tile `index`, looking straight down with x to its right
## and z down its picture.
func _aim(index: int) -> void:
	var box := tile_rect(index)
	var ground := terrain.height_range(box)
	var base := maxf(ground.x, terrain.water_level)
	var middle := box.get_center()
	_camera.far = HEADROOM + 4.0
	_camera.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP),
		Vector3(middle.x, base + HEADROOM, middle.y))

func cell() -> float:
	return SIDE / cells

## The map's corner of least x and z with the eye at home.
func home_corner() -> Vector2:
	return centre - Vector2.ONE * SIDE * 0.5

## The map's corner of least x and z where it stands.
func corner() -> Vector2:
	return home_corner() + Vector2(steps) * FieldWindow.STEP

## What the shaders locate the map by: its corner (x, z), its side (m), 1.
func rect() -> Vector4:
	var from := corner()
	return Vector4(from.x, from.y, SIDE, 1.0)

func tiles_per_side() -> int:
	return cells / TILE

## The land tile `index` covers (world x, z).
func tile_rect(index: int) -> Rect2:
	var tiles := tiles_per_side()
	var side := TILE * cell()
	return Rect2(corner() + Vector2(index % tiles, index / tiles) * side, Vector2.ONE * side)
