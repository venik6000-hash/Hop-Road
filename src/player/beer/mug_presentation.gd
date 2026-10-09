class_name MugPresentation
extends Node3D
## One private, lit viewmodel scene. Geometry never clips into the world walls.
const MODEL := preload("res://assets/models/beer/iron_tankard.glb")
const CLOTH := preload("res://src/player/beer/cloth.gdshader")
const WorldLighting := preload("res://src/player/beer/viewmodel_lighting.gd")
var pivot: Node3D
var fluid: BeerFluid
var camera: Camera3D
var key: DirectionalLight3D
var fill_light: DirectionalLight3D
var environment: Environment
var _world_lighting := WorldLighting.new()
var base_position := Vector3(0.16, -0.28, -0.66)
var base_rotation := Vector3(deg_to_rad(24), deg_to_rad(-12), deg_to_rad(-7))

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "MugCamera"
	camera.near = 0.01
	camera.far = 4.0
	camera.fov = 62.0
	camera.current = true
	add_child(camera)
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 8.0
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.71, 0.79, 1.0)
	environment.ambient_light_energy = 0.35
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.21, 0.34, 0.52)
	sky_material.sky_horizon_color = Color(0.8, 0.84, 0.90)
	sky_material.ground_bottom_color = Color(0.10, 0.065, 0.035)
	environment.sky = Sky.new()
	environment.sky.sky_material = sky_material
	world.environment = environment
	add_child(world)
	key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -36, 0)
	key.light_color = Color(1.0, 0.89, 0.72)
	key.light_energy = 0.8
	key.shadow_enabled = true
	add_child(key)
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15, 140, 0)
	fill_light.light_color = Color(0.60, 0.72, 1.0)
	fill_light.light_energy = 0.15
	add_child(fill_light)
	pivot = Node3D.new()
	pivot.name = "Wrist"
	pivot.position = base_position
	pivot.rotation = base_rotation
	add_child(pivot)
	var mug := MODEL.instantiate()
	mug.name = "IronTankard"
	pivot.add_child(mug)
	_build_sleeve()
	fluid = BeerFluid.new()
	fluid.name = "Beer"
	pivot.add_child(fluid)

func _material(color: Color, cloth: float = 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOTH
	material.set_shader_parameter("cloth_color", color)
	material.set_shader_parameter("weave", cloth)
	return material

func _sleeve(label: String, start: Vector3, end: Vector3, start_radius: float,
		end_radius: float, material: Material) -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axis := (end - start).normalized()
	var right := axis.cross(Vector3.UP).normalized()
	var up := right.cross(axis).normalized()
	var rings := 24
	var sides := 32
	for ring in range(rings + 1):
		var t := float(ring) / rings
		var centre := start.lerp(end, t)
		for side in sides:
			var angle := TAU * side / sides
			var folds := sin(t * 35.0 + sin(angle * 3.0) * 1.2) * 0.0025
			folds += sin(angle * 7.0 + t * 6.0) * 0.0015
			var radius := lerpf(start_radius, end_radius, t) + folds * sin(PI * t)
			mesh.set_uv(Vector2(float(side) / sides, t))
			mesh.set_smooth_group(0)
			mesh.add_vertex(centre + (right * cos(angle) + up * sin(angle)) * radius)
	for ring in rings:
		for side in sides:
			var a := ring * sides + side
			var b := ring * sides + (side + 1) % sides
			for index in [a, b, a+sides, b, b+sides, a+sides]: mesh.add_index(index)
	mesh.generate_normals()
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh.commit()
	node.material_override = material
	pivot.add_child(node)

func _build_sleeve() -> void:
	var cloth := _material(Color("71634c"), 1.0)
	_sleeve("LinenSleeve", Vector3(0.154, 0.15, 0.12), Vector3(0.32, -0.07, 0.48), 0.052, 0.075, cloth)

## Called from player physics so the world shadow rays use an unlocked space.
func sync_world(world_camera: Camera3D, sky: SkySystem, delta: float = 0.0) -> void:
	_world_lighting.sync(self, world_camera, sky, delta)
