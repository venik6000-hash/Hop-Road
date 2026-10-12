class_name RockField
extends Node3D
## Scanned rocks (tools/pipeline/rocks/build_rocks.py shapes with the maps
## of tools/pipeline/rocks/rock_textures.py) in place of the Blender scene's
## blockout stones, and the scanned faces of the waterfall cliff.
##
## The blockout batches are split back into their stones (pieces of the batch
## mesh that share no vertex position); each stone becomes a scan of about
## its footprint, turned at random and set into the generated terrain. Where
## the terrain now lies deeper in the lake than the Blender ground did, a
## shore stone grows down to the bed so that it still breaks the surface. By
## the water the stones are bare scans; in the meadows and at the brook most
## are mossy ones.
##
## Drawing: a MultiMesh per shape and 64 m tile, so Godot's automatic mesh LOD
## is chosen per tile; INSTANCE_CUSTOM = (array layer, moss, tone seed, 0).
## Collision: the convex hull of each stone, the coarse copy of each cliff face.
##
## A cliff face is a shell, open at the back, and the terrain is its core:
## seat() lays the ground it stands against into the heightfield.

const MeshUtil = preload("res://src/common/mesh_util.gd")
const LayoutStore = preload("res://src/layout/layout_store.gd")
const SHAPES := preload("res://assets/models/rocks/rock_shapes.glb")
const SHADER := preload("res://src/rocks/rock.gdshader")
const CLIFF_SHADER := preload("res://src/rocks/rock_cliff.gdshader")
const DATA := "res://assets/generated/rocks/"
## The ground behind the cliff's faces (tools/pipeline/rocks/cliff_seat.py).
const SEAT := DATA + "cliff_seat.json"
const TILE := 64.0
## Array layers in tools/pipeline/rocks/rock_textures.py order, and their
## grades: rgb tint carrying the exposure gain, and saturation. The scanned
## granites become the valley's grey limestone; the mossy sets keep their green.
const BOULDER_SCANS := ["boulder_01", "namaqualand_boulder_02", "namaqualand_boulder_03", "rock_07", "rock_09",
	"stone_01", "rock_moss_set_01", "rock_moss_set_02"]
const BOULDER_GRADES := [
	Vector4(1.22, 1.22, 1.28, 0.4), Vector4(1.55, 1.55, 1.63, 0.3), Vector4(1.39, 1.39, 1.46, 0.3),
	Vector4(1.15, 1.15, 1.2, 0.4), Vector4(2.7, 2.7, 2.83, 0.4), Vector4(1.1, 1.1, 1.15, 0.3),
	Vector4(1.17, 1.23, 1.1, 0.9), Vector4(1.0, 1.02, 0.97, 0.9),
]
const CLIFF_SCANS := ["coastal_cliff_02", "rock_face_01", "rock_face_02"]
const CLIFF_GRADES := [Vector4(2.05, 2.05, 2.15, 0.55), Vector4(1.23, 1.23, 1.29, 0.45),
	Vector4(1.12, 1.12, 1.18, 0.45)]
## Relative odds of the bare scans (the mossy sets share the rest equally).
const BARE_ODDS := {"boulder_01": 3.0, "namaqualand_boulder_02": 2.0, "namaqualand_boulder_03": 3.0,
	"rock_07": 2.0, "rock_09": 1.0, "stone_01": 1.0}
