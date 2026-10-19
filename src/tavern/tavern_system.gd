class_name TavernSystem
extends Building
## The refined tavern (tools/pipeline/tavern/build.py) in place of the Blender
## map's blockout one. The builder remakes the old tavern piece by piece in
## the same places; tavern.json names the old map objects the stages built so
## far replace. Their meshes go; their colliders stay where the new pieces
## fill the same volumes (the vegetation's obstacle scan keeps seeing them),
## and go too where the new pieces bring their own or nothing stands in their
## place (`drop_colliders`): the yard's old paving gave way to the terrain's
## trodden earth. A piece the builder stood elsewhere takes its part of the
## old collider with it (`moved_colliders`): the signpost left the middle of
## the trail to the beach for the corner where that trail leaves the lane.
##
## The tavern is a Building: its part scenes, materials, colliders, the light
## of its rooms and what it gives the lamps registry are made as every
## building's are. The old map's colliders, the cuckoo clock, the doorway's
## stones, the worn floors and what E finds in the rooms are the tavern's own.
##
## Materials: one per table entry, found by the name the glTF surfaces carry:
## tavern_surface.gdshader for the building, tavern_glass.gdshader for the
## windows, tavern_foliage.gdshader for the ivy and the flowers,
## tavern_flame.gdshader for the fires. Everything the tavern draws is on
## LightLayers.ROOMS, the only layer its rooms' lamps reach, so no light
## inside shines through a wall onto the ground outside. The light of the
## rooms, the day through the openings and what the rooms see of the
## outdoors are its BuildingLight's (Building.add_light), from the tables'
## `rooms`, `openings` and `lights`; the hearths' flames are the tables' `fires`.
##
## The doorway: the porch ends above the vestibule's flags, and the stones
## that join the two are laid by tavern_threshold.gd; the ground under the
## stone floors is taken down by tavern_ground.gd as the terrain loads.
##
## What E finds in the rooms (the seats, the ladder to the attic, the beds)
## and the staff's grid of the hall are the tables' too, in the tavern's
## frame: furnish() hands the first to the player's E (TavernFurnishings),
## TavernNavigation reads the grid.

## Every tavern of the level is in this group (nearest).
const TAVERNS := &"tavern"

## The old map's colliders, the doorway's stones and the worn floors are the
## tavern's own; the dressing of the part scenes is Building's.
const TAVERN_COLLISION = preload("res://src/tavern/tavern_collision.gd")
const TAVERN_THRESHOLD = preload("res://src/tavern/tavern_threshold.gd")
const TAVERN_WEAR = preload("res://src/tavern/tavern_wear.gd")
## The floor of the tavern in the map (the builder's FLOOR), for the grime.
const GROUND := 6.6

var map: Node3D
## The tables of the exported parts (build.py GROUPS; RegionDef.tavern): the
## building's shell, then the interior. Set before the tavern enters the tree.
var parts: PackedStringArray = []
## For the daylight in the rooms: the ridges that take the sun (may be null).
var terrain: TerrainSystem
## The old map's meshes the tavern took away (TavernCollision.replace_old).
var replaced := 0
## The hall's cuckoo clock, which calls the game's hours; made in _ready.
var cuckoo: TavernCuckoo
## The tables' seats, in the tavern's frame.
var seats: Array[Dictionary] = []
## The boxes of the beds of the guest rooms, in the tavern's frame (TavernBeds).
var beds: Array[AABB] = []
## The ladder to the attic; null in a tavern without one.
var ladder: TavernLadder
## The table's grid of the hall for the staff (TavernNavigation); {} for none.
var hall_grid: Dictionary = {}
## What E finds in the rooms, once furnish() has handed it over; null before.
var furnishings: TavernFurnishings
## Whether the tavern has its interior part: the old walls give way to it.
var has_interior := false
## The boards the ground floor is walked on, once a table has told how the
## rooms have aged (its `indoor`); NAN until then.
var _walked_floor := NAN

