class_name MillWater
extends Node3D
## The water of the mill, by its table's `water`, in the building's frame.
## `ribbons` are what runs in the flume's troughs, stands in its tanks and
## runs from under the wheel over the rock's ledges into the pool: the
## stream's shader on a ribbon each (`points` of the surface on the centre
## line, `half` the water's width, its `speed`, and whether boards hold its
## edges). `falls` are what drops: from the spout onto the wheel and from
## under the wheel onto the ledges, each a fall of WaterfallSystem's kind
## (lip, heading from the building's +z, speed, dip, width, spread, depth,
## approach, floor, and how far the sheet goes under that floor and its back
## sheet lies behind it). It is the falls' water, on their materials, and it
## runs day and night, as the wheel turns.

const Meshes = preload("res://src/water/waterfall_meshes.gd")
## The stream's shader thins a ribbon out over this far from its edges
## (stream.gdshader's ALPHA), as water thins over rock. Between a trough's
## boards it is whole to its edge: a `boarded` ribbon is told it is this much
## wider a side than it is.
const BOARDED := 0.5
## The lake's smallest ripples shrunk to a trough's width, and its swirls, m.
const RIPPLES := 0.12
const SWIRLS := 0.005
## Metres from the eye beyond which the mill's water is not drawn.
const REACH := 260.0

## Draws `water` on the materials of `falls`; what falls lands in the lake's
## cove, whose surface lies at `lake_level` in the map.
func build(water: Dictionary, falls: WaterfallSystem, lake_level: float) -> void:
	var stream := falls.stream_material()
	stream.set_shader_parameter("landing", Vector2(1e6, 1e6))
	stream.set_shader_parameter("rapids", 0.85)
	# Nothing of the lake lies behind a trough's water.
	stream.set_shader_parameter("water_level", -100.0)
	stream.set_shader_parameter("max_depth", water.depth)
	stream.set_shader_parameter("ripple_scale", RIPPLES)
	stream.set_shader_parameter("swirl_height", SWIRLS)
	for ribbon: Dictionary in water.ribbons:
		_add(str(ribbon.name), Meshes.ribbon_mesh(MillWater.course(ribbon), 1, BOARDED if ribbon.boarded else 0.0), stream)
	var sheet := falls.sheet_material()
	for fall: Dictionary in water.falls:
		var item := _add(str(fall.name), Meshes.fall_mesh(MillWater.fall_of(fall)), sheet)
		item.set_instance_shader_parameter("floor_level", lake_level)

## The rows of a table's ribbon as WaterfallSystem.ribbon_mesh takes them.
static func course(ribbon: Dictionary) -> Array:
	var rows := []
	for point: Array in ribbon.points:
		rows.append([Vector3(point[0], point[1], point[2]), float(ribbon.half), float(ribbon.speed)])
	return rows

## A table's fall as WaterfallSystem's falls are, in the building's frame.
static func fall_of(fall: Dictionary) -> Dictionary:
	var leaving := fall.duplicate()
	var lip: Array = fall.lip
	leaving.lip = Vector3(lip[0], lip[1], lip[2])
	return leaving

func _add(piece: String, mesh: ArrayMesh, material: ShaderMaterial) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = piece.to_pascal_case()
	item.mesh = mesh
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	item.visibility_range_end = REACH
	add_child(item)
	return item
