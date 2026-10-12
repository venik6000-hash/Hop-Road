extends RefCounted
## The meshes of WaterfallSystem: the falling sheets and the stream ribbons
## (VillageBrook draws its brook with ribbon_mesh() too).

## Front sheet and a narrower one 0.4 m behind it, from `approach` seconds
## before the lip (still sliding over it) to 0.8 m under the floor. The one
## behind comes first: the sheets are blended in the order they are drawn.
## A small fall says otherwise: `behind`, how far back its second sheet lies,
## and `sink`, how far under its floor it goes (the mill's spout, whose water
## ends in the wheel's buckets).
static func fall_mesh(fall: Dictionary) -> ArrayMesh:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var lip: Vector3 = fall.lip
	var speed: float = fall.speed
	var dip: float = fall.dip
	var depth: float = fall.depth
	var floor_y: float = fall.floor
	var heading := deg_to_rad(fall.heading)
	var ahead := Vector3(sin(heading), 0.0, cos(heading))
	var side := Vector3(ahead.z, 0.0, -ahead.x)
	var t_end := WaterfallSystem.fall_time(fall, lip.y - floor_y + float(fall.get("sink", 0.8)))
	var t_start: float = -fall.approach
	for layer: int in [1, 0]:
		var base := points.size()
		var behind := float(fall.get("behind", 0.4)) * layer
		var narrow := 1.0 - 0.2 * layer
		for i in WaterfallSystem.SHEET_ROWS + 1:
			# Rows crowd toward the lip, where the water is slow and the sheet turns.
			var t := t_start + (t_end - t_start) * pow(float(i) / WaterfallSystem.SHEET_ROWS, 1.35)
			var fallen := maxf(t, 0.0)
			var center := lip + (ahead * speed + Vector3.DOWN * dip) * t + Vector3.DOWN * 0.5 * WaterfallSystem.GRAVITY * fallen * fallen
			var velocity := ahead * speed + Vector3.DOWN * (dip + WaterfallSystem.GRAVITY * fallen)
			var normal := velocity.normalized().cross(side).normalized()
			center -= normal * behind
			var share := clampf(t / t_end, 0.0, 1.0)
			var width: float = (fall.width + fall.spread * pow(share, 0.8)) * narrow
			for j in WaterfallSystem.SHEET_COLUMNS + 1:
				var u := float(j) / WaterfallSystem.SHEET_COLUMNS
				points.append(center + side * (u - 0.5) * width)
				normals.append(normal)
				tangents.append_array([side.x, side.y, side.z, 1.0])
				colors.append(Color(layer, depth, speed / 10.0, 1.0))
				uvs.append(Vector2(u, t))
				uv2s.append(Vector2((u - 0.5) * width, share))
		_grid_indices(indices, base, WaterfallSystem.SHEET_ROWS, WaterfallSystem.SHEET_COLUMNS)
	return _surface(points, normals, tangents, colors, uvs, uv2s, indices)

## Two triangles per quad of a (rows + 1) x (columns + 1) grid, wound so the
## front faces the side the grid's normal points to (Godot: clockwise).
static func _grid_indices(indices: PackedInt32Array, base: int, rows: int, columns: int) -> void:
	for i in rows:
		for j in columns:
			var a := base + i * (columns + 1) + j
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])

## A ribbon of running water along `course` (rows of [surface point on the
## centre line, half width, speed m/s]), `steps` rows per stretch: rows across
## the flow, UV = (across 0..1, metres along), UV2 = (metres from the centre
## line, flow speed), COLOR.r = half the width / 8, tangent across with the
## binormal downstream. A ribbon the shader is not to thin out at its edges
## (water between boards) names its half width `edge` metres wider than it is.
static func ribbon_mesh(course: Array, steps: int, edge := 0.0) -> ArrayMesh:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var along := 0.0
	var rows := 0
	for k in course.size() - 1:
		var a: Vector3 = course[k][0]
		var b: Vector3 = course[k + 1][0]
		var ahead := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var side := Vector3(ahead.z, 0.0, -ahead.x)
		var normal := (b - a).normalized().cross(side).normalized()
		var length := a.distance_to(b)
		for s in steps + (1 if k == course.size() - 2 else 0):
			var f := float(s) / steps
			var at := a.lerp(b, f)
			var half := lerpf(course[k][1], course[k + 1][1], f)
			var speed := lerpf(course[k][2], course[k + 1][2], f)
			for j in WaterfallSystem.STREAM_COLUMNS + 1:
				var u := float(j) / WaterfallSystem.STREAM_COLUMNS
				var across := (u - 0.5) * 2.0 * half
				points.append(at + side * across)
				normals.append(normal)
				# w = -1: the binormal (normal x tangent) points downstream.
				tangents.append_array([side.x, side.y, side.z, -1.0])
				colors.append(Color((half + edge) / 8.0, 0.0, 0.0, 1.0))
				uvs.append(Vector2(u, along + length * f))
				uv2s.append(Vector2(across, speed))
			rows += 1
		along += length
	_grid_indices(indices, 0, rows - 1, WaterfallSystem.STREAM_COLUMNS)
	return _surface(points, normals, tangents, colors, uvs, uv2s, indices)

## One triangle surface from the arrays of a sheet or a ribbon.
static func _surface(points: PackedVector3Array, normals: PackedVector3Array, tangents: PackedFloat32Array,
		colors: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
