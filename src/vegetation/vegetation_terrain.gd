class_name VegetationTerrain
extends RefCounted
## CPU copy of the generated terrain fields (tools/pipeline/terrain/terrain.py)
## that the vegetation placement reads: both heightfields, the 1 m material
## masks of the near field and the 8 m masks of the far field.
##
## Everything is kept as flat packed arrays and sampled by hand, because the
## placement runs hundreds of thousands of lookups and Image.get_pixel() costs
## several times more than an array index. Sampling conventions match
## TerrainSystem and terrain.gdshader: sample [row z][column x] sits at
## origin + (x, z) * cell, bilinear between neighbouring samples, and the near
## field fades into the far one over its outer 40 m.

const NEAR_FADE := 40.0

var water_level := 0.72
var near_h := PackedFloat32Array()
var near_origin := Vector2.ZERO
var near_cell := 0.5
var near_size := 0
var far_h := PackedFloat32Array()
var far_origin := Vector2.ZERO
var far_cell := 8.0
var far_size := 0
## RGBA8: R path, G beach, B forest floor, A meadow flowers (1 m).
var control := PackedByteArray()
## RGBA8: R rock outcrop, G wet, B lake SDF (128 = shore), A occlusion (1 m).
var extra := PackedByteArray()
var mask_origin := Vector2.ZERO
var mask_cell := 1.0
var mask_size := 0
## RGBA8 on the far grid: R snow, G bare rock/scree, B forest, A gully wetness.
var far_masks := PackedByteArray()
## Mean far forest mask per 256 m block (mip level 5 of far_masks), 0..255.
var far_forest_blocks := PackedByteArray()
var far_block_count := 0
## Optional 0/255 grid of ground covered by buildings and props (ObstacleMap),
## row-major [z][x], cell centres at obstacle_origin + (x, z) * obstacle_cell.
var obstacles := PackedByteArray()
var obstacle_origin := Vector2.ZERO
var obstacle_cell := 0.5
var obstacle_size := Vector2i.ZERO

## Copies the fields out of a running TerrainSystem.
static func from_terrain(terrain: TerrainSystem) -> VegetationTerrain:
	var data := VegetationTerrain.new()
	data.water_level = terrain.water_level
	data.near_h = terrain.near_image.get_data().to_float32_array()
	data.near_origin = terrain.near_origin
	data.near_cell = terrain.near_cell
	data.near_size = terrain.near_size
	data.far_h = terrain.far_image.get_data().to_float32_array()
	data.far_origin = terrain.far_origin
	data.far_cell = terrain.far_cell
	data.far_size = terrain.far_size
	var masks: Dictionary = terrain.meta.masks
	data.mask_origin = Values.vec2(masks.origin)
	data.mask_cell = masks.cell
	data.mask_size = Values.whole(masks.size)
	var control: Texture2D = terrain.material.get_shader_parameter("near_control")
	var extra: Texture2D = terrain.material.get_shader_parameter("near_extra")
	var far_masks: Texture2D = terrain.material.get_shader_parameter("far_masks")
	data.control = _rgba_bytes(control, data.mask_size)
	data.extra = _rgba_bytes(extra, data.mask_size)
	var far_image := _rgba_image(far_masks, data.far_size)
	data._summarise_far_forest(far_image)
	far_image.clear_mipmaps()
	data.far_masks = far_image.get_data()
	return data

static func _rgba_bytes(texture: Texture2D, size: int) -> PackedByteArray:
	var image := _rgba_image(texture, size)
	image.clear_mipmaps()
	return image.get_data()

static func _rgba_image(texture: Texture2D, size: int) -> Image:
	if texture == null:
		return Image.create(size, size, true, Image.FORMAT_RGBA8)
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

## Per-block forest averages from a mip level whose texel spans 256 m, so the
## far placement can skip bare blocks without touching their 1024 texels.
func _summarise_far_forest(image: Image) -> void:
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var level := roundi(log(256.0 / far_cell) / log(2.0))
	far_block_count = far_size >> level
	var offset := image.get_mipmap_offset(level)
	var bytes := image.get_data()
	far_forest_blocks.resize(far_block_count * far_block_count)
	for i in far_forest_blocks.size():
		far_forest_blocks[i] = bytes[offset + i * 4 + 2]

## Highest mean forest (0..1) of the 256 m block containing `block` and its
## eight neighbours (bilinear sampling reaches a little over block edges).
## Without a summary every block counts as forested.
func far_forest_max(block: Rect2) -> float:
	if far_block_count == 0:
		return 1.0
	var span := far_cell * far_size / far_block_count
	var bx := floori((block.position.x - far_origin.x) / span)
	var bz := floori((block.position.y - far_origin.y) / span)
	var best := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ix := clampi(bx + dx, 0, far_block_count - 1)
			var iz := clampi(bz + dz, 0, far_block_count - 1)
			best = maxi(best, far_forest_blocks[iz * far_block_count + ix])
	return best / 255.0

