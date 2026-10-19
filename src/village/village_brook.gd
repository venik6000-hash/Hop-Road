class_name VillageBrook
extends Node3D
## The village brook: from a spring among boulders in the wood above the
## tavern meadow, down the meadow in steps and pools, over the scarp west of
## the lane as a cascade, under the arched footbridge and out into the lake
## across the gravel fan it has built there.
##
## It is the lake's water (WaterfallSystem's stream shader on the lake's
## optics) on a ribbon that follows a channel cut into the terrain: carve()
## shapes the heightfield in the valley's ground bake
## (tools/pipeline/terrain/valley_ground.gd), which keeps the courses for the
## game (TerrainSystem.course()); paint() lays the pebble bed and the wet
## margin into the terrain masks.
##
## The street's rill is drawn here too: a spring below the brewery's lane,
## water two hands wide past the well, along the upper lane and the cross
## lane, and a fall over stones into the pond. Its groove, its pebbles and
## its wet margin come with the village's ground
## (tools/pipeline/terrain/terrain_village.py reads the same line).
##
## Both lines lie in the region's file (RegionDef.brook, WorldSchemas.brook):
## the centre line downstream, each point x, z and the half width of the
## water there. The rill's are the points of its groove; a cell of the
## heightfield is half a metre, so no narrower water has a bed everywhere
## along it.

## Blender pieces this replaces (their alpine_label).
const REPLACES := ["Village brook current", "Village brook rock banks"]
## Metres between the rows of the course.
const STEP := 0.5
## The water lies this far under the ground the course crosses.
const SET_IN := 0.3
## Least fall toward the lake (m per m), so the lowest reach still runs.
const LEAST_FALL := 0.022
## The gravel fan at the mouth (m of the course): the water spreads over it
## and asks for no fall of its own.
const FAN := 7.0
## The ribbon reaches this far into its banks.
const INTO_BANK := 0.45
## The rill's water is this deep, lies this far under its banks, and those stand that
## high within this many metres of the water (the brook's: SET_IN in 1.2 m).
const RILL_DEPTH := 0.1
const RILL_SET_IN := 0.1
const RILL_BANK := 0.5
## Where it falls faster than this (m per m) it breaks white over its stones.
const RILL_STEEP := 0.16

## The names of the courses carve() cuts: the brook and the rill. A course is
## rows downstream: {at: Vector3 (the surface on the centre line), half,
## speed, depth, step: bool}.
const BROOK := &"brook"
const RILL_COURSE := &"rill"

var map: Node3D
var falls: WaterfallSystem
var terrain: TerrainSystem

func _ready() -> void:
	if map != null:
		var index := MapIndex.of(map)
		for item: MeshInstance3D in index.labelled_any(REPLACES):
			index.drop(item)
	var rows := terrain.course(BROOK)
	var rill := terrain.course(RILL_COURSE)
	_add_water("Water", rows, 0.8, 0.3, 0.02)
	_add_water("Rill", rill, RILL_DEPTH * 2.0, 0.2, 0.008)
	print("BROOK rows=%d length=%.0fm spring=%s mouth=%s rill=%.0fm from %s" % [rows.size(), rows.size() * STEP,
		rows[0].at, rows[-1].at, rill.size() * STEP, rill[0].at])

## The ribbon of the water of `course`: nowhere deeper than `depth`, its
## ripples the lake's smallest shrunk by `ripples`, its swirls `swirls` high.
func _add_water(ribbon: String, course: Array[Dictionary], depth: float, ripples: float, swirls: float) -> void:
	var line := []
	for row: Dictionary in course:
		line.append([row.at, row.half + INTO_BANK, row.speed])
	var material := falls.stream_material()
	material.set_shader_parameter("landing", Vector2(1e6, 1e6))
	material.set_shader_parameter("rapids", 0.85)
	# Its bed by the bridge lies under the lake's level without the lake
	# being behind it: nothing of the lake shows through this water.
	material.set_shader_parameter("water_level", -100.0)
	material.set_shader_parameter("max_depth", depth)
	material.set_shader_parameter("ripple_scale", ripples)
	material.set_shader_parameter("swirl_height", swirls)
	var item := MeshInstance3D.new()
	item.name = ribbon
	item.mesh = WaterfallSystem.ribbon_mesh(line, 1)
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(item)

