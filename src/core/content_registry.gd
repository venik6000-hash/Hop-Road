class_name ContentRegistry
extends RefCounted
## One registry of the shared systems (docs/LEVEL.md, «Реестры»): what the
## region's content gives a shared system. Each entry comes with the node of
## the content that gives it. The entry goes when that node leaves the tree,
## so a shared system that reads the registry never holds content that is
## gone, and nobody has to make it forget.

## Told after `entry` came in.
signal added(entry: Variant)
## Told after `entry` went: its node left the tree.
signal removed(entry: Variant)

## The node of each entry, in the order they came.
var _givers: Array[Node] = []
var _entries: Array = []

## Adds `entry`, which `giver` gives; it goes when `giver` leaves the tree.
func add(giver: Node, entry: Variant) -> void:
	if not _givers.has(giver):
		giver.tree_exiting.connect(_drop.bind(giver), CONNECT_ONE_SHOT)
	_givers.append(giver)
	_entries.append(entry)
	added.emit(entry)

## The entries in the order they came.
func entries() -> Array:
	return _entries.duplicate()

func size() -> int:
	return _entries.size()

func is_empty() -> bool:
	return _entries.is_empty()

## Drops every entry `giver` gave.
func _drop(giver: Node) -> void:
	var index := _givers.rfind(giver)
	while index >= 0:
		var entry: Variant = _entries[index]
		_givers.remove_at(index)
		_entries.remove_at(index)
		removed.emit(entry)
		index = _givers.rfind(giver)