## Blender batches of blockout stones (alpine_label) and where they lie.
const SOURCES := {
	"Cliff talus and shoreline boulders": "shore",
	"Island rocky foundation": "shore",
	"Meadow granite and mossy stones": "meadow",
	"Village brook rock banks": "brook",
}
## Chance of a mossy scan, and the moss laid on a bare one, per place.
const MOSSY_ODDS := {"shore": 0.12, "meadow": 0.7, "brook": 0.55}
const MOSS := {"shore": 0.3, "meadow": 0.85, "brook": 0.7}
## The bathing water off the village beach (where the beach zone of
## tools/pipeline/terrain/terrain.py is whole, x and z): its shore stones lie
## on the bed instead of standing up through the swim as pillars.
const BATHING := Rect2(-110.0, -45.0, 75.0, 63.0)
## Faces of the waterfall cliff: scan, base point (centre of the footprint at
## the lowest point), yaw in degrees, scale. The upper step of the terrain
## drops from the 30 m plateau to the 17 m shelf along z = -149, the lower one
## to about 7 m along z = -129, both between x = -66 and -33; the water falls
## at x = -50. The scans face +z, toward the lake: coastal_cliff_02 is a shell
## whose face lies about 2 m in front of its pivot, its top curling 4 m back.
## The upper face stands 2.5 m short of the plateau: the ground comes down to
## the back of its top as a shoulder (cliff_seat.py, which has this face too),
## and the water crosses that top to fall from its brink (WaterfallSystem.HEAD).
## The lower face is tall enough for its top to be the lip of the lower fall:
## a ledge at the stream's level from z = -130 to -128.5 (terrain.py carries
## the shelf forward to meet it).
## Past the ends of those two the steps turn into the flanks of the butte and
## of the shelf, and under the lower fall into the banks of its cove: slopes
## too steep for the terrain's textures. There lie rock_face_01 scans, which
## lean back as those slopes do (foot 1.9 m before the pivot, top as far behind).
## None stands further forward than the great face beside it: the ground that
## seat() lays under it would show a bare side there.
## That scan is cut square at its -x end and runs out low at the other: a scale
## of -x turns it over, so that the square end is the one inside the next face.
const CLIFF_FACES := [
	{"scan": "coastal_cliff_02", "at": Vector3(-49.5, 15.6, -149.3), "yaw": 0.0, "scale": Vector3(0.82, 1.44, 0.9)},
	{"scan": "coastal_cliff_02", "at": Vector3(-47.0, 0.0, -128.8), "yaw": 7.0, "scale": Vector3(0.8, 1.9, 0.8)},
	{"scan": "rock_face_01", "at": Vector3(-29.4, 16.0, -158.25), "yaw": 90.0, "scale": Vector3(-4.5, 4.0, 1.9)},
	{"scan": "rock_face_01", "at": Vector3(-70.1, 14.5, -158.25), "yaw": -90.0, "scale": Vector3(4.5, 4.3, 2.0)},
	{"scan": "rock_face_01", "at": Vector3(-68.3, 6.0, -128.7), "yaw": -20.0, "scale": Vector3(-2.7, 3.2, 1.6)},
	{"scan": "rock_face_01", "at": Vector3(-29.3, 8.5, -129.2), "yaw": 10.0, "scale": Vector3(1.4, 1.9, 1.2)},
	{"scan": "rock_face_01", "at": Vector3(-59.2, -1.5, -121.0), "yaw": 90.0, "scale": Vector3(-2.2, 2.2, 1.0)},
	{"scan": "rock_face_01", "at": Vector3(-41.8, -1.5, -123.5), "yaw": -90.0, "scale": Vector3(2.0, 2.25, 1.0)},
	{"scan": "rock_face_01", "at": Vector3(-29.6, 16.0, -149.45), "yaw": 10.0, "scale": Vector3(1.9, 4.0, 1.5)},
	{"scan": "rock_face_01", "at": Vector3(-69.4, 14.5, -149.45), "yaw": -10.0, "scale": Vector3(-1.9, 4.3, 1.5)},
]

var terrain: TerrainSystem
var map: Node3D
## Circles (x, z, radius) left free of stones: where the waterfalls land.
var keep_clear: Array[Vector3] = []
## Optional rigid placement adjustment before the same visual/collider are installed.
var placement: Callable
## More stones than the Blender map has: [AABB, place] each (VillageBrook).
var extra_stones: Array = []
var stone_count := 0
## Every stone as it stands: {shape, xform, moss, tone}. The layout bake
## writes them to LayoutStore.ROCKS; once that file is there, the stones come
## from it and the Blender batches only say what to remove.
var stones: Array[Dictionary] = []

var _shapes: Array[Dictionary] = []   # {name, mesh, size, layer, cliff, bare, hull, coarse}
var _by_name := {}
var _groups := {}                      # "shape/tile" -> {shape, transforms, customs, size}
var _boulder_material: ShaderMaterial
var _cliff_material: ShaderMaterial
var _body: StaticBody3D

