class_name WorldSchemas
extends RefCounted
## The schemas of the files a region names (RegionDef) and of the lists the
## layout scene writes (docs/LEVEL.md, «Данные содержимого»; docs/VILLAGE.md).

const D := preload("res://src/data/data_schema.gd")
## The models of the village pack (VillagePack.DIRECTORY).
const PACK_DIRECTORY := "res://assets/models/village_pack/"

## regions.json: the regions of the game (RegionDef.listed()), the first
## one where a new game starts.
static func regions() -> Dictionary:
	return D.object({"regions": D.list(D.file(), 1)})

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
					outlines += int((value as Dictionary).has(key))
				return "" if outlines == 1 else "a shape has one of box, circle, path or polygon"), 1),
		}), 1),
	})

## village_plan.json: where the old map's houses and the cottages stand now,
## and the paths of the village. A cottage goes by the key of its entry in
## the region's cottages (BuildingSchemas.cottages).
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
		"main_road": D.list(D.vector(2), 2),
		# Read by the layout scene and tools/pipeline/village_layout, not by the game.
		"part_moves": D.list(D.object({
			"house": D.text(),
			"prefixes": D.list(D.text(), 1),
			"near": D.vector(2),
			"radius": D.number(0.0),
			"delta": D.vector(3),
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
## the template, the position, the yaw and the scale.
static func woodland() -> Dictionary:
	return D.object({
		"trees": trees(),
		"bushes": D.list(D.object({"min": D.vector(3), "max": D.vector(3)})),
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
		"cameras": D.list(D.object({"name": D.text(), "position": D.vector(3), "forward": D.vector(3), "fov": D.number(1.0, 179.0)})),
		"lights": D.list(D.object({"position": D.vector(3), "color": D.vector(3)})),
		"sun_forward": D.vector(3),
		"smoke": D.list(D.vector(3)),
		"collections": D.table(D.whole(0)),
	})
