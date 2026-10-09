extends RefCounted
## The impostors of VegetationSystem: every tree as a camera-facing quad in a
## static 1 km chunk (static functions over the VegetationSystem `system`).

# --- impostors ----------------------------------------------------------------

## A unit quad standing on its bottom edge: x -0.5..0.5, y 0..1, uv v down.
static func impostor_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Partition only: every input row survives once, in original per-chunk order.
static func group_members(trees: TreeSet, chunk: float) -> Dictionary:
	var low := Vector2(INF, INF)
	for i in trees.size():
		low = Vector2(minf(low.x, trees.x[i]), minf(low.y, trees.z[i]))
	var origin := (low / chunk).floor() * chunk
	var groups := {}
	for i in trees.size():
		var key := Vector2i(int((trees.x[i] - origin.x) / chunk), int((trees.z[i] - origin.y) / chunk))
		if not groups.has(key):
			groups[key] = PackedInt32Array()
		groups[key].append(i)
	return groups

static func make(system: VegetationSystem) -> void:
	var trees := system.trees
	var quad := impostor_quad()
	quad.surface_set_material(0, system.impostor_material)
	var groups := group_members(trees, VegetationSystem.CHUNK)
	for key: Vector2i in groups:
		var members: PackedInt32Array = groups[key]
		var data := PackedFloat32Array()
		data.resize(members.size() * TreeLodGrid.STRIDE)
		var box_low := Vector3(INF, INF, INF)
		var box_high := -box_low
		for n in members.size():
			var i := members[n]
			var s := trees.scale[i]
			var c := cos(trees.yaw[i]) * s
			var r := sin(trees.yaw[i]) * s
			var k := n * TreeLodGrid.STRIDE
			data[k] = c
			data[k + 2] = r
			data[k + 3] = trees.x[i]
			data[k + 5] = s
			data[k + 7] = trees.y[i]
			data[k + 8] = -r
			data[k + 10] = c
			data[k + 11] = trees.z[i]
			data[k + 12] = trees.seed[i]
			data[k + 13] = trees.species[i]
			data[k + 14] = trees.width[i]
			var frame := system.impostor_frames[trees.species[i]]
			var half := frame.x * 0.5 * s * trees.width[i]
			box_low = box_low.min(Vector3(trees.x[i] - half, trees.y[i] - 1.0, trees.z[i] - half))
			box_high = box_high.max(Vector3(trees.x[i] + half, trees.y[i] + frame.y * s, trees.z[i] + half))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		multimesh.instance_count = members.size()
		multimesh.buffer = data
		multimesh.custom_aabb = AABB(box_low, box_high - box_low)
		var item := MultiMeshInstance3D.new()
		item.name = "Impostors_%d_%d" % [key.x, key.y]
		item.multimesh = multimesh
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		item.layers = VegetationSystem.VISUAL_LAYER
		system.add_child(item)
		system._impostor_chunks.append(item)
