class_name LevelParts
extends RefCounted
## The steps a level (src/alpine/level.gd) is built by, in order, and the
## parts of a region among them (docs/LEVEL.md, «Части уровня»). A step is
## either one of the core, built for every region, or a part
## (RegionDef.PARTS), built when the region names it (RegionDef.parts). Each
## step's builder is a small static function of level_nature.gd or
## level_village.gd; the level builds the steps that are about itself (its
## picture, its HUD, its keys, the player's spawn).
##
## A step builds either shared systems (SHARED: SharedSystems, once, with the
## level) or content (CellContent: every time the content is built). The
## content gives the shared systems what they need through the registries of
## WorldContext (docs/LEVEL.md, «Реестры»). The few shared steps that still
## take the content by hand (LINKS) take it again when the content is built
## again (rebuild).

const NATURE = preload("res://src/alpine/level_nature.gd")
const VILLAGE = preload("res://src/alpine/level_village.gd")

## Steps that belong to a part without being it: built when the region has
## that part.
const PART_OF := {&"animals": &"village_pack", &"refraction": &"lakeside"}
## The stages of the build in order: the words the loading screen shows
## (Level.loading_stage) and the steps of each.
const STAGES: Array[Dictionary] = [
	{"message": "Готовим небо и землю…", "steps": [&"sky", &"quality", &"terrain", &"lake", &"falls", &"brook"]},
	{"message": "Открываем таверну…", "steps": [&"tavern", &"eye", &"map", &"tracks"]},
	{"message": "Собираем деревню…", "steps": [&"cottages", &"buildings", &"village_pack"]},
	{"message": "Рассаживаем лес…", "steps": [&"rocks", &"vegetation", &"flora"]},
	{"message": "Готовим жителей и озеро…", "steps": [&"post", &"smoke", &"interface", &"people", &"interactions",
		&"camping", &"wildlife", &"animals", &"dragon", &"lamps", &"lakeside", &"refraction", &"panels", &"spawn", &"controls",
		&"placement", &"shelter"]},
]
## The steps of the shared systems. Every other step builds content.
const SHARED: Array[StringName] = [&"sky", &"quality", &"terrain", &"lake", &"eye", &"tracks", &"post", &"interface",
	&"people", &"interactions", &"camping", &"lamps", &"refraction", &"panels", &"spawn", &"controls", &"shelter"]
## The shared steps that take the content by hand: the villagers move again,
## the lake's refraction looks at the new geometry, the keys take the new
## lakeside, and the level's step "placement" places the content's forest,
## plants and animals.
const LINKS: Array[StringName] = [&"people", &"refraction", &"controls", &"placement"]

## Whether the level of `region` builds the step `step`.
static func builds(region: RegionDef, step: StringName) -> bool:
	var part: StringName = PART_OF.get(step, step)
	return not part in RegionDef.PARTS or region.has_part(part)

## Whether building the content again runs the step `step`: a content step,
## or a shared step that takes the content (LINKS).
static func rebuilds(step: StringName) -> bool:
	return not step in SHARED or step in LINKS

## Builds the step `step` (a step the level does not build itself): a shared
## system into `s`, or a part of the content `c`.
static func build(step: StringName, s: SharedSystems, c: CellContent) -> void:
	match step:
		&"sky": NATURE.sky(s)
		&"terrain": NATURE.terrain(s)
		&"lake": NATURE.lake(s)
		&"falls": NATURE.falls(s, c)
		&"brook": NATURE.brook(s, c)
		&"tavern": VILLAGE.tavern(s, c)
		&"eye": NATURE.eye(s)
		&"map": VILLAGE.map(s, c)
		&"tracks": VILLAGE.tracks(s)
		&"cottages": VILLAGE.cottages(s, c)
		&"buildings": VILLAGE.buildings(s, c)
		&"village_pack": await VILLAGE.village_pack(s, c)
		&"rocks": NATURE.rocks(s, c)
		&"vegetation": NATURE.vegetation(s, c)
		&"flora": VILLAGE.flora(s, c)
		&"post": NATURE.post(s)
		&"smoke": VILLAGE.smoke(s, c)
		&"people": VILLAGE.people(s)
		&"interactions": VILLAGE.interactions(s)
		&"camping": VILLAGE.camping(s)
		&"wildlife": NATURE.wildlife(s, c)
		&"dragon": NATURE.dragon(s, c)
		&"animals": c.village_pack.add_animals()
		&"lamps": VILLAGE.lamps(s)
		&"lakeside": NATURE.lakeside(s, c)
		&"refraction": NATURE.refraction(s)
		&"shelter": NATURE.shelter(s)
		_: push_error("LevelParts: no builder for the step %s" % step)

## Builds the content `c` of the step `step` again under the shared systems
## `s` that stand (rebuilds): a content step as build() does, a shared step's
## link to the content.
static func rebuild(step: StringName, s: SharedSystems, c: CellContent) -> void:
	if not step in SHARED:
		await build(step, s, c)
		return
	match step:
		&"people": s.people.process_mode = Node.PROCESS_MODE_INHERIT
		&"refraction": s.refraction.register_geometry.call_deferred()
		_: push_error("LevelParts: no link for the step %s" % step)
