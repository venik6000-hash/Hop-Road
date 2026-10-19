class_name WorldSchemas
extends RefCounted
## The schemas of the files a region names (RegionDef) and of the lists the
## layout scene writes (docs/LEVEL.md, «Данные содержимого»; docs/VILLAGE.md).

const D := preload("res://src/data/data_schema.gd")
## The models of the village pack (VillagePack.DIRECTORY).
const PACK_DIRECTORY := "res://assets/models/village_pack/"
## The kinds of a lake's shore (tools/pipeline/terrain/terrain_village.py).
const SHORE_KINDS: Array[String] = ["gravel", "marsh", "turf", "rock"]

## regions.json: the regions of the game (RegionDef.listed()) by the id
## each one's RegionDef has, the first one where a new game starts.
static func regions() -> Dictionary:
	return D.object({"regions": D.list(D.object({"id": D.id(&"region"), "region": D.file()}), 1)})

## zones.json: the named places of the valley (ValleyZones). A zone is a few
## shapes; the first zone of the list that holds a point names it.
static func zones() -> Dictionary:
	var shape := D.object({
		"box": D.optional(D.vector(4)),
		"circle": D.optional(D.vector(3)),
		"path": D.optional(D.list(D.vector(2), 2)),
		"reach": D.optional(D.number(0.0)),
		"polygon": D.optional(D.list(D.vector(2), 3)),
		"floor": D.optional(D.vector(2)),
	})
	return D.object({
		"zones": D.list(D.object({
			"id": D.id(&"zone"),
			"name": D.text(),
			"from": D.text(),
			"shapes": D.list(D.checked(shape, func(value: Variant) -> String:
				var outlines := 0
				for key: String in ["box", "circle", "path", "polygon"]:
					outlines += int(Values.table(value).has(key))
				return "" if outlines == 1 else "a shape has one of box, circle, path or polygon"), 1),
		}), 1),
	})

## village_plan.json: where the old map's houses and the cottages stand now,
## the paths of the village, its main road and its green. A cottage goes by
## the key of its entry in the region's cottages (BuildingSchemas.cottages).
## `main_road`: the centre line from north to south, a point (x, z, half
## width of the paving) every half metre, and `street`, the z from and to of
## its stretch through the village (VillageRoad). `green`: the green between
## the yards that the loose plants cover (x, z, width, depth; VillageFlora).
static func village_plan() -> Dictionary:
	var cottage := D.object({
		"source": D.vector(3),
		"position": D.vector(3),
		"yaw": D.number(),
		"built": D.optional(D.object({"position": D.vector(3), "yaw": D.number()})),
	})
	return D.object({
		"cottages": D.table(cottage, &"", &"cottage"),
		"houses": D.list(D.object({
			"id": D.whole(0),
			"source": D.vector(2),
			"ground": D.number(),
			"position": D.vector(2),
			"yaw": D.number(),
			"lift": D.optional(D.number()),
		}), 1),
		"paths": D.list(D.object({
			"name": D.text(),
			"points": D.list(D.vector(2), 2),
			"paved": D.optional(D.flag()),
		})),
		"main_road": D.object({"points": D.list(D.vector(3), 2), "street": D.vector(2)}),
		"green": D.vector(4),
		# Read by the layout scene and tools/pipeline/village_layout, not by the game.
		"part_moves": D.list(D.object({
			"house": D.text(),
			"prefixes": D.list(D.text(), 1),
			"near": D.vector(2),
			"radius": D.number(0.0),
			"delta": D.vector(3),
		})),
	})

## map_edits.json: the edits of the region's Blender map by the labels of its
## pieces (MapEdits). `drop`: pieces taken out with their colliders, by label
## or by the start of it. `raise`: pieces that rise with the ground under
## `base` (x, y, z: the height of the map there). `split`: one mesh moved in
## two parts, the part past `z` (south) by `south` and the rest by `north`;
## what of the south part lies under `foot` (y) goes `sink` m deeper.
## `lower`: pieces taken `by` m down. `walkways`: a body over the stones of
## the `deck` piece, `half_width` to either side of its middle, `depth` thick,
## its top `above` the highest stone of each row, and ramps `approach` m long
## down to the ground at both ends.
static func map_edits() -> Dictionary:
	return D.object({
		"drop": D.object({"labels": D.list(D.text()), "prefixes": D.list(D.text())}),
		"raise": D.list(D.object({"labels": D.list(D.text(), 1), "base": D.vector(3)})),
		"split": D.list(D.object({
			"label": D.text(),
			"z": D.number(),
			"south": D.vector(3),
			"north": D.vector(3),
			"foot": D.number(),
			"sink": D.number(0.0),
		})),
		"lower": D.list(D.object({"labels": D.list(D.text(), 1), "by": D.number()})),
		"walkways": D.list(D.object({
			"deck": D.text(),
			"name": D.text(),
			"half_width": D.number(0.01),
			"approach": D.number(0.0),
			"depth": D.number(0.01),
			"above": D.number(0.0),
		})),
	})

