class_name BuildingSchemas
extends RefCounted
## The schemas of the tables that stand the buildings: the village's twelve
## (assets/models/<name>/<name>.json, written by tools/pipeline/buildings/kit.py),
## the two cottages, the tavern's two, and the stalls' (assets/models/trade/trade.json).
## docs/VILLAGE.md, «Таблица», tells what each section does.
##
## The fields marked "build" are written by the Blender build and read by
## tools/verify; the game ignores them.

const D := preload("res://src/data/data_schema.gd")
const TAVERN_MATERIALS := preload("res://src/tavern/tavern_materials.gd")

## The shaders a material may name; none names `surface`.
const SHADERS: Array[String] = ["surface", "flame", "foliage", "fur", "cloth", "glass"]

static func vec3() -> Dictionary:
	return D.vector(3)

## One material of a table (TavernMaterials.build). Which fields count
## depends on `shader`: a surface takes the textures and the grime, a flame
## its colour and energy, glass its pane.
static func material() -> Dictionary:
	return D.object({
		"shader": D.choice(SHADERS),
		"tint": D.vector(3),
		"albedo": D.optional(D.file()),
		"normal": D.optional(D.file()),
		"orm": D.optional(D.file()),
		"mask": D.optional(D.file()),
		"emblem": D.optional(D.file()),
		"desaturate": D.optional(D.number(0.0, 1.0)),
		"albedo_gain": D.optional(D.number(0.0)),
		"uv_scale": D.optional(D.number(0.001)),
		"normal_strength": D.optional(D.number(0.0)),
		"roughness": D.optional(D.number(0.0)),
		"metallic": D.optional(D.number(0.0, 1.0)),
		"grime": D.optional(D.number(0.0, 1.0)),
		"moss": D.optional(D.number(0.0, 1.0)),
		"lichen": D.optional(D.number(0.0, 1.0)),
		"detail": D.optional(D.choice(TAVERN_MATERIALS.DETAIL_MAPS.keys())),
		"detail_scale": D.optional(D.number(0.001)),
		"detail_strength": D.optional(D.number(0.0)),
		"detail_turn": D.optional(D.whole(0, 1)),
		# flame
		"color": D.optional(D.vector(3)),
		"energy": D.optional(D.number(0.0)),
		"wildness": D.optional(D.number(0.0)),
		"dusk_only": D.optional(D.flag()),
		"core": D.optional(D.vector(3)),
		"emission": D.optional(D.number(0.0)),
		"emission_color": D.optional(D.vector(3)),
		# foliage
		"wrap": D.optional(D.number(0.0)),
		"transmission": D.optional(D.number(0.0)),
		"flutter": D.optional(D.number(0.0)),
		# glass
		"alpha": D.optional(D.number(0.0, 1.0)),
		"wave": D.optional(D.number(0.0)),
		"quarry": D.optional(D.number(0.0)),
		"pane": D.optional(D.number(0.0)),
		# cloth
		"cloth_wrap": D.optional(D.number(0.0)),
		"cloth_through": D.optional(D.number(0.0)),
		"cloth_sheen": D.optional(D.number(0.0)),
		"stain": D.optional(D.number(0.0)),
		"threads": D.optional(D.number(0.0)),
		"emblem_color": D.optional(D.vector(3)),
		"emblem_size": D.optional(D.vector(2)),
		# fur
		"tip": D.optional(D.vector(3)),
		"tip_inside": D.optional(D.number(0.0)),
		"tip_edge": D.optional(D.number(0.0)),
		"fur_length": D.optional(D.number(0.0)),
		"fur_lean": D.optional(D.number(0.0)),
		"fur_droop": D.optional(D.number(0.0)),
		"strand_cell": D.optional(D.number(0.0)),
		"tuft_cell": D.optional(D.number(0.0)),
		"tuft_pull": D.optional(D.number(0.0)),
	})

static func materials() -> Dictionary:
	return D.table(material())

