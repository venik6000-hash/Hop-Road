extends RefCounted
## The trunk colliders of VegetationSystem, made straight in the physics
## server (static functions over the VegetationSystem `system`, which holds
## the bodies and shapes).

# --- collision ----------------------------------------------------------------

## Cylinders around the trunks of the trees in the walkable near field, one
## static body per 128 m cell. Shapes are added before the body enters the
## space, so the broadphase is built once.
static func make(system: VegetationSystem) -> void:
	var trees := system.trees
	var near := Rect2(system.terrain.near_origin, Vector2.ONE * system.terrain.near_cell * (system.terrain.near_size - 1))
	var shapes := {}
	var bodies := {}
	for i in trees.size():
		if not trees.is_detail(i) or not near.has_point(Vector2(trees.x[i], trees.z[i])):
			continue
		var radius := maxf(snappedf(VegetationSystem.TRUNK_RADIUS[trees.species[i]] * trees.scale[i], 0.02), 0.12)
		if not shapes.has(radius):
			var shape := PhysicsServer3D.cylinder_shape_create()
			PhysicsServer3D.shape_set_data(shape, {"radius": radius, "height": VegetationSystem.TRUNK_HEIGHT})
			shapes[radius] = shape
			system._shapes.append(shape)
		var cell := Vector2i(floori(trees.x[i] / VegetationSystem.COLLIDER_CELL), floori(trees.z[i] / VegetationSystem.COLLIDER_CELL))
		if not bodies.has(cell):
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
			bodies[cell] = body
			system._bodies.append(body)
		var at := Transform3D(Basis.IDENTITY, Vector3(trees.x[i], trees.y[i] + VegetationSystem.TRUNK_HEIGHT * 0.5 - 0.2, trees.z[i]))
		PhysicsServer3D.body_add_shape(bodies[cell], shapes[radius], at)
	var space := system.get_world_3d().space
	for body in system._bodies:
		PhysicsServer3D.body_set_space(body, space)

## Frees the bodies and shapes that make() created.
static func free_all(system: VegetationSystem) -> void:
	for body in system._bodies:
		PhysicsServer3D.free_rid(body)
	for shape in system._shapes:
		PhysicsServer3D.free_rid(shape)
	system._bodies.clear()
	system._shapes.clear()
