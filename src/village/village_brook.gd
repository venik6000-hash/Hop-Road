class_name VillageBrook
extends Node3D
## The village brook: from a spring among boulders in the wood above the
## tavern meadow, down the meadow in steps and pools, over the scarp west of
## the lane as a cascade, under the arched footbridge and out into the lake.
##
## It is the lake's water (WaterfallSystem's stream shader on the lake's
## optics) on a ribbon that follows a channel cut into the terrain: carve()
## shapes the heightfield before the terrain is drawn or made solid, paint()
## lays the pebble bed and the wet margin into the terrain masks, stones()
## gives RockField the boulders of the steps, banks and spring.

const ImageUtil = preload("res://src/common/image_util.gd")
## Centre line downstream (x, z) and the half width of the water there.
const POINTS: Array[Vector3] = [
	Vector3(-30.0, 46.0, 0.3), Vector3(-28.6, 40.5, 0.7), Vector3(-25.8, 34.5, 0.85),
	Vector3(-27.4, 27.5, 0.9), Vector3(-24.2, 20.5, 0.9), Vector3(-25.6, 13.0, 1.0),
	Vector3(-21.8, 6.0, 1.0), Vector3(-22.6, -1.0, 1.0), Vector3(-18.8, -7.0, 1.05),
	Vector3(-17.6, -13.0, 1.1), Vector3(-14.4, -17.5, 1.1), Vector3(-13.4, -21.5, 1.0),
	Vector3(-14.6, -25.2, 1.3), Vector3(-18.2, -27.0, 1.5), Vector3(-22.0, -27.6, 1.5),
	Vector3(-23.5, -30.0, 1.4), Vector3(-24.6, -32.4, 1.5), Vector3(-27.6, -34.2, 1.7),
	Vector3(-31.5, -35.0, 2.2), Vector3(-35.5, -35.3, 3.0),
]
## Blender pieces this replaces (their alpine_label).
const REPLACES := ["Village brook current", "Village brook rock banks"]
## Metres between the rows of the course.
const STEP := 0.5
## The water lies this far under the ground the course crosses.
const SET_IN := 0.3
## Least fall toward the lake (m per m), so the lowest reach still runs.
const LEAST_FALL := 0.022
## The ribbon reaches this far into its banks.
const INTO_BANK := 0.45
## The footbridge: no boulders on its abutments.
const BRIDGE := Rect2(-29.0, -32.2, 11.0, 4.4)

## The beach trail fords the brook where it crosses this z.
const FORD_Z := 9.5

## Rows of the course downstream: {at: Vector3 (the surface on the centre
## line), half, speed, depth, step: bool}. Worked out by carve().
static var rows: Array[Dictionary] = []

var map: Node3D
var falls: WaterfallSystem

func _ready() -> void:
	if map != null:
		for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
			if RockField.label_of(item) in REPLACES:
				item.get_parent().remove_child(item)
				item.queue_free()
	var course := []
	for row: Dictionary in rows:
		course.append([row.at, row.half + INTO_BANK, row.speed])
	var material := falls.stream_material()
	material.set_shader_parameter("landing", Vector2(1e6, 1e6))
	material.set_shader_parameter("rapids", 0.85)
	# Its bed by the bridge lies under the lake's level without the lake
	# being behind it: nothing of the lake shows through this water.
	material.set_shader_parameter("water_level", -100.0)
	material.set_shader_parameter("max_depth", 0.8)
	material.set_shader_parameter("ripple_scale", 0.3)
	material.set_shader_parameter("swirl_height", 0.02)
	var item := MeshInstance3D.new()
	item.name = "Water"
	item.mesh = WaterfallSystem.ribbon_mesh(course, 1)
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(item)
	print("BROOK rows=%d length=%.0fm spring=%s mouth=%s" % [rows.size(), rows.size() * STEP, rows[0].at, rows[-1].at])

## The centre line every STEP metres: (x, z, half width).
static func centre_line() -> Array[Vector3]:
	var dense: Array[Vector3] = []
	for k in POINTS.size() - 1:
		var p0 := POINTS[maxi(k - 1, 0)]
		var p1 := POINTS[k]
		var p2 := POINTS[k + 1]
		var p3 := POINTS[mini(k + 2, POINTS.size() - 1)]
		for s in 16:
			var t := s / 16.0
			dense.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	dense.append(POINTS[-1])
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

## The course over the ground `height` (x, z -> m) gives: the surface falls
## in pools and steps, as mountain brooks do, and ends at the lake's level.
static func plan(height: Callable, water_level: float) -> Array[Dictionary]:
	var line := centre_line()
	var count := line.size()
	var surface := PackedFloat32Array()
	surface.resize(count)
	var low := INF
	for i in count:
		low = minf(low, float(height.call(line[i].x, line[i].y)) - SET_IN)
		surface[i] = maxf(low, water_level + 0.02 + LEAST_FALL * (count - 1 - i) * STEP)
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

## Cuts the channel into the near heightfield (row z, column x at origin +
## index * cell) and remembers the course for the water and the stones.
static func carve(image: Image, origin: Vector2, cell: float, water_level: float) -> void:
	var sample := func(x: float, z: float) -> float:
		return image.get_pixel(int(round((x - origin.x) / cell)), int(round((z - origin.y) / cell))).r
	rows = plan(sample, water_level)
	var nearest := _nearest(origin, cell, 4.0)
	for key: Vector2i in nearest:
		var entry: Vector2 = nearest[key]
		var row: Dictionary = rows[int(entry.x)]
		var d := entry.y
		var half: float = row.half
		var depth: float = row.depth
		var surface: float = row.at.y
		var target: float
		if d < half:
			var t := d / half
			target = surface - depth * (1.0 - 0.85 * t * t)
		else:
			target = surface - 0.15 * depth + (0.15 * depth + SET_IN) * smoothstep(half, half + 1.2, d)
		var weight := 1.0 - smoothstep(half + 1.0, half + 3.4, d)
		var before := image.get_pixel(key.x, key.y).r
		image.set_pixel(key.x, key.y, Color(lerpf(before, target, weight), 0, 0))

