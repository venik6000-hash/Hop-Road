class_name CampProps
extends RefCounted
## Small tactile props using the project's existing wood/stone and flame art.
static func stone(parent: Node3D, at: Vector3, size: Vector3, index: int) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	shape.radial_segments = 9
	shape.rings = 5
	var rock := NpcProps.mesh(parent, shape, Color("807b6c").darkened(float(index % 3) * 0.09), at)
	rock.scale = size
	rock.rotation = Vector3(0.08 * index, index * 1.3, 0.06 * index)
	var material := rock.material_override as StandardMaterial3D
	material.albedo_texture = load("res://assets/generated/tavern/worn_rock_natural_01_diff_2k.jpg")
	material.roughness = 0.95
	return rock

static func log_mesh(parent: Node3D, at: Vector3, length: float, radius: float, yaw: float) -> MeshInstance3D:
	var log := NpcProps.mesh(parent, NpcProps.cylinder(radius, length), Color("9a7754"), at)
	log.rotation = Vector3(PI / 2.0, yaw, 0)
	var material := log.material_override as StandardMaterial3D
	material.albedo_texture = load("res://assets/generated/tavern/rough_wood_diff_2k.jpg")
	material.roughness = 0.95
	return log

static func potato(split := false) -> Node3D:
	var root := Node3D.new()
	root.name = "BakedPotato" if split else "PotatoInCoals"
	var shape := SphereMesh.new()
	shape.radius = 0.09
	shape.height = 0.18
	shape.radial_segments = 18
	shape.rings = 10
	var skin := NpcProps.mesh(root, shape, Color("9f784d"))
	skin.name = "Skin"
	skin.scale = Vector3(1.45, 0.75, 1.0)
	for index in range(9):
		var angle := index * 2.4
		var eye := NpcProps.mesh(root, NpcProps.cylinder(0.009, 0.003), Color("4c3323"),
			Vector3(cos(angle) * 0.085, 0.052 - float(index % 3) * 0.013, sin(angle) * 0.05))
		eye.rotation.z = -cos(angle) * 0.4
	if split:
		var flesh := NpcProps.mesh(root, NpcProps.cylinder(0.072, 0.009), Color("ffe0a0"), Vector3(0, 0.045, 0))
		flesh.scale.x = 1.5
		for index in range(6):
			var salt := BoxMesh.new()
			salt.size = Vector3(0.005, 0.004, 0.004)
			NpcProps.mesh(root, salt, Color("fff0d1"), Vector3(sin(index * 2.0) * 0.07, 0.052, cos(index * 1.3) * 0.04))
		root.add_child(steam())
	return root

static func steam() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "Steam"
	particles.position.y = 0.06
	particles.amount = 9
	particles.lifetime = 1.4
	particles.direction = Vector3.UP
	particles.spread = 12
	particles.initial_velocity_min = 0.06
	particles.initial_velocity_max = 0.13
	particles.gravity = Vector3(0, 0.03, 0)
	particles.scale_amount_min = 0.015
	particles.scale_amount_max = 0.04
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1
	puff.radial_segments = 8
	puff.rings = 4
	var material := NpcProps.material(Color(0.86, 0.83, 0.77, 0.12))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = material
	particles.mesh = puff
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles
