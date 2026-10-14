class_name WaterfallSystem
extends Node3D
## The two falls below the plateau west of the village, the stream that feeds
## the upper one and the stream on the shelf between them, in place of the
## Blender scene's modelled ribbons.
##
## All of it is the lake's water: the streams, the falling sheets and the foam
## where the lower fall lands are shaded with the lake's optics
## (water_look.gdshaderinc), their parameters copied from the lake's own
## material, which is left as it is. Each fall is a pair of sheets along the
## ballistic path of water leaving its lip (a front sheet and a narrower one
## behind it, for depth), with spray and mist where it lands. The water rises
## from a spring among boulders on the plateau, runs down the shoulder behind
## the upper cliff and over the rock of its top, and falls from its brink into
## a basin on the 17 m shelf, whose stream runs over the lower cliff's rock to
## the lip of the lower fall; that one plunges into a cove of the lake and its
## foam streams out over the lake's surface. The basin, the channel and the
## cove are cut into the terrain by tools/pipeline/terrain/terrain.py
## (SHELF_*, POOL_*), the bed above the upper fall by carve(), and the rock
## faces stand where RockField.CLIFF_FACES puts them.

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
## A fall leaves where its stream ends, along its last stretch (falls()), which
## gives it its lip (the centre of the crest), its heading (the direction of
## the flow in degrees, 0 = +z, toward the lake) and its dip (the water's
## downward speed over the lip). speed: of the water over the lip (m/s); width
## at the lip and how much wider it is at the bottom; depth: the water's
## thickness over the lip (m); approach: seconds of sheet before the lip,
## sliding over it; floor: the surface it falls into; mist: strength of the
## spray and mist where it lands.
const UPPER_FALL := {"speed": 3.0, "width": 2.4, "spread": 2.2, "depth": 0.25, "approach": 0.03,
	"floor": 16.35, "mist": 0.6}
const LOWER_FALL := {"speed": 3.0, "width": 3.6, "spread": 2.0, "depth": 0.3, "approach": 0.03,
	"floor": 0.72, "mist": 1.0}