func _ready() -> void:
	var start := Time.get_ticks_usec()
	_load_shapes()
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "Solid"
	add_child(_body)
	var removed := 0
	var placed := LayoutStore.placed(LayoutStore.ROCKS)
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var label := RockField.label_of(item)
		if SOURCES.has(label):
			if placed.is_empty():
				for box in RockField.stones_of(item):
					_add_stone(box, SOURCES[label])
			_remove(item)
			removed += 1
		elif label == "Jointed waterfall cliff geology":
			_remove(item)
			removed += 1
	if placed.is_empty():
		for stone: Array in extra_stones:
			_add_stone(stone[0], stone[1])
	for entry: Dictionary in placed:
		if _by_name.has(entry.shape):
			_place_stone(_by_name[entry.shape], LayoutStore.unpack(entry.xform), entry.moss, entry.tone)
	for face: Dictionary in CLIFF_FACES:
		_add_cliff_face(face)
	_build_multimeshes()
	print("ROCKS stones=%d groups=%d replaced=%d load=%.2fs" % [stone_count, _groups.size(), removed,
		(Time.get_ticks_usec() - start) / 1e6])

## Lays the ground the cliff's faces stand against into the near heightfield
## (row z, column x at origin + index * cell): the heights cliff_seat.py worked
## out for the samples round each face. Before anything is built on the
## heightfield or cut into it.
static func seat(image: Image, origin: Vector2, cell: float) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAT))
	for face: Dictionary in data.faces:
		var corner := Vector2i(((Vector2(face.origin[0], face.origin[1]) - origin) / cell).round())
		var heights: Array = face.heights
		for row in heights.size():
			var line: Array = heights[row]
			for column in line.size():
				if line[column] != null:
					image.set_pixel(corner.x + column, corner.y + row, Color(float(line[column]), 0.0, 0.0))

static func label_of(item: Node) -> String:
	var extras: Dictionary = item.get_meta("extras", {})
	return str(extras.get("alpine_label", item.name))

## World AABBs of the separate stones of a blockout batch. The batch is
## flat shaded, so faces share no vertices; they are welded by position.
static func stones_of(item: MeshInstance3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var xform := item.global_transform
	for surface in item.mesh.get_surface_count():
		var arrays := item.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var parent := PackedInt32Array()
		parent.resize(points.size())
		for i in points.size():
			parent[i] = i
		var first := {}
		for i in points.size():
			var key := Vector3i((points[i] * 1000.0).round())
			if first.has(key):
				RockField._union(parent, i, first[key])
			else:
				first[key] = i
		for t in range(0, index.size(), 3):
			RockField._union(parent, index[t], index[t + 1])
			RockField._union(parent, index[t], index[t + 2])
		var box_of := {}
		for i in points.size():
			var root := RockField._find(parent, i)
			var p := xform * points[i]
			box_of[root] = (box_of[root] as AABB).expand(p) if box_of.has(root) else AABB(p, Vector3.ZERO)
		for box: AABB in box_of.values():
			boxes.append(box)
	return boxes

static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := RockField._find(parent, a)
	var rb := RockField._find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)

func _remove(item: Node) -> void:
	# Gone from the physics space at once: the vegetation scans it next.
	item.get_parent().remove_child(item)
	item.queue_free()

# --- shapes and materials ------------------------------------------------------

func _load_shapes() -> void:
	var scene := SHAPES.instantiate()
	var coarse := {}
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var shape_name := String(item.name)
		if shape_name.ends_with("__coarse"):
			coarse[shape_name.trim_suffix("__coarse")] = item.mesh
			continue
		var scan := shape_name.get_slice("__", 0)
		var cliff := CLIFF_SCANS.has(scan)
		var info := {
			"name": shape_name, "mesh": item.mesh, "size": item.mesh.get_aabb().size, "cliff": cliff,
			"layer": CLIFF_SCANS.find(scan) if cliff else BOULDER_SCANS.find(scan),
			"bare": BARE_ODDS.has(scan), "odds": BARE_ODDS.get(scan, 1.0),
		}
		if not cliff:
			var hull := item.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
			info.hull = hull.points
		_by_name[shape_name] = _shapes.size()
		_shapes.append(info)
	for shape_name: String in coarse:
		_shapes[_by_name[shape_name]].coarse = coarse[shape_name]
	scene.free()