## A light (TavernLights.make_light): `layer` says where it shines, `night`
## whether it is a lantern lit at dusk.
static func light() -> Dictionary:
	return D.object({
		"name": D.text(),
		"position": D.vector(3),
		"type": D.choice(["point", "spot"]),
		"color": D.vector(3),
		"energy": D.number(0.0),
		"range": D.number(0.1),
		"shadow": D.flag(),
		"flicker": D.number(0.0),
		"night": D.number(0.0, 1.0),
		"layer": D.choice(["exterior", "interior"]),
		"size": D.number(0.0),
		"speed": D.number(0.0),
		"sway": D.number(0.0),
		"direction": D.optional(D.vector(3)),
		"angle": D.optional(D.number(1.0, 179.0)),
	})

## A reflection probe over a room.
static func probe() -> Dictionary:
	return D.object({
		"name": D.text(),
		"position": D.vector(3),
		"extents": D.vector(3),
		"ambient": D.vector(3),
		"room": D.text(),
	})

static func window() -> Dictionary:
	return D.object({"at": D.vector(3), "out": D.vector(3), "size": D.vector(2)})

## A place to stand and look (BrewHouse, BuildingMachinery). `kind` makes
## the ids of one building a kind that other files point at (the guide's
## marks); "" leaves them the building's own.
static func station(kind := &"") -> Dictionary:
	return D.object({"id": D.id(kind) if kind != &"" else D.text(), "title": D.text(), "stand": D.vector(3), "look": D.vector(3)})

static func vent() -> Dictionary:
	return D.object({"id": D.text(), "kind": D.choice(["smoke", "steam"]), "at": D.vector(3), "fire": D.optional(D.text())})

static func fire() -> Dictionary:
	return D.object({
		"name": D.text(),
		"at": D.vector(3),
		"along": D.vector(3),
		"width": D.number(0.0),
		"height": D.number(0.0),
		"lamps": D.list(D.text()),
		"blown": D.optional(D.text()),
		"far": D.object({"radius": D.number(0.0), "out": D.vector(3)}),
	})

## What a table asks of the ground (VillageBuildings.shape_ground), and the
## points that record what the model stands on.
static func terrain() -> Dictionary:
	var corners := D.list(D.vector(2), 2, 2)
	var points := D.optional(D.list(D.vector(3)))
	return D.object({
		"lower": D.optional(D.list(D.object({"rect": corners, "to": D.number()}))),
		"seat": D.optional(D.list(D.object({"at": D.vector(2), "radius": D.number(0.0), "skirt": D.number(0.0), "to": D.number()}))),
		"ramp": D.optional(D.list(D.object({
			"from": D.vector(2), "to": D.vector(2), "height": D.number(), "half": D.number(0.0), "shoulder": D.number(0.0)}))),
		"level": D.optional(D.list(D.object({"rect": corners, "to": D.number(), "skirt": D.number(0.0)}))),
		"spring": D.optional(D.vector(3)),
		# build: what the model stands on.
		"walls_reach": D.optional(D.number()),
		"terrace": points,
		"road_end": points,
		"yard": points,
		"wheel_pit": points,
		"north_alley": points,
		"feet": D.optional(D.list(D.object({"what": D.text(), "at": D.vector(3)}))),
	})

## Trodden ground round the building (GroundWear).
static func worn() -> Dictionary:
	return D.object(_worn_fields())

## The region's worn ground (RegionDef.worn_ground): what worn() holds, in
## the map's frame, and the patches of softly worn earth round the village's
## yards (GroundWear.paint_patches): a middle (x, z) and the half sizes.
static func worn_ground() -> Dictionary:
	var fields := _worn_fields()
	fields["patches"] = D.optional(D.list(D.object({"at": D.vector(2), "reach": D.vector(2, 0.0)})))
	return D.object(fields)

static func _worn_fields() -> Dictionary:
	return {
		"yards": D.optional(D.list(D.object({"name": D.text(), "outline": D.list(D.vector(2), 3)}))),
		"routes": D.list(D.object({"name": D.text(), "kind": D.choice(["cart", "foot"]), "points": D.list(D.vector(2), 2)})),
		"stands": D.optional(D.list(D.object({"name": D.text(), "radius": D.number(0.0), "at": D.list(D.vector(2), 1)}))),
		"cinder": D.optional(D.list(D.object({"name": D.text(), "fade": D.number(0.0), "outline": D.list(D.vector(2), 3)}))),
	}

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

