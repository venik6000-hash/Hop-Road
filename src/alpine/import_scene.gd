@tool
extends EditorScenePostImport
## Derived Godot resources. Reimporting the GLB rebuilds materials and bodies.
const SURFACE = preload("res://src/alpine/surface.gdshader")
var materials: Dictionary = {}
var root_scene: Node3D
var mesh_count := 0
var body_count := 0

func _post_import(scene: Node) -> Object:
	root_scene = scene as Node3D
	materials.clear()
	mesh_count = 0
	body_count = 0
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/alpine/manifest.json"))
	for mat_name: String in manifest.materials:
		materials[mat_name] = make_material(mat_name, manifest.materials[mat_name])
	process_nodes(scene)
	print("ALPINE_IMPORT meshes=%d bodies=%d" % [mesh_count, body_count])
	return scene

func make_material(label: String, settings: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = label
	mat.shader = SURFACE
	var values: Array = settings.color
	var color := Color(values[0], values[1], values[2], values[3]).linear_to_srgb()
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("roughness_value", settings.roughness)
	mat.set_shader_parameter("metallic_value", settings.metallic)
	mat.set_shader_parameter("emission_value", settings.emission)
	var foliage := "Leaves" in label
	mat.set_shader_parameter("noise_scale", 0.0 if foliage else settings.noise)
	var stretch: Array = settings.stretch
	mat.set_shader_parameter("grain_stretch", Vector3(stretch[0], stretch[2], stretch[1]))
	mat.set_shader_parameter("leaf_motion", 0.025 if foliage else 0.0)
	return mat

func process_nodes(node: Node) -> void:
	for child in node.get_children():
		process_nodes(child)
	if not node is MeshInstance3D:
		return
	var item := node as MeshInstance3D
	mesh_count += 1
	for surface in item.mesh.get_surface_count():
		var old := item.mesh.surface_get_material(surface)
		if old != null and materials.has(old.resource_name):
			item.mesh.surface_set_material(surface, materials[old.resource_name])
	var extras: Dictionary = item.get_meta("extras", {})
	var label := str(extras.get("alpine_label", item.name))
	var collision := str(extras.get("alpine_collision", ""))
	# Her source pose stood in the middle of the only doorway. Keep the
	# resident solid and place her beside the route on the same porch.
	if label == "Door hostess":
		item.position.x += 1.1
	# Place the crossing a little downstream to clear the neighbouring house.
	if label in ["Arched village footbridge", "Bridge stone walkway"]:
		item.position.z -= 3.0
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if collision == "mesh":
		var shape := item.mesh.create_trimesh_shape()
		shape.backface_collision = true
		add_body(item, shape, Transform3D.IDENTITY)
	elif collision == "resident":
		var bounds := item.mesh.get_aabb()
		var capsule := CapsuleShape3D.new()
		capsule.radius = minf(bounds.size.x, bounds.size.z) * 0.32
		capsule.height = maxf(bounds.size.y, capsule.radius * 2.0)
		add_body(item, capsule, Transform3D(Basis.IDENTITY, bounds.get_center()))

func add_body(parent: Node3D, shape: Shape3D, transform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	parent.add_child(body)
	body.owner = root_scene
	var holder := CollisionShape3D.new()
	holder.name = "Surface"
	holder.shape = shape
	holder.transform = transform
	body.add_child(holder)
	holder.owner = root_scene
	body_count += 1