## Height at a world position, identical to TerrainSystem.height_at().
func height(x: float, z: float) -> float:
	var far := _sample_f(far_h, far_origin, far_cell, far_size, x, z)
	var w := near_weight(x, z)
	if w <= 0.0:
		return far
	return lerpf(far, _sample_f(near_h, near_origin, near_cell, near_size, x, z), w)

func near_weight(x: float, z: float) -> float:
	if near_size == 0:
		return 0.0
	var lx := (x - near_origin.x) / near_cell
	var lz := (z - near_origin.y) / near_cell
	var edge := minf(minf(lx, lz), minf(near_size - 1 - lx, near_size - 1 - lz)) * near_cell
	return clampf(edge / NEAR_FADE, 0.0, 1.0)

## One channel (0..3) of the near control mask, 0..1, zero outside the field.
func control_at(x: float, z: float, channel: int) -> float:
	return _sample_b(control, mask_origin, mask_cell, mask_size, x, z, channel)

## One channel (0..3) of the near extra mask, 0..1. Outside the field the
## lake SDF channel reads as dry land far from the shore.
func extra_at(x: float, z: float, channel: int) -> float:
	if not _inside(mask_origin, mask_cell, mask_size, x, z):
		return 1.0 if channel == 2 else 0.0
	return _sample_b(extra, mask_origin, mask_cell, mask_size, x, z, channel)

## Signed distance to the lake shore in metres (negative in the water); only
## meaningful inside the near field, elsewhere a large positive value.
func shore_distance(x: float, z: float) -> float:
	if not _inside(mask_origin, mask_cell, mask_size, x, z):
		return 1000.0
	return extra_at(x, z, 2) * 255.0 - 128.0

## 1 where a building, wall, prop or cliff covers the ground, else 0.
func obstacle_at(x: float, z: float) -> float:
	if obstacles.is_empty():
		return 0.0
	var ix := floori((x - obstacle_origin.x) / obstacle_cell + 0.5)
	var iz := floori((z - obstacle_origin.y) / obstacle_cell + 0.5)
	if ix < 0 or iz < 0 or ix >= obstacle_size.x or iz >= obstacle_size.y:
		return 0.0
	return obstacles[iz * obstacle_size.x + ix] / 255.0

## True when nothing covers the ground within `radius` metres: the centre and
## two rings of eight points are tested, enough for walls and houses.
func obstacle_clear(x: float, z: float, radius: float) -> bool:
	if obstacles.is_empty():
		return true
	var reach := Rect2(obstacle_origin, Vector2(obstacle_size) * obstacle_cell).grow(radius)
	if not reach.has_point(Vector2(x, z)):
		return true
	if obstacle_at(x, z) > 0.5:
		return false
	for ring: float in [radius * 0.5, radius]:
		for k in 8:
			var angle := k * TAU / 8.0
			if obstacle_at(x + cos(angle) * ring, z + sin(angle) * ring) > 0.5:
				return false
	return true

static func _inside(origin: Vector2, cell: float, size: int, x: float, z: float) -> bool:
	var fx := (x - origin.x) / cell
	var fz := (z - origin.y) / cell
	return fx >= 0.0 and fz >= 0.0 and fx <= size - 1 and fz <= size - 1

static func _sample_f(data: PackedFloat32Array, origin: Vector2, cell: float, size: int, x: float, z: float) -> float:
	if size == 0:
		return 0.0
	var fx := clampf((x - origin.x) / cell, 0.0, size - 1.001)
	var fz := clampf((z - origin.y) / cell, 0.0, size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * size + ix
	var top := lerpf(data[i], data[i + 1], tx)
	var bottom := lerpf(data[i + size], data[i + size + 1], tx)
	return lerpf(top, bottom, tz)

static func _sample_b(data: PackedByteArray, origin: Vector2, cell: float, size: int, x: float, z: float, channel: int) -> float:
	if size == 0 or data.is_empty():
		return 0.0
	var fx := (x - origin.x) / cell
	var fz := (z - origin.y) / cell
	if fx < 0.0 or fz < 0.0 or fx > size - 1 or fz > size - 1:
		return 0.0
	fx = minf(fx, size - 1.001)
	fz = minf(fz, size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := (iz * size + ix) * 4 + channel
	var row := size * 4
	var top := lerpf(data[i], data[i + 4], tx)
	var bottom := lerpf(data[i + row], data[i + row + 4], tx)
	return lerpf(top, bottom, tz) / 255.0
