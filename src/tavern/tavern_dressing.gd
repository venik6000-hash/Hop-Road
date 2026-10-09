extends RefCounted
## Dresses the tavern's part scenes: materials, layer and shadows per mesh,
## doors, colliders, and the old fire surfaces the hearth fires replace.
const TAVERN_COLLISION = preload("res://src/tavern/tavern_collision.gd")

static func dress(tavern: TavernSystem, item: MeshInstance3D, room := false) -> void:
	tavern.mesh_count += 1
	var extras: Dictionary = item.get_meta("extras", {})
	for surface in item.mesh.get_surface_count():
		var old := item.mesh.surface_get_material(surface)
		if old != null and tavern._materials.has(old.resource_name):
			item.set_surface_override_material(surface, tavern._materials[old.resource_name])
	item.layers = TavernSystem.LAYER | (TavernSystem.ROOM_SUN_LAYER if room else TavernSystem.SUN_LAYER)
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if int(extras.get("tav_shadow", 1)) == 0:
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if casts_lamp_shadows(item):
		item.layers |= TavernSystem.SHADOW_LAYER
	# Collision-only pieces (a ramp under the stairs...).
	if int(extras.get("tav_invisible", 0)) == 1:
		item.visible = false
	var reach: float = extras.get("tav_reach", 0.0)
	if reach > 0.0:
		item.visibility_range_end = reach
		item.visibility_range_end_margin = reach * 0.1
	if int(extras.get("tav_door", 0)) == 1:
		var door := TavernDoor.new()
		door.name = item.name
		tavern.add_child(door)
		door.configure(item, extras)
		tavern.doors.append(door)
		return
	match str(extras.get("tav_collide", "none")):
		"mesh":
			TAVERN_COLLISION.add_shape(tavern, item, TAVERN_COLLISION.cached_shape(tavern, item.mesh, "mesh"))
		"hull":
			TAVERN_COLLISION.add_shape(tavern, item, TAVERN_COLLISION.cached_shape(tavern, item.mesh, "hull"))
		"box":
			var bounds := item.mesh.get_aabb()
			var box := TAVERN_COLLISION.cached_shape(tavern, item.mesh, "box")
			TAVERN_COLLISION.add_shape(tavern, item, box, Transform3D(Basis.IDENTITY, bounds.get_center()))

## Whether the tavern's lamps draw `item` into their shadow maps (see
## TavernSystem.SHADOW_LAYER): it casts shadows at all, and none of its
## materials moves by itself.
static func casts_lamp_shadows(item: MeshInstance3D) -> bool:
	if item.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return false
	for surface in item.mesh.get_surface_count():
		var material := item.get_active_material(surface) as ShaderMaterial
		if material != null and (material.shader == TavernSystem.FOLIAGE or material.shader == TavernSystem.FLAME):
			return false
	return true

static func remove_replaced_fire(root: Node3D) -> void:
	for item: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var removed: Array[int] = []
		for surface in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface)
			if material != null and material.resource_name == "tav_fire":
				removed.append(surface)
		if removed.is_empty():
			continue
		if removed.size() == item.mesh.get_surface_count():
			item.hide()
		elif item.mesh is ArrayMesh:
			# Mixed ember/fire meshes keep all other surfaces and their overrides.
			var mesh := item.mesh.duplicate() as ArrayMesh
			for surface in mesh.get_surface_count():
				mesh.surface_set_material(surface, item.get_active_material(surface))
			removed.reverse()
			for surface in removed:
				mesh.surface_remove(surface)
			mesh.shadow_mesh = null
			item.mesh = mesh
			for surface in mesh.get_surface_count():
				item.set_surface_override_material(surface, null)
