class_name RagdollBudget
extends RefCounted
## How many active ragdolls the game runs at once and how far from the player
## (docs/LIFE.md, «Толчок»): a ragdoll costs physics in every tick it lives.
## The level's villagers share one (NpcPopulation.ragdolls).

## Ragdolls at once at most.
const MOST := 2
## A body farther from the player than this, metres, does not go limp.
const REACH := 15.0

## The owners of the ragdolls that run now. Untyped: an owner may be freed.
var _owners: Array = []

## Gives `owner` a ragdoll when one is free and it stands `distance` metres
## from the player; an owner that has one keeps it.
func take(owner: Object, distance: float) -> bool:
	_forget_freed()
	if _owners.has(owner):
		return true
	if distance > REACH or _owners.size() >= MOST:
		return false
	_owners.append(owner)
	return true

## The ragdoll of `owner` is gone.
func give_back(owner: Object) -> void:
	_owners.erase(owner)

## The ragdolls that run now.
func count() -> int:
	_forget_freed()
	return _owners.size()

func _forget_freed() -> void:
	for index in range(_owners.size() - 1, -1, -1):
		if not is_instance_valid(_owners[index]):
			_owners.remove_at(index)
