class_name NpcCookJob
extends NpcJob
## A cook of the tavern's kitchen: the tool of the trade is in the hand while
## the body works with it (`held`), else it lies by the work (`rest`), or is
## put away where the work has no place for it. A raw catch may be brought to
## the cook. The scripts of the jobs say which tool and which prop the work
## has (jobs/chop.gd, jobs/stir.gd).

## The clips (NpcActing) in which the tool is in the hand.
var held: Array[String] = []
## Where the tool lies when the hand is busy with something else, from the
## villager's place of work.
var rest := Transform3D.IDENTITY

func _init() -> void:
	takes_catch = true

## The tool of the trade, made for the villager's hand.
func make_utensil() -> Node3D:
	return null

func setup(actor: VillageNPC) -> void:
	actor.utensil = make_utensil()
	if actor.utensil != null:
		actor.add_child(actor.utensil)

func frame(actor: VillageNPC, _delta: float) -> void:
	var utensil := actor.utensil
	if utensil == null or not actor.recorded:
		return
	if held.has(actor.activity):
		utensil.visible = true
		utensil.global_transform = Transform3D(actor.global_basis, actor.hand_position(actor.right_hand))
	elif actor.at_work():
		utensil.visible = true
		utensil.global_transform = Transform3D(Basis(Vector3.UP, actor.work_yaw), actor.work_point) * rest
	else:
		utensil.visible = false

## `prop` never moves: the lamps draw it into their shadow maps with the
## tavern's own pieces.
static func shade_with_tavern(prop: Node3D) -> void:
	for item: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		item.layers |= LightLayers.LAMP_CASTERS
