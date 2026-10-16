class_name GrassScatter
extends RefCounted
## What a grass MultiMesh holds.
##
## One row of a buffer (TRANSFORM_3D with custom data, STRIDE floats):
##   transform  origin: the clump's root on the ground; Y axis: the ground's
##              normal there (grass.gdshader reads both from MODEL_MATRIX; the
##              other two axes only complete the rotation);
##   custom     r size (a factor on the size of the plant's cell), g the cell
##              of the atlas it shows (GrassClump.Sheet) and, in its fraction,
##              CROWD of how closely tall plants stand round the clump (0 a
##              lone tuft or low turf, lit to its foot .. 1 the thick of the
##              meadow, its foot in the others' shade), b tone (0 the deep
##              green .. 0.5 the fresh .. 1 grass dried on the stalk:
##              sward.gdshaderinc), a rank.
##
## Rank (0..1) is the order in which clumps drop out with distance: the shader
## draws a clump while its rank is under keep(distance). Rows are written in
## rank order and every prefix of them covers the surface evenly, so the first
## share of a buffer is the whole of what a far tile needs (see share()).

const STRIDE := 16
## The shader's CROWD: the fraction of a row's cell that is 1 in the thick of
## the meadow.
const CROWD := 0.9
## The shader's FADE_SOFTNESS: clumps shrink away over the last of the ranks
## still standing.
const SOFTNESS := 0.25
## Steps of the R2 low-discrepancy sequence (M. Roberts, 2018): point k is
## fract(k * step), and any run of them is evenly spread.
const R2 := Vector2(0.7548776662466927, 0.5698402909980532)

## The shader's thin_start, thin_power, fade_start and fade_end where neither
## a material nor the renderer can tell them (a headless run has no shaders).
const FADE := Vector4(18.0, 1.3, 95.0, 115.0)
## The shader's mat_start and mat_end, likewise.
const MAT_FADE := Vector2(10.0, 24.0)

## The shader's thin_start, thin_power, fade_start and fade_end as `material`
## draws with them: its own values, else the shader's defaults.
static func fade_of(material: ShaderMaterial) -> Vector4:
	return Vector4(_number(material, "thin_start", FADE.x), _number(material, "thin_power", FADE.y),
		_number(material, "fade_start", FADE.z), _number(material, "fade_end", FADE.w))

## The shader's mat_start and mat_end as `material` draws with them.
static func mat_fade_of(material: ShaderMaterial) -> Vector2:
	return Vector2(_number(material, "mat_start", MAT_FADE.x), _number(material, "mat_end", MAT_FADE.y))

static func _number(material: ShaderMaterial, parameter: String, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(parameter)
	if value == null and material.shader != null:
		value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), parameter)
	return value if value != null else fallback

## Share of the clumps standing `distance` metres from the eye. `fade` holds the
## shader's thin_start, thin_power, fade_start and fade_end; grass_keep() in
## grass.gdshader is the same arithmetic.
static func keep(distance: float, fade: Vector4) -> float:
	var thin := pow(clampf(fade.x / maxf(distance, 0.001), 0.0, 1.0), fade.y)
	return thin * (1.0 - smoothstep(fade.z, fade.w, distance))

## Share of a buffer's rows the shader may draw at `distance`: those standing
## and those still shrinking away. Flowers thin out by the square root of what
## the grass does.
static func share(distance: float, fade: Vector4, flowers := false) -> float:
	var standing := keep(distance, fade)
	return clampf((sqrt(standing) if flowers else standing) / (1.0 - SOFTNESS), 0.0, 1.0)

## Share of the mat's rows the shader may draw at `distance`; `reach` holds
## the shader's mat_start and mat_end.
static func mat_share(distance: float, reach: Vector2) -> float:
	return clampf((1.0 - smoothstep(reach.x, reach.y, distance)) / (1.0 - SOFTNESS), 0.0, 1.0)

## Writes one row at float index `at`.
static func put(buffer: PackedFloat32Array, at: int, x: float, y: float, z: float, nx: float, ny: float, nz: float,
		size: float, cell: int, crowd: float, tone: float, rank: float) -> void:
	# X is a unit vector across the normal, Z = X x normal.
	var length := sqrt(nx * nx + ny * ny)
	var xx := 1.0
	var xy := 0.0
	if length > 1e-5:
		xx = ny / length
		xy = -nx / length
	buffer[at] = xx
	buffer[at + 1] = nx
	buffer[at + 2] = xy * nz
	buffer[at + 3] = x
	buffer[at + 4] = xy
	buffer[at + 5] = ny
	buffer[at + 6] = -xx * nz
	buffer[at + 7] = y
	buffer[at + 8] = 0.0
	buffer[at + 9] = nz
	buffer[at + 10] = xx * ny - xy * nx
	buffer[at + 11] = z
	buffer[at + 12] = size
	buffer[at + 13] = cell + CROWD * crowd
	buffer[at + 14] = tone
	buffer[at + 15] = rank

## The rank of every row of `buffer`, in its order (ascending).
static func ranks(buffer: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(buffer.size() / STRIDE)
	for row in result.size():
		result[row] = buffer[row * STRIDE + 15]
	return result

## The rows of `buffer` grouped by the square of `size` metres (x, z) their
## root stands in, each group in the buffer's order.
static func split(buffer: PackedFloat32Array, size: float) -> Dictionary:
	var squares: Dictionary[Vector2i, PackedFloat32Array] = {}
	for at in range(0, buffer.size(), STRIDE):
		var key := Vector2i(floori(buffer[at + 3] / size), floori(buffer[at + 11] / size))
		if not squares.has(key):
			squares[key] = PackedFloat32Array()
		squares[key].append_array(buffer.slice(at, at + STRIDE))
	return squares