func _make_materials() -> void:
	var weather := load("res://assets/generated/sky/cloud_weather.png")
	var moss := load("res://assets/generated/terrain/terrain_albedo.jpg")
	var grain := load("res://assets/generated/terrain/terrain_normal.jpg")
	_boulder_material = _material(SHADER, "boulder", BOULDER_GRADES, weather, moss, grain)
	_cliff_material = _material(CLIFF_SHADER, "cliff", CLIFF_GRADES, weather, moss, grain)

func _material(shader: Shader, prefix: String, grades: Array, weather: Texture2D, moss: TextureLayered,
		grain: TextureLayered) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("rock_albedo", load(DATA + prefix + "_albedo.jpg"))
	material.set_shader_parameter("rock_normal", load(DATA + prefix + "_normal.jpg"))
	material.set_shader_parameter("rock_rah", load(DATA + prefix + "_rah.jpg"))
	var padded: Array[Vector4] = []
	for grade: Vector4 in grades:
		padded.append(grade)
	padded.resize(8)
	material.set_shader_parameter("layer_grade", padded)
	material.set_shader_parameter("moss_albedo", moss)
	material.set_shader_parameter("grain_normal", grain)
	material.set_shader_parameter("cloud_weather", weather)
	# The heights the stones' feet are measured against, and the water level.
	terrain.share_fields(material)
	material.set_shader_parameter("water_absorption", WaterSystem.ABSORPTION)
	material.set_shader_parameter("water_scattering", WaterSystem.SCATTERING)
	return material

# --- stones ----------------------------------------------------------------------

func _pick(rng: RandomNumberGenerator, bare: bool) -> int:
	var total := 0.0
	for info: Dictionary in _shapes:
		if not info.cliff and info.bare == bare:
			total += info.odds
	var roll := rng.randf() * total
	for i in _shapes.size():
		var info: Dictionary = _shapes[i]
		if info.cliff or info.bare != bare:
			continue
		roll -= info.odds
		if roll <= 0.0:
			return i
	return 0

func _add_stone(box: AABB, place: String) -> void:
	var center := box.get_center()
	for zone in keep_clear:
		if Vector2(center.x - zone.x, center.z - zone.y).length() < zone.z:
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(center.x * 100.0), roundi(center.z * 100.0)))
	var water := terrain.water_level
	var mossy: bool = rng.randf() < MOSSY_ODDS[place] and box.position.y > water + 0.6
	var index := _pick(rng, not mossy)
	var info: Dictionary = _shapes[index]
	var size: Vector3 = info.size
	# The footprint of the blockout stone, and about its height.
	var s := sqrt(maxf(box.size.x * box.size.z, 0.01) / (size.x * size.z)) * rng.randf_range(0.9, 1.12)
	var sy := clampf(box.size.y / size.y, s * 0.7, s * 1.4)
	var ground := _ground_under(center, box.size * 0.45)
	var base := ground - 0.12 * size.y * sy
	# A stone that broke the surface keeps doing so where the bed now lies
	# deeper, if it can grow that far. One that would still end under water
	# (the old shoreline now lies metres deep) or stands in the bathing water
	# stays its size on the bed: a stretched pillar would be all it became.
	var top_wanted := minf(box.end.y, water + 0.35)
	if box.end.y > water + 0.1 and base + size.y * sy < top_wanted and not BATHING.has_point(Vector2(center.x, center.z)):
		var needed := (top_wanted - base) / size.y
		var grown_s := clampf(needed / 1.5, s, s * 2.0)
		var grown_sy := minf(needed, grown_s * 1.5)
		if ground + 0.88 * size.y * grown_sy > water - 0.3:
			s = grown_s
			sy = grown_sy
			base = ground - 0.12 * size.y * sy
	var lean := rng.randf() * TAU
	var tilt_axis := Vector3(cos(lean), 0.0, sin(lean))
	var tilt := deg_to_rad(rng.randf_range(0.0, 4.0 if mossy else 10.0))
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(tilt_axis, tilt) * Basis.from_scale(Vector3(s, sy, s))
	var xform := Transform3D(basis, Vector3(center.x, base, center.z))
	if placement.is_valid():
		xform = placement.call(xform, maxf(size.x, size.z) * s * 0.5)
	var moss: float = 0.25 if mossy else MOSS[place]
	_place_stone(index, xform, moss, rng.randf())

