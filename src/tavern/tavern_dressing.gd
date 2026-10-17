extends RefCounted
## Dresses the tavern's part scenes: materials, layer and shadows per mesh,
## doors, colliders, and the old fire surfaces the hearth fires replace.
const TAVERN_COLLISION = preload("res://src/tavern/tavern_collision.gd")
## How many times a hide is drawn over itself to stand its hair up (tavern_fur.gdshader).
const FUR_SHELLS := 20

static func dress(tavern: TavernSystem, item: MeshInstance3D, room := false) -> void:
	tavern.mesh_count += 1
	var extras: Dictionary = item.get_meta("extras", {})
	for surface in item.mesh.get_surface_count():
		var old := item.mesh.surface_get_material(surface)
		if old != null and tavern.materials.has(old.resource_name):
			var material: Material = tavern.materials[old.resource_name]
			item.set_surface_override_material(surface, material)
	item.layers = LightLayers.ROOMS | (LightLayers.ROOM_SUN if room else LightLayers.SUN)
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if Values.whole(extras.get("tav_shadow", 1)) == 0:
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if casts_lamp_shadows(item):
		item.layers |= LightLayers.LAMP_CASTERS
	# Collision-only pieces (a ramp under the stairs...).
	if Values.whole(extras.get("tav_invisible", 0)) == 1:
		item.visible = false
	var reach: float = extras.get("tav_reach", 0.0)
	if reach > 0.0:
		item.visibility_range_end = reach
		item.visibility_range_end_margin = reach * 0.1
	var coat := item.get_active_material(0) as ShaderMaterial
	if coat != null and coat.shader == TavernSystem.FUR:
		grow_fur(item, coat)
		return
	if Values.whole(extras.get("tav_door", 0)) == 1:
		var door := TavernDoor.new()
		door.name = item.name
		tavern.add_child(door)
		door.configure(item, extras)
		tavern.doors.append(door)
		return
	if extras.has("tav_cuckoo"):
		tavern.cuckoo.add(str(extras.tav_cuckoo), item, extras)
	match str(extras.get("tav_collide", "none")):
		"mesh":
			TAVERN_COLLISION.add_shape(tavern, item, TAVERN_COLLISION.cached_shape(tavern, item.mesh, "mesh"))
		"hull":
			TAVERN_COLLISION.add_shape(tavern, item, TAVERN_COLLISION.cached_shape(tavern, item.mesh, "hull"))
		"box":
			var bounds := item.mesh.get_aabb()
			var box := TAVERN_COLLISION.cached_shape(tavern, item.mesh, "box")
			TAVERN_COLLISION.add_shape(tavern, item, box, Transform3D(Basis.IDENTITY, bounds.get_center()))

## The hair of a hide: its mesh again in FUR_SHELLS shells, the copies' custom
## data running from the tips (1) down to the skin, which `item` itself is; in
## that order what a shell hides is not shaded. The shader moves each shell out
## along the hair, so the shells' bounds are the hide's grown by the hair.
static func grow_fur(item: MeshInstance3D, coat: ShaderMaterial) -> void:
	var shells := MultiMesh.new()
	shells.transform_format = MultiMesh.TRANSFORM_3D
	shells.use_custom_data = true
	shells.mesh = item.mesh
	shells.instance_count = FUR_SHELLS
	for index in FUR_SHELLS:
		shells.set_instance_transform(index, Transform3D.IDENTITY)
		shells.set_instance_custom_data(index, Color(float(FUR_SHELLS - index) / FUR_SHELLS, 0.0, 0.0, 0.0))
	shells.custom_aabb = item.mesh.get_aabb().grow(Values.real(coat.get_shader_parameter("fur_length")))
	coat.set_shader_parameter("shells", float(FUR_SHELLS))
	var hair := MultiMeshInstance3D.new()
	hair.name = "Hair"
	hair.multimesh = shells
	hair.material_override = coat
	hair.layers = item.layers
	hair.gi_mode = item.gi_mode
	hair.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hair.visibility_range_end = item.visibility_range_end
	hair.visibility_range_end_margin = item.visibility_range_end_margin
	item.add_child(hair)

## Whether the tavern's lamps draw `item` into their shadow maps (see
## LightLayers.LAMP_CASTERS): it casts shadows at all, and none of its
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
