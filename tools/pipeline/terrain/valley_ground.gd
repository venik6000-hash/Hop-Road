extends RefCounted
## The ground recipe of the valley (ground_bake.gd, RECIPES): what is laid
## into the near heights of terrain.py and painted into its masks before the
## game reads them. Order matters: the cliff's seat first, the head stream's
## bed cut into it, the village, the tavern's floors and the buildings
## levelled, and the brook and the street's rill planned over that ground and
## cut last. The masks take the beds of the brook and of the head stream, the
## trodden earth round the houses, the tavern's and the buildings' worn yards
## and the patches round the village's yards, in that order.

const VillageLayout = preload("res://src/village/village_layout.gd")
const VillageBuildings = preload("res://src/village/village_buildings.gd")
const TavernGround = preload("res://src/tavern/tavern_ground.gd")
const GroundWear = preload("res://src/terrain/ground_wear.gd")

## The code that shapes the ground and paints it. Its data files are in inputs().
const CODE := [
	"res://tools/pipeline/terrain/valley_ground.gd",
	"res://src/rocks/rock_field.gd",
	"res://src/water/waterfall_system.gd",
	"res://src/village/village_layout.gd",
	"res://src/tavern/tavern_ground.gd",
	"res://src/village/village_buildings.gd",
	"res://src/village/village_brook.gd",
	"res://src/terrain/ground_wear.gd",
	"res://src/terrain/terrain_system.gd",
]

## Every file settle() and paint() read, code first. The heights and masks
## of terrain.py and its terrain.json are the bake's own inputs (ground_bake.gd).
static func inputs(region: RegionDef) -> PackedStringArray:
	var files := PackedStringArray(CODE)
	files.append(region.cliff)
	files.append(region.village_plan)
	files.append_array(region.buildings)
	files.append(region.worn_ground)
	files.append(region.map.resource_path)
	files.append(region.map.resource_path + ".import")
	files.append(region.terrain_dir.path_join("far_height.bin"))
	return files

## Lays everything into `image` (FORMAT_RF, row z, column x at origin +
## index * cell). Returns the water courses cut, by name, for the game.
static func settle(region: RegionDef, image: Image, origin: Vector2, cell: float, water_level: float) -> Dictionary:
	RockField.seat(image, origin, cell, region.cliff)
	WaterfallSystem.carve(image, origin, cell)
	VillageLayout.settle_ground(image, origin, cell, VillageLayout.read_plan(region.village_plan))
	TavernGround.settle(image, origin, cell)
	VillageBuildings.settle_ground(image, origin, cell, region)
	return VillageBrook.carve(image, origin, cell, water_level)

## Paints the masks of `settled` (ground_bake.gd settle(): the settled
## heights, the courses, the masks of terrain.py; texel (0, 0) of the masks at
## `origin`, `cell` metres apart). Returns the worn ground's fields
## (GroundWear.bake). The houses' aprons need the houses where the level
## stands them: on a map of the bake's own, over the settled heights.
static func paint(region: RegionDef, settled: Dictionary, origin: Vector2, cell: float) -> Dictionary:
	var control: Image = settled.control
	var extra: Image = settled.extra
	var courses: Dictionary = settled.courses
	var beds: Array[Array] = [courses[VillageBrook.BROOK], WaterfallSystem.head_rows()]
	VillageBrook.paint(control, extra, origin, cell, beds)
	var heights := ground(region, settled)
	var map := region.map.instantiate() as Node3D
	VillageLayout.paint_aprons(control, origin, cell, map, heights, VillageLayout.read_plan(region.village_plan))
	map.free()
	heights.free()
	return GroundWear.bake(region, control, origin, cell)

## A terrain outside the tree that answers height_at() as the level's does:
## the settled near heights and the far field of terrain.py.
static func ground(region: RegionDef, settled: Dictionary) -> TerrainSystem:
	var meta: Dictionary = settled.meta
	var terrain := TerrainSystem.new()
	terrain.region = region
	terrain.near_image = settled.image
	terrain.near_origin = Vector2(meta.near.origin[0], meta.near.origin[1])
	terrain.near_cell = meta.near.cell
	terrain.near_size = int(meta.near.size)
	var far_size := int(meta.far.size)
	var far := FileAccess.get_file_as_bytes(region.terrain_dir.path_join("far_height.bin"))
	terrain.far_image = Image.create_from_data(far_size, far_size, false, Image.FORMAT_RF, far)
	terrain.far_origin = Vector2(meta.far.origin[0], meta.far.origin[1])
	terrain.far_cell = meta.far.cell
	terrain.far_size = far_size
	return terrain