## The brook and the rill of the file `path` (WorldSchemas.brook): {brook,
## rill: Array[Vector3] of (x, z, half width)}; {} for "" or a file that does
## not read.
static func read(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var data: Variant = DataFile.read(path, WorldSchemas.brook())
	if not data is Dictionary:
		return {}
	var file: Dictionary = data
	var lines := {}
	for key: String in ["brook", "rill"]:
		var points: Array[Vector3] = []
		var listed: Array = file[key]
		for point: Variant in listed:
			points.append(Values.vec3(point))
		lines[key] = points
	return lines

## The centre line through `points` every STEP metres: (x, z, half width).
static func centre_line(points: Array[Vector3]) -> Array[Vector3]:
	var dense: Array[Vector3] = []
	for k in points.size() - 1:
		var p0 := points[maxi(k - 1, 0)]
		var p1 := points[k]
		var p2 := points[k + 1]
		var p3 := points[mini(k + 2, points.size() - 1)]
		for s in 16:
			var t := s / 16.0
			dense.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	dense.append(points[-1])
	var line: Array[Vector3] = [dense[0]]
	var carried := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var length := Vector2(b.x - a.x, b.y - a.y).length()
		while carried + length >= STEP:
			var f := (STEP - carried) / length
			a = a.lerp(b, f)
			line.append(a)
			length *= 1.0 - f
			carried = 0.0
		carried += length
	return line

## The course of the brook through `points` over the ground `height` (x, z
## -> m) gives: the surface falls in pools and steps, as mountain brooks do,
## and ends at the lake's level.
static func plan(points: Array[Vector3], height: Callable, water_level: float) -> Array[Dictionary]:
	var line := centre_line(points)
	var count := line.size()
	var surface := PackedFloat32Array()
	surface.resize(count)
	var low := INF
	for i in count:
		low = minf(low, Values.real(height.call(line[i].x, line[i].y)) - SET_IN)
		surface[i] = maxf(low, water_level + 0.02 + LEAST_FALL * maxf((count - 1 - i) * STEP - FAN, 0.0))
	var result: Array[Dictionary] = []
	for i in count:
		result.append({"at": Vector3(line[i].x, surface[i], line[i].y), "half": line[i].z, "speed": 1.0,
			"depth": 0.35, "step": false})
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	var start := 6
	while start < count - 8:
		var last := mini(start + int(rng.randf_range(4.0, 7.5) / STEP), count - 1)
		var drop := surface[start] - surface[last]
		if drop > 0.08:
			# A pool takes a fifth of the fall, the step at its end the rest.
			var lip := last - 2
			for i in range(start, last + 1):
				var row: Dictionary = result[i]
				var at: Vector3 = row.at
				if i <= lip:
					var f := float(i - start) / maxf(lip - start, 1)
					at.y = surface[start] - drop * 0.2 * f
					var belly := sin(f * PI)
					row.half *= 1.0 + 0.3 * belly
					row.depth = 0.22 + 0.3 * belly
					row.speed = clampf(0.5 + drop * 0.6, 0.5, 1.3)
				else:
					at.y = lerpf(surface[start] - drop * 0.2, surface[last], float(i - lip) / (last - lip))
					row.half *= 0.85
					row.depth = 0.16
					row.speed = clampf(2.3 + drop * 3.0, 2.5, 4.8)
					row.step = true
				row.at = at
		else:
			for i in range(start, last + 1):
				result[i].speed = 0.55
				result[i].depth = 0.6
		start = last
	# The mouth slips under the lake's surface.
	for k in 5:
		var row: Dictionary = result[count - 1 - k]
		var at: Vector3 = row.at
		at.y = minf(at.y, water_level - 0.3 + 0.08 * k)
		row.at = at
		row.speed = 0.4
		row.step = false
	return result

## The course of the rill through `points` over the ground `height` (x, z ->
## m) gives: its water lies in the groove dug for it and never runs uphill,
## slow where the street is level and white where it falls to the pond, under
## whose surface (the lake's, `water_level`) its last rows slip.
static func plan_rill(points: Array[Vector3], height: Callable, water_level: float) -> Array[Dictionary]:
	var line := centre_line(points)
	var count := line.size()
	var result: Array[Dictionary] = []
	var low := INF
	for i in count:
		low = minf(low, Values.real(height.call(line[i].x, line[i].y)))
		result.append({"at": Vector3(line[i].x, maxf(low, water_level + 0.02), line[i].y), "half": line[i].z, "speed": 0.5,
			"depth": RILL_DEPTH, "step": false})
	for i in count:
		var from: Vector3 = result[maxi(i - 2, 0)].at
		var to: Vector3 = result[mini(i + 2, count - 1)].at
		var fall := (from.y - to.y) / maxf(Vector2(to.x - from.x, to.z - from.z).length(), STEP)
		result[i].speed = clampf(0.4 + 9.0 * fall, 0.4, 3.2)
		result[i].step = fall > RILL_STEEP
	for k in 3:
		var row: Dictionary = result[count - 1 - k]
		var at: Vector3 = row.at
		at.y = minf(at.y, water_level - 0.06 + 0.04 * k)
		row.at = at
		row.speed = 0.4
		row.step = false
	return result

## Cuts the channels of `lines` (read; {} for none) into the near
## heightfield (row z, column x at origin + index * cell). Returns the
## courses for the water and the stones, by name.
static func carve(image: Image, origin: Vector2, cell: float, water_level: float, lines: Dictionary) -> Dictionary:
	if lines.is_empty():
		return {}
	var sample := func(x: float, z: float) -> float:
		return image.get_pixel(roundi((x - origin.x) / cell), roundi((z - origin.y) / cell)).r
	var brook: Array[Vector3] = lines.brook
	var rill_line: Array[Vector3] = lines.rill
	var rows := plan(brook, sample, water_level)
	cut(image, origin, cell, rows)
	var rill := plan_rill(rill_line, sample, water_level)
	cut(image, origin, cell, rill, RILL_SET_IN, RILL_BANK)
	return {BROOK: rows, RILL_COURSE: rill}

## Cuts the channel of `course` (rows as `rows`) into the heightfield: the
## stream above the upper fall takes its bed from here too
## (WaterfallSystem.carve). Where a row has no depth the water runs over bare
## rock and nothing is cut. The banks stand `set_in` over the water from `bank`
## metres off its edge, and the ground comes back to its own over twice that.
static func cut(image: Image, origin: Vector2, cell: float, course: Array[Dictionary], set_in := SET_IN,
		bank := 1.2) -> void:
	# The brook's own distances, for a narrower bank drawn in.
	var wide := bank / 1.2
	var nearest := nearest_cells(course, origin, cell, 4.0 * wide)
	for key: Vector2i in nearest:
		var entry: Vector2 = nearest[key]
		var row: Dictionary = course[int(entry.x)]
		var d := entry.y
		var half: float = row.half
		var depth: float = row.depth
		var surface: float = row.at.y
		if depth <= 0.0:
			continue
		var target: float
		if d < half:
			var t := d / half
			target = surface - depth * (1.0 - 0.85 * t * t)
		else:
			target = surface - 0.15 * depth + (0.15 * depth + set_in) * smoothstep(half, half + bank, d)
		var weight := 1.0 - smoothstep(half + 1.0 * wide, half + 3.4 * wide, d)
		var before := image.get_pixel(key.x, key.y).r
		image.set_pixel(key.x, key.y, Color(lerpf(before, target, weight), 0, 0))

## Cells of a grid within `reach` metres of the water's edge of `course`:
## cell -> (row index, distance to the centre line).
static func nearest_cells(course: Array[Dictionary], origin: Vector2, cell: float, reach: float) -> Dictionary:
	var nearest := {}
	for index in course.size():
		var row: Dictionary = course[index]
		var at := Vector2(Values.real(row.at.x), Values.real(row.at.z))
		var radius: float = row.half + reach
		var lo := Vector2i(((at - Vector2.ONE * radius - origin) / cell).floor())
		var hi := Vector2i(((at + Vector2.ONE * radius - origin) / cell).ceil())
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				var d := (origin + Vector2(ix, iz) * cell).distance_to(at)
				if d > radius:
					continue
				var key := Vector2i(ix, iz)
				if not nearest.has(key) or d < nearest[key].y:
					nearest[key] = Vector2(index, d)
	return nearest

## The beds' pebbles and the wet margins in the terrain's masks, which the
## grass and the trees read too: neither grows in the water. Paints the path
## mask `control` and the extra mask `extra` (texel (0, 0) at `origin`,
## `cell` metres apart) along each of `courses` (rows as carve() cuts them):
## the ground bake does it for the brook and the stream above the upper fall.
static func paint(control: Image, extra: Image, origin: Vector2, cell: float, courses: Array[Array]) -> void:
	for course: Array[Dictionary] in courses:
		var nearest := nearest_cells(course, origin, cell, 3.0)
		for key: Vector2i in nearest:
			var entry: Vector2 = nearest[key]
			var row: Dictionary = course[int(entry.x)]
			var half: float = row.half
			var bed := 1.0 - smoothstep(half - 0.1, half + 1.1, entry.y)
			var color := control.get_pixel(key.x, key.y)
			color.r *= 1.0 - bed
			color.g = maxf(color.g, bed)
			color.a *= 1.0 - bed
			control.set_pixel(key.x, key.y, color)
			var more := extra.get_pixel(key.x, key.y)
			more.g = maxf(more.g, 1.0 - smoothstep(half + 0.2, half + 1.5, entry.y))
			if row.step:
				more.r = maxf(more.r, 0.7 * (1.0 - smoothstep(half, half + 1.8, entry.y)))
			extra.set_pixel(key.x, key.y, more)
