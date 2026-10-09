class_name TreeSet
extends RefCounted
## Flat, packed list of placed trees. One index per tree across all arrays.

## Tree may be drawn with meshes (it lies where the camera can come close).
const DETAIL := 1
## Tree comes from the Blender composition (woodland.json), not the masks.
const COMPOSED := 2

var x := PackedFloat32Array()
var y := PackedFloat32Array()
var z := PackedFloat32Array()
var yaw := PackedFloat32Array()
var scale := PackedFloat32Array()
## Crown widening of far, thinned-out trees so the canopy stays closed.
var width := PackedFloat32Array()
## 0..1 per tree, drives tint and wind phase in the shaders.
var seed := PackedFloat32Array()
var species := PackedByteArray()
var flags := PackedByteArray()

func size() -> int:
	return x.size()

func add(px: float, py: float, pz: float, turn: float, grow: float, widen: float, kind: int, random: float,
		flag_bits: int) -> int:
	x.append(px)
	y.append(py)
	z.append(pz)
	yaw.append(turn)
	scale.append(grow)
	width.append(widen)
	seed.append(random)
	species.append(kind)
	flags.append(flag_bits)
	return x.size() - 1

func is_detail(index: int) -> bool:
	return flags[index] & DETAIL != 0

## Counts per species, for reports and tests.
func species_counts(kinds: int) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(kinds)
	for kind in species:
		counts[kind] += 1
	return counts

## Raw little-endian arrays after a count, in declaration order.
func store(file: FileAccess) -> void:
	file.store_32(size())
	for values: PackedFloat32Array in [x, y, z, yaw, scale, width, seed]:
		file.store_buffer(values.to_byte_array())
	file.store_buffer(species)
	file.store_buffer(flags)

## Reads what store() wrote; null if the file ends early.
static func read(file: FileAccess) -> TreeSet:
	var trees := TreeSet.new()
	var count := file.get_32()
	trees.x = file.get_buffer(count * 4).to_float32_array()
	trees.y = file.get_buffer(count * 4).to_float32_array()
	trees.z = file.get_buffer(count * 4).to_float32_array()
	trees.yaw = file.get_buffer(count * 4).to_float32_array()
	trees.scale = file.get_buffer(count * 4).to_float32_array()
	trees.width = file.get_buffer(count * 4).to_float32_array()
	trees.seed = file.get_buffer(count * 4).to_float32_array()
	trees.species = file.get_buffer(count)
	trees.flags = file.get_buffer(count)
	return trees if trees.flags.size() == count else null
