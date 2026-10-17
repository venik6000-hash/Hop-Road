class_name TavernDoor
extends AnimatableBody3D
## Existing oak leaf pivots on its actual hinge; its collision moves with it.
## It stops short of the player's body, and is a target of E of its own
## (Interaction.GROUP).
const GROUP := &"tavern_door"

var title := "Дверь"
var opened := false
var closed_angle := 0.0
var open_angle := 0.0
var target_angle := 0.0
var leaf_shape: CollisionShape3D
## The player's body stands in the way of the leaf.
var obstructed := false

func configure(item: MeshInstance3D, extras: Dictionary) -> void:
	sync_to_physics = false
	var hinge: Array = extras.tav_hinge
	position = Vector3(Values.real(hinge[0]), Values.real(hinge[2]), Values.real(-hinge[1]))
	title = extras.get("tav_title", "Дверь")
	closed_angle = -Values.real(extras.get("tav_initial", 0.0))
	open_angle = Values.real(extras.tav_swing) + closed_angle
	opened = absf(closed_angle) > 0.1
	target_angle = open_angle if opened else closed_angle
	item.reparent(self, true)
	leaf_shape = CollisionShape3D.new()
	leaf_shape.shape = item.mesh.create_convex_shape(true, true)
	leaf_shape.transform = item.transform
	add_child(leaf_shape)
	# A leaf the table hangs open (tav_open, e.g. the kitchen's yard door)
	# starts standing open, before the first frame is drawn.
	if Values.whole(extras.get("tav_open", 0)) != 0:
		opened = true
		target_angle = open_angle
		rotation.y = open_angle
	add_to_group(GROUP)
	add_to_group(Interaction.GROUP)

func center() -> Vector3:
	var item := get_child(0) as MeshInstance3D
	return item.global_transform * item.mesh.get_aabb().get_center()

## The door as E's target nearer than `best` (Interaction.GROUP).
func interaction(best: float, eye: TavernInteractions) -> Interaction:
	var distance := eye.target_distance(center(), self)
	return Interaction.of(self, distance, prompt, interact) if distance < best else null

## What E would do to the door.
func prompt() -> String:
	if obstructed:
		return "Отойдите от створки · {interact} — повернуть дверь"
	return (tr("{interact} — закрыть · %s") if opened else tr("{interact} — открыть · %s")) % tr(title)

func interact() -> void:
	opened = not opened
	obstructed = false
	target_angle = open_angle if opened else closed_angle

func _physics_process(delta: float) -> void:
	if is_equal_approx(rotation.y, target_angle):
		return
	var next := move_toward(rotation.y, target_angle, delta * 1.65)
	var predicted := global_transform
	# The leaf turns in its building's frame (a village building may stand at a yaw).
	predicted.basis = get_parent_node_3d().global_basis * Basis(Vector3.UP, next)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = leaf_shape.shape
	query.transform = predicted * leaf_shape.transform
	query.collision_mask = PhysicsLayers.PLAYER
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		obstructed = true
		return
	obstructed = false
	rotation.y = next
