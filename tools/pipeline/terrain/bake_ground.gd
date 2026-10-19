extends "res://tools/lib/tool_script.gd"
## Bakes the settled ground of a region (ground_bake.gd): its near heights
## with the rocks, buildings and water courses laid in, its masks with the
## beds, yards and worn ground painted in, and the manifest with the courses
## and the key (TerrainBake reads them in the game). A bake whose key is
## current is left alone; pass `-- --force` to bake anyway. The region is the
## first of the game's list (RegionDef.LIST); `-- --region=<id>` bakes another
## region of the list, `-- --region=res://...tres` a region that is not in it.
##
##   tools/run/godot_lock.sh "$GODOT" --headless --path . --script res://tools/lib/tool_runner.gd -- res://tools/pipeline/terrain/bake_ground.gd
##
## After writing, the files are read back as the game reads them and must give
## the same heights, courses and masks.

const GroundBake = preload("res://tools/pipeline/terrain/ground_bake.gd")

func _initialize() -> void:
	var force := false
	var named := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--force":
			force = true
		elif argument.begins_with("--region="):
			named = argument.trim_prefix("--region=")
	quit(_bake(region_named(named), force))

## The region `named` names: a RegionDef file, an id of the game's list, or
## the first region of the list when empty. Null for an id the list lacks.
static func region_named(named: String) -> RegionDef:
	if named.begins_with("res://"):
		return load(named) as RegionDef
	for entry: Dictionary in RegionDef.entries():
		if named.is_empty() or str(entry.id) == named:
			return load(str(entry.region)) as RegionDef
	return null

func _bake(region: RegionDef, force: bool) -> int:
	if region == null:
		push_error("TERRAIN_GROUND_BAKE no region")
		return 1
	# A region that reads another's bake (the test's stub) must not overwrite it.
	for other: RegionDef in RegionDef.listed():
		if other.id != region.id and not _shared(region, other).is_empty():
			push_error("TERRAIN_GROUND_BAKE %s names the bake of %s: %s" % [region.id, other.id, _shared(region, other)])
			return 1
	var key := GroundBake.key(region)
	if key.is_empty():
		push_error("TERRAIN_GROUND_BAKE an input of %s is missing: %s" % [region.id, GroundBake.inputs(region)])
		return 1
	if not force and GroundBake.problems(region).is_empty():
		print("TERRAIN_GROUND_BAKE up-to-date region=%s key=%s" % [region.id, key.left(12)])
		return 0
	var start := Time.get_ticks_usec()
	var settled := GroundBake.settle(region)
	var settle_msec := (Time.get_ticks_usec() - start) / 1000.0
	var error := GroundBake.write(region, settled)
	if error != OK:
		push_error("TERRAIN_GROUND_BAKE cannot write: %s" % error_string(error))
		return 1
	start = Time.get_ticks_usec()
	var read_back := FileAccess.get_file_as_bytes(region.settled_heights)
	var saved: Dictionary = TerrainBake.read_manifest(region)
	var courses := TerrainBake.courses_of(saved)
	var masks := TerrainBake.read_masks(region, saved)
	var read_msec := (Time.get_ticks_usec() - start) / 1000.0
	var image: Image = settled.image
	var amiss := PackedStringArray()
	if read_back != image.get_data():
		amiss.append("heights")
	var cut: Dictionary = settled.courses
	for course_name: StringName in cut:
		if not courses.has(course_name) or courses[course_name] != cut[course_name]:
			amiss.append(course_name)
	for mask: String in ["control", "extra", "wear", "cinder"]:
		var made: Image = settled.get(mask)
		var read: Image = masks.get(mask)
		if (made == null) != (read == null) or (made != null and made.get_data() != read.get_data()):
			amiss.append(mask)
	amiss.append_array(GroundBake.problems(region))
	if not amiss.is_empty():
		push_error("TERRAIN_GROUND_BAKE read back differs: %s" % ", ".join(amiss))
		return 1
	print("TERRAIN_GROUND_BAKE region=%s size=%d courses=%s masks=%s key=%s settle=%.0fms read=%.0fms" % [region.id,
		image.get_width(), courses.keys(), masks.keys(), key.left(12), settle_msec, read_msec])
	return 0

## The files of the bake that `region` and `other` both name.
static func _shared(region: RegionDef, other: RegionDef) -> PackedStringArray:
	var shared := PackedStringArray()
	for path: String in [region.settled_heights, region.settled_masks, region.settled_ground]:
		if path in [other.settled_heights, other.settled_masks, other.settled_ground]:
			shared.append(path)
	return shared
