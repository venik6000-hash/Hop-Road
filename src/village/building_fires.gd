class_name BuildingFires
extends RefCounted
## The fires a building's table draws (`fires`, VillageBuilding): flames with
## hot air over them (HearthFire) and the lamps they light. A fire the
## bellows blow (`blown`, a group of BuildingMachinery) flares with their
## air; a fire a work tends (BrewHouse) is stoked or let die here.

## A fire under a full draught of the bellows: how much taller its flames
## stand, and how much brighter its lamps burn.
const FLARE := 0.45
const FLARE_LIGHT := 0.6

## The building's lamps, which a fire lights.
var lamps: InteriorLamps
## What moves in the building; null where nothing does.
var machinery: BuildingMachinery

## {name, fire: HearthFire, blown (the machinery's group whose air it takes),
## lamps (its lamps' names), draught}.
var _fires: Array[Dictionary] = []

func _init(building_lamps: InteriorLamps, building_machinery: BuildingMachinery) -> void:
	lamps = building_lamps
	machinery = building_machinery

## The fire of a row of the table's `fires`, along `along` at `at`, `width`
## across and `height` tall. The building stands it in the tree.
func add(config: Dictionary) -> HearthFire:
	var fire := HearthFire.from_table(config)
	_fires.append({"name": str(config.name), "fire": fire, "blown": str(config.get("blown", "")),
		"lamps": PackedStringArray(Values.list(config.get("lamps", []))), "draught": 0.0})
	return fire

## The bellows' air on each fire: taller flames, more hot air, brighter lamps.
func blow() -> void:
	for entry: Dictionary in _fires:
		_blow(entry)

func _blow(entry: Dictionary) -> void:
	if machinery == null or entry.blown == "":
		return
	var draught := machinery.draught(str(entry.blown))
	if draught == Values.real(entry.draught):
		return
	entry.draught = draught
	var fire: HearthFire = entry.fire
	fire.flare(1.0 + FLARE * draught)
	fire.haze_strength = 1.0 + draught
	for lamp: String in entry.lamps:
		lamps.set_strength(lamp, 1.0 + FLARE_LIGHT * draught)

## The fire named `fire_name`; null when the table has none.
func fire(fire_name: String) -> HearthFire:
	for entry: Dictionary in _fires:
		if entry.name == fire_name:
			var found: HearthFire = entry.fire
			return found
	return null

## The lamp of the table named `lamp` burns at `strength` of its light: a
## fire stoked or let die. At 0 it is out.
func stoke(lamp: String, strength: float) -> void:
	lamps.set_strength(lamp, strength)
	for flame: Dictionary in lamps.flames:
		var light: Light3D = flame.light
		if str(light.name) == lamp:
			light.visible = strength > 0.01