## Cells of a grid within `reach` metres of the water's edge: cell -> (row
## index, distance to the centre line).
static func _nearest(origin: Vector2, cell: float, reach: float) -> Dictionary:
	var nearest := {}
	for index in rows.size():
		var row: Dictionary = rows[index]
		var at := Vector2(row.at.x, row.at.z)
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

## The bed's pebbles and the wet margin in the terrain's masks, which the
## grass and the trees read too: neither grows in the water.
static func paint(terrain: TerrainSystem) -> void:
	var config: Dictionary = terrain.meta.masks
	var origin := Vector2(config.origin[0], config.origin[1])
	var cell: float = config.cell
	var control := _image(terrain, "near_control")
	var extra := _image(terrain, "near_extra")
	var nearest := _nearest(origin, cell, 3.0)
	for key: Vector2i in nearest:
		var entry: Vector2 = nearest[key]
		var row: Dictionary = rows[int(entry.x)]
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
	terrain.material.set_shader_parameter("near_control", ImageTexture.create_from_image(control))
	terrain.material.set_shader_parameter("near_extra", ImageTexture.create_from_image(extra))

static func _image(terrain: TerrainSystem, parameter: String) -> Image:
	return ImageUtil.rgba8(terrain.material.get_shader_parameter(parameter))

## Boulders for RockField ([AABB, place]): the outcrop the spring comes out
## of, the stones each step falls over, those along the banks and in the bed.
static func stones() -> Array:
	var list := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	var spring: Vector3 = rows[0].at
	var far: Vector3 = rows[4].at
	var ahead: Vector3 = (far - spring).normalized()
	var side := Vector3(ahead.z, 0.0, -ahead.x)
	# A horseshoe of large mossy boulders behind and beside the spring.
	for k in 7:
		var angle := lerpf(-1.9, 1.9, k / 6.0)
		var at: Vector3 = spring - ahead * cos(angle) * rng.randf_range(1.5, 2.4) + side * sin(angle) * rng.randf_range(1.6, 2.6)
		_stone(list, at, rng.randf_range(1.7, 3.1), rng.randf_range(0.75, 1.1))
	_stone(list, spring - ahead * 0.9 + Vector3.UP * 0.4, 2.3, 0.9)
	for k in 9:
		var at: Vector3 = spring + ahead * rng.randf_range(-3.5, 3.0) + side * rng.randf_range(1.0, 4.5) * (1.0 if k % 2 == 0 else -1.0)
		_stone(list, at, rng.randf_range(0.5, 1.3), 0.7)
	var ford := 0
	for index in rows.size():
		if absf(rows[index].at.z - FORD_Z) < absf(rows[ford].at.z - FORD_Z):
			ford = index
	for index in range(3, rows.size() - 5):
		var row: Dictionary = rows[index]
		var at: Vector3 = row.at
		var next: Vector3 = rows[index + 1].at
		ahead = Vector3(next.x - at.x, 0.0, next.z - at.z).normalized()
		side = Vector3(ahead.z, 0.0, -ahead.x)
		var half: float = row.half
		if row.step and not rows[index - 1].step:
			# The lip of a step: stones the water breaks between.
			for hand: float in [-1.0, 1.0]:
				_stone(list, at + side * hand * (half + rng.randf_range(0.0, 0.5)), rng.randf_range(0.7, 1.3), 0.75)
				_stone(list, at + side * hand * half * rng.randf_range(0.35, 0.8) + ahead * rng.randf_range(-0.3, 0.3),
					rng.randf_range(0.4, 0.7), 0.8)
			if rng.randf() < 0.6:
				_stone(list, at + side * rng.randf_range(-0.25, 0.25) * half, rng.randf_range(0.35, 0.6), 0.8)
		for hand: float in [-1.0, 1.0]:
			if rng.randf() < 0.3:
				_stone(list, at + side * hand * (half + rng.randf_range(0.0, 1.3)), rng.randf_range(0.25, 0.8), 0.7)
			if rng.randf() < 0.035:
				_stone(list, at + side * hand * (half + rng.randf_range(1.4, 3.2)), rng.randf_range(1.2, 2.3), 0.8)
		if index == ford:
			# Stepping stones where the beach trail crosses.
			for k in 4:
				_stone(list, at + side * lerpf(-1.0, 1.0, k / 3.0) * half + ahead * rng.randf_range(-0.15, 0.15)
					+ Vector3.DOWN * 0.2, 0.85, 0.6)
		if rng.randf() < 0.22:
			_stone(list, at + side * rng.randf_range(-0.9, 0.9) * half, rng.randf_range(0.18, 0.36), 0.6)
	return list

static func _stone(list: Array, at: Vector3, width: float, squat: float) -> void:
	if BRIDGE.has_point(Vector2(at.x, at.z)) and width > 0.4:
		return
	var size := Vector3(width, width * squat, width)
	list.append([AABB(at - size * 0.5 + Vector3.UP * size.y * 0.5, size), "brook"])
