class_name MugPresentation
extends Node3D
## One private, lit viewmodel scene. Geometry never clips into the world walls.
const MODEL := preload("res://assets/models/beer/iron_tankard.glb")
const HAND := preload("res://assets/models/beer/right_hand_grip.glb")
const CLOTH := preload("res://src/player/beer/cloth.gdshader")
const WET := preload("res://src/player/beer/wet_tankard.gdshader")
const WorldLighting := preload("res://src/player/beer/viewmodel_lighting.gd")
const SLEEVE_COLOR := Color("71634c")
var pivot: Node3D
var fluid: BeerFluid
var camera: Camera3D
var key: DirectionalLight3D
var fill_light: DirectionalLight3D
var environment: Environment
## How the world lights the mug: sampled at the wrist.
var world_lighting := WorldLighting.new()
var _wet_materials: Array[ShaderMaterial] = []
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
	_wet_materials = wet_tankard(mug)
	_build_hand()
	fluid = BeerFluid.new()
	fluid.name = "Beer"
	pivot.add_child(fluid)

## The player's sleeve, brown wool: on the mug's hand and on the brewer's arms (BrewArms).
static func sleeve_cloth() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOTH
	material.set_shader_parameter("cloth_color", SLEEVE_COLOR)
	material.set_shader_parameter("weave", 1.0)
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
			for index: int in [a, b, a+sides, b, b+sides, a+sides]: mesh.add_index(index)
	mesh.generate_normals()
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh.commit()
	node.material_override = material
	pivot.add_child(node)

## The tankard keeps its maps; the wet layer runs from the rim and dries with the head.
## Dresses the iron tankard `mug` in wet iron (wet_tankard.gdshader): the
## player's mug and the villagers' (Tankard). Returns the materials, whose
## "wetness" follows the beer.
static func wet_tankard(mug: Node) -> Array[ShaderMaterial]:
	var made: Array[ShaderMaterial] = []
	for item: MeshInstance3D in mug.find_children("*", "MeshInstance3D", true, false):
		for surface in item.mesh.get_surface_count():
			var original := item.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null: continue
			var wet := ShaderMaterial.new()
			wet.shader = WET
			wet.set_shader_parameter("albedo_map", original.albedo_texture)
			wet.set_shader_parameter("normal_map", original.normal_texture)
			wet.set_shader_parameter("orm_map", original.metallic_texture)
			item.set_surface_override_material(surface, wet)
			made.append(wet)
	return made

func _process(_delta: float) -> void:
	if fluid == null: return
	for wet in _wet_materials:
		wet.set_shader_parameter("wetness", fluid.head)

func _build_hand() -> void:
	# The grip is solved in the tankard's own space (tools/pipeline/beer/prepare_hand.py).
	var hand := HAND.instantiate()
	hand.name = "RightHandGrip"
	pivot.add_child(hand)
	for item: MeshInstance3D in hand.find_children("*", "MeshInstance3D", true, false):
		for surface in item.mesh.get_surface_count():
			var original := item.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null: continue
			var skin := original.duplicate() as StandardMaterial3D
			skin.roughness = 0.72
			skin.normal_scale = 0.65
			item.set_surface_override_material(surface, skin)
	# Cuff and forearm line as prepare_hand.py prints them (SLEEVE).
	_sleeve("Sleeve", Vector3(0.209, 0.082, 0.079), Vector3(0.37, -0.202, 0.415), 0.05, 0.075, sleeve_cloth())

## Called from player physics so the world shadow rays use an unlocked space.
func sync_world(world_camera: Camera3D, sky: SkySystem, delta: float = 0.0) -> void:
	world_lighting.sync(self, world_camera, sky, delta)
