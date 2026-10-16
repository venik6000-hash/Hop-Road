class_name VillageCottage
extends Node3D
## A cottage of the village plan in place of an old house of the Blender map
## (RegionDef.cottages, BuildingSchemas.cottages): its placed model with the
## tavern's PBR lighting, its colliders, a walking surface over its porch's
## stair if it has one, and a porch lantern that lights at dusk. The old
## house's meshes go only once the cottage has loaded.

const LAYOUT := preload("res://src/village/village_layout.gd")
const MATERIALS := preload("res://src/village/cottage_materials.gd")
## The lantern's light, of every cottage.
const LANTERN_COLOR := Color(1.0, 0.67, 0.36)

## The cottage's entry of the region's cottages; set before install().
var spec: Dictionary
var replaced := 0
var mesh_count := 0
var collision_count := 0
var sky: SkySystem
var lantern: OmniLight3D
## Its table (BuildingSchemas.cottage), from install().
var table: Dictionary
# The lantern's energy at full dark.
var _energy := 0.0
# The darkness _process last applied, and to which lantern (-1: none yet).
var _last_darkness := -1.0
var _lit_lantern: OmniLight3D

## The entries of the cottages file at `path` (RegionDef.cottages); none without one.
static func entries(path: String) -> Array:
	if path.is_empty():
		return []
	var data: Variant = DataFile.read(path, BuildingSchemas.cottages())
	return (data as Dictionary).get("cottages", []) if data is Dictionary else []

## Whether the map's chimney smoke at `origin` is the smoke of the old house
## this cottage stands in place of (its entry's `smoke`). After install().
func hides_smoke(origin: Array) -> bool:
	if not spec.has("smoke"):
		return false
	var at: Array = table.origin
	return Vector2(float(origin[0]) - float(at[0]), float(origin[2]) - float(at[2])).length() < float(spec.smoke)

func install(map: Node3D, sky_system: SkySystem, village_plan: Dictionary) -> void:
	sky = sky_system
	var key: String = spec.key
	table = DataFile.read(spec.table, BuildingSchemas.cottage())
	var pose := LAYOUT.cottage_pose(village_plan, key)
	var origin := Vector3(table.origin[0], table.origin[1], table.origin[2])
	var materials := MATERIALS.build(table, (pose * origin).y)
	# Resolve the replacement before removing any source geometry.
	var scene := (load(spec.scene) as PackedScene).instantiate() as Node3D
	scene.transform = LAYOUT.cottage_shift(village_plan, key)
	add_child(scene)
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mesh_count += 1
		for surface in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface)
			if material != null and materials.has(material.resource_name):
				item.set_surface_override_material(surface, materials[material.resource_name])
		MATERIALS.leave_out_of_lantern_shadows(item)
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var extras: Dictionary = item.get_meta("extras", {})
		if extras.get(spec.solid, false):
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
	if spec.has("ramp"):
		_add_stair_ramp(spec.ramp, pose, origin)
	var light: Dictionary = spec.lantern
	lantern = OmniLight3D.new()
	lantern.name = light.name
	lantern.position = pose * Vector3(table.lantern[0], table.lantern[1], table.lantern[2])
	lantern.light_color = LANTERN_COLOR
	lantern.omni_range = light.range
	_energy = light.energy
	lantern.light_energy = 0.0
	lantern.shadow_enabled = true
	# As the tavern's lanterns: swaying plants and the tavern's ivy would
	# redraw the shadow map every frame.
	lantern.shadow_caster_mask = 0xFFFFFFFF & ~VegetationSystem.VISUAL_LAYER & ~TavernSystem.LAYER & ~TavernSystem.SUN_LAYERS
	FarLights.fade(lantern, "lantern")
	lantern.add_to_group(AtmosphereFog.LAMP_GROUP)
	add_child(lantern)
	print("COTTAGE %s replaced=%d meshes=%d colliders=%d" % [key, replaced, mesh_count, collision_count])

## A continuous walking surface over the chamfered treads keeps the capsule
## from catching on their bevels: the convex hull of `ramp`'s points, which
## follow the stair's noses and end on the deck (cottage frame, at `origin`).
func _add_stair_ramp(ramp: Dictionary, pose: Transform3D, origin: Vector3) -> void:
	var points := PackedVector3Array()
	for point: Array in ramp.points:
		points.append(Vector3(point[0], point[1], point[2]))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	var holder := CollisionShape3D.new()
	holder.shape = hull
	var body := StaticBody3D.new()
	body.name = ramp.name
	body.position = origin
	body.add_child(holder)
	add_child(body)
	body.transform = pose * body.transform
	collision_count += 1

func _process(_delta: float) -> void:
	if lantern != null and sky != null:
		var darkness := 1.0 - smoothstep(-0.02, 0.18, sky.sun_direction.y)
		# The same darkness gives the same energy and visibility; write on change.
		if darkness == _last_darkness and lantern == _lit_lantern:
			return
		_last_darkness = darkness
		_lit_lantern = lantern
		lantern.light_energy = _energy * darkness
		lantern.visible = darkness > 0.01
