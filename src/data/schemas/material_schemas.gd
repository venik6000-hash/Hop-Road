class_name MaterialSchemas
extends RefCounted
## The schema of a table's `materials` (TavernMaterials.build): the shader
## materials of the buildings' tables, the cottages', the tavern's parts and
## the stalls' (BuildingSchemas).

const D := preload("res://src/data/data_schema.gd")
const TAVERN_MATERIALS := preload("res://src/tavern/tavern_materials.gd")

## The shaders a material may name; none names `surface`.
const SHADERS: Array[String] = ["surface", "flame", "foliage", "fur", "cloth", "glass"]

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
