class_name PhysicsLayers
extends RefCounted
## The physics layers of the game, what each layer's bodies must collide
## with, and the few bodies allowed to differ (docs/LEVEL.md, «Слои
## столкновений»). Every collision_layer, collision_mask and query mask in the
## code names these constants; tools/pipeline/physics/check_layer_literals.py
## refuses a number there. PhysicsAudit holds the bodies of the running game
## to MASKS and EXCEPTIONS.

## Terrain, buildings, props fixed in place, the tavern door, the rowboat.
const WORLD := 1
const PLAYER := 2
const VILLAGERS := 4
const ANIMALS := 8
## The boulders and the drowned wood of the lake bed.
const BOULDERS := 16
## Things a hand can carry or a push can move.
const PROPS := 32
## The physical bones of an active ragdoll.
const RAGDOLL := 64
## Area3D volumes that only detect.
const ZONES := 128

## A query mask: what stands under feet and what a line of sight stops at.
const GROUND := WORLD | BOULDERS
## A query mask that meets every layer.
const ALL := 0xFFFFFFFF
## A body on no layer: nothing meets it.
const NONE := 0

## The layer names of project.godot (layer_names/3d_physics/layer_N), by bit.
const NAMES := {
	WORLD: "мир",
	PLAYER: "игрок",
	VILLAGERS: "жители",
	ANIMALS: "звери",
	BOULDERS: "валуны",
	PROPS: "переносимые предметы",
	RAGDOLL: "кости рэгдолла",
	ZONES: "зоны",
}

## The mask every body of a layer carries. A static body searches no contacts,
## so WORLD and BOULDERS keep Godot's default mask. The ragdoll's bones meet
## the world and the props, not the player, the villagers or each other.
const MASKS := {
	WORLD: WORLD,
	BOULDERS: WORLD,
	PLAYER: GROUND | VILLAGERS | ANIMALS | PROPS,
	VILLAGERS: GROUND | PLAYER | VILLAGERS | ANIMALS | PROPS,
	ANIMALS: GROUND | PLAYER | VILLAGERS | ANIMALS | PROPS,
	PROPS: GROUND | PLAYER | VILLAGERS | ANIMALS | PROPS | RAGDOLL,
	RAGDOLL: GROUND | PROPS,
	ZONES: PLAYER | VILLAGERS | ANIMALS,
}

## Bodies that may break one rule of PhysicsAudit. A row names the body's
## script, the rule ("mask" or "shape"), for "mask" the mask it carries
## instead, for "shape" the property values under which it has no live shape,
## and the reason.
const EXCEPTIONS: Array[Dictionary] = [
	{"script": "res://src/lakeside/lake_boat.gd", "rule": "mask", "mask": GROUND | PLAYER | VILLAGERS | ANIMALS,
		"reason": "The boat lies on WORLD so that feet and ground rays find it, but it moves: it meets the bed, the shore, the people and the animals."},
	{"script": "res://src/npc/village_npc.gd", "rule": "shape", "when": {"seated": true},
		"reason": "A seated villager has the collision off (VillagerPresence): the seat holds the body."},
	{"script": "res://src/wildlife/pack_animal.gd", "rule": "shape", "when": {"kind": "goose"},
		"reason": "The geese fly in circles high over the village and meet nothing."},
]

## The mask a body on `layer` must carry, or -1 for a value that is not one
## layer of MASKS.
static func mask_of(layer: int) -> int:
	return Values.whole(MASKS.get(layer, -1))

## Whether the ray hit `hit` (intersect_ray) met the terrain's body
## (TerrainCollision). A trunk collider of a tree has no node (TreeColliders):
## its hit holds a null collider.
static func hit_terrain(hit: Dictionary) -> bool:
	if not hit.get("collider") is Node:
		return false
	var body: Node = hit.collider
	return body.name == &"TerrainBody"

## The 1-based layer number of a bit, as project.godot and the editor count.
static func number_of(bit: int) -> int:
	return int(log(float(bit)) / log(2.0) + 0.5) + 1

## The row of EXCEPTIONS that lets `body` break `rule`, or {}.
static func exception_for(body: Object, rule: String) -> Dictionary:
	var script: Script = body.get_script()
	if script == null:
		return {}
	for row: Dictionary in EXCEPTIONS:
		if row["script"] != script.resource_path or row["rule"] != rule:
			continue
		var holds := true
		var when: Dictionary = row.get("when", {})
		for property: String in when:
			if body.get(property) != when[property]:
				holds = false
		if holds:
			return row
	return {}
