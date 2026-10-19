class_name MapEdits
extends RefCounted
## The edits of a region's Blender map by the labels of its pieces
## (RegionDef.map_edits, WorldSchemas.map_edits): what the region's new
## ground did away with or moved. In the valley the chapel and its lawn are
## gone (the island is rock of the terrain), the campanile rises with the
## knoll under it, the pier goes to the turf bank, where the water is deep at
## once, and the sailing boat to the pier's side; the footbridge sits lower
## and gets a walkway over its stones. A house on whose lot a building of the
## region (RegionDef.buildings, its `replaces`) stands goes too, with its
## colliders, whatever the file says.

const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")

## The edits of `region`; empty when it names none.
static func read(region: RegionDef) -> Dictionary:
	if region.map_edits.is_empty():
		return {}
	var data: Variant = DataFile.read(region.map_edits, WorldSchemas.map_edits())
	return data if data is Dictionary else {}

## Edits `map`, which stands on `terrain`, by the region's file.
static func apply(map: Node3D, terrain: TerrainSystem) -> void:
	var edits := read(terrain.region)
	var replaced := VILLAGE_BUILDINGS.replaced(terrain.region)
	var drop: Dictionary = edits.get("drop", {})
	var labels := Values.list(drop.get("labels", []))
	var prefixes := PackedStringArray(Values.list(drop.get("prefixes", [])))
	var raises: Array = edits.get("raise", [])
	var lifts: Array[float] = []
	for raise: Dictionary in raises:
		var base := Values.vec3(raise.base)
		lifts.append(terrain.height_at(base.x, base.z) - base.y)
	var splits: Array = edits.get("split", [])
	var index := MapIndex.of(map)
	for item: MeshInstance3D in index.labelled_any(labels):
		index.drop(item)
	for prefix: String in prefixes + replaced:
		for item: MeshInstance3D in index.starting(prefix):
			index.drop(item)
	# A piece takes the first raise or split that names it; a raised piece is
	# not split.
	var edited := {}
	for at in raises.size():
		var raise: Dictionary = raises[at]
		for item: MeshInstance3D in index.labelled_any(Values.list(raise.labels)):
			if not edited.has(item):
				item.global_position.y += lifts[at]
				edited[item] = true
	for split: Dictionary in splits:
		for item: MeshInstance3D in index.labelled(str(split.label)):
			if not edited.has(item):
				_split(item, split)
				edited[item] = true
	var lowers: Array = edits.get("lower", [])
	for lower: Dictionary in lowers:
		for item: MeshInstance3D in index.labelled_any(Values.list(lower.labels)):
			item.position.y -= Values.real(lower.by)
	var walkways: Array = edits.get("walkways", [])
	for walkway: Dictionary in walkways:
		_lay_walkway(map, terrain, walkway)

## One mesh, which every instance of the map shares, moved in two parts: a
## copy takes the move, each vertex by the part it belongs to.
static func _split(item: MeshInstance3D, split: Dictionary) -> void:
	var to_local := item.global_transform.basis.inverse()
	var line := Values.real(split.z)
	var south := Values.vec3(split.south)
	var north := Values.vec3(split.north)
	var foot := Values.real(split.foot)
	var sink := Vector3.DOWN * Values.real(split.sink)
	var source := item.mesh
	var moved := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in points.size():
			var at := item.global_transform * points[i]
			var shift := north
			if at.z > line:
				shift = south
				if at.y < foot:
					shift += sink
			points[i] += to_local * shift
		arrays[Mesh.ARRAY_VERTEX] = points
		moved.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		moved.surface_set_material(surface, source.surface_get_material(surface))
	item.mesh = moved
	for holder: CollisionShape3D in item.find_children("*", "CollisionShape3D", true, false):
		var shape := moved.create_trimesh_shape()
		shape.backface_collision = true
		holder.shape = shape

## A body over the stones of the deck piece, row by row across x, with a
## ramp down to the ground at either end.
static func _lay_walkway(map: Node3D, terrain: TerrainSystem, walkway: Dictionary) -> void:
	var decks := MapIndex.of(map).labelled(str(walkway.deck))
	if decks.is_empty():
		return
	var deck := decks[-1]
	var half_width := Values.real(walkway.half_width)
	var approach := Values.real(walkway.approach)
	var depth := Values.real(walkway.depth)
	var rows := {}
	var box := deck.global_transform * deck.get_aabb()
	var centre_z := box.get_center().z
	for stone: AABB in RockField.stones_of(deck):
		var x := snappedf(stone.get_center().x, 0.01)
		rows[x] = maxf(Values.real(rows.get(x, -INF)), stone.end.y + Values.real(walkway.above))
	var keys := rows.keys()
	keys.sort()
	var profile: Array[Vector2] = []
	profile.append(Vector2(box.position.x - approach, terrain.height_at(box.position.x - approach, centre_z)))
	profile.append(Vector2(box.position.x, Values.real(rows[keys[0]])))
	for x: float in keys:
		profile.append(Vector2(x, Values.real(rows[x])))
	profile.append(Vector2(box.end.x, Values.real(rows[keys[-1]])))
	profile.append(Vector2(box.end.x + approach, terrain.height_at(box.end.x + approach, centre_z)))
	var body := StaticBody3D.new()
	body.name = str(walkway.name)
	map.add_child(body)
	for i in range(profile.size() - 1):
		var points := PackedVector3Array()
		for point: Vector2 in [profile[i], profile[i + 1]]:
			for z: float in [centre_z - half_width, centre_z + half_width]:
				points.append(Vector3(point.x, point.y, z))
				points.append(Vector3(point.x, point.y - depth, z))
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var holder := CollisionShape3D.new()
		holder.shape = shape
		body.add_child(holder)
