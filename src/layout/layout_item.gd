@tool
extends Node3D
## One movable object of the layout scene (src/layout/map_layout.gd): a house,
## a yard prop, a stone or a piece of forest wood. Its node is what the editor
## moves; what it shows hangs under it and is selected with it.
##
## While `snap_to_ground` is on, the object keeps `ground_offset` metres above
## the terrain under its pivot wherever it is dragged. With the snap off it
## moves freely and `ground_offset` follows.

## Kinds that stand upright at their own size: only their yaw is stored.
const UPRIGHT := ["house", "cottage"]

## "house", "cottage", "prop", "rock" or "wood".
@export var kind := ""
@export var snap_to_ground := true:
	set(value):
		snap_to_ground = value
		settle()
## Height of the pivot above the terrain (m); negative sets it into the ground.
@export var ground_offset := 0.0:
	set(value):
		ground_offset = value
		if not _settling and _layout() != null:
			_settling = true
			global_position.y = _layout().ground_at(global_position.x, global_position.z) + value
			_settling = false
## The record this object was read from; the save changes only what moved.
@export_storage var entry := {}
## Where the object stood when it was read: an unmoved one is saved as it was.
@export_storage var placed := Transform3D.IDENTITY

var _settling := false
var _root: Node

func _enter_tree() -> void:
	set_notify_transform(true)
	# What the object shows belongs to it, as an instanced scene's nodes do: a
	# click on a mesh selects this node, and none of it is saved with the scene.
	for node: Node in find_children("*", "", true, false):
		node.owner = self

func _exit_tree() -> void:
	_root = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not _settling:
		settle()

func moved() -> bool:
	return not transform.is_equal_approx(placed)

func _layout() -> Node:
	if _root == null and is_inside_tree():
		var node := get_parent()
		while node != null and not node.has_method(&"ground_at"):
			node = node.get_parent()
		_root = node
	return _root

func settle() -> void:
	var layout := _layout()
	if layout == null or _settling:
		return
	_settling = true
	if kind in UPRIGHT:
		if absf(rotation.x) > 0.0001 or absf(rotation.z) > 0.0001:
			rotation = Vector3(0.0, rotation.y, 0.0)
		if not scale.is_equal_approx(Vector3.ONE):
			scale = Vector3.ONE
	var ground: float = layout.ground_at(global_position.x, global_position.z)
	if snap_to_ground:
		if absf(global_position.y - ground - ground_offset) > 0.0005:
			global_position.y = ground + ground_offset
	else:
		ground_offset = global_position.y - ground
	_settling = false
	layout.item_moved(self)
