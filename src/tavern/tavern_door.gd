class_name TavernDoor
extends AnimatableBody3D
## Existing oak leaf pivots on its actual hinge; its collision moves with it.
var title := "Дверь"
var opened := false
var closed_angle := 0.0
var open_angle := 0.0
var target_angle := 0.0
var leaf_shape: CollisionShape3D
var player: Player
var obstructed := false

func configure(item: MeshInstance3D, extras: Dictionary) -> void:
	sync_to_physics = false
	var hinge: Array = extras.tav_hinge
	position = Vector3(hinge[0], hinge[2], -hinge[1])
	title = extras.get("tav_title", "Дверь")
	closed_angle = -float(extras.get("tav_initial", 0.0))
	open_angle = float(extras.tav_swing) + closed_angle
	opened = absf(closed_angle) > 0.1
	target_angle = open_angle if opened else closed_angle
	item.reparent(self, true)
	leaf_shape = CollisionShape3D.new()
	leaf_shape.shape = item.mesh.create_convex_shape(true, true)
	leaf_shape.transform = item.transform
	add_child(leaf_shape)
	add_to_group(&"tavern_door")

func center() -> Vector3:
	var item := get_child(0) as MeshInstance3D
	return item.global_transform * item.mesh.get_aabb().get_center()

func interact() -> void:
	opened = not opened
	obstructed = false
	target_angle = open_angle if opened else closed_angle

func _physics_process(delta: float) -> void:
	if is_equal_approx(rotation.y, target_angle):
		return
	var next := move_toward(rotation.y, target_angle, delta * 1.65)
	var predicted := global_transform
	predicted.basis = Basis(Vector3.UP, next)
	if player != null:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = leaf_shape.shape
		query.transform = predicted * leaf_shape.transform
		query.exclude = [get_rid()]
		for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
			if hit.collider == player:
				obstructed = true
				return
	obstructed = false
	rotation.y = next
