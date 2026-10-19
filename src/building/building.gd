@abstract
class_name Building
extends Node3D
## A building of the level stood from its tables: the tavern (TavernSystem)
## and the buildings of the village (VillageBuilding). Both are made the same
## way, and that way is here:
##
## - the part scenes, each dressed piece by piece (load_part, TavernDressing):
##   materials by the names the glTF surfaces carry, layers, shadows, doors
##   on their hinges, colliders by the `tav_*` properties;
## - the materials of the tables, one per entry (TavernMaterials);
## - the one solid body ("Solid") that the pieces' colliders go on;
## - the light of its rooms (BuildingLight, add_light): the lamps and the
##   probes of the tables, the day and the sight through the openings, in
##   which the doors' leaves stand (leaves);
## - what the building gives the lamps registry (lamps_for): its lanterns
##   outdoors that cast shadows, and its glows from far away.
##
## What one kind of building has and the other has not is its own: the
## tavern's cuckoo clock, threshold, seats and beds; a village building's
## lamps by the hours, fires, machinery and brewing.

const TAVERN_MATERIALS = preload("res://src/tavern/tavern_materials.gd")
const TAVERN_DRESSING = preload("res://src/tavern/tavern_dressing.gd")
const TAVERN_BATCHING = preload("res://src/tavern/tavern_batching.gd")
const SURFACE := TAVERN_MATERIALS.SURFACE
const FLAME := TAVERN_MATERIALS.FLAME
const FOLIAGE := TAVERN_MATERIALS.FOLIAGE
const FUR := TAVERN_MATERIALS.FUR

var sky_system: SkySystem
## The level's context, which the rooms join; null in a tool that builds
## the building alone.
var world: WorldContext
## What the building takes up, in world space.
var bounds := AABB()
## The pieces dressed, the colliders on the body and the doors on their
## hinges, as TavernDressing and TavernCollision count them.
var mesh_count := 0
var bodies := 0
var doors: Array[TavernDoor] = []
## The light of the rooms (add_light); null before.
var light: BuildingLight
## The materials of the tables, by entry name (TavernMaterials.build).
var materials := {}
var body: StaticBody3D
## The colliders made once per mesh (TavernCollision.cached_shape).
var shape_cache := {}
## What the building gives the lamps registry (lamps_for); null before.
var lamp_set: LampSet

## Makes the light of the rooms, over `bounds` as they are now. `contact`:
## the rooms' contact shadows are drawn. The tables go to it by
## BuildingLight.add_table, and BuildingLight.finish(leaves()) ends it.
func add_light(contact := true) -> BuildingLight:
	light = BuildingLight.new(str(name), global_transform, bounds, contact)
	light.sky = sky_system
	light.world = world
	add_child(light)
	return light

## The lamps of the building's rooms (InteriorLamps).
func interior_lamps() -> InteriorLamps:
	return light.lamps

## What the light of the rooms knows of the doors: their leaves.
func leaves() -> Array[OpeningLeaf]:
	var found: Array[OpeningLeaf] = []
	for door: TavernDoor in doors:
		found.append(door.leaf)
	return found

## Makes the solid body. `top_level`: each shape stands where its piece
## stands in the world (TavernCollision), not in the building's frame.
func add_body(top_level := false) -> void:
	body = StaticBody3D.new()
	body.name = "Solid"
	body.top_level = top_level
	add_child(body)

## Stands the part scene at `path` as the child `node_name` and dresses each
## of its pieces (`room`: the pieces are indoors). Then the building takes
## from the scene what is its own (_take_part), and batches what is left.
func load_part(path: String, node_name: String, room: bool) -> Node3D:
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	scene.name = node_name
	add_child(scene)
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		_dress_piece(item, room)
	_take_part(scene, room)
	TAVERN_BATCHING.apply(scene, self, SURFACE, room)
	return scene

## Dresses one piece of a part scene (TavernDressing.dress).
func _dress_piece(item: MeshInstance3D, room: bool) -> void:
	TAVERN_DRESSING.dress(self, item, room)

## Takes what is the building's own out of a dressed part scene, before the
## batches.
@abstract func _take_part(scene: Node3D, room: bool) -> void

## The material of table entry `name` (TavernMaterials), null when the tables have none.
func material(name: String) -> Material:
	var found: Variant = materials.get(name)
	return found if found is Material else null

## What the building is from far away at night, in world space: its lamps'
## far glows ({at, color, radius, facing}, see LampSet.add_glow).
func glows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for glow: Dictionary in interior_lamps().far_glows:
		var facing: Vector3 = glow.facing
		var at: Vector3 = glow.at
		result.append({"at": to_global(at), "color": glow.color, "radius": glow.radius,
			"facing": global_basis * facing})
	return result

## What the building gives the lamps registry (WorldContext.lamps): its
## lanterns outdoors that cast shadows, and its glows(). Made at the first call.
func lamps_for() -> LampSet:
	if lamp_set != null:
		return lamp_set
	lamp_set = LampSet.new()
	lamp_set.lanterns = interior_lamps().shadowed_lanterns()
	for glow: Dictionary in glows():
		var at: Vector3 = glow.at
		var color: Color = glow.color
		var facing: Vector3 = glow.facing
		_glow_added(glow, lamp_set.add_glow(at, color, Values.real(glow.radius), facing))
	return lamp_set

## Told that `glow` of glows() is the glow `index` of lamp_set.
func _glow_added(_glow: Dictionary, _index: int) -> void:
	pass
