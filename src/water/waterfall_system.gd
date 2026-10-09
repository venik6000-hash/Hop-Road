class_name WaterfallSystem
extends Node3D
## The two falls below the plateau west of the village and the stream on the
## shelf between them, in place of the Blender scene's modelled ribbons.
##
## All of it is the lake's water: the stream, the falling sheets and the foam
## where the lower fall lands are shaded with the lake's optics
## (water_look.gdshaderinc), their parameters copied from the lake's own
## material, which is left as it is. Each fall is a pair of sheets along the
## ballistic path of water leaving its lip (a front sheet and a narrower one
## behind it, for depth), with spray and mist where it lands. The upper fall
## lands in a basin on the 17 m shelf whose stream runs over the lower cliff's
## rock to the lip of the lower fall; that one plunges into a cove of the lake
## and its foam streams out over the lake's surface. The basin, the channel
## and the cove are cut into the terrain by tools/pipeline/terrain/terrain.py
## (SHELF_*, POOL_*), and the rock faces behind stand where
## RockField.CLIFF_FACES puts them.

const SHEET_SHADER := preload("res://src/water/waterfall.gdshader")
const STREAM_SHADER := preload("res://src/water/stream.gdshader")
const FOAM_SHADER := preload("res://src/water/plunge_foam.gdshader")
const MIST_SHADER := preload("res://src/water/mist.gdshader")
const Meshes = preload("res://src/water/waterfall_meshes.gd")
const Spray = preload("res://src/water/waterfall_spray.gd")
const GRAVITY := 9.81
## Blender pieces this replaces (their alpine_label).
const REPLACES := ["Two stepped waterfalls - modeled ribbons", "Waterfall splash droplets"]
## The lake's optics (water_look.gdshaderinc) copied from its material; those
## it leaves unset keep the lake shader's defaults, which the include repeats.
const LAKE_LOOK := ["absorption", "scatter_color", "deep_color", "refraction_strength", "base_roughness",
	"foam_color", "sss_strength", "macro_noise"]
## lip: centre of the crest; heading: direction of the flow in degrees (0 = +z,
## toward the lake); speed: of the water over the lip (m/s) and dip: its
## downward speed there; width at the lip and how much wider it is at the
## bottom; depth: the water's thickness over the lip (m); approach: seconds of
## sheet before the lip, sliding over it; floor: the surface it falls into;
## mist: strength of the spray and mist where it lands.
const UPPER_FALL := {"lip": Vector3(-50.0, 29.95, -147.9), "heading": 0.0, "speed": 2.4, "dip": 0.0,
	"width": 3.2, "spread": 1.8, "depth": 0.25, "approach": 0.25, "floor": 16.35, "mist": 0.6}
## The lower fall leaves where the stream ends, along its last stretch (falls()).
const LOWER_FALL := {"speed": 3.0, "width": 3.6, "spread": 2.0, "depth": 0.3, "approach": 0.03,
	"floor": 0.72, "mist": 1.0}
## The shelf stream: its surface on the centre line (the water level in y, as
## terrain.py's SHELF_STREAM cuts the channel), half the ribbon's width and the
## speed of the flow (m/s). From under the cliff behind the upper fall's basin
## to the lower fall's lip; the ribbon runs into the banks but at the lip.
const STREAM := [
	[Vector3(-50.0, 16.35, -147.6), 4.6, 0.2], [Vector3(-50.0, 16.35, -145.0), 4.9, 0.25],
	[Vector3(-49.8, 16.34, -142.2), 4.3, 0.5], [Vector3(-49.2, 16.32, -138.6), 2.8, 1.0],
	[Vector3(-50.3, 16.27, -133.2), 2.8, 1.2], [Vector3(-49.7, 16.2, -130.2), 2.8, 1.8],
	[Vector3(-49.5, 15.85, -128.6), 1.8, 3.0],
]
const SHEET_ROWS := 64
const SHEET_COLUMNS := 12
const STREAM_COLUMNS := 8
## How far the lower fall's foam streams out over the lake (m).
const PLUNGE_REACH := 8.0
## Draw order among the transparent things: after the lake (0), the stream and
## the lake foam, then the sheets, the mist over everything.
const STREAM_PRIORITY := 1
const FOAM_PRIORITY := 1
const SHEET_PRIORITY := 2
const MIST_PRIORITY := 3

var map: Node3D
var water: WaterSystem

var _weather: Texture2D

func _ready() -> void:
	if map != null:
		for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
			if RockField.label_of(item) in REPLACES:
				item.get_parent().remove_child(item)
				item.queue_free()
	_weather = load("res://assets/generated/sky/cloud_weather.png")
	var all := WaterfallSystem.falls()
	var sheet := _lake_material(SHEET_SHADER, SHEET_PRIORITY)
	for index in all.size():
		var fall := all[index]
		var item := MeshInstance3D.new()
		item.name = "Fall%d" % index
		item.mesh = WaterfallSystem.fall_mesh(fall)
		item.material_override = sheet
		item.set_instance_shader_parameter("floor_level", fall.floor)
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(item)
		Spray.add_mist(self, WaterfallSystem.landing_of(fall), fall.width + fall.spread, fall.mist)
	_add_stream(WaterfallSystem.landing_of(all[0]))
	if water != null:
		_add_plunge_foam(WaterfallSystem.landing_of(all[1]))

