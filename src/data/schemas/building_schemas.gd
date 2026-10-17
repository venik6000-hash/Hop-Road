class_name BuildingSchemas
extends RefCounted
## The schemas of the tables that stand the buildings: the village's twelve
## (assets/models/<name>/<name>.json, written by tools/pipeline/buildings/kit.py),
## the two cottages, the tavern's two, and the stalls' (assets/models/trade/trade.json).
## docs/VILLAGE.md, «Таблица», tells what each section does. The materials
## are MaterialSchemas', the working parts MachinerySchemas'.
##
## The fields marked "build" are written by the Blender build and read by
## tools/verify; the game ignores them.

const D := preload("res://src/data/data_schema.gd")

## The kinds of a room's lamp (assets/light/profiles.json, `lamps`).
const LAMP_KINDS: Array[String] = ["candle", "lantern", "chandelier", "stove", "hearth"]

## A light (InteriorLamps.add_light). A lamp of a room names the `room` and
## its `kind`, which gives its shadow and its size; any other light says
## where it shines (`layer`), whether it is a lantern lit at dusk (`night`),
## its shadow and its size.
static func light() -> Dictionary:
	var row := D.object({
		"name": D.text(),
		"position": D.vector(3),
		"type": D.choice(["point", "spot"]),
		"color": D.vector(3),
		"energy": D.number(0.0),
		"range": D.number(0.1),
		"room": D.optional(D.text()),
		"kind": D.optional(D.choice(LAMP_KINDS)),
		"shadow": D.optional(D.flag()),
		"flicker": D.number(0.0),
		"night": D.optional(D.number(0.0, 1.0)),
		"layer": D.optional(D.choice(["exterior", "interior"])),
		"size": D.optional(D.number(0.0)),
		"speed": D.number(0.0),
		"sway": D.number(0.0),
		"direction": D.optional(D.vector(3)),
		"angle": D.optional(D.number(1.0, 179.0)),
	})
	var of_room: Array[String] = ["kind"]
	var of_other: Array[String] = ["shadow", "night", "layer", "size"]
	return D.checked(row, func(value: Variant) -> String:
		var lamp := Values.table(value)
		var what := "lamp of a room" if lamp.has("room") else "light"
		for field: String in of_room + of_other:
			var needed := of_room.has(field) == lamp.has("room")
			if needed and not lamp.has(field):
				return "a %s needs `%s`" % [what, field]
			if not needed and lamp.has(field):
				return "a %s has no `%s`" % [what, field]
		return "")

## A room of an interior (Interior.Room): its air as boxes (middle and half
## size, in the building's frame), how far it reaches through its walls, the
## height of its floor, its profile and its probe's ambient light.
static func room() -> Dictionary:
	return D.object({
		"name": D.text(),
		"boxes": D.list(D.vector(6), 1),
		"wall": D.vector(3, 0.0),
		"floor": D.number(),
		"profile": D.ref(&"light_profile"),
		"ambient": D.vector(3, 0.0),
	})

## An opening between two rooms or a room and the outdoors (Interior.Opening).
## A window or a door is a rectangle on the line of its wall: the middle of
## its sill, the way into its first room, its width, the heights of its sill,
## of its springing and of its top over the sill's middle, the depth of its
## reveal, and whether the day comes in through it. The stairs and a hatch
## are a hole in a floor: its height and its corners (x0, z0, x1, z1).
static func opening() -> Dictionary:
	var row := D.object({
		"name": D.text(),
		"kind": D.choice(Interior.WALL_KINDS + Interior.FLOOR_KINDS),
		"rooms": D.list(D.text(), 2, 2),
		"position": D.optional(D.vector(3)),
		"inward": D.optional(D.vector(3)),
		"width": D.optional(D.number(0.0)),
		"sill": D.optional(D.number()),
		"spring": D.optional(D.number()),
		"top": D.optional(D.number()),
		"reveal": D.optional(D.number(0.0)),
		"floor": D.optional(D.number()),
		"daylight": D.optional(D.flag()),
		"height": D.optional(D.number()),
		"hole": D.optional(D.vector(4)),
	})
	var in_floors: Array[String] = ["height", "hole"]
	var in_walls: Array[String] = ["position", "inward", "width", "sill", "top"]
	return D.checked(row, func(value: Variant) -> String:
		var opening_row := Values.table(value)
		for field: String in in_floors if Interior.FLOOR_KINDS.has(str(opening_row.kind)) else in_walls:
			if not opening_row.has(field):
				return "a %s needs `%s`" % [opening_row.kind, field]
		return "")

