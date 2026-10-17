extends RefCounted
## Instancing and collision blocks that the scanned-rock code repeats.

## A MultiMesh of `mesh` with one instance per transform and its custom data.
static func custom_multimesh(mesh: Mesh, transforms: Array, customs: Array) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in multimesh.instance_count:
		var pose: Transform3D = transforms[i]
		var custom: Color = customs[i]
		multimesh.set_instance_transform(i, pose)
		multimesh.set_instance_custom_data(i, custom)
	return multimesh

## Adds to `body` the convex hull `points` placed by `xform`.
static func add_hull(body: Node, xform: Transform3D, points: PackedVector3Array) -> void:
	var holder := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = xform * points
	holder.shape = hull
	body.add_child(holder)
