extends RefCounted
## The drowned boulders of LakeBed (static functions over the LakeBed node
## `lake`, drawing from its random numbers).
const Ground = preload("res://src/wildlife/lake_bed_ground.gd")
const MeshUtil = preload("res://src/common/mesh_util.gd")

## Groups of drowned boulders, as the glacier left them: a big stone with a
## few smaller ones around it, set into the silt by their lowest edge. They
## are the scans of the valley's shore stones, worn wet and filmed under
## water (rock.gdshaderinc lake_film).
static func place(lake: LakeBed) -> void:
	var library := lake.habitat.rocks
	var temporary := library == null
	if temporary:
		library = RockField.new()
		library.terrain = lake.habitat.terrain
		library.load_shapes()
		library.make_materials()
	# Real boulders only: the pebble scans would be blown up tenfold and
	# their photographs smeared over metres of stone, and the flat slabs
	# read as boxes once silt lies on them. Half are the mossy sets, whose
	# moss reads as the water moss and algae of a drowned stone.
	var bare: Array[Dictionary] = []
	var mossy: Array[Dictionary] = []
	for info: Dictionary in library.shapes:
		var size: Vector3 = info.size
		var across := maxf(size.x, size.z)
		if not info.cliff and across > 1.0 and size.y > across * 0.38:
			(bare if info.bare else mossy).append(info)
	for attempt in LakeBed.BOULDERS.groups * 10:
		if lake.boulder_places.size() >= LakeBed.BOULDERS.groups:
			break
		var center := Ground.random_point(lake)
		var depth := Ground.depth(lake, center)
		if depth < LakeBed.BOULDERS.depth.x or depth > LakeBed.BOULDERS.depth.y or Ground.slope(lake, center) > 0.7:
			continue
		if not Ground.free_of_others(center, lake.boulder_places, 9.0):
			continue
		var width := lake.rng.randf_range(LakeBed.BOULDERS.width.x, LakeBed.BOULDERS.width.y)
		if not _boulder(lake, bare if lake.rng.randf() < 0.5 else mossy, center, width):
			continue
		lake.boulder_places.append(Vector3(center.x, lake.habitat.terrain.height_at(center.x, center.z), center.z))
		for index in lake.rng.randi_range(LakeBed.BOULDERS.satellites.x, LakeBed.BOULDERS.satellites.y):
			var small := lake.rng.randf_range(LakeBed.BOULDERS.satellite_width.x, LakeBed.BOULDERS.satellite_width.y)
			var angle := lake.rng.randf_range(0, TAU)
			var reach := width * 0.45 + small * 0.4 + lake.rng.randf_range(0.1, 1.6)
			_boulder(lake, bare if lake.rng.randf() < 0.5 else mossy, center + Vector3(cos(angle), 0, sin(angle)) * reach, small)
	for key: String in lake.boulder_groups:
		var group: Dictionary = lake.boulder_groups[key]
		var mesh: Mesh = group.mesh
		var multi := MeshUtil.custom_multimesh(mesh, Values.list(group.transforms), Values.list(group.customs))
		var outcrop := MultiMeshInstance3D.new()
		outcrop.name = "LakeBoulders_" + key.replace("/", "_")
		outcrop.multimesh = multi
		outcrop.material_override = library.boulder_material()
		outcrop.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		outcrop.visibility_range_end = 120
		outcrop.visibility_range_end_margin = 14
		outcrop.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		lake.add_child(outcrop)
	if temporary:
		library.free()

## One boulder about `width` across at `at`: its lowest edge pressed into the
## bed, its top kept under the surface. False where there is no room.
static func _boulder(lake: LakeBed, available: Array[Dictionary], at: Vector3, width: float) -> bool:
	var info: Dictionary = available[lake.rng.randi_range(0, available.size() - 1)]
	var size: Vector3 = info.size
	var s := width / maxf(size.x, size.z)
	var sy := s * lake.rng.randf_range(0.75, 1.2)
	var ground := Ground.lowest_ground(lake, at, maxf(size.x, size.z) * s * 0.45)
	if Ground.depth(lake, at) < 0.9 or is_nan(Ground.bed_at(lake, at.x, at.z, false)):
		return false
	var embed := lake.rng.randf_range(0.12, 0.25)
	# Lower the stone rather than let it reach the surface.
	var room := lake.habitat.terrain.water_level - LakeBed.CLEARANCE - ground
	if size.y * sy * (1.0 - embed) > room:
		sy = room / (size.y * (1.0 - embed))
		if sy < s * 0.45:
			return false
	var lean := lake.rng.randf_range(0, TAU)
	var tilt := deg_to_rad(lake.rng.randf_range(0.0, 8.0))
	var basis := Basis(Vector3.UP, lake.rng.randf_range(0, TAU)) * Basis(Vector3(cos(lean), 0, sin(lean)), tilt) * Basis.from_scale(Vector3(s, sy, s))
	var transform := Transform3D(basis, Vector3(at.x, ground - embed * size.y * sy, at.z))
	var tile := Vector2i(floori(at.x / 48.0), floori(at.z / 48.0))
	var key := "%s/%d/%d" % [info.name, tile.x, tile.y]
	if not lake.boulder_groups.has(key):
		lake.boulder_groups[key] = {"mesh": info.mesh, "transforms": [], "customs": []}
	var group: Dictionary = lake.boulder_groups[key]
	var transforms: Array = group.transforms
	var customs: Array = group.customs
	transforms.append(transform)
	# Moss only grows above the water; the film and silt come from the shader.
	customs.append(Color(Values.real(info.layer), 0.25, lake.rng.randf(), 0))
	var hull: PackedVector3Array = info.hull
	MeshUtil.add_hull(lake.solid, transform, hull)
	lake.rock_count += 1
	return true