## A thing the hands take (BrewStation).
static func utensil() -> Dictionary:
	return D.object({
		"id": D.text(),
		"title": D.text(),
		"kind": D.choice(["sack", "vessel", "tool", "raw", "log", "instrument"]),
		"nodes": D.list(D.text(), 1),
		"at": D.vector(3),
		"grip": D.vector(3),
	})

## The tables of a region's buildings (RegionDef.buildings). Every one has the common
## sections; the rest are what the building has.
static func building(station_kind := &"") -> Dictionary:
	return D.object({
		"title": D.text(),
		"description": D.text(),
		"scenes": D.object({"shell": D.file(), "interior": D.optional(D.file())}),
		"origin": D.vector(3),
		"yaw": D.number(),
		"materials": materials(),
		"color_range": D.number(0.0),
		"lights": D.list(light()),
		"probes": D.list(probe()),
		# build: the size of the model.
		"stats": D.object({
			"shell": D.object({"meshes": D.whole(0), "vertices": D.whole(0), "triangles": D.whole(0)}),
			"interior": D.optional(D.object({"meshes": D.whole(0), "vertices": D.whole(0), "triangles": D.whole(0)})),
		}),
		"windows": D.optional(D.list(window())),
		"stations": D.optional(D.list(station(station_kind))),
		"vents": D.optional(D.list(vent())),
		"fires": D.optional(D.list(fire())),
		"hours": D.optional(D.table(D.vector(2))),
		"glows": D.optional(D.list(D.object({"parts": D.list(D.text(), 1), "hours": D.vector(2)}))),
		"terrain": D.optional(terrain()),
		"worn": D.optional(worn()),
		"replaces": D.optional(D.list(D.text(), 1)),
		"outdoors": D.optional(D.list(D.text(), 1)),
		"moving": D.optional(D.list(moving())),
		"turning": D.optional(D.list(turning())),
		"vanes": D.optional(D.list(D.object({"id": D.text(), "pivot": D.vector(3), "lee": D.vector(3)}))),
		"optic": D.optional(optic()),
		"water": D.optional(water()),
		# build: outlines and ground measures for tools/verify.
		"footprint": D.optional(D.list(D.vector(3), 3)),
		"roofs": D.optional(D.list(D.list(D.vector(3), 2))),
		"heights": D.optional(D.table(D.number())),
		"doors": D.optional(D.table(D.object({"clear": D.vector(2), "swing": D.number()}))),
		"trail": D.optional(D.text()),
		"wet": D.optional(D.number()),
		"lake": D.optional(D.number()),
		"runs": D.optional(D.list(D.object({
			"id": D.text(), "title": D.text(), "trail": D.vector(2), "length": D.number(0.0), "width": D.number(0.0),
			"ends": D.list(D.vector(2), 2), "map": D.list(D.vector(2), 2)}))),
		"deck": D.optional(D.object({
			"top": D.number(), "kneeling": D.number(), "land_end": D.vector(2), "far_end": D.vector(2), "width": D.number(0.0)})),
		"moorings": D.optional(D.list(D.object({"kind": D.text(), "at": D.vector(3)}))),
		"stair": D.optional(D.object({
			"head": D.vector(3), "foot": D.vector(3), "riser": D.number(0.0), "going": D.number(0.0), "steps": D.whole(1),
			"width": D.number(0.0)})),
		"lanterns": D.optional(D.list(D.object({
			"lamp": D.text(), "title": D.text(), "kind": D.text(), "at": D.vector(3), "proposed": D.vector(2),
			"note": D.any_text()}))),
		"hills": D.optional(D.list(D.object({"at": D.vector(2), "tread": D.whole(0), "row": D.whole(0), "picked": D.flag()}))),
		"anchors": D.optional(D.list(anchor())),
		"surfaces": D.optional(D.list(surface())),
		"utensils": D.optional(D.list(utensil())),
	})

