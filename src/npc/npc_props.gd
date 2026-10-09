class_name NpcProps
extends RefCounted

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

static func mug() -> Node3D:
	var root := Node3D.new()
	root.name = "Tankard"
	mesh(root, cylinder(0.065, 0.15, true), Color("80603c"), Vector3(0, 0.075, 0))
	for height: float in [0.025, 0.13]:
		mesh(root, cylinder(0.067, 0.015, true), Color("6b7174"), Vector3(0, height, 0), 0.8)
	var handle := TorusMesh.new()
	handle.inner_radius = 0.028
	handle.outer_radius = 0.045
	var ring := mesh(root, handle, Color("6b7174"), Vector3(0.085, 0.078, 0), 0.8)
	ring.rotation.x = PI / 2.0
	var beer := mesh(root, cylinder(0.057, 0.008), Color("e5b450"), Vector3(0, 0.01, 0))
	beer.name = "Beer"
	return root

static func jug() -> Node3D:
	var root := Node3D.new()
	root.name = "BeerJug"
	mesh(root, cylinder(0.078, 0.20, true), Color("807766"), Vector3(0, 0.1, 0), 0.65)
	mesh(root, cylinder(0.05, 0.045, true), Color("807766"), Vector3(0, 0.22, 0), 0.65)
	var handle := TorusMesh.new()
	handle.inner_radius = 0.04
	handle.outer_radius = 0.055
	var ring := mesh(root, handle, Color("807766"), Vector3(0.09, 0.11, 0), 0.65)
	ring.rotation.x = PI / 2.0
	var spout := mesh(root, cylinder(0.025, 0.08, true), Color("807766"), Vector3(-0.07, 0.215, 0), 0.65)
	spout.rotation.z = PI / 2.0
	var lip := Marker3D.new()
	lip.name = "Lip"
	lip.position = Vector3(-0.11, 0.215, 0)
	root.add_child(lip)
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
