class_name GrassScatter
extends RefCounted
## What a grass MultiMesh holds, and clumps spread over a triangle mesh.
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
##              green .. 1 the fresh), a rank.
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
## Steps of the R2 and R3 low-discrepancy sequences (M. Roberts, 2018): point
## k is fract(k * step), and any run of them is evenly spread.
const R2 := Vector2(0.7548776662466927, 0.5698402909980532)
const R3 := Vector3(0.8191725133961645, 0.6710436067037893, 0.5497004779019703)

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

## Lowest and highest corner of the roots in `buffer`.
static func bounds(buffer: PackedFloat32Array) -> AABB:
	if buffer.is_empty():
		return AABB()
	var low := Vector3(buffer[3], buffer[7], buffer[11])
	var high := low
	for at in range(0, buffer.size(), STRIDE):
		var root := Vector3(buffer[at + 3], buffer[at + 7], buffer[at + 11])
		low = low.min(root)
		high = high.max(root)
	return AABB(low, high - low)

## The rows of `buffer` grouped by the square of `size` metres (x, z) their
## root stands in, each group in the buffer's order.
static func split(buffer: PackedFloat32Array, size: float) -> Dictionary:
	var squares := {}
	for at in range(0, buffer.size(), STRIDE):
		var key := Vector2i(floori(buffer[at + 3] / size), floori(buffer[at + 11] / size))
		if not squares.has(key):
			squares[key] = PackedFloat32Array()
		squares[key].append_array(buffer.slice(at, at + STRIDE))
	return squares

## Clumps over the triangles `indices` of a mesh, `density` to the square
## metre of surface. `vertices` and `normals` are per vertex, in the space the
## clumps are wanted in; where the surface turns more than `slope_limit`
## (radians) from `up`, none grows. `cells` are the atlas's cells by kind
## (GrassClump.Sheet.cells). `patches`, when given, varies the tone and the
## height in broad patches and lets tall grass in seed take up to `seeding` of
## the richest of them; `flowers` is the share of clumps that are flowers.
static func over_triangles(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		density: float, slope_limit: float, up: Vector3, seed_value: int, cells: Array[PackedInt32Array],
		patches: Noise = null, seeding := 0.0, flowers := 0.0) -> PackedFloat32Array:
	# A hair under the limit, so that a wall grows at a limit of 90 degrees.
	var floor_y := cos(slope_limit) - 1e-5
	# Running total of the triangles' areas: a point of [0, total) names a
	# triangle, and larger triangles get their larger share of the clumps.
	# A triangle too steep at all three corners gets none.
	var reach := PackedFloat32Array()
	reach.resize(indices.size() / 3)
	var total := 0.0
	for triangle in reach.size():
		var i := indices[triangle * 3]
		var j := indices[triangle * 3 + 1]
		var k := indices[triangle * 3 + 2]
		if maxf(normals[i].dot(up), maxf(normals[j].dot(up), normals[k].dot(up))) >= floor_y:
			total += (vertices[j] - vertices[i]).cross(vertices[k] - vertices[i]).length() * 0.5
		reach[triangle] = total
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := int(total * density + rng.randf())
	var start := Vector3(rng.randf(), rng.randf(), rng.randf())
	var buffer := PackedFloat32Array()
	buffer.resize(count * STRIDE)
	var at := 0
	for n in count:
		var triangle := mini(reach.bsearch(fposmod(start.x + n * R3.x, 1.0) * total), reach.size() - 1)
		var i := indices[triangle * 3]
		var j := indices[triangle * 3 + 1]
		var k := indices[triangle * 3 + 2]
		# A point of the unit square folded into the triangle.
		var s := fposmod(start.y + n * R3.y, 1.0)
		var t := fposmod(start.z + n * R3.z, 1.0)
		if s + t > 1.0:
			s = 1.0 - s
			t = 1.0 - t
		# The same numbers of chance whether the clump grows or not, so that
		# changing the slope limit moves no other clump.
		var pick := rng.randf()
		var variant := rng.randi()
		var jitter := rng.randf()
		var normal := (normals[i] + (normals[j] - normals[i]) * s + (normals[k] - normals[i]) * t).normalized()
		if normal.dot(up) < floor_y:
			continue
		var root := vertices[i] + (vertices[j] - vertices[i]) * s + (vertices[k] - vertices[i]) * t
		var size := lerpf(0.9, 1.1, jitter)
		var tone := 0.5
		var seeded := 0.0
		if patches != null:
			tone = 0.5 + 0.5 * patches.get_noise_2d(root.x, root.z)
			size *= lerpf(0.8, 1.2, 0.5 + 0.5 * patches.get_noise_2d(root.x * 2.3 + 71.0, root.z * 2.3 - 19.0))
			seeded = seeding * clampf(patches.get_noise_2d(root.x * 0.4 - 33.0, root.z * 0.4 + 57.0) * 2.0, 0.0, 1.0)
		var kind := GrassClump.Kind.GREEN
		if pick < flowers:
			kind = GrassClump.Kind.FLOWER
		elif pick < flowers + (1.0 - flowers) * seeded:
			kind = GrassClump.Kind.SEEDING
		var kin := cells[kind]
		put(buffer, at, root.x, root.y, root.z, normal.x, normal.y, normal.z, size, kin[variant % kin.size()], 1.0,
			tone, (n + 0.5) / count)
		at += STRIDE
	buffer.resize(at)
	return buffer