func _ready() -> void:
	var start := Time.get_ticks_usec()
	add_to_group(TAVERNS)
	add_body()
	cuckoo = TavernCuckoo.new()
	cuckoo.name = "Cuckoo"
	cuckoo.tavern = self
	add_child(cuckoo)
	has_interior = parts.size() > 1 and FileAccess.file_exists(parts[1])
	var tables: Array[Dictionary] = []
	for path: String in parts:
		if FileAccess.file_exists(path):
			tables.append(Values.table(DataFile.read(path, BuildingSchemas.tavern_part())))
	for table: Dictionary in tables:
		if table.has("bounds"):
			var b: Array = table.bounds
			var low := Vector3(Values.real(b[0]), Values.real(b[1]), Values.real(b[2]))
			var high := Vector3(Values.real(b[3]), Values.real(b[4]), Values.real(b[5]))
			bounds = global_transform * AABB(low, high - low)
	add_light()
	light.terrain = terrain
	for table: Dictionary in tables:
		_load_table(table)
	TAVERN_THRESHOLD.build(self)
	_wear_floors()
	light.finish(leaves())
	var occlusion := preload("res://src/tavern/tavern_occlusion.gd").new()
	occlusion.name = "InteriorOcclusion"
	add_child(occlusion)
	print("TAVERN parts=%d meshes=%d replaced=%d materials=%d lights=%d bodies=%d load=%.2fs" % [tables.size(),
		mesh_count, replaced, materials.size(), light.lamps.flames.size() + light.lamps.lanterns.size(), bodies,
		(Time.get_ticks_usec() - start) / 1e6])

func _load_table(table: Dictionary) -> void:
	for seat: Dictionary in table.get("seats", []):
		seats.append(seat)
	beds.append_array(TavernBeds.from_table(Values.list(table.get("beds", []))))
	if table.has("ladder"):
		ladder = TavernLadder.from_table(Values.table(table.ladder))
	if table.has("hall"):
		hall_grid = Values.table(table.hall)
	TAVERN_MATERIALS.build(table, GROUND, materials)
	TAVERN_MATERIALS.age_indoors(table, materials, global_transform)
	if table.has("indoor"):
		_walked_floor = Values.real(Values.table(table.indoor).get("walked", GROUND))
	TAVERN_COLLISION.replace_old(self, Values.list(table.get("replaces", [])), Values.list(table.get("drop_colliders", [])),
		Values.list(table.get("moved_colliders", [])))
	for path: String in table.get("scenes", []):
		load_part(path, path.get_file().get_basename().to_pascal_case(), "interior" in path)
	light.add_table(table)
	for config: Dictionary in table.get("fires", []):
		var fire := HearthFire.from_table(config)
		add_child(fire)

## A piece of the cuckoo clock (`tav_cuckoo`) goes to the clock.
func _dress_piece(item: MeshInstance3D, room: bool) -> void:
	super(item, room)
	var extras: Dictionary = item.get_meta("extras", {})
	if extras.has("tav_cuckoo"):
		cuckoo.add(str(extras.tav_cuckoo), item, extras)

## The flames the model has stand for the pictures: the hearths draw their
## own. The interior's candles are the light's.
func _take_part(scene: Node3D, room: bool) -> void:
	TAVERN_DRESSING.remove_replaced_fire(scene)
	if room:
		light.lamps.find_candles(scene)

## Hands what E finds in the rooms to the player's E: the seats, the ladder
## and the beds (TavernFurnishings).
func furnish(interactions: TavernInteractions) -> void:
	furnishings = TavernFurnishings.new()
	furnishings.name = "Furnishings"
	furnishings.tavern = self
	furnishings.interactions = interactions
	add_child(furnishings)

## The tavern of the level nearest to `node`; null when the level has none.
static func nearest(node: Node3D) -> TavernSystem:
	var found: TavernSystem = null
	var best := INF
	for candidate: Node in node.get_tree().get_nodes_in_group(TAVERNS):
		var tavern := candidate as TavernSystem
		var away := tavern.bounds.get_center().distance_squared_to(node.global_position)
		if away < best:
			best = away
			found = tavern
	return found

## Hands the worn floors their map of where the ground floor is walked
## (tavern_wear.gd), once every part's colliders, doors and seats are in.
func _wear_floors() -> void:
	if is_nan(_walked_floor):
		return
	var at_doors := PackedVector3Array()
	for door: TavernDoor in doors:
		at_doors.append(door.global_position)
	var at_seats := PackedVector3Array()
	for seat: Dictionary in seats:
		var p: Array = seat.position
		at_seats.append(global_transform * Values.vec3(p))
	var map: Dictionary = TAVERN_WEAR.build(body, bounds,
		_walked_floor + global_position.y, at_doors, at_seats)
	for material: ShaderMaterial in materials.values():
		var worn: Variant = material.get_shader_parameter("wear")
		if material.shader == SURFACE and worn != null and Values.real(worn) > 0.0:
			material.set_shader_parameter("floor_wear", map.texture)
			material.set_shader_parameter("floor_wear_rect", map.rect)
