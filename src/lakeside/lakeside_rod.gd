extends RefCounted
## The fishing rod on the player's camera, its line and the bobber.

const OutdoorScan = preload("res://src/render/outdoor_scan.gd")

static func build(lake: LakesideSystem) -> void:
	lake.rod = Node3D.new()
	lake.rod.name = "FishingRod"
	lake.player.camera.add_child(lake.rod)
	lake.rod.position = Vector3(0.30, -0.32, -0.48)
	for i in range(8):
		var section := NpcProps.mesh(lake.rod, NpcProps.cylinder(0.012 - i * 0.0012, 0.24), Color("9a7348"), Vector3(0, i * 0.078, -i * 0.21))
		section.rotation.x = -1.21
	var reel := NpcProps.mesh(lake.rod, NpcProps.cylinder(0.055, 0.045), Color("55534c"), Vector3(0.035, -0.04, -0.05), 0.6)
	reel.rotation.z = PI / 2
	lake.rod_tip = Node3D.new()
	lake.rod_tip.position = Vector3(0, 0.57, -1.58)
	lake.rod.add_child(lake.rod_tip)
	lake.rod.visible = false
	lake.line = MeshInstance3D.new()
	lake.line.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("c8c6a2")
	lake.line.material_override = mat
	lake.line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lake.add_child(lake.line)
	lake.bobber = NpcProps.mesh(lake, NpcProps.cylinder(0.035, 0.14), Color("e66532"))
	lake.bobber.visible = false
	# The rod and the bobber stand in the weather; the line is drawn unlit.
	OutdoorScan.dress(lake.rod, OutdoorScan.PROP_SHINE, false)
	OutdoorScan.dress(lake.bobber, OutdoorScan.PROP_SHINE, false)

static func draw_line(lake: LakesideSystem) -> void:
	var mesh := lake.line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(13):
		var t := float(i) / 12
		var point := lake.rod_tip.global_position.lerp(lake.bobber.global_position, t)
		point.y -= sin(t * PI) * (0.20 if lake.phase == "fight" else 0.6)
		mesh.surface_add_vertex(point)
	mesh.surface_end()
