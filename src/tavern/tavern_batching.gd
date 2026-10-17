extends RefCounted
## Keep repeated props close enough for frustum, occlusion and shadow culling.
## A MultiMesh spanning the whole building submits every instance together.
const CELL_SIZE := 6.0

static func apply(root: Node3D, parent: Node3D, surface_shader: Shader, interior: bool) -> Dictionary:
	var groups := {}
	var to_local := parent.global_transform.affine_inverse()
	for item: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not item.visible or item.mesh == null or item.get_parent() is TavernDoor:
			continue
		if item.get_child_count() > 0 or item.skin != null or item.get_blend_shape_count() > 0:
			continue
		var materials: Array[Material] = []
		var supported := true
		for surface in item.mesh.get_surface_count():
			var material := item.get_active_material(surface)
			# Transparent objects need individual depth sorting. Animated shaders
			# may use the object's origin, which instancing would change.
			if material is BaseMaterial3D:
				supported = (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			elif material is ShaderMaterial:
				supported = (material as ShaderMaterial).shader == surface_shader
			elif material != null:
				supported = false
			if material != null and material.next_pass != null:
				supported = false
			if not supported:
				break
			materials.append(material)
		if not supported or item.material_overlay != null:
			continue
		var bounds: AABB = (to_local * item.global_transform) * item.mesh.get_aabb()
		var center := bounds.get_center()
		var storey := 0
		if interior:
			storey = int(center.y >= 10.86) + int(center.y >= 14.875)
		var cell := Vector3i(floori(center.x / CELL_SIZE), storey, floori(center.z / CELL_SIZE))
		# Arrays compare by value; material resources compare by identity.
		var key := [item.mesh, materials, item.cast_shadow, item.layers,
			item.visibility_range_end, item.visibility_range_end_margin,
			item.visibility_range_begin, item.visibility_range_begin_margin,
			item.visibility_range_fade_mode, item.lod_bias, cell]
		if not groups.has(key):
			groups[key] = []
		var group: Array = groups[key]
		group.append(item)
	var instances := 0
	var batches := 0
	for key: Array in groups:
		var items: Array = groups[key]
		if items.size() < 2:
			continue
		var first: MeshInstance3D = items[0]
		var mesh: Mesh = first.mesh
		# Copy once per group only when dressing changed an imported material.
		# The shared imported mesh and its other instances remain untouched.
		var needs_copy := false
		for surface in mesh.get_surface_count():
			needs_copy = needs_copy or mesh.surface_get_material(surface) != key[1][surface]
		if needs_copy:
			mesh = mesh.duplicate() as Mesh
			for surface in mesh.get_surface_count():
				var material: Material = key[1][surface]
				mesh.surface_set_material(surface, material)
		var bounds: AABB = (to_local * first.global_transform) * mesh.get_aabb()
		for item: MeshInstance3D in items:
			bounds = bounds.merge((to_local * item.global_transform) * mesh.get_aabb())
		var origin := bounds.get_center()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = items.size()
		var radius := 0.0
		for i in items.size():
			var item: MeshInstance3D = items[i]
			var local := to_local * item.global_transform
			radius = maxf(radius, (local * mesh.get_aabb().get_center()).distance_to(origin))
			local.origin -= origin
			multimesh.set_instance_transform(i, local)
		multimesh.custom_aabb = AABB(bounds.position - origin, bounds.size)
		var holder := MultiMeshInstance3D.new()
		holder.name = "Props_" + str(first.name).validate_node_name()
		holder.position = origin
		holder.multimesh = multimesh
		holder.layers = first.layers
		holder.cast_shadow = first.cast_shadow
		holder.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		holder.lod_bias = first.lod_bias
		holder.visibility_range_fade_mode = first.visibility_range_fade_mode
		# Expand the group range conservatively so a near member never vanishes
		# just because the batch centre is farther away than its original limit.
		if first.visibility_range_end > 0.0:
			holder.visibility_range_end = first.visibility_range_end + radius
			holder.visibility_range_end_margin = first.visibility_range_end_margin
		if first.visibility_range_begin > 0.0:
			holder.visibility_range_begin = maxf(0.0, first.visibility_range_begin - radius)
			holder.visibility_range_begin_margin = first.visibility_range_begin_margin
		parent.add_child(holder)
		for item: MeshInstance3D in items:
			item.get_parent().remove_child(item)
			item.queue_free()
		instances += items.size()
		batches += 1
	return {"instances": instances, "batches": batches}