## village_pack/layout.json: the props of the yards, the pasture, the farm and
## the square. `asset` is a model of the pack; `zone` the group the layout
## scene lists it in.
static func props() -> Dictionary:
	return D.list(D.object({
		"name": D.text(),
		"asset": D.stem(PACK_DIRECTORY, ".glb"),
		"x": D.number(),
		"z": D.number(),
		"size": D.number(0.01),
		"yaw": D.number(),
		"lift": D.number(),
		"solid": D.flag(),
		"zone": D.text(),
		"tilt": D.optional(D.vector(2)),
	}))

## rocks.json: the scanned stones. `shape` is a rock of rock_shapes.glb.
static func rocks() -> Dictionary:
	return D.list(D.object({
		"shape": D.text(),
		"xform": D.vector(12),
		"moss": D.number(0.0, 1.0),
		"tone": D.number(0.0, 1.0),
	}))

## forest_wood.json: stumps, roots, logs and branches of the forest floor.
static func forest_wood() -> Dictionary:
	return D.list(D.object({
		"asset": D.stem(PACK_DIRECTORY, ".glb"),
		"xform": D.vector(12),
	}))

## forest_floor.json: where the ferns, clover and bracken of the forest floor
## are scattered (VillagePack): `count` tries in a disc of `radius` m round
## each of `places` (x, z), from `seed`.
static func forest_floor() -> Dictionary:
	return D.object({
		"seed": D.whole(0),
		"radius": D.number(0.0),
		"count": D.whole(0),
		"places": D.list(D.vector(2)),
	})

## map_context.json: the labels of the Blender map's pieces the layout scene
## shows for orientation.
static func map_context() -> Dictionary:
	return D.list(D.text())

## village_trees.json and woodland.json's `trees`: the trees the placer is
## given. `template` is a key of TreePlacer.COMPOSED for the woodland.
static func trees() -> Dictionary:
	return D.list(D.object({
		"kind": D.text(),
		"template": D.text(),
		"position": D.vector(3),
		"yaw": D.number(),
		"scale": D.number(0.01),
	}))

## woodland.json: the trees of the Blender composition. `kind` and `bushes`
## are written by tools/pipeline/alpine_scene/export_godot.py; the placer reads
## the template, the position, the yaw and the scale. `backdrop` (x, z,
## width, depth) is the rectangle the composition's backdrop forest was
## scattered in, which the placer's own forest fades into (TreePlacer); the
## export does not write it.
static func woodland() -> Dictionary:
	return D.object({
		"trees": trees(),
		"bushes": D.list(D.object({"min": D.vector(3), "max": D.vector(3)})),
		"backdrop": D.optional(D.vector(4)),
	})

## cliff_seat.json: the heights behind the scanned faces of the waterfall
## cliff (tools/pipeline/rocks/cliff_seat.py). A row is a list of numbers
## and nulls, one per cell.
static func cliff_seat() -> Dictionary:
	return D.object({
		"faces": D.list(D.object({
			"scan": D.text(),
			"at": D.vector(3),
			"yaw": D.number(),
			"scale": D.vector(3),
			"origin": D.vector(2),
			"cell": D.number(0.01),
			"size": D.vector(2),
			"heights": D.list(D.list(D.any()), 1),
		}), 1),
	})

## The scans of a region's cliff and where they stand (RegionDef.cliff_faces;
## tools/pipeline/rocks/cliff_seat.py seats them): `keep` is the stretch along
## a face whose ground stays, `floor` the lowest ground before its foot.
static func cliff_faces() -> Dictionary:
	return D.object({
		"faces": D.list(D.object({
			"note": D.optional(D.any_text()),
			"scan": D.text(),
			"at": D.vector(3),
			"yaw": D.number(),
			"scale": D.vector(3),
			"keep": D.optional(D.vector(2)),
			"floor": D.optional(D.number()),
		}), 1),
	})