## The region's cottages (RegionDef.cottages, VillageCottage). `key` is the
## cottage's entry in the village plan, `node` the name of its node under the
## map, `table` its table (cottage()), `scene` the placed model of
## tools/pipeline/village_layout/build.py. Meshes whose extras carry the
## flag `solid` get a collider. A porch lantern of `range` and `energy`; a
## `ramp` lays a walking surface (convex points, cottage frame, at the
## table's origin) over the porch's stair. `smoke` hides the map's chimney
## smoke within that many metres of the table's origin: the old house's.
static func cottages() -> Dictionary:
	return D.object({
		"cottages": D.list(D.object({
			"key": D.id(&"cottage"),
			"node": D.text(),
			"table": D.file(),
			"scene": D.file(),
			"solid": D.text(),
			"lantern": D.object({"name": D.text(), "range": D.number(0.0), "energy": D.number(0.0)}),
			"ramp": D.optional(D.object({"name": D.text(), "points": D.list(D.vector(3), 4)})),
			"smoke": D.optional(D.number(0.0)),
		})),
	})

## A cottage's table (herbalist.json, potter.json; tools/pipeline/cottage, potter).
static func cottage() -> Dictionary:
	return D.object({
		"scene": D.file(),
		"origin": D.vector(3),
		"replaces_prefix": D.text(),
		"materials": materials(),
		"color_range": D.number(0.0),
		"lantern": D.vector(3),
		"description": D.text(),
		"meshes": D.optional(D.whole(0)),
		"vertices": D.optional(D.whole(0)),
	})

## tavern.json and tavern_interior.json: the parts of the tavern (RegionDef.tavern).
static func tavern_part() -> Dictionary:
	var fields: Dictionary = {
		"scenes": D.list(D.file(), 2, 2),
		"replaces": D.list(D.text(), 1),
		"drop_colliders": D.list(D.text()),
		"moved_colliders": D.list(D.object({"box": D.vector(6), "by": D.vector(3), "of": D.text()})),
		"materials": materials(),
		"color_range": D.number(0.0),
		"lights": D.list(light()),
		"probes": D.list(probe()),
		"seats": D.list(D.object({
			"name": D.id(&"seat"),
			"position": D.vector(3),
			"facing": D.vector(3),
			"height": D.number(0.0),
			"exits": D.list(D.vector(3), 1),
		})),
		"indoor": D.optional(D.object({
			"materials": D.table(D.object({
				"indoor_tint": D.optional(D.vector(3)),
				"soot": D.optional(D.number(0.0)),
				"indoor_grime": D.optional(D.number(0.0)),
				"wear": D.optional(D.number(0.0)),
				"handled": D.optional(D.number(0.0)),
				"crevice": D.optional(D.number(0.0)),
			})),
			"storeys": D.vector(4),
			"walked": D.number(),
		})),
		"portal_floors": D.optional(D.list(D.object({"height": D.number(), "holes": D.list(D.vector(4))}))),
		"portals": D.optional(D.list(D.object({
			"name": D.text(), "position": D.vector(3), "inward": D.vector(3), "sill": D.number(), "top": D.number(),
			"width": D.number(0.0)}))),
		"windows": D.optional(D.list(D.object({
			"name": D.text(), "position": D.vector(3), "inward": D.vector(3), "floor": D.number(), "reveal": D.number(),
			"room": D.text(), "sill": D.number(), "spring": D.number(), "top": D.number(), "width": D.number(0.0)}))),
	}
	return D.object(fields)

## assets/models/trade/trade.json: the points and boxes of the stall, the
## order board and the cart, and their materials.
static func trade_models() -> Dictionary:
	var boxes := D.list(D.object({"center": D.vector(3), "size": D.vector(3)}), 1)
	return D.object({
		"stall": D.object({
			"price_board": D.vector(3), "coin_slot": D.vector(3), "chest_lid": D.vector(3), "colliders": boxes}),
		"order_board": D.object({"board": D.vector(3), "colliders": boxes}),
		"cart": D.object({"bed": D.vector(3), "colliders": boxes}),
		"materials": materials(),
		"color_range": D.number(0.0),
	})
