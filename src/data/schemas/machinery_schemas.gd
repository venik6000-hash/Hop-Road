class_name MachinerySchemas
extends RefCounted
## The schemas of the working parts of a building's table
## (BuildingSchemas.building): what moves and turns (BuildingMachinery), the
## lighthouse's optic, the mill's water (MillWater), and the brewery's points,
## vessels and utensils (BrewHouse, BrewStation).

const D := preload("res://src/data/data_schema.gd")

## A part that moves by hand or on its own (BuildingMachinery).
static func moving() -> Dictionary:
	return D.object({
		"id": D.text(),
		"title": D.text(),
		"group": D.text(),
		"kind": D.choice(["swing", "slide", "spin"]),
		"nodes": D.list(D.text(), 1),
		"pivot": D.vector(3),
		"axis": D.vector(3),
		"travel": D.number(),
		"grip": D.optional(D.vector(3)),
		"hand": D.optional(D.vector(3)),
	})

## A wheel or shaft that turns with others (BuildingMachinery).
static func turning() -> Dictionary:
	return D.object({
		"id": D.text(),
		"title": D.text(),
		"centre": D.vector(3),
		"axis": D.vector(3),
		"radius": D.number(0.0),
		"ratio": D.number(),
		"rpm": D.number(),
		"drives": D.list(D.text()),
		"clutch": D.flag(),
	})

static func optic() -> Dictionary:
	return D.object({
		"pivot": D.vector(3),
		"axis": D.vector(3),
		"period": D.number(0.1),
		"prefix": D.text(),
		"beams": D.list(D.object({
			"direction": D.vector(3), "spread": D.number(0.0), "range": D.number(0.0), "color": D.vector(3)}), 1),
		"lamp": D.vector(3),
	})

## The mill's water: the intake, the ribbons of the race, the falls (MillWater).
static func water() -> Dictionary:
	return D.object({
		"intake": D.object({"at": D.vector(3), "stream_level": D.number()}),
		"depth": D.number(0.0),
		"ribbons": D.list(D.object({
			"name": D.text(), "half": D.number(0.0), "speed": D.number(), "boarded": D.flag(), "points": D.list(D.vector(3), 2)})),
		"falls": D.list(D.object({
			"name": D.text(), "lip": D.vector(3), "heading": D.number(), "speed": D.number(), "dip": D.number(),
			"width": D.number(0.0), "spread": D.number(0.0), "depth": D.number(0.0), "approach": D.number(),
			"floor": D.number(), "sink": D.number(), "behind": D.number()})),
		"spill": D.object({"from": D.vector(3), "to": D.vector(3)}),
	})

## A point of the brewery's hands and pipes (BrewHouse): where liquid is
## poured, a vessel's brim and bottom, a grip.
static func anchor() -> Dictionary:
	return D.object({
		"id": D.text(),
		"kind": D.choice(["nozzle", "pour", "brim", "bottom", "bucket", "grip", "hook"]),
		"at": D.vector(3),
		"radius": D.optional(D.number(0.0)),
		"into": D.optional(D.text()),
		"rect": D.optional(D.list(D.vector(2), 2, 2)),
		"turn": D.optional(D.number()),
	})

## What a vessel holds and how far (BrewDay.COPPER and the other ids).
static func surface() -> Dictionary:
	return D.object({
		"id": D.text(),
		"vessel": D.text(),
		"kind": D.choice(["wort", "grain", "water", "foam", "mash"]),
		"node": D.text(),
		"at": D.vector(3),
		"bottom": D.optional(D.number()),
		"brim": D.optional(D.number()),
		"level": D.optional(D.number()),
		"radius": D.optional(D.number(0.0)),
		"rect": D.optional(D.list(D.vector(2), 2, 2)),
		"heap": D.optional(D.vector(3)),
	})

## A thing the hands take (BrewStation): the works of works.json point at it.
static func utensil() -> Dictionary:
	return D.object({
		"id": D.id(&"utensil"),
		"title": D.text(),
		"kind": D.choice(["sack", "vessel", "tool", "raw", "log", "instrument"]),
		"nodes": D.list(D.text(), 1),
		"at": D.vector(3),
		"grip": D.vector(3),
	})