## terrain.json: the grids of the terrain's fields (tools/pipeline/terrain/terrain.py).
static func terrain() -> Dictionary:
	var field := D.object({
		"size": D.whole(1),
		"cell": D.number(0.01),
		"origin": D.vector(2),
		"min": D.number(),
		"max": D.number(),
	})
	return D.object({
		"water_level": D.number(),
		"far": field,
		"near": field,
		"masks": D.object({"size": D.whole(1), "cell": D.number(0.01), "origin": D.vector(2)}),
		"minmax": D.object({"cell": D.number(0.01), "size": D.whole(1), "origin": D.vector(2), "layout": D.text()}),
		"convention": D.text(),
	})

## world.json: the grid of the world's terrain tiles, the mid field and the
## bounds (tools/pipeline/terrain/terrain_tiles.py; TerrainTiles).
static func world_tiles() -> Dictionary:
	var mask := D.object({"file": D.text(), "channels": D.list(D.text(), 4, 4)})
	return D.object({
		"format_version": D.whole(1),
		"origin": D.vector(2),
		"tile": D.number(1.0),
		"tiles": D.object({"first": D.whole(), "last": D.whole(), "folder": D.text()}),
		"land": D.vector(4),
		"water_level": D.number(),
		"height": D.object({"file": D.text(), "samples": D.whole(2), "cell": D.number(0.01), "format": D.text()}),
		"masks": D.object({"samples": D.whole(2), "cell": D.number(0.01), "format": D.text(), "control": mask, "extra": mask}),
		"mid": D.object({
			"file": D.text(),
			"samples": D.whole(2),
			"cell": D.number(0.01),
			"origin": D.vector(2),
			"format": D.text(),
			"min": D.number(),
			"max": D.number(),
		}),
		"minmax": D.object({"cell": D.number(0.01), "size": D.whole(1), "origin": D.vector(2), "layout": D.text(), "file": D.text()}),
		"region": D.text(),
		"sources": D.table(D.text()),
		"convention": D.text(),
	})

## settled_ground.json: the manifest of the ground bake (TerrainBake): the
## checksums of the heights and of the masks, the courses by name, and how
## the masks file is laid out.
static func settled_ground() -> Dictionary:
	return D.object({
		"format_version": D.whole(1),
		"key": D.text(),
		"heights_sha256": D.text(),
		"masks_sha256": D.text(),
		"courses": D.table(D.text()),
		"masks": D.object({
			"size": D.whole(1),
			"wear": D.object({"rect": D.vector(4), "size": D.vector(2, 0.0)}),
			"cinder": D.flag(),
		}),
	})

## placement-manifest.json: the manifest of the tree bake (VegetationCache).
static func placement_manifest() -> Dictionary:
	return D.object({
		"format_version": D.whole(1),
		"key": D.text(),
		"placement_sha256": D.text(),
		"static_digest": D.text(),
		"tree_placer_version": D.whole(0),
	})

## impostors.json: the sizes of the tree impostors (tools/pipeline/vegetation).
static func impostors() -> Dictionary:
	return D.object({
		"views": D.whole(1),
		"slice_size": D.vector(2),
		"species": D.list(D.object({
			"name": D.text(),
			"width_m": D.number(0.0),
			"height_m": D.number(0.0),
			"bottom_m": D.number(),
			"tree_height_m": D.number(0.0),
			"crown_radius_m": D.number(0.0),
		}), 1),
	})

## grass_cards.json: the cards of the grass atlas.
static func grass_cards() -> Dictionary:
	return D.object({
		"atlas_size": D.vector(2),
		"px_per_m": D.number(1.0),
		"rect_convention": D.text(),
		"hull_convention": D.text(),
		"cards": D.list(D.object({
			"species": D.text(),
			"variant": D.whole(0),
			"rect": D.vector(4),
			"size": D.vector(2),
			"hull": D.vector(2),
			"coverage": D.number(0.0, 1.0),
			"mean": D.vector(3),
		}), 1),
	})

