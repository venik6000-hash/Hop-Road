class_name GrassGround
extends RefCounted
## The terrain's fields as flat arrays, for the grass's tile jobs: copied from
## the terrain's material once (read()), shared by every job and only read,
## from worker threads too.

const CanopyField = preload("res://src/vegetation/canopy_field.gd")
const ImageUtil = preload("res://src/common/image_util.gd")

var water_level := 0.72
var near_origin := Vector2.ZERO
var near_cell := 0.5
var near_size := 0
## RGBA8, `mask_size` squared (control: R path, G beach, A flowers; extra:
## R rock outcrop, G wet, B metres from the lake's edge + 128, A open sky),
## sample [z][x] at mask_origin + (x, z) * mask_cell.
var control := PackedByteArray()
var extra := PackedByteArray()
var mask_origin := Vector2.ZERO
var mask_cell := 1.0
var mask_size := 0
## RGBA8, the far masks (R snow, G bare rock, A gullies) cut to the near
## field: `far_size` samples from far_origin every far_cell.
var far := PackedByteArray()
var far_origin := Vector2.ZERO
var far_cell := 8.0
var far_size := Vector2i.ZERO
## RGBA8, the terrain's tileable macro noise, `macro_size` squared.
var macro := PackedByteArray()
var macro_size := 0
## Ground covered by buildings and props (ObstacleMap), empty when none.
var cover := PackedByteArray()
var cover_origin := Vector2.ZERO
var cover_cell := 0.5
var cover_size := Vector2i.ZERO
## The cover of the trees' crowns, none where no trees stand.
var canopy: CanopyField
## The atlas's cells by kind (GrassClump.Sheet.cells).
var cells: Array[PackedInt32Array] = []

## What the fields are read from: when it changes, the terrain has been given
## other fields and they must be read again.
static func source_of(terrain: TerrainSystem) -> Array:
	return [terrain.near_image, terrain.far_image, terrain.material.get_shader_parameter("near_control"),
		terrain.material.get_shader_parameter("near_extra"), terrain.material.get_shader_parameter("water_level")]

## Copies of the terrain's masks, as the terrain's material holds them now
## (the village and the brook have painted theirs in by this time), with the
## buildings' footprint (null: none) and the crowns' cover.
static func read(terrain: TerrainSystem, obstacles: ObstacleMap, canopy_field: CanopyField) -> GrassGround:
	var ground := GrassGround.new()
	ground.water_level = terrain.material.get_shader_parameter("water_level")
	ground.near_origin = terrain.near_origin
	ground.near_cell = terrain.near_cell
	ground.near_size = terrain.near_size
	var masks: Dictionary = terrain.meta.masks
	ground.mask_origin = Values.vec2(masks.origin)
	ground.mask_cell = masks.cell
	ground.mask_size = Values.whole(masks.size)
	var control_masks: Texture2D = terrain.material.get_shader_parameter("near_control")
	var extra_masks: Texture2D = terrain.material.get_shader_parameter("near_extra")
	ground.control = _bytes(control_masks)
	ground.extra = _bytes(extra_masks)
	# The far masks matter under the near field only: keep that part.
	var far_masks: Texture2D = terrain.material.get_shader_parameter("far_masks")
	var far_image := ImageUtil.rgba8(far_masks)
	var first := Vector2i(((terrain.near_origin - terrain.far_origin) / terrain.far_cell).floor()) - Vector2i.ONE
	var span := ceili(terrain.near_size * terrain.near_cell / terrain.far_cell) + 3
	var part := Rect2i(first, Vector2i(span, span)).intersection(Rect2i(0, 0, far_image.get_width(), far_image.get_height()))
	far_image.clear_mipmaps()
	ground.far = far_image.get_region(part).get_data()
	ground.far_origin = terrain.far_origin + Vector2(part.position) * terrain.far_cell
	ground.far_cell = terrain.far_cell
	ground.far_size = part.size
	var noise: Texture2D = terrain.material.get_shader_parameter("macro_noise")
	var macro_image := ImageUtil.rgba8(noise)
	macro_image.clear_mipmaps()
	ground.macro = macro_image.get_data()
	ground.macro_size = macro_image.get_width()
	if obstacles != null:
		ground.cover = obstacles.cover
		ground.cover_origin = obstacles.origin
		ground.cover_cell = obstacles.cell
		ground.cover_size = obstacles.size
	ground.canopy = canopy_field
	ground.cells = GrassClump.sheet().cells
	return ground

static func _bytes(texture: Texture2D) -> PackedByteArray:
	var image := ImageUtil.rgba8(texture)
	image.clear_mipmaps()
	return image.get_data()

## The most of one channel (0..1) of a mask at the eight texels `reach` away
## from (mx, mz).
func around(mask: PackedByteArray, mx: int, mz: int, channel: int, reach: int) -> float:
	var size := mask_size
	var most := 0
	for dz in range(-reach, reach + 1, reach):
		var row := mz + dz
		if row < 0 or row >= size:
			continue
		for dx in range(-reach, reach + 1, reach):
			var column := mx + dx
			if column >= 0 and column < size:
				most = maxi(most, mask[(row * size + column) * 4 + channel])
	return most / 255.0

## Whether something solid covers the ground a metre from (x, z) on any side.
func beside_cover(x: float, z: float) -> bool:
	if cover.is_empty():
		return false
	var cx := int(floorf((x - cover_origin.x) / cover_cell + 0.5))
	var cz := int(floorf((z - cover_origin.y) / cover_cell + 0.5))
	var step := maxi(int(roundf(1.0 / cover_cell)), 1)
	for dz in range(-step, step + 1, step):
		var row := cz + dz
		if row < 0 or row >= cover_size.y:
			continue
		for dx in range(-step, step + 1, step):
			var column := cx + dx
			if column >= 0 and column < cover_size.x and cover[row * cover_size.x + column] > 0:
				return true
	return false

## One channel (0..1) of the far masks at a world position, bilinear.
func far_at(x: float, z: float, channel: int) -> float:
	if far.is_empty():
		return 0.0
	var fx := clampf((x - far_origin.x) / far_cell, 0.0, far_size.x - 1.001)
	var fz := clampf((z - far_origin.y) / far_cell, 0.0, far_size.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var at := (iz * far_size.x + ix) * 4 + channel
	var row := far_size.x * 4
	var top := lerpf(far[at], far[at + 4], tx)
	var bottom := lerpf(far[at + row], far[at + row + 4], tx)
	return lerpf(top, bottom, fz - iz) / 255.0

## One channel (0..1) of the macro noise at uv (wrapping), nearest sample.
func macro_at(u: float, v: float, channel: int) -> float:
	if macro_size == 0:
		return 0.5
	var ix := posmod(int(floorf(u * macro_size)), macro_size)
	var iy := posmod(int(floorf(v * macro_size)), macro_size)
	return macro[(iy * macro_size + ix) * 4 + channel] / 255.0
