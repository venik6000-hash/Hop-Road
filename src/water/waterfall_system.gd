class_name WaterfallSystem
extends Node3D
## The two falls of the region (RegionDef.falls; "" for none; the valley's
## stand below the plateau west of the village), the stream that feeds the
## upper one and the stream on the shelf between them, in place of the
## Blender scene's modelled ribbons. A region without falls still has the
## materials of the lake's water for its brook and its mills.
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
## faces stand where the valley's cliff file puts them (RegionDef.cliff).
##
## The falls' file (WorldSchemas.falls) is read as a plan: {head, upper,
## stream, lower}. `head` is the stream above the upper fall: rows of [its
## surface on the centre line, half the water's width, the speed of the flow
## (m/s), the depth of the bed carve() cuts for it (m)]. From the spring it
## winds over the plateau, set into the ground as the village brook is, and
## runs down the shoulder the cliff's seat left behind the scan
## (tools/pipeline/rocks/cliff_seat.py); over the scan's top nothing is cut
## (depth 0): a film over the rock to the brink the fall leaves from.
## `stream` is the shelf stream: rows of [its surface on the centre line (the
## water level, as terrain.py's SHELF_STREAM cuts the channel), half the
## ribbon's width, the speed of the flow], from the foot of the cliff behind
## the upper fall's basin to the lower fall's lip.
## A fall (`upper`, `lower`) leaves where its stream ends, along its last
## stretch (falls()), which gives it its lip (the centre of the crest), its
## heading (the direction of the flow in degrees, 0 = +z, toward the lake)
## and its dip (the water's downward speed over the lip). speed: of the water
## over the lip (m/s); width at the lip and how much wider it is at the
## bottom; depth: the water's thickness over the lip (m); approach: seconds
## of sheet before the lip, sliding over it; floor: the surface it falls
## into; mist: strength of the spray and mist where it lands.

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
## The region's file of its falls; "" for none.
var falls_file := ""


func _ready() -> void:
	if map != null:
		var index := MapIndex.of(map)
		for item: MeshInstance3D in index.labelled_any(REPLACES):
			index.drop(item)
	var plan := WaterfallSystem.read(falls_file)
	if plan.is_empty():
		return
	var all := WaterfallSystem.falls(plan)
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
	_add_head(plan)
	_add_stream(plan, WaterfallSystem.landing_of(all[0]))
	if water != null:
		_add_plunge_foam(WaterfallSystem.landing_of(all[1]))

## The plan of the falls in the file `path` (WorldSchemas.falls): {head,
## upper, stream, lower}, the streams as rows of arrays; {} for "" or a file
## that does not read.
static func read(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var data: Variant = DataFile.read(path, WorldSchemas.falls())
	if not data is Dictionary:
		return {}
	var file: Dictionary = data
	var head := []
	var listed_head: Array = file.head
	for row: Dictionary in listed_head:
		head.append([Values.vec3(row.at), Values.real(row.half), Values.real(row.speed), Values.real(row.depth)])
	var stream := []
	var listed_stream: Array = file.stream
	for row: Dictionary in listed_stream:
		stream.append([Values.vec3(row.at), Values.real(row.half), Values.real(row.speed)])
	return {"head": head, "upper": file.upper, "stream": stream, "lower": file.lower}

## Both falls of `plan` (read), the upper one first.
static func falls(plan: Dictionary) -> Array[Dictionary]:
	var upper: Dictionary = plan.upper
	var lower: Dictionary = plan.lower
	var head: Array = plan.head
	var stream: Array = plan.stream
	return [WaterfallSystem._fall_from(upper, head), WaterfallSystem._fall_from(lower, stream)]

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

## Rows of the stream above the upper fall of `plan` (read; none for {}),
## every VillageBrook.STEP metres, as a course of VillageBrook: {at: Vector3
## (the surface on the centre line), half, speed, depth, step: bool (white
## water)}.
static func head_rows(plan: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var head: Array = plan.get("head", [])
	for k in head.size() - 1:
		var here: Array = head[k]
		var next: Array = head[k + 1]
		var a: Vector3 = here[0]
		var b: Vector3 = next[0]
		var count := maxi(roundi(Vector2(b.x - a.x, b.z - a.z).length() / VillageBrook.STEP), 1)
		for s in count + (1 if k == head.size() - 2 else 0):
			var f := float(s) / count
			var speed := lerpf(here[2], next[2], f)
			result.append({"at": a.lerp(b, f), "half": lerpf(here[1], next[1], f), "speed": speed,
				"depth": lerpf(here[3], next[3], f), "step": speed > 2.0})
	return result

## Cuts the bed of the stream above the upper fall of `plan` (read) into the
## near heightfield (row z, column x at origin + index * cell), after the
## cliff's seat is laid into it (RockField.seat). The valley's ground bake
## calls it (tools/pipeline/terrain/valley_ground.gd).
static func carve(image: Image, origin: Vector2, cell: float, plan: Dictionary) -> void:
	var rows := WaterfallSystem.head_rows(plan)
	if not rows.is_empty():
		VillageBrook.cut(image, origin, cell, rows)

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
	if water != null:
		for parameter: String in LAKE_LOOK:
			var value: Variant = water.material.get_shader_parameter(parameter)
			if value != null:
				material.set_shader_parameter(parameter, value)
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

## The ribbon of the stream above the upper fall of `plan`: a brook, white
## where it runs fast, that reaches into its banks as the village's does.
func _add_head(plan: Dictionary) -> void:
	var course := []
	for row: Dictionary in WaterfallSystem.head_rows(plan):
		course.append([row.at, row.half + VillageBrook.INTO_BANK, row.speed])
	var material := stream_material()
	material.set_shader_parameter("landing", Vector2(1e6, 1e6))
	material.set_shader_parameter("rapids", 0.85)
	# Past the brink the eye looks through it down into the basin, whose
	# water is not in the screen copy.
	var upper: Dictionary = plan.upper
	material.set_shader_parameter("water_level", Values.real(upper.floor))
	material.set_shader_parameter("max_depth", 0.5)
	material.set_shader_parameter("ripple_scale", 0.3)
	material.set_shader_parameter("swirl_height", 0.02)
	_add_ribbon("HeadStream", WaterfallSystem.ribbon_mesh(course, 1), material)

## The ribbon of the shelf stream of `plan`.
func _add_stream(plan: Dictionary, landing: Vector3) -> void:
	var material := stream_material()
	material.set_shader_parameter("landing", Vector2(landing.x, landing.z))
	var stream: Array = plan.stream
	_add_ribbon("ShelfStream", WaterfallSystem.ribbon_mesh(stream, 6), material)

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
	water.terrain.share_fields(material)
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
