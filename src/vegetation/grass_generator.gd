@tool
class_name GrassGenerator
extends Node3D
## Grows grass over a terrain mesh, in the editor and in the game.
##
## Reads the triangles of `terrain` (the positions and normals of its
## vertices), spreads clumps of meadow plants (GrassClump) over them at
## `density` to the square metre, none where the surface is steeper than
## `slope_threshold`, and draws them with MultiMeshes and
## shaders/grass.gdshader: one MultiMesh per square chunk of ground, so the
## camera culls the chunks it does not see and those beyond the shader's
## fade_end are not drawn at all.
##
## The look (colours, wind, light, distance fade) is the shader's: change it
## on `material`. The clumps are not saved with the scene; they grow again
## when the scene loads (the same every time for one `scatter_seed`), so a
## scene file stays small. After moving or reshaping the terrain, or after
## changing the numbers here, press the button again.
##
## The alpine level's own ground is no mesh (TerrainSystem); its grass is
## GrassField, which scatters the same clumps from the height fields and
## picks the plants by the lie of the land.

const SHADER := preload("res://src/vegetation/shaders/grass.gdshader")
const NOISE := "res://assets/generated/sky/cloud_weather.png"

## The mesh the grass grows on.
@export var terrain: MeshInstance3D:
	set(value):
		terrain = value
		update_configuration_warnings()
## Clumps to the square metre of surface.
@export_range(0.0, 30.0, 0.5, "or_greater") var density := 9.0
## Surfaces steeper than this grow nothing (cliffs, walls).
@export_range(0.0, 90.0, 0.5, "radians_as_degrees") var slope_threshold := deg_to_rad(35.0)
## The same seed grows the same meadow.
@export var scatter_seed := 1
## Side (m) of the squares the clumps are grouped by.
@export_range(4.0, 64.0, 1.0, "suffix:m") var chunk_size := 16.0
## More than this many clumps are not grown: the density is lowered to fit.
@export var max_clumps := 150000
## Cards in a clump: 0 three bent ones, 1 two flat ones (GrassClump.DETAIL).
@export_range(0, 1) var detail := 0
@export_group("Patches")
## Size (m) of the patches of lighter, darker, taller and shorter grass.
@export_range(1.0, 80.0, 0.5, "suffix:m") var patch_size := 12.0
## How much of the richest patches is tall grass in seed (0: none anywhere).
@export_range(0.0, 1.0, 0.01) var seeding := 0.6
## The share of clumps that are flowers.
@export_range(0.0, 0.3, 0.005) var flowers := 0.04
@export_group("")
## Draws the grass (shaders/grass.gdshader); made when first needed.
@export var material: ShaderMaterial
## Grow the grass when the scene loads.
@export var grow_on_ready := true
@export_tool_button("Вырастить траву", "Reload") var grow_action := generate
@export_tool_button("Убрать траву", "Clear") var clear_action := clear

## Clumps grown by the last generate().
var clump_count := 0

var _chunks: Array[MultiMeshInstance3D] = []

func _ready() -> void:
	if grow_on_ready and terrain != null:
		generate()

func _get_configuration_warnings() -> PackedStringArray:
	if terrain == null:
		return PackedStringArray(["Укажите Terrain: MeshInstance3D, по которому растить траву."])
	return PackedStringArray()

## Removes the grass grown before and grows it anew.
func generate() -> void:
	clear()
	if terrain == null or terrain.mesh == null:
		push_warning("GrassGenerator: нет меша рельефа (Terrain).")
		return
	# The triangles go into this node's own space, where the chunks are drawn.
	grow(terrain.mesh, global_transform.affine_inverse() * terrain.global_transform,
		(global_basis.inverse() * Vector3.UP).normalized())

