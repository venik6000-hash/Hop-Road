extends Node3D
## Unique replacement of Alpine house 00. All other houses retain their source meshes.
const LAYOUT := preload("res://src/village/village_layout.gd")
const TABLE := "res://assets/models/cottage/herbalist.json"
const MATERIALS := preload("res://src/village/cottage_materials.gd")
var replaced := 0
var mesh_count := 0
var collision_count := 0
var sky: SkySystem
var lantern: OmniLight3D
# The darkness _process last applied, and to which lantern (-1: none yet).
var _last_darkness := -1.0
var _lit_lantern: OmniLight3D

func install(map: Node3D, sky_system: SkySystem) -> void:
	sky = sky_system
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	var pose := LAYOUT.cottage_pose("herbalist")
	var origin := Vector3(table.origin[0], table.origin[1], table.origin[2])
	var materials := MATERIALS.build(table, (pose * origin).y)
	# Resolve the replacement before removing any source geometry.
	var scene := (load("res://assets/generated/layout/herbalist_placed.glb") as PackedScene).instantiate() as Node3D
	scene.transform = LAYOUT.cottage_shift("herbalist")
	add_child(scene)
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mesh_count += 1
		for surface in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface)
			if material != null and materials.has(material.resource_name):
				item.set_surface_override_material(surface, materials[material.resource_name])
		MATERIALS.leave_out_of_lantern_shadows(item)
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if item.get_meta("extras", {}).get("cottage_collision", false):
			var body := StaticBody3D.new()
			body.name = "Solid"
			var shape := CollisionShape3D.new()
			shape.shape = item.mesh.create_trimesh_shape()
			body.add_child(shape)
			item.add_child(body)
			collision_count += 1
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		if RockField.label_of(item).begins_with(table.replaces_prefix):
			item.get_parent().remove_child(item)
			item.queue_free()
			replaced += 1
	_add_stair_ramp(origin)
	var ramp := get_node("PorchStairRamp") as Node3D
	ramp.transform = pose * ramp.transform
	lantern = OmniLight3D.new()
	lantern.name = "PorchLantern"
	lantern.position = pose * Vector3(table.lantern[0], table.lantern[1], table.lantern[2])
	lantern.light_color = Color(1.0, 0.67, 0.36)
	lantern.omni_range = 3.2
	lantern.light_energy = 0.0
	lantern.shadow_enabled = true
	# As the tavern's lanterns: swaying plants and the tavern's ivy would
	# redraw the shadow map every frame.
	lantern.shadow_caster_mask = 0xFFFFFFFF & ~VegetationSystem.VISUAL_LAYER & ~TavernSystem.LAYER & ~TavernSystem.SUN_LAYERS
	FarLights.fade(lantern, "lantern")
	lantern.add_to_group(AtmosphereFog.LAMP_GROUP)
	add_child(lantern)
	print("COTTAGE replaced=%d meshes=%d colliders=%d" % [replaced, mesh_count, collision_count])

## A continuous walking surface over the chamfered treads prevents the capsule
## catching their bevels. Its slope follows the stair noses and ends on the deck.
func _add_stair_ramp(origin: Vector3) -> void:
	var points := PackedVector3Array()
	for x in [-0.045, 1.605]:
		points.append(Vector3(x, -0.1, 5.0))
		points.append(Vector3(x, 0.055, 5.0))
		points.append(Vector3(x, 0.56, 4.12))
		points.append(Vector3(x, -0.1, 3.5))
		points.append(Vector3(x, 0.56, 3.5))
	var ramp := ConvexPolygonShape3D.new()
	ramp.points = points
	var holder := CollisionShape3D.new()
	holder.shape = ramp
	var body := StaticBody3D.new()
	body.name = "PorchStairRamp"
	body.position = origin
	body.add_child(holder)
	add_child(body)
	collision_count += 1

func _process(_delta: float) -> void:
	if lantern != null and sky != null:
		var darkness := 1.0 - smoothstep(-0.02, 0.18, sky.sun_direction.y)
		# The same darkness gives the same energy and visibility; write on change.
		if darkness == _last_darkness and lantern == _lit_lantern:
			return
		_last_darkness = darkness
		_lit_lantern = lantern
		lantern.light_energy = 1.5 * darkness
		lantern.visible = darkness > 0.01

static func replaces_smoke(origin: Array) -> bool:
	return Vector2(float(origin[0]) + 15.0, float(origin[2]) + 24.0).length() < 4.0
