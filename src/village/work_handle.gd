class_name WorkHandle
extends Node3D
## A thing of a village building a hand works: the pull of the smithy's
## bellows, the crank of its grindstone. It stands where the hand takes hold;
## the player's E works it (TavernInteractions), as it opens a door.

const GROUP := &"work_handle"

## What it is, and what the hand does to it, for the prompt.
var title := ""
var verb := ""
var machinery: BuildingMachinery
## The machinery's group of pieces it works.
var group := ""

func _init() -> void:
	add_to_group(GROUP)

func interact() -> void:
	machinery.work(group)
