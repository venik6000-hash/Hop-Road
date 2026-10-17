extends RefCounted
## The stones between the tavern's porch and its vestibule. The porch climbs
## to 7.18 m; the vestibule's flags, where the entrance leaves stand, lie at
## 6.6. Without these stones the doorway is a pit between the two: a landing
## of slabs carries the porch through the wall, and two steps go down from it
## to the flags, between the open leaves. They are laid here and not in the
## tavern's model, in its stone, and are solid.

## The top of the porch's last step and the vestibule's flags (the builder's
## ENTRY), metres.
const PORCH := 7.184
const FLAGS := 6.6
## The slabs' undersides, below the flags.
const BED := 6.5
## The courses from the porch inward: the metres of z each covers, its top,
## the joints of its slabs along x, and whether the weather reaches it. The
## first lies between the entrance pillars against the back of the porch's
## last step, the second in the wall as far as the door frame; the steps
## beyond are no wider than the open leaves leave free.
const COURSES := [
	{"z": Vector2(0.14, 0.57), "top": 7.07, "x": [9.56, 10.5, 11.46, 12.44], "open": 1.0},
	{"z": Vector2(-0.16, 0.14), "top": 7.07, "x": [9.58, 11.02, 12.42], "open": 1.0},
	{"z": Vector2(-0.46, -0.16), "top": 6.913, "x": [9.72, 10.6, 11.43, 12.28], "open": 0.0},
	{"z": Vector2(-0.76, -0.46), "top": 6.757, "x": [9.72, 10.96, 12.28], "open": 0.0},
]
## Half the joint between two slabs, the chamfer of a slab's upper edges and
## how far below its course a slab's top may lie, metres.
const JOINT := 0.006
const CHAMFER := 0.012
const SETTLE := 0.003
## The vertex colours of the tavern's stones (its shader doubles them).
const TINTS := [Color(0.31, 0.295, 0.265), Color(0.28, 0.27, 0.255), Color(0.295, 0.281, 0.263),
	Color(0.319, 0.31, 0.284), Color(0.272, 0.273, 0.28)]

## Lays the stones in `tavern`, drawn and solid.
static func build(tavern: TavernSystem) -> void:
	var stones := MeshInstance3D.new()
	stones.name = "Threshold"
	stones.mesh = mesh()
	stones.material_override = tavern.materials.get("tav_stone")
	stones.layers = LightLayers.ROOMS | LightLayers.SUN | LightLayers.LAMP_CASTERS
	stones.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	tavern.add_child(stones)
	for course: Dictionary in COURSES:
		var bounds := box(course)
		var holder := CollisionShape3D.new()
		holder.name = "Threshold"
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		holder.shape = shape
		holder.position = bounds.get_center()
		tavern.body.add_child(holder)
		tavern.bodies += 1

## The space a course fills, from the slabs' bed to its top.
static func box(course: Dictionary) -> AABB:
	var joints: Array = course.x
	var z: Vector2 = course.z
	return AABB(Vector3(Values.real(joints[0]), Values.real(BED), z.x), Vector3(Values.real(joints[-1] - joints[0]), Values.real(course.top - BED), z.y - z.x))

## The tops a walker steps on from the porch to the flags, in order.
static func walk() -> PackedFloat32Array:
	var tops := PackedFloat32Array([PORCH])
	for course: Dictionary in COURSES:
		if not is_equal_approx(tops[tops.size() - 1], Values.real(course.top)):
			tops.append(Values.real(course.top))
	tops.append(FLAGS)
	return tops

## Every slab of every course, in one surface.
static func mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for course: Dictionary in COURSES:
		var joints: Array = course.x
		var z: Vector2 = course.z
		for i in joints.size() - 1:
			var tint: Color = TINTS[(count * 3 + 1) % TINTS.size()]
			tint.a = course.open
			var top: float = course.top - SETTLE * ((count * 7) % 3) * 0.5
			_slab(tool, Vector3(Values.real(joints[i] + JOINT), BED, z.x + JOINT), Vector3(Values.real(joints[i + 1] - JOINT), top, z.y - JOINT), tint,
				Vector2(count * 0.37, count * 0.61))
			count += 1
	tool.generate_tangents()
	return tool.commit()

## A slab from `low` to `high` with its upper edges chamfered; its texture
## runs a metre to a unit, shifted by `shift` so that no two slabs match.
static func _slab(tool: SurfaceTool, low: Vector3, high: Vector3, tint: Color, shift: Vector2) -> void:
	var edge := high.y - CHAMFER
	var inner_low := Vector2(low.x + CHAMFER, low.z + CHAMFER)
	var inner_high := Vector2(high.x - CHAMFER, high.z - CHAMFER)
	# The top.
	_quad(tool, PackedVector3Array([Vector3(inner_low.x, high.y, inner_low.y), Vector3(inner_high.x, high.y, inner_low.y),
		Vector3(inner_high.x, high.y, inner_high.y), Vector3(inner_low.x, high.y, inner_high.y)]), tint, shift)
	# The four sides, each a chamfer over a face: toward -z, +x, +z, -x.
	var corners := [Vector2(low.x, low.z), Vector2(high.x, low.z), Vector2(high.x, high.z), Vector2(low.x, high.z)]
	var inner := [inner_low, Vector2(inner_high.x, inner_low.y), inner_high, Vector2(inner_low.x, inner_high.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var top_a: Vector2 = inner[side]
		var top_b: Vector2 = inner[(side + 1) % 4]
		_quad(tool, PackedVector3Array([Vector3(top_a.x, high.y, top_a.y), Vector3(a.x, edge, a.y), Vector3(b.x, edge, b.y),
			Vector3(top_b.x, high.y, top_b.y)]), tint, shift)
		_quad(tool, PackedVector3Array([Vector3(a.x, edge, a.y), Vector3(a.x, low.y, a.y), Vector3(b.x, low.y, b.y),
			Vector3(b.x, edge, b.y)]), tint, shift)

## A quad of two triangles facing along its corners' winding, textured by its
## own plane.
static func _quad(tool: SurfaceTool, corners: PackedVector3Array, tint: Color, shift: Vector2) -> void:
	var normal := (corners[2] - corners[0]).cross(corners[1] - corners[0]).normalized()
	for index: int in [0, 1, 2, 0, 2, 3]:
		var point: Vector3 = corners[index]
		var uv := Vector2(point.x, point.z)
		if absf(normal.y) < 0.5:
			uv = Vector2(point.x if absf(normal.z) > absf(normal.x) else point.z, -point.y)
		tool.set_normal(normal)
		tool.set_color(tint)
		tool.set_uv(uv + shift)
		tool.add_vertex(point)
