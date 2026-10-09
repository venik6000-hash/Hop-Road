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
## shelter anything (ShelterCapture opens the map).

## Side of the map, m, and its texels along a side.
const SIDE := 256.0
const CELLS := 1024
## Texels along a side of the tile one frame draws.
const TILE := 256
## The camera's height above the lowest ground of its tile, m: over the
## tavern's ridge, under the props' shortest useful range.
const HEADROOM := 60.0
const GLOBALS := ["rain_shelter", "rain_shelter_rect"]

var terrain: TerrainSystem
## The middle of the map (world x, z).
var centre := Vector2.ZERO
var capture := ShelterCapture.new()
## Whether the map is drawn and the shaders read it.
var drawn := false

var _viewport: SubViewport
var _camera: Camera3D
var _tile := 0
var _asked := 0

func _ready() -> void:
	name = "RainShelter"
	# No device in a headless run (the tests): no map, and nothing is sheltered.
	if RenderingServer.get_rendering_device() == null:
		set_process(false)
		return
	capture.configure(corner(), cell(), CELLS)
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
	# Not the plants, and not the lake refraction's private copies.
	_camera.cull_mask = 0xFFFFF & ~VegetationSystem.VISUAL_LAYER & ~LakeRefraction.LAYER
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

func _exit_tree() -> void:
	for global_name: String in GLOBALS:
		RenderingServer.global_shader_parameter_set(global_name, Vector4.ZERO if global_name.ends_with("_rect") else null)

func _process(_delta: float) -> void:
	# A covered window draws nothing: each tile waits for its own frame.
	if capture.captured < _asked:
		return
	var tiles := tiles_per_side()
	if _tile < tiles * tiles:
		_aim(_tile)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_asked += 1
		_tile += 1
		return
	if not capture.finished:
		RenderingServer.call_on_render_thread(capture.finish)
		return
	RenderingServer.global_shader_parameter_set("rain_shelter", capture.texture)
	RenderingServer.global_shader_parameter_set("rain_shelter_rect", rect())
	drawn = true
	_viewport.queue_free()
	_viewport = null
	set_process(false)

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
	return SIDE / CELLS

## The map's corner of least x and z.
func corner() -> Vector2:
	return centre - Vector2.ONE * SIDE * 0.5

## What the shaders locate the map by: its corner (x, z), its side (m), 1.
func rect() -> Vector4:
	var from := corner()
	return Vector4(from.x, from.y, SIDE, 1.0)

static func tiles_per_side() -> int:
	return CELLS / TILE

## The land tile `index` covers (world x, z).
func tile_rect(index: int) -> Rect2:
	var tiles := tiles_per_side()
	var side := TILE * cell()
	return Rect2(corner() + Vector2(index % tiles, index / tiles) * side, Vector2.ONE * side)
