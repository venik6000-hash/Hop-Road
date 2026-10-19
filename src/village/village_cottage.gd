class_name VillageCottage
extends Node3D
## A cottage of the village plan in place of an old house of the Blender map
## (RegionDef.cottages, BuildingSchemas.cottages): its placed model with the
## tavern's PBR lighting, its colliders, a walking surface over its porch's
## stair if it has one, and a porch lantern that lights at dusk (a lamp of
## kind `lantern`, InteriorLamps). The old house's meshes go only once the
## cottage has loaded.

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
## The porch lantern, among the lamps that light it at dusk.
var lamps: InteriorLamps
var lantern: Light3D
## Its table (BuildingSchemas.cottage), from install().
var table: Dictionary

## The entries of the cottages file at `path` (RegionDef.cottages); none without one.
static func entries(path: String) -> Array:
	if path.is_empty():
		return []
	var data: Variant = DataFile.read(path, BuildingSchemas.cottages())
	return Values.table(data).get("cottages", []) if data is Dictionary else []

## Whether the map's chimney smoke at `origin` is the smoke of the old house
## this cottage stands in place of (its entry's `smoke`). After install().
func hides_smoke(origin: Array) -> bool:
	if not spec.has("smoke"):
		return false
	var at: Array = table.origin
	return Vector2(Values.real(origin[0]) - Values.real(at[0]), Values.real(origin[2]) - Values.real(at[2])).length() < Values.real(spec.smoke)

func install(map: Node3D, sky_system: SkySystem, village_plan: Dictionary) -> void:
	sky = sky_system
	var key: String = spec.key
	table = DataFile.read(str(spec.table), BuildingSchemas.cottage())
	var pose := LAYOUT.cottage_pose(village_plan, key)
	var origin := Values.vec3(table.origin)
	var materials := MATERIALS.build(table, (pose * origin).y)
	# Resolve the replacement before removing any source geometry.
	var scene := (load(str(spec.scene)) as PackedScene).instantiate() as Node3D
	scene.transform = LAYOUT.cottage_shift(village_plan, key)
	add_child(scene)
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mesh_count += 1
		for surface in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface)
			if material != null and materials.has(material.resource_name):
				var dressed: Material = materials[material.resource_name]
				item.set_surface_override_material(surface, dressed)
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
	var index := MapIndex.of(map)
	for item: MeshInstance3D in index.starting(str(table.replaces_prefix)):
		index.drop(item)
		replaced += 1
	if spec.has("ramp"):
		_add_stair_ramp(Values.table(spec.ramp), pose, origin)
	var light: Dictionary = spec.lantern
	lamps = InteriorLamps.new()
	lamps.name = "Lamps"
	lamps.sky = sky
	add_child(lamps)
	var at := pose * Values.vec3(table.lantern)
	lantern = lamps.add_light({"name": light.name, "type": "point", "kind": "lantern", "layer": "exterior", "night": 1.0,
		"position": [at.x, at.y, at.z], "color": [LANTERN_COLOR.r, LANTERN_COLOR.g, LANTERN_COLOR.b],
		"energy": light.energy, "range": light.range})
	print("COTTAGE %s replaced=%d meshes=%d colliders=%d" % [key, replaced, mesh_count, collision_count])

## A continuous walking surface over the chamfered treads keeps the capsule
## from catching on their bevels: the convex hull of `ramp`'s points, which
## follow the stair's noses and end on the deck (cottage frame, at `origin`).
func _add_stair_ramp(ramp: Dictionary, pose: Transform3D, origin: Vector3) -> void:
	var points := PackedVector3Array()
	for point: Array in ramp.points:
		points.append(Values.vec3(point))
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

## What the cottage gives the lamps registry (WorldContext.lamps): its porch
## lantern, in the shadow watch and as a glow from far away.
func lamps_for() -> LampSet:
	var given := LampSet.new()
	given.lanterns = lamps.shadowed_lanterns()
	for glow: Dictionary in lamps.far_glows:
		var glow_at: Vector3 = glow.at
		var glow_color: Color = glow.color
		given.add_glow(to_global(glow_at), glow_color, Values.real(glow.radius))
	return given