## The stream above the upper fall: its surface on the centre line, half the
## water's width, the speed of the flow (m/s) and the depth of the bed carve()
## cuts for it (m). From the spring it winds over the plateau, set into the
## ground as the village brook is, and runs down the shoulder the cliff's seat
## left behind the scan (tools/pipeline/rocks/cliff_seat.py), whose back rim
## its banks close on at z = -151. From there it is over the scan's top, where
## nothing is cut (depth 0): a film over the rock, as deep as the notch the
## scan has there, to the brink the fall leaves from.
const HEAD := [
	[Vector3(-45.4, 29.66, -162.6), 0.4, 0.3, 0.3], [Vector3(-46.2, 29.63, -160.4), 0.6, 0.5, 0.3],
	[Vector3(-47.6, 29.6, -158.6), 0.75, 0.6, 0.32], [Vector3(-49.2, 29.57, -157.2), 0.85, 0.8, 0.3],
	[Vector3(-49.9, 29.52, -156.2), 0.9, 1.2, 0.28], [Vector3(-50.0, 29.47, -155.3), 0.9, 1.8, 0.25],
	[Vector3(-49.9, 28.32, -153.0), 0.9, 3.4, 0.22], [Vector3(-49.8, 27.76, -151.6), 1.0, 3.6, 0.15],
	[Vector3(-49.8, 27.64, -151.0), 1.2, 3.2, 0.05], [Vector3(-49.8, 27.55, -150.5), 1.2, 3.0, 0.0],
	[Vector3(-49.8, 27.42, -150.0), 1.15, 3.0, 0.0], [Vector3(-49.7, 27.36, -149.5), 1.05, 3.0, 0.0],
	[Vector3(-49.7, 27.32, -149.2), 1.05, 3.0, 0.0],
]
## The shelf stream: its surface on the centre line (the water level in y, as
## terrain.py's SHELF_STREAM cuts the channel), half the ribbon's width and the
## speed of the flow (m/s). From the foot of the cliff behind the upper fall's
## basin to the lower fall's lip; the ribbon runs into the banks but at the lip.
const STREAM := [
	[Vector3(-50.0, 16.35, -149.4), 4.4, 0.2], [Vector3(-50.0, 16.35, -145.0), 4.9, 0.25],
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

## Rows of the stream above the upper fall, as VillageBrook.rows has the
## brook's: {at: Vector3 (the surface on the centre line), half, speed, depth,
## step: bool (white water)}. Worked out by carve().
static var head: Array[Dictionary] = []

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
	var sheet := sheet_material()
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
	_add_head()
	_add_stream(WaterfallSystem.landing_of(all[0]))
	if water != null:
		_add_plunge_foam(WaterfallSystem.landing_of(all[1]))

## Both falls, the upper one first.
static func falls() -> Array[Dictionary]:
	return [WaterfallSystem._fall_from(UPPER_FALL, HEAD), WaterfallSystem._fall_from(LOWER_FALL, STREAM)]

## `fall` leaving where `course` ends, along its last stretch.
static func _fall_from(fall: Dictionary, course: Array) -> Dictionary:
	var leaving := fall.duplicate()
	var last: Vector3 = course[-1][0]
	var before: Vector3 = course[-2][0]
	var run := Vector2(last.x - before.x, last.z - before.z)
	var speed: float = leaving.speed
	leaving.lip = last
	leaving.heading = rad_to_deg(atan2(run.x, run.y))
	leaving.dip = speed * (before.y - last.y) / run.length()
	return leaving

## HEAD every VillageBrook.STEP metres.
static func head_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for k in HEAD.size() - 1:
		var here: Array = HEAD[k]
		var next: Array = HEAD[k + 1]
		var a: Vector3 = here[0]
		var b: Vector3 = next[0]
		var count := maxi(roundi(Vector2(b.x - a.x, b.z - a.z).length() / VillageBrook.STEP), 1)
		for s in count + (1 if k == HEAD.size() - 2 else 0):
			var f := float(s) / count
			var speed := lerpf(here[2], next[2], f)
			result.append({"at": a.lerp(b, f), "half": lerpf(here[1], next[1], f), "speed": speed,
				"depth": lerpf(here[3], next[3], f), "step": speed > 2.0})
	return result

## Cuts the bed of the stream above the upper fall into the near heightfield
## (row z, column x at origin + index * cell), after the cliff's seat is laid
## into it (RockField.seat), and remembers the course for the water.
static func carve(image: Image, origin: Vector2, cell: float) -> void:
	head = WaterfallSystem.head_rows()
	VillageBrook.cut(image, origin, cell, head)

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

## The falls' shader on the lake's optics, for `fall_mesh` sheets anywhere.
func sheet_material() -> ShaderMaterial:
	return _lake_material(SHEET_SHADER, SHEET_PRIORITY)

## The stream shader on the lake's optics, for `ribbon_mesh` ribbons anywhere.
func stream_material() -> ShaderMaterial:
	var material := _lake_material(STREAM_SHADER, STREAM_PRIORITY)
	if water != null:
		material.set_shader_parameter("water_level", water.water_level)
	return material

## The ribbon of the stream above the upper fall: a brook, white where it
## runs fast, that reaches into its banks as the village's does.
func _add_head() -> void:
	var course := []
	for row: Dictionary in head:
		course.append([row.at, row.half + VillageBrook.INTO_BANK, row.speed])
	var material := stream_material()
	material.set_shader_parameter("landing", Vector2(1e6, 1e6))
	material.set_shader_parameter("rapids", 0.85)
	# Past the brink the eye looks through it down into the basin, whose
	# water is not in the screen copy.
	material.set_shader_parameter("water_level", UPPER_FALL.floor)
	material.set_shader_parameter("max_depth", 0.5)
	material.set_shader_parameter("ripple_scale", 0.3)
	material.set_shader_parameter("swirl_height", 0.02)
	_add_ribbon("HeadStream", WaterfallSystem.ribbon_mesh(course, 1), material)

## The ribbon of the shelf stream.
func _add_stream(landing: Vector3) -> void:
	var material := stream_material()
	material.set_shader_parameter("landing", Vector2(landing.x, landing.z))
	_add_ribbon("ShelfStream", WaterfallSystem.ribbon_mesh(STREAM, 6), material)

func _add_ribbon(ribbon_name: String, mesh: ArrayMesh, material: ShaderMaterial) -> void:
	var item := MeshInstance3D.new()
	item.name = ribbon_name
	item.mesh = mesh
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
