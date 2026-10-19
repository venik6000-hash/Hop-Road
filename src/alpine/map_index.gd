class_name MapIndex
extends RefCounted
## The pieces of a region's Blender map by their labels (RockField.label_of),
## made by one walk of the map (docs/LEVEL.md, «Индекс карты»). The systems
## that edit, drop or dress pieces of the map ask the index, not the tree.
## The level makes the index with the content (CellContent.map_index) as the
## map comes in, before any step changes it; a tool's map of its own gets
## its index the first time a system asks for it (of()).
##
## The index holds the pieces the map had when it was made. A piece that
## leaves the map (drop(), or any removal) is not given out again; a mesh
## added to the map later is not in it. The index notes every label, prefix
## and suffix it is asked for: missing() names those that no piece of the
## map had, so that a test finds a label the code or the data asks for in
## vain (tests/test_level_content.gd).

## The meta of the map node that keeps its index.
const META := &"map_index"

## The map the pieces are of.
var map: Node3D
## The pieces in the order of the walk (the tree's order) and their labels.
var _pieces: Array[MeshInstance3D] = []
var _labels := PackedStringArray()
## Label -> Array[MeshInstance3D], each in the tree's order.
var _by_label := {}
## What the index was asked: "label:", "prefix:" or "suffix:" and the text.
var _asked := {}

## The index of `map`: the one kept on the map, else made now and kept there.
static func of(map: Node3D) -> MapIndex:
	if map.has_meta(META):
		var kept: MapIndex = map.get_meta(META)
		return kept
	var index := MapIndex.new()
	index.map = map
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var label := RockField.label_of(item)
		index._pieces.append(item)
		index._labels.append(label)
		if not index._by_label.has(label):
			var same: Array[MeshInstance3D] = []
			index._by_label[label] = same
		var found: Array[MeshInstance3D] = index._by_label[label]
		found.append(item)
	map.set_meta(META, index)
	return index

## The pieces still in the map, in the tree's order.
func pieces() -> Array[MeshInstance3D]:
	return _where(func(_label: String) -> bool: return true)

## The pieces labelled `label`.
func labelled(label: String) -> Array[MeshInstance3D]:
	_asked["label:" + label] = true
	var found: Array[MeshInstance3D] = []
	var same: Array[MeshInstance3D] = _by_label.get(label, found)
	for at in same.size():
		var item: Variant = same[at]
		if _stands(item):
			found.append(same[at])
	return found

## The pieces with any label of `labels`, in the tree's order.
func labelled_any(labels: Array) -> Array[MeshInstance3D]:
	var wanted := {}
	for label: String in labels:
		_asked["label:" + label] = true
		wanted[label] = true
	return _where(func(label: String) -> bool: return wanted.has(label))

## The pieces whose label begins with `prefix`, in the tree's order.
func starting(prefix: String) -> Array[MeshInstance3D]:
	_asked["prefix:" + prefix] = true
	return _where(func(label: String) -> bool: return label.begins_with(prefix))

## The pieces whose label ends with `suffix`, in the tree's order.
func ending(suffix: String) -> Array[MeshInstance3D]:
	_asked["suffix:" + suffix] = true
	return _where(func(label: String) -> bool: return label.ends_with(suffix))

## Takes `item` out of the map and frees it: out of the physics space at once.
func drop(item: Node) -> void:
	item.get_parent().remove_child(item)
	item.queue_free()

## The labels, prefixes and suffixes asked so far that no piece of the map
## had when the index was made: "label: <text>", "prefix: <text>",
## "suffix: <text>".
func missing() -> PackedStringArray:
	var found := PackedStringArray()
	for asked: String in _asked:
		var kind := asked.get_slice(":", 0)
		var text := asked.substr(kind.length() + 1)
		var known := false
		match kind:
			"label": known = _by_label.has(text)
			"prefix": known = _labels_match(func(label: String) -> bool: return label.begins_with(text))
			"suffix": known = _labels_match(func(label: String) -> bool: return label.ends_with(text))
		if not known:
			found.append("%s: %s" % [kind, text])
	return found

## How many labels, prefixes and suffixes the index was asked.
func asked_count() -> int:
	return _asked.size()

func _where(test: Callable) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for at in _pieces.size():
		var item: Variant = _pieces[at]
		if test.call(_labels[at]) and _stands(item):
			found.append(_pieces[at])
	return found

func _labels_match(test: Callable) -> bool:
	for label: String in _by_label:
		if test.call(label):
			return true
	return false

## Whether `item` (a piece, or what is left of a freed one) is still a piece
## of the map: not freed, and the map is still above it.
func _stands(item: Variant) -> bool:
	if not is_instance_valid(item):
		return false
	var node: Node = item
	return map.is_ancestor_of(node)
