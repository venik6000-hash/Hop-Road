extends RefCounted
## Suspend event callbacks after each node's _ready enables its script methods.
## Physical colliders stay active, so placement rays see the complete world.
var _root: Node
var _tree: SceneTree
var _saved: Array[Dictionary] = []
var _prepared := {}
var _captured := {}
func lock(world: Node, tree: SceneTree) -> void:
	_root = world
	_tree = tree
	_tree.node_added.connect(_on_node_added)
	_prepare(world)
func _prepare(node: Node) -> void:
	if _prepared.has(node.get_instance_id()):
		return
	_prepared[node.get_instance_id()] = true
	if node.is_node_ready():
		_capture(node)
	else:
		node.ready.connect(_capture.bind(node), CONNECT_ONE_SHOT)
	for child in node.get_children():
		_prepare(child)
func _capture(node: Node) -> void:
	if _captured.has(node.get_instance_id()):
		return
	_captured[node.get_instance_id()] = true
	_saved.append({"node": weakref(node), "input": node.is_processing_input(),
		"unhandled": node.is_processing_unhandled_input(), "key": node.is_processing_unhandled_key_input(),
		"shortcut": node.is_processing_shortcut_input()})
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process_shortcut_input(false)
func _on_node_added(node: Node) -> void:
	if _root.is_ancestor_of(node):
		_prepare(node)
func release() -> void:
	_tree.node_added.disconnect(_on_node_added)
	for entry: Dictionary in _saved:
		var ref: WeakRef = entry.node
		var node: Node = ref.get_ref()
		if node == null:
			continue
		node.set_process_input(entry.input)
		node.set_process_unhandled_input(entry.unhandled)
		node.set_process_unhandled_key_input(entry.key)
		node.set_process_shortcut_input(entry.shortcut)
	_saved.clear()
	_prepared.clear()
	_captured.clear()
