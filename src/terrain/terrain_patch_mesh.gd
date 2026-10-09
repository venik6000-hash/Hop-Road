extends RefCounted
## The grid patch every CDLOD node of TerrainSystem (and WaterSystem) draws:
## `quads` x `quads` cells over the unit square, alternating diagonals.

static func patch_mesh(quads: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var side := quads + 1
	for z in side:
		for x in side:
			vertices.append(Vector3(float(x) / quads, 0.0, float(z) / quads))
	for z in quads:
		for x in quads:
			var a := z * side + x
			# Alternate the diagonal so the patch has no directional bias.
			if (x + z) % 2 == 0:
				indices.append_array([a, a + 1, a + side + 1, a, a + side + 1, a + side])
			else:
				indices.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-1, -200, -1), Vector3(3, 4400, 3))
	return mesh
