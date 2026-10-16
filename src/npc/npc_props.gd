class_name NpcProps
extends RefCounted
const JUG := preload("res://assets/models/bar/jug.glb")

static func material(color: Color, metal := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metal
	result.roughness = 0.65
	return result

static func mesh(parent: Node3D, shape: Mesh, color: Color, at := Vector3.ZERO, metal := 0.0) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material(color, metal)
	result.position = at
	result.layers = 1 | TavernSystem.LAYER
	parent.add_child(result)
	return result

static func cylinder(radius: float, height: float, open_top := false) -> CylinderMesh:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	shape.cap_top = not open_top
	return shape

## A tankard of beer (Tankard), full as `fill` says.
static func mug(fill := 0.0) -> Tankard:
	var tankard := Tankard.new()
	tankard.fill = fill
	return tankard

## The beer jug: its foot at the origin, the pouring lip at "Lip".
static func jug() -> Node3D:
	var root := JUG.instantiate() as Node3D
	root.name = "BeerJug"
	return root

static func knife() -> Node3D:
	var root := Node3D.new()
	root.name = "KitchenKnife"
	var blade := BoxMesh.new()
	blade.size = Vector3(0.008, 0.045, 0.19)
	mesh(root, blade, Color("a8aba6"), Vector3(0, -0.025, -0.10), 0.8)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.025, 0.025, 0.09)
	mesh(root, grip, Color("573522"), Vector3(0, 0, 0.015))
	return root

static func spoon() -> Node3D:
	var root := Node3D.new()
	root.name = "WoodenSpoon"
	mesh(root, cylinder(0.012, 0.46), Color("9a6e40"), Vector3(0, -0.21, 0))
	var bowl := SphereMesh.new()
	bowl.radius = 0.03
	bowl.height = 0.065
	mesh(root, bowl, Color("9a6e40"), Vector3(0, -0.45, 0))
	return root