## Grows grass over `mesh` as `to_local` places it in this node's space, where
## `up` is the way the world's up points. Adds to what is grown already.
func grow(mesh: Mesh, to_local: Transform3D, up: Vector3) -> void:
	var start := Time.get_ticks_msec()
	_ensure_material()
	var surface := read_triangles(mesh, to_local)
	var vertices: PackedVector3Array = surface.vertices
	var normals: PackedVector3Array = surface.normals
	# Too many clumps for one meadow: thin them all alike.
	var area := surface_area(vertices, surface.indices)
	var per_metre := density
	if area * per_metre > max_clumps:
		per_metre = max_clumps / area
		push_warning("GrassGenerator: %d м² × %.1f — больше %d кочек; плотность снижена до %.1f на м²."
			% [int(area), density, max_clumps, per_metre])
	var patches := FastNoiseLite.new()
	patches.seed = scatter_seed
	patches.frequency = 1.0 / patch_size
	var clump := GrassClump.mesh(detail)
	clump.surface_set_material(0, material)
	var fade := GrassScatter.fade_of(material)
	var chunks := GrassScatter.split(GrassScatter.over_triangles(vertices, normals, surface.indices, per_metre,
		slope_threshold, up, scatter_seed, GrassClump.sheet().cells, patches, seeding, flowers), chunk_size)
	for key: Vector2i in chunks:
		var buffer: PackedFloat32Array = chunks[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = clump
		multimesh.instance_count = buffer.size() / GrassScatter.STRIDE
		multimesh.buffer = buffer
		var item := MultiMeshInstance3D.new()
		item.name = "Chunk_%d_%d" % [key.x, key.y]
		item.multimesh = multimesh
		item.custom_aabb = GrassScatter.bounds(buffer).grow(GrassClump.REACH)
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Past the shader's fade_end every clump of the chunk has shrunk away.
		item.visibility_range_end = fade.w + item.custom_aabb.size.length() * 0.5
		# Not saved with the scene and not shown in its tree: grown anew on load.
		add_child(item, false, Node.INTERNAL_MODE_BACK)
		_chunks.append(item)
		clump_count += multimesh.instance_count
	print("GrassGenerator: %d кочек, %d чанков, %d мс" % [clump_count, _chunks.size(), Time.get_ticks_msec() - start])

## Removes the grass.
func clear() -> void:
	for item in _chunks:
		if is_instance_valid(item):
			item.queue_free()
	_chunks.clear()
	clump_count = 0

func _ensure_material() -> void:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SHADER
	if material.get_shader_parameter("atlas") == null:
		GrassClump.dress(material)
	# The gust field and the cloud shadows read the same tileable noise.
	for parameter: String in ["wind_noise", "cloud_weather"]:
		if material.get_shader_parameter(parameter) == null:
			material.set_shader_parameter(parameter, load(NOISE))

## The triangles of `mesh` moved by `to_local`: {vertices, normals, indices},
## the surfaces one after another. Where a surface has no normals, its
## vertices take those of the faces round them.
static func read_triangles(mesh: Mesh, to_local: Transform3D) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var turn := to_local.basis.inverse().transposed()
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var corners := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			corners = arrays[Mesh.ARRAY_INDEX]
		else:
			corners = PackedInt32Array(range(points.size()))
		var facing := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] != null:
			facing = arrays[Mesh.ARRAY_NORMAL]
		else:
			facing = face_normals(points, corners)
		var first := vertices.size()
		vertices.append_array(to_local * points)
		for normal in facing:
			normals.append((turn * normal).normalized())
		for corner in corners:
			indices.append(first + corner)
	return {"vertices": vertices, "normals": normals, "indices": indices}

## Per vertex, the area-weighted mean of the normals of the faces it belongs
## to (Godot's front faces wind clockwise).
static func face_normals(points: PackedVector3Array, corners: PackedInt32Array) -> PackedVector3Array:
	var sums := PackedVector3Array()
	sums.resize(points.size())
	for at in range(0, corners.size() - 2, 3):
		var face := (points[corners[at + 2]] - points[corners[at]]).cross(points[corners[at + 1]] - points[corners[at]])
		for k in 3:
			sums[corners[at + k]] += face
	for index in sums.size():
		sums[index] = sums[index].normalized()
	return sums

static func surface_area(vertices: PackedVector3Array, indices: PackedInt32Array) -> float:
	var area := 0.0
	for at in range(0, indices.size() - 2, 3):
		area += (vertices[indices[at + 1]] - vertices[indices[at]]).cross(
			vertices[indices[at + 2]] - vertices[indices[at]]).length() * 0.5
	return area
