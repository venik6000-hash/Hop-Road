extends RefCounted
## The tavern's colliders: the old map colliders it keeps or cuts, and the
## shapes of its own pieces on the "Solid" body.

## Old tavern meshes go; a collider under one moves up to the map to stay,
## unless the new pieces bring their own.
static func replace_old(tavern: TavernSystem, labels: Array, drop: Array) -> void:
	for item: MeshInstance3D in tavern.map.find_children("*", "MeshInstance3D", true, false):
		var label := RockField.label_of(item)
		if not labels.has(label):
			continue
		# The old solid walls had no service openings. Their replacement boxes
		# come from the furnished interior, while the old porch geometry stays.
		var replace_wall := tavern._has_interior and label in ["Continuous mortar behind interior masonry", "Annex oak plank door"]
		if not drop.has(label) and not replace_wall:
			for body in item.get_children():
				if body is CollisionObject3D:
					body.set_meta("tavern_source", label)
					if tavern._has_interior and label == "Tavern structural masonry":
							cut_service_openings(body)
					body.reparent(item.get_parent(), true)
		item.get_parent().remove_child(item)
		item.queue_free()
		tavern.replaced += 1

static func cached_shape(tavern: TavernSystem, mesh: Mesh, kind: String) -> Shape3D:
	var key := str(mesh.get_instance_id()) + ":" + kind
	if not tavern._shape_cache.has(key):
		var shape: Shape3D
		match kind:
			"mesh": shape = mesh.create_trimesh_shape()
			"hull": shape = mesh.create_convex_shape(true, true)
			"box":
				var box := BoxShape3D.new()
				box.size = mesh.get_aabb().size
				shape = box
		tavern._shape_cache[key] = shape
	return tavern._shape_cache[key]

static func add_shape(tavern: TavernSystem, item: MeshInstance3D, shape: Shape3D, local := Transform3D.IDENTITY) -> void:
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	var holder := CollisionShape3D.new()
	holder.name = item.name
	holder.shape = shape
	holder.transform = item.global_transform * local
	tavern._body.add_child(holder)
	tavern.bodies += 1

static func cut_service_openings(body: CollisionObject3D) -> void:
	# Remove legacy stone faces intersecting the three existing service
	# passages; keep its porch, arch, steps and every other outside collider.
	var passages: Array[AABB] = [
		AABB(Vector3(4.98, 6.55, -14.7), Vector3(1.24, 2.75, 1.45)),
		AABB(Vector3(19.72, 6.55, -1.7), Vector3(1.36, 2.4, 1.5)),
		AABB(Vector3(17.3, 6.85, -8.94), Vector3(1.4, 2.3, 1.28)),
	]
	for holder: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
		if not holder.shape is ConcavePolygonShape3D:
			continue
		var faces := (holder.shape as ConcavePolygonShape3D).get_faces()
		var kept := PackedVector3Array()
		var transform := holder.global_transform
		for index in range(0, faces.size(), 3):
			var a := transform * faces[index]
			var b := transform * faces[index + 1]
			var c := transform * faces[index + 2]
			var bounds := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(0.001)
			if passages.any(func(passage: AABB) -> bool: return passage.intersects(bounds)):
				continue
			kept.append_array(faces.slice(index, index + 3))
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(kept)
		shape.backface_collision = true
		holder.shape = shape
