class_name LevelParts
extends RefCounted
## The steps a level (src/alpine/level.gd) is built by, in order, and the
## parts of a region among them (docs/LEVEL.md, «Части уровня»). A step is
## either one of the core, built for every region, or a part
## (RegionDef.PARTS), built when the region names it (RegionDef.parts). Each
## step's builder is a small static function of level_nature.gd or
## level_village.gd; the level builds the steps that are about itself (its
## picture, its HUD, its keys, the player's spawn).

const NATURE = preload("res://src/alpine/level_nature.gd")
const VILLAGE = preload("res://src/alpine/level_village.gd")

## Steps that belong to a part without being it: built when the region has
## that part.
const PART_OF := {&"animals": &"village_pack"}
## The stages of the build in order: the words the loading screen shows
## (Level.loading_stage) and the steps of each.
const STAGES: Array[Dictionary] = [
	{"message": "Готовим небо и землю…", "steps": [&"sky", &"quality", &"terrain", &"lake", &"falls", &"brook"]},
	{"message": "Открываем таверну…", "steps": [&"tavern", &"eye", &"map", &"tracks"]},
	{"message": "Собираем деревню…", "steps": [&"cottages", &"buildings", &"village_pack"]},
	{"message": "Рассаживаем лес…", "steps": [&"rocks", &"vegetation", &"flora"]},
	{"message": "Готовим жителей и озеро…", "steps": [&"post", &"smoke", &"interface", &"people", &"interactions",
		&"camping", &"wildlife", &"animals", &"lamps", &"lakeside", &"panels", &"spawn", &"controls", &"placement",
		&"shelter"]},
]

## Whether the level of `region` builds the step `step`.
static func builds(region: RegionDef, step: StringName) -> bool:
	var part: StringName = PART_OF.get(step, step)
	return not part in RegionDef.PARTS or region.has_part(part)

## Builds the step `step` of the systems `s` (a step the level does not
## build itself).
static func build(step: StringName, s: LevelSystems) -> void:
	match step:
		&"sky": NATURE.sky(s)
		&"terrain": NATURE.terrain(s)
		&"lake": NATURE.lake(s)
		&"falls": NATURE.falls(s)
		&"brook": NATURE.brook(s)
		&"tavern": VILLAGE.tavern(s)
		&"eye": NATURE.eye(s)
		&"map": VILLAGE.map(s)
		&"tracks": VILLAGE.tracks(s)
		&"cottages": VILLAGE.cottages(s)
		&"buildings": VILLAGE.buildings(s)
		&"village_pack": await VILLAGE.village_pack(s)
		&"rocks": NATURE.rocks(s)
		&"vegetation": NATURE.vegetation(s)
		&"flora": VILLAGE.flora(s)
		&"post": NATURE.post(s)
		&"smoke": VILLAGE.smoke(s)
		&"people": VILLAGE.people(s)
		&"interactions": VILLAGE.interactions(s)
		&"camping": VILLAGE.camping(s)
		&"wildlife": NATURE.wildlife(s)
		&"animals": s.village_pack.add_animals()
		&"lamps": VILLAGE.lamps(s)
		&"lakeside": NATURE.lakeside(s)
		&"shelter": NATURE.shelter(s)
		_: push_error("LevelParts: no builder for the step %s" % step)