## texture_quality manifest: the compressed copies of the textures per tier.
static func texture_quality() -> Dictionary:
	var tier := D.object({"bytes": D.whole(0), "format": D.whole(0), "path": D.text(), "size": D.vector(2)})
	return D.object({
		"compression": D.text(),
		"textures": D.list(D.object({
			"low": tier,
			"medium": tier,
			"original_rgba_mip_bytes": D.whole(0),
			"sha256": D.text(),
			"size": D.vector(2),
			"source": D.text(),
		}), 1),
		"tiers": D.object({"low": D.whole(1), "medium": D.whole(1)}),
		"totals": D.object({"low": D.whole(0), "medium": D.whole(0), "original_rgba_mip_bytes": D.whole(0)}),
		"version": D.whole(1),
	})

## The Blender map's manifest (tools/pipeline/alpine_scene/export_godot.py):
## the materials by label, the cameras, the lights, the sun and the smoke.
static func map_manifest() -> Dictionary:
	return D.object({
		"source": D.text(),
		"coordinate_conversion": D.text(),
		"materials": D.table(D.object({
			"color": D.vector(4),
			"roughness": D.number(0.0, 1.0),
			"metallic": D.number(0.0, 1.0),
			"emission": D.number(0.0),
			"noise": D.number(0.0),
			"stretch": D.vector(3),
		})),
		# A map without cameras gives the overview a view of the spawn (Level._place_spawn).
		"cameras": D.optional(D.list(D.object({"name": D.text(), "position": D.vector(3), "forward": D.vector(3),
			"fov": D.number(1.0, 179.0)}))),
		"lights": D.list(D.object({"position": D.vector(3), "color": D.vector(3)})),
		"sun_forward": D.vector(3),
		"smoke": D.list(D.vector(3)),
		"collections": D.table(D.whole(0)),
	})

## weathers.json: each kind of weather (WeatherTable.KINDS) with its name,
## its state, the wind sea of the lake and where it may go by itself.
static func weathers() -> Dictionary:
	var state := {}
	for field: String in WeatherTable.FIELDS:
		state[field] = D.number()
	var kind := D.object({
		"name": D.text(),
		"lake": D.choice(OceanFFT.PRESETS.keys()),
		"heading": D.vector(2, -360.0, 360.0),
		"state": D.object(state),
		"next": D.table(D.whole(1), &"", &"weather"),
	})
	return D.checked(D.table(kind, &"weather"), func(value: Variant) -> String:
		for id: String in Values.table(value):
			var row: Variant = Values.table(value)[id]
			if row is Dictionary and Values.table(Values.table(row).get("next", {})).has(id):
				return "the weather '%s' goes to itself" % id
			var heading: Variant = Values.table(row).get("heading", [])
			if heading is Array and Values.list(heading).size() == 2 and Values.real(heading[0]) > Values.real(heading[1]):
				return "the weather '%s' turns the wind from a heading past its last" % id
		return "")

## fish.json: the fish of the lake (FishingState).
static func fish() -> Dictionary:
	return D.table(D.object({
		"title": D.text(),
		"length": D.vector(2, 1.0),
		"mass": D.number(0.0),
		"habitat": D.choice(FishingState.HABITATS),
		"time": D.choice(FishingState.TIMES),
	}), &"fish")

## flora.json: the village's ground plants and what grows where (FloraTable).
static func flora() -> Dictionary:
	var model := D.checked(D.text(), func(value: Variant) -> String:
		var path := FloraTable.model_path(str(value))
		return "" if DataCheck.file_there(path) else "the file %s does not exist" % path)
	return D.object({
		"plants": D.table(D.object({
			"model": model,
			"tris": D.whole(1),
			"least": D.optional(D.whole(0)),
			"scale": D.vector(2, 0.0),
			"sway": D.number(0.0),
			"shadow": D.optional(D.flag()),
			"view": D.optional(D.number(0.0)),
		}), &"plant"),
		"mixes": D.table(D.table(D.number(0.0), &"", &"plant")),
	})

## The region's brook (RegionDef.brook; VillageBrook): the centre line of the
## brook and of the street's rill downstream, each point x, z and the half
## width of the water there.
static func brook() -> Dictionary:
	return D.object({"brook": D.list(D.vector(3), 2), "rill": D.list(D.vector(3), 2)})

