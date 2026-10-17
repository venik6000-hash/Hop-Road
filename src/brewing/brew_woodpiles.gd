class_name BrewWoodpiles
extends RefCounted
## The stacks of logs a log is taken from for the brewery's fires (BrewWork):
## the brewery's two piles by their anchors, and every woodpile of the valley
## by its name, its mesh or its box.

## Names of the valley's woodpiles (the village's yards, the tavern's yard and
## kitchen): a node named so is a stack a log is taken from.
const WOOD_NAMES: Array[String] = ["yards_woodpile", "yards_firewood", "woodpile", "firewood", "kitchen woodpile",
	"Yard props woodstack"]
## Half the size of the brewery's own piles about their anchors (`logs`,
## `beech_logs`, the pile's top), and how far below the top their middle is.
const PILE_HALF := Vector3(0.25, 0.32, 0.38)
const PILE_DROP := 0.3
## Metres a woodpile may stand behind what the eye's ray meets first: the
## pile's own logs before its box (VALLEY_WOOD_SLACK); in the brewery also the
## stair rail, whose collider stands to the ceiling before the piles and is
## met up to a metre before them when the eye looks down (BREWERY_WOOD_SLACK).
const VALLEY_WOOD_SLACK := 0.4
const BREWERY_WOOD_SLACK := 1.0

## {box (world AABB), log (utensil id), title, valley (a woodpile of the
## valley, not the brewery's own), slack}.
var stacks: Array[Dictionary] = []

## The stacks of `house` and of the level it stands in (`level`).
func gather(house: BrewHouse, level: Node) -> void:
	stacks.clear()
	for pile: Array in [["logs", "log", "Поленница"], ["beech_logs", "beech_log", "Буковая поленница"]]:
		if not house.layout.anchors.has(pile[0]):
			continue
		var middle: Vector3 = house.layout.anchors[pile[0]] - Vector3.UP * PILE_DROP
		var box := AABB(house.to_global(middle), Vector3.ZERO)
		for corner in 8:
			var side := Vector3(1.0 if corner & 1 else -1.0, 1.0 if corner & 2 else -1.0, 1.0 if corner & 4 else -1.0)
			box = box.expand(house.to_global(middle + PILE_HALF * side))
		stacks.append({"box": box, "log": pile[1], "title": pile[2], "valley": false, "slack": BREWERY_WOOD_SLACK})
	_find(level, house)

func _find(node: Node, house: BrewHouse) -> void:
	if node == house:
		return
	var name_of := str(node.name)
	if WOOD_NAMES.any(func(prefix: String) -> bool: return name_of.begins_with(prefix)):
		var box := AABB()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			box = (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		elif node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
			var size := ((node as CollisionShape3D).shape as BoxShape3D).size
			box = (node as CollisionShape3D).global_transform * AABB(-size * 0.5, size)
		# A pile's mesh and its collider are one stack.
		var known := stacks.any(func(stack: Dictionary) -> bool:
			var other: AABB = stack.box
			return other.is_equal_approx(box))
		if box.has_volume() and not known:
			stacks.append({"box": box, "log": "log", "title": "Поленница", "valley": true, "slack": VALLEY_WOOD_SLACK})
	for child in node.get_children():
		_find(child, house)

## The stack the eye's ray enters before anything else stops it within
## `best` metres: {index, distance}; {} for none.
func looked_at(eye: BrewEye, best: float) -> Dictionary:
	if stacks.is_empty():
		return {}
	var from := eye.camera.global_position
	var to := from - eye.camera.global_basis.z * BrewEye.REACH
	var hit := eye.ahead()
	var struck: Vector3 = hit.get("position", from)
	var wall := INF if hit.is_empty() else from.distance_to(struck)
	var found := {}
	for index in stacks.size():
		var box: AABB = stacks[index].box
		var entry: Variant = box.intersects_segment(from, to)
		if entry == null:
			continue
		var met: Vector3 = entry
		var distance := from.distance_to(met)
		if distance < best and distance <= wall + Values.real(stacks[index].slack):
			best = distance
			found = {"index": index, "distance": distance}
	return found