## The boulders' material, for stones drawn elsewhere (ForestLitter). An
## instance tells it the layer of its scan (its place in BOULDER_SCANS), how
## bare of moss it is and its tone, as _place_stone() does.
func boulder_material() -> ShaderMaterial:
	return _boulder_material

## One stone of shape `index` as drawn and as a collider.
func _place_stone(index: int, xform: Transform3D, moss: float, tone: float) -> void:
	var info: Dictionary = _shapes[index]
	var size: Vector3 = info.size
	_instance(index, xform, Color(info.layer, moss, tone, 0.0), maxf(size.x, size.z) * xform.basis.x.length())
	MeshUtil.add_hull(_body, xform, info.hull)
	stones.append({"shape": info.name, "xform": xform, "moss": moss, "tone": tone})
	stone_count += 1

## Lowest terrain under an ellipse of half-extents `reach` (x, z) around `at`.
func _ground_under(at: Vector3, reach: Vector3) -> float:
	var low := terrain.height_at(at.x, at.z)
	for k in 8:
		var a := k * TAU / 8.0
		low = minf(low, terrain.height_at(at.x + cos(a) * reach.x, at.z + sin(a) * reach.z))
	return low

func _add_cliff_face(face: Dictionary) -> void:
	var index: int = _by_name[face.scan]
	var info: Dictionary = _shapes[index]
	var turn := Basis(Vector3.UP, deg_to_rad(face.yaw))
	var xform := Transform3D(turn * Basis.from_scale(face.scale), face.at)
	# A face turned over is drawn as a mirrored copy of the mesh, set upright:
	# an instance of a MultiMesh that mirrors shows its triangles from behind.
	if face.scale.x < 0.0:
		_instance(_mirror_of(index), Transform3D(turn * Basis.from_scale(face.scale.abs()), face.at),
			Color(info.layer, 0.6, 0.5, 0.0), 1000.0)
	else:
		_instance(index, xform, Color(info.layer, 0.6, 0.5, 0.0), 1000.0)
	var coarse: Mesh = info.get("coarse", info.mesh)
	var holder := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(xform * coarse.get_faces())
	shape.backface_collision = true
	holder.shape = shape
	_body.add_child(holder)

## The shape that is `index` in a mirror (x turned over), made on first use.
func _mirror_of(index: int) -> int:
	var info: Dictionary = _shapes[index]
	if not info.has("mirror"):
		var source: Mesh = info.mesh
		var mesh := ArrayMesh.new()
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in points.size():
				points[i].x = -points[i].x
				normals[i].x = -normals[i].x
				tangents[i * 4] = -tangents[i * 4]
				tangents[i * 4 + 3] = -tangents[i * 4 + 3]
			var corners: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, corners.size(), 3):
				var held := corners[i + 1]
				corners[i + 1] = corners[i + 2]
				corners[i + 2] = held
			arrays[Mesh.ARRAY_VERTEX] = points
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = tangents
			arrays[Mesh.ARRAY_INDEX] = corners
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var copy := info.duplicate()
		copy.name = info.name + "~mirror"
		copy.mesh = mesh
		info.mirror = _shapes.size()
		_shapes.append(copy)
	return info.mirror

func _instance(shape: int, xform: Transform3D, custom: Color, reach: float) -> void:
	var tile := Vector2i(floori(xform.origin.x / TILE), floori(xform.origin.z / TILE))
	var key := "%d/%d/%d" % [shape, tile.x, tile.y]
	if not _groups.has(key):
		_groups[key] = {"shape": shape, "transforms": [], "customs": [], "reach": 0.0}
	var group: Dictionary = _groups[key]
	group.transforms.append(xform)
	group.customs.append(custom)
	group.reach = maxf(group.reach, reach)

func _build_multimeshes() -> void:
	for key: String in _groups:
		var group: Dictionary = _groups[key]
		var info: Dictionary = _shapes[group.shape]
		var multimesh := MeshUtil.custom_multimesh(info.mesh, group.transforms, group.customs)
		var item := MultiMeshInstance3D.new()
		item.name = "Rocks_" + key.replace("/", "_")
		item.multimesh = multimesh
		item.material_override = _cliff_material if info.cliff else _boulder_material
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Small stones go first; a 2 m boulder stays for about 200 m.
		if not info.cliff:
			item.visibility_range_end = clampf(60.0 + 70.0 * group.reach, 90.0, 420.0)
		add_child(item)