## The region's lake (RegionDef.lake; LakePlan, tools/lib/lake_plan.py). Rects are
## x, z, width, depth. `search`: where the bed is searched; `shore_field`:
## the square of the shore's waves (x, z, side); `beach`: its `rect` keeps
## the reeds off, its `x` and `z` are the ramps of the beach the terrain
## shapes (rising from the first to the second, falling from the third to
## the fourth); `cove` and `reedless` (x, z, radius): more shores without
## reeds; `shore`: the village's waterline from south to north (x, z, the
## kind that holds to the next point); `marsh_stands`: reed beds (x, z,
## radius); `mooring`: where the boat's mooring is searched, the point it
## moors nearest to, the mooring when none is found.
static func lake() -> Dictionary:
	var waterline := D.checked(D.list(D.any(), 3, 3), func(value: Variant) -> String:
		var point := Values.list(value)
		if not (point[0] is float and point[1] is float):
			return "a point of the shore starts with x and z"
		return "" if str(point[2]) in SHORE_KINDS else "the kind of the shore is one of %s" % [SHORE_KINDS])
	return D.object({
		"search": D.vector(4),
		"shore_field": D.vector(3),
		"beach": D.object({"rect": D.vector(4), "x": D.vector(4), "z": D.vector(4)}),
		"cove": D.vector(4),
		"reedless": D.list(D.vector(3)),
		"shore": D.list(waterline),
		"marsh_stands": D.list(D.vector(3)),
		"mooring": D.object({"search": D.vector(4), "near": D.vector(2), "fallback": D.vector(2)}),
	})

## The region's dragon (RegionDef.dragon; LakeDragon): the middle of its
## circuit, the circuit's half axes along x and z (m) and how much the circuit
## rises along z per metre along x.
static func dragon() -> Dictionary:
	return D.object({"centre": D.vector(3), "radii": D.vector(2), "slope": D.number()})

## The region's falls (RegionDef.falls; WaterfallSystem): the stream above
## the upper fall (its surface on the centre line, half its width, the speed
## of the flow, the depth of the bed cut for it), the upper fall, the stream
## on the shelf below it and the lower fall. A fall leaves where its stream
## ends; `floor` is the surface it falls into.
static func falls() -> Dictionary:
	var fall := D.object({
		"speed": D.number(0.0),
		"width": D.number(0.0),
		"spread": D.number(0.0),
		"depth": D.number(0.0),
		"approach": D.number(0.0),
		"floor": D.number(),
		"mist": D.number(0.0),
	})
	return D.object({
		"head": D.list(D.object({"at": D.vector(3), "half": D.number(0.0), "speed": D.number(0.0), "depth": D.number(0.0)}), 2),
		"upper": fall,
		"stream": D.list(D.object({"at": D.vector(3), "half": D.number(0.0), "speed": D.number(0.0)}), 2),
		"lower": fall,
	})

## The region's village animals (RegionDef.animals; VillagePack): the kind
## (a model of the village pack), the middle of the yard (x, z), the height
## (m), the clip and the radius of the circle it walks (m; 0: it stands).
static func animals() -> Dictionary:
	return D.object({"animals": D.list(D.object({
		"kind": D.stem(PACK_DIRECTORY, "/scene.gltf"),
		"at": D.vector(2),
		"height": D.number(0.0),
		"clip": D.text(),
		"radius": D.number(0.0),
	}))})

## The region's wild animals (RegionDef.wildlife; WildlifeSystem): herds on
## the ground round a middle (x, z), flocks of birds and butterflies over one,
## the box of open water the fish schools keep to (x0, z0, x1, z1) and where
## the birdsong sounds (x, z). A region without the box or the birdsong has
## neither. `seed` draws every place and turn, the same on each load.
static func wildlife() -> Dictionary:
	return D.object({
		"seed": D.whole(0),
		"herds": D.list(D.object({
			"kind": D.choice(["deer", "fox", "chicken"]),
			"at": D.vector(2),
			"radius": D.number(0.0),
			"count": D.whole(1),
		})),
		"flocks": D.list(D.object({
			"kind": D.choice(["bird", "butterfly"]),
			"species": D.optional(D.choice(["bird", "raven", "seagull"])),
			"at": D.vector(2),
			"count": D.whole(1),
		})),
		"fish_water": D.optional(D.vector(4)),
		"birdsong": D.optional(D.vector(2)),
	})
