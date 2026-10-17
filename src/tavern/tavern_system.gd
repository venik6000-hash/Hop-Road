class_name TavernSystem
extends Node3D
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
## Materials: one per table entry, found by the name the glTF surfaces carry:
## tavern_surface.gdshader for the building, tavern_glass.gdshader for the
## windows, tavern_foliage.gdshader for the ivy and the flowers,
## tavern_flame.gdshader for the fires. Everything the tavern draws is on
## LightLayers.ROOMS, the only layer its rooms' lamps reach, so no light
## inside shines through a wall onto the ground outside. The light of the
## rooms, the day through the openings and what the rooms see of the
## outdoors are its BuildingLight's, from the tables' `rooms`, `openings`
## and `lights`; the hearths' flames are the tables' `fires`.
##
## The doorway: the porch ends above the vestibule's flags, and the stones
## that join the two are laid by tavern_threshold.gd; the ground under the
## stone floors is taken down by tavern_ground.gd as the terrain loads.

## The materials, the colliders and the dressing of the part scenes live in
## these helpers.
const TAVERN_MATERIALS = preload("res://src/tavern/tavern_materials.gd")
const TAVERN_COLLISION = preload("res://src/tavern/tavern_collision.gd")
const TAVERN_DRESSING = preload("res://src/tavern/tavern_dressing.gd")
const TAVERN_THRESHOLD = preload("res://src/tavern/tavern_threshold.gd")
const TAVERN_WEAR = preload("res://src/tavern/tavern_wear.gd")
const SURFACE := TAVERN_MATERIALS.SURFACE
const GLASS := TAVERN_MATERIALS.GLASS
const FLAME := TAVERN_MATERIALS.FLAME
const FOLIAGE := TAVERN_MATERIALS.FOLIAGE
const FUR := TAVERN_MATERIALS.FUR
## The floor of the tavern in the map (the builder's FLOOR), for the grime.
const GROUND := 6.6

var map: Node3D
## The tables of the exported parts (build.py GROUPS; RegionDef.tavern): the
## building's shell, then the interior. Set before the tavern enters the tree.
var parts: PackedStringArray = []
var sky_system: SkySystem
## For the daylight in the rooms: the ridges that take the sun (may be null).
var terrain: TerrainSystem
## The level's context, which the rooms join; null in a tool that builds
## the tavern alone.
var world: WorldContext
## What the building takes up, in world space (a table's `bounds`).
var bounds := AABB()
## The light of the rooms; made in _ready.
var light: BuildingLight
var mesh_count := 0
var replaced := 0
var bodies := 0
var doors: Array[TavernDoor] = []
## The hall's cuckoo clock, which calls the game's hours. Made in _ready: a
## VillageBuilding has its own _ready and no clock.
var cuckoo: TavernCuckoo
var seats: Array[Dictionary] = []

var materials := {}
var body: StaticBody3D
var has_interior := false
## The boards the ground floor is walked on, once a table has told how the
## rooms have aged (its `indoor`); NAN until then.
var _walked_floor := NAN
var shape_cache := {}

func _ready() -> void:
	var start := Time.get_ticks_usec()
	body = StaticBody3D.new()
	body.name = "Solid"
	add_child(body)
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
	light = BuildingLight.new(str(name), global_transform, bounds)
	light.sky = sky_system
	light.terrain = terrain
	light.world = world
	add_child(light)
	for table: Dictionary in tables:
		_load_part(table)
	TAVERN_THRESHOLD.build(self)
	_wear_floors()
	light.finish(doors)
	var occlusion := preload("res://src/tavern/tavern_occlusion.gd").new()
	occlusion.name = "InteriorOcclusion"
	add_child(occlusion)
	print("TAVERN parts=%d meshes=%d replaced=%d materials=%d lights=%d bodies=%d load=%.2fs" % [tables.size(),
		mesh_count, replaced, materials.size(), light.lamps.flames.size() + light.lamps.lanterns.size(), bodies,
		(Time.get_ticks_usec() - start) / 1e6])

func _load_part(table: Dictionary) -> void:
	for seat: Dictionary in table.get("seats", []):
		seats.append(seat)
	TAVERN_MATERIALS.build(table, GROUND, materials)
	TAVERN_MATERIALS.age_indoors(table, materials, global_transform)
	if table.has("indoor"):
		_walked_floor = Values.real(Values.table(table.indoor).get("walked", GROUND))
	TAVERN_COLLISION.replace_old(self, Values.list(table.get("replaces", [])), Values.list(table.get("drop_colliders", [])),
		Values.list(table.get("moved_colliders", [])))
	for path: String in table.get("scenes", []):
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		scene.name = path.get_file().get_basename().to_pascal_case()
		add_child(scene)
		for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			TAVERN_DRESSING.dress(self, item, "interior" in path)
		TAVERN_DRESSING.remove_replaced_fire(scene)
		if "interior" in path:
			light.lamps.find_candles(scene)
		_batch(scene, "interior" in path)
	light.add_table(table)
	for config: Dictionary in table.get("fires", []):
		var fire := HearthFire.from_table(config)
		add_child(fire)

## The material of table entry `name` (TavernMaterials), null when the table has none.
func material(name: String) -> Material:
	var found: Variant = materials.get(name)
	return found if found is Material else null

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

## Spatial batches retain local culling and the dressed surface materials.
func _batch(root: Node3D, interior := false) -> void:
	preload("res://src/tavern/tavern_batching.gd").apply(root, self, SURFACE, interior)