## assets/light/profiles.json (LightProfile): how each kind of room takes the
## light, and the defaults of each kind of lamp.
static func light_profiles() -> Dictionary:
	var day_night := D.object({"day": D.number(0.0), "night": D.number(0.0)})
	var lamps := {}
	for kind: String in LAMP_KINDS:
		lamps[kind] = D.object({"shadow": D.flag(), "size": D.number(0.0)})
	var daylight := {}
	for field: String in ["sky", "sky_area", "overcast", "moonlit", "beam", "moon_air", "bounce", "moon_patch", "moon_bounce"]:
		daylight[field] = D.number(0.0)
	return D.object({
		"profiles": D.table(D.object({
			"exposure": D.object({
				"day": D.number(0.0), "night": D.number(0.0), "over_day": D.number(0.0), "over_night": D.number(0.0)}),
			"ambient": day_night,
			"haze": D.number(0.0, 1.0),
			"daylight": D.optional(D.object(daylight)),
		}), &"light_profile"),
		"lamps": D.object(lamps),
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

## Flames with hot air over them (HearthFire.from_table): the middle of
## their base, the way along the grate, its width and the flames' height.
static func hearth() -> Dictionary:
	return D.object(_hearth_fields())

## A fire of a village building: a hearth with the lamps that flicker with it,
## the machinery's group whose draught blows it up, and its glow from afar.
static func fire() -> Dictionary:
	var fields := _hearth_fields()
	fields["lamps"] = D.list(D.text())
	fields["blown"] = D.optional(D.text())
	fields["far"] = D.object({"radius": D.number(0.0), "out": D.vector(3)})
	return D.object(fields)

static func _hearth_fields() -> Dictionary:
	return {
		"name": D.text(),
		"at": D.vector(3),
		"along": D.vector(3),
		"width": D.number(0.0),
		"height": D.number(0.0),
	}

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

## The floors of the region's tavern the ground is taken down under
## (RegionDef.tavern_ground; TavernGround): each floor's corner and size (x,
## z), and how far the ground goes down (m).
static func tavern_ground() -> Dictionary:
	return D.object({
		"floors": D.list(D.object({"at": D.vector(2), "size": D.vector(2, 0.0)}), 1),
		"drop": D.number(0.0),
	})

## Where the staff of the region's tavern work (RegionDef.tavern_work;
## NpcPopulation): the cook's board and the stew's pot, the maid's round after
## her place at the counter, and the stops of the round where she wipes a top
## (`stop`: 0 is her place, 1 the first point of `round`; the strip and the
## stance as NpcWipe.set_strip reads them, `yaw` the way she faces).
static func tavern_work() -> Dictionary:
	return D.object({
		"board": D.vector(3),
		"pot": D.vector(3),
		"round": D.list(D.vector(3), 1),
		"wipes": D.list(D.object({
			"stop": D.whole(0),
			"yaw": D.number(-TAU, TAU),
			"middle": D.number(),
			"across": D.number(0.0),
			"near": D.number(0.0),
			"far": D.number(0.0),
			"drop": D.optional(D.number(0.0)),
			"rest": D.vector(3),
		})),
	})

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

## The tables of a region's buildings (RegionDef.buildings). Every one has the common
## sections; the rest are what the building has.
static func building(station_kind := &"") -> Dictionary:
	return D.object({
		"title": D.text(),
		"description": D.text(),
		"scenes": D.object({"shell": D.file(), "interior": D.optional(D.file())}),
		"origin": D.vector(3),
		"yaw": D.number(),
		"materials": MaterialSchemas.materials(),
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
		"moving": D.optional(D.list(MachinerySchemas.moving())),
		"turning": D.optional(D.list(MachinerySchemas.turning())),
		"vanes": D.optional(D.list(D.object({"id": D.text(), "pivot": D.vector(3), "lee": D.vector(3)}))),
		"optic": D.optional(MachinerySchemas.optic()),
		"water": D.optional(MachinerySchemas.water()),
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
		"anchors": D.optional(D.list(MachinerySchemas.anchor())),
		"surfaces": D.optional(D.list(MachinerySchemas.surface())),
		"utensils": D.optional(D.list(MachinerySchemas.utensil())),
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
		"materials": MaterialSchemas.materials(),
		"color_range": D.number(0.0),
		"lantern": D.vector(3),
		"description": D.text(),
		"meshes": D.optional(D.whole(0)),
		"vertices": D.optional(D.whole(0)),
	})

## tavern.json and tavern_interior.json: the parts of the tavern (RegionDef.tavern).
## The interior's part holds the building's light (BuildingLight): what the
## building takes up (`bounds`: x0, y0, z0, x1, y1, z1 in its frame), its
## rooms, their openings and the lamps that name them.
static func tavern_part() -> Dictionary:
	var fields: Dictionary = {
		"scenes": D.list(D.file(), 2, 2),
		"replaces": D.list(D.text(), 1),
		"drop_colliders": D.list(D.text()),
		"moved_colliders": D.list(D.object({"box": D.vector(6), "by": D.vector(3), "of": D.text()})),
		"materials": MaterialSchemas.materials(),
		"color_range": D.number(0.0),
		"lights": D.list(light()),
		"bounds": D.optional(D.vector(6)),
		"rooms": D.optional(D.list(room(), 1)),
		"openings": D.optional(D.list(opening())),
		"fires": D.optional(D.list(hearth())),
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
	}
	return D.checked(D.object(fields), func(value: Variant) -> String:
		var part := Values.table(value)
		var rooms: Array[String] = [Interior.OUT]
		for row: Dictionary in part.get("rooms", []):
			rooms.append(str(row.name))
		for lamp: Dictionary in part.lights:
			if lamp.has("room") and not rooms.has(str(lamp.room)):
				return "lamp %s: no room %s" % [lamp.name, lamp.room]
		for row: Dictionary in part.get("openings", []):
			for side: Variant in row.rooms:
				if not rooms.has(str(side)):
					return "opening %s: no room %s" % [row.name, side]
		if part.has("rooms") and not part.has("bounds"):
			return "a part with rooms needs `bounds`"
		return "")

## assets/models/trade/trade.json: the points and boxes of the stall, the
## order board and the cart, and their materials.
static func trade_models() -> Dictionary:
	var boxes := D.list(D.object({"center": D.vector(3), "size": D.vector(3)}), 1)
	return D.object({
		"stall": D.object({
			"price_board": D.vector(3), "coin_slot": D.vector(3), "chest_lid": D.vector(3), "colliders": boxes}),
		"order_board": D.object({"board": D.vector(3), "colliders": boxes}),
		"cart": D.object({"bed": D.vector(3), "colliders": boxes}),
		"materials": MaterialSchemas.materials(),
		"color_range": D.number(0.0),
	})