## Both falls; the lower one leaves where the stream ends, along its last stretch.
static func falls() -> Array[Dictionary]:
	var lower := LOWER_FALL.duplicate()
	var last: Vector3 = STREAM[-1][0]
	var before: Vector3 = STREAM[-2][0]
	var run := Vector2(last.x - before.x, last.z - before.z)
	var speed: float = lower.speed
	lower.lip = last
	lower.heading = rad_to_deg(atan2(run.x, run.y))
	lower.dip = speed * (before.y - last.y) / run.length()
	return [UPPER_FALL, lower]

## Seconds the water of `fall` takes to drop `height` metres below its lip.
static func fall_time(fall: Dictionary, height: float) -> float:
	var dip: float = fall.dip
	return (sqrt(dip * dip + 2.0 * GRAVITY * height) - dip) / GRAVITY

## Where the water of `fall` meets its floor.
static func landing_of(fall: Dictionary) -> Vector3:
	var lip: Vector3 = fall.lip
	var floor_y: float = fall.floor
	var speed: float = fall.speed
	var t := WaterfallSystem.fall_time(fall, lip.y - floor_y)
	var heading := deg_to_rad(fall.heading)
	var at := lip + Vector3(sin(heading), 0.0, cos(heading)) * speed * t
	return Vector3(at.x, floor_y, at.z)

## Circles (x, z, radius) that boulders must keep out of: under the falls.
static func keep_clear() -> Array[Vector3]:
	var zones: Array[Vector3] = []
	for fall: Dictionary in WaterfallSystem.falls():
		var landing := WaterfallSystem.landing_of(fall)
		zones.append(Vector3(landing.x, landing.z, fall.width + fall.spread))
	return zones

## Front sheet and a narrower one 0.4 m behind it, from `approach` seconds
## before the lip (still sliding over it) to 0.8 m under the floor. The one
## behind comes first: the sheets are blended in the order they are drawn.
static func fall_mesh(fall: Dictionary) -> ArrayMesh:
	return Meshes.fall_mesh(fall)

## A material with `shader` and the lake's optics copied from the lake.
func _lake_material(shader: Shader, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	material.set_shader_parameter("cloud_weather", _weather)
	if water != null:
		for parameter: String in LAKE_LOOK:
			var value: Variant = water.material.get_shader_parameter(parameter)
			if value != null:
				material.set_shader_parameter(parameter, value)
		if water.ocean != null:
			material.set_shader_parameter("wind_heading", deg_to_rad(water.ocean.wind_direction_deg))
	return material

## A ribbon of running water along `course` (rows of [surface point on the
## centre line, half width, speed m/s]), `steps` rows per stretch (see
## waterfall_meshes.gd).
static func ribbon_mesh(course: Array, steps: int) -> ArrayMesh:
	return Meshes.ribbon_mesh(course, steps)

## The stream shader on the lake's optics, for `ribbon_mesh` ribbons anywhere.
func stream_material() -> ShaderMaterial:
	var material := _lake_material(STREAM_SHADER, STREAM_PRIORITY)
	if water != null:
		material.set_shader_parameter("water_level", water.water_level)
	return material

## The ribbon of the shelf stream.
func _add_stream(landing: Vector3) -> void:
	var material := stream_material()
	material.set_shader_parameter("landing", Vector2(landing.x, landing.z))
	var item := MeshInstance3D.new()
	item.name = "ShelfStream"
	item.mesh = WaterfallSystem.ribbon_mesh(STREAM, 6)
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(item)

## The lake's foam streaming out where the lower fall lands: a grid over the
## lake that rides its waves (plunge_foam.gdshader).
func _add_plunge_foam(landing: Vector3) -> void:
	var material := _lake_material(FOAM_SHADER, FOAM_PRIORITY)
	for parameter in ["near_height", "far_height", "near_rect", "far_rect", "water_level"]:
		material.set_shader_parameter(parameter, water.material.get_shader_parameter(parameter))
	material.set_shader_parameter("plunge", Vector4(landing.x, landing.z, PLUNGE_REACH, 1.0))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * PLUNGE_REACH * 2.0
	plane.subdivide_width = 63
	plane.subdivide_depth = 63
	var item := MeshInstance3D.new()
	item.name = "PlungeFoam"
	item.mesh = plane
	item.material_override = material
	item.position = Vector3(landing.x, water.water_level, landing.z)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The waves lift and drop it.
	item.extra_cull_margin = 2.0
	add_child(item)
