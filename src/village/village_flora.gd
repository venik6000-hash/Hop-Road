class_name VillageFlora
extends Node3D
## The village's ground plants: scanned ferns, nettles, flowers, grass clumps
## and shrubs (Poly Haven, CC0, assets/models/flora) grown where they would
## be: against the houses' walls, along the brook's banks, on the verges of
## the lanes and loosely over the green between the yards. Placed once from a
## fixed seed, on open terrain only, and drawn as a MultiMesh per plant and
## tile. The engine picks one mesh LOD and one visibility for a whole
## MultiMesh, from its nearest point and its centre: the tiles are small so
## that only the plants round the walker are drawn in full.

const ImageUtil = preload("res://src/common/image_util.gd")
const DIRECTORY := "res://assets/models/flora/"
const SHADER := preload("res://src/village/village_foliage.gdshader")
const TILE := 16.0
## How far a plant shows (m) unless it names its own `view`: about where the
## grass blades end, beyond which a knee-high plant is a few pixels.
const VIEW := 42.0
## Plant: model, variants no heavier than `tris`, scale range, sway, shadow.
const PLANTS := {
	"fern": {"model": "fern_02", "tris": 2400, "scale": Vector2(0.8, 1.5), "sway": 0.05},
	"nettle": {"model": "nettle_plant", "tris": 6000, "scale": Vector2(3.5, 6.0), "sway": 0.3},
	"periwinkle": {"model": "periwinkle_plant", "tris": 5400, "scale": Vector2(1.0, 1.5), "sway": 0.08},
	"dandelion": {"model": "dandelion_01", "tris": 3200, "scale": Vector2(1.0, 1.6), "sway": 0.1},
	"celandine": {"model": "celandine_01", "tris": 4400, "scale": Vector2(1.1, 1.8), "sway": 0.1},
	"weed": {"model": "weed_plant_02", "tris": 3000, "scale": Vector2(1.2, 2.2), "sway": 0.05},
	"tuft": {"model": "grass_medium_01", "tris": 2400, "least": 250, "scale": Vector2(1.6, 2.8), "sway": 0.25},
	"tall_grass": {"model": "grass_medium_02", "tris": 2500, "scale": Vector2(1.3, 2.3), "sway": 0.2},
	"sprig": {"model": "shrub_03", "tris": 2400, "scale": Vector2(1.6, 2.6), "sway": 0.12},
	"shrub": {"model": "shrub_02", "tris": 9500, "scale": Vector2(0.75, 1.25), "sway": 0.02, "shadow": true,
		"view": 70.0},
}
## What grows where, by relative odds.
const MIXES := {
	"wall": {"nettle": 3.0, "tall_grass": 3.0, "fern": 2.0, "tuft": 2.0, "periwinkle": 1.5, "weed": 1.0,
		"celandine": 1.0, "sprig": 1.0, "shrub": 0.45},
	"bank": {"fern": 3.5, "tall_grass": 3.0, "tuft": 2.0, "celandine": 1.5, "periwinkle": 1.2, "nettle": 1.0,
		"sprig": 1.0, "shrub": 0.35},
	"verge": {"tuft": 3.0, "dandelion": 2.5, "celandine": 2.0, "weed": 2.0, "tall_grass": 1.5, "periwinkle": 0.8},
	"green": {"tuft": 3.0, "tall_grass": 2.5, "celandine": 1.5, "dandelion": 1.5, "periwinkle": 1.0, "fern": 0.8,
		"sprig": 1.0, "shrub": 0.5},
}
## The village green the loose plants cover (x, z).
const GREEN := Rect2(-34.0, -90.0, 66.0, 74.0)

var terrain: TerrainSystem
## The region's village plan (VillageLayout.read_plan): its lanes stay bare.
var village_plan: Dictionary
var map: Node3D
var plant_count := 0
var ready_for_visitors := false
var auto_grow := true

var _variants := {}   # plant -> [{mesh, base: Transform3D}]
var _batches := {}    # "plant/variant/tile" -> {mesh, plant, origin, poses, tones}
var _houses: Array[Dictionary] = []   # {inverse: Transform3D, box: AABB}
var _lanes: Array = []
var _control: Image
var _mask_origin := Vector2.ZERO
var _mask_cell := 1.0

func _ready() -> void:
	# After every building, stone and prop has its collider.
	if auto_grow:
		_grow.call_deferred()

func _grow() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start := Time.get_ticks_usec()
	_load_plants()
	var config: Dictionary = terrain.meta.masks
	_mask_origin = Vector2(config.origin[0], config.origin[1])
	_mask_cell = config.cell
	_control = ImageUtil.rgba8(terrain.material.get_shader_parameter("near_control"))
	var paths: Array = village_plan.paths
	_lanes = paths.duplicate()
	_lanes.append({"points": village_plan.main_road})
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		if RockField.label_of(item).ends_with("limewashed rooms"):
			_houses.append({"inverse": item.global_transform.affine_inverse(), "pose": item.global_transform,
				"box": item.get_aabb()})
	var rng := RandomNumberGenerator.new()
	rng.seed = 4102026
	_grow_walls(rng)
	_grow_banks(rng)
	_grow_verges(rng)
	_grow_green(rng)
	_build()
	ready_for_visitors = true
	print("FLORA plants=%d batches=%d houses=%d load=%.2fs" % [plant_count, _batches.size(), _houses.size(),
		(Time.get_ticks_usec() - start) / 1e6])

func _load_plants() -> void:
	for plant: String in PLANTS:
		var spec: Dictionary = PLANTS[plant]
		var scene := (load("%s%s/%s_1k.gltf" % [DIRECTORY, spec.model, spec.model]) as PackedScene).instantiate()
		var list := []
		for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var faces := 0
			for surface in item.mesh.get_surface_count():
				faces += (item.mesh as ArrayMesh).surface_get_array_index_len(surface) / 3
			if faces > int(spec.tris) or faces < int(spec.get("least", 0)):
				continue
			# Each variant stands on its own base point, whatever its place in the scan sheet.
			var basis := item.transform.basis
			var box := Transform3D(basis, Vector3.ZERO) * item.mesh.get_aabb()
			var centre := box.get_center()
			var mesh := item.mesh.duplicate() as ArrayMesh
			for surface in mesh.get_surface_count():
				var old := mesh.surface_get_material(surface) as BaseMaterial3D
				var material := ShaderMaterial.new()
				material.shader = SHADER
				if old != null:
					material.set_shader_parameter("albedo_map", old.albedo_texture)
					material.set_shader_parameter("normal_map", old.normal_texture)
				material.set_shader_parameter("sway", spec.sway)
				mesh.surface_set_material(surface, material)
			if list.size() >= 3:
				break
			list.append({"mesh": mesh, "base": Transform3D(basis, -Vector3(centre.x, box.position.y, centre.z))})
		_variants[plant] = list
		scene.free()

# --- where ---------------------------------------------------------------------

## Against the walls: a skirt of weeds a step wide, thickest at the corners
## and the back, thin where a lane comes to the house.
func _grow_walls(rng: RandomNumberGenerator) -> void:
	for house: Dictionary in _houses:
		var box: AABB = house.box
		var pose: Transform3D = house.pose
		var lo := Vector2(box.position.x, box.position.z)
		var hi := Vector2(box.end.x, box.end.z)
		var corners := [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]
		for side in 4:
			var a: Vector2 = corners[side]
			var b: Vector2 = corners[(side + 1) % 4]
			var out := (b - a).normalized().orthogonal() * -1.0
			if out.dot((a + b) * 0.5 - (lo + hi) * 0.5) < 0.0:
				out = -out
			var count := int(a.distance_to(b) * 5.5)
			for k in count:
				var along := rng.randf()
				var corner := absf(along - 0.5) * 2.0
				if rng.randf() > 0.45 + 0.55 * corner:
					continue
				var local := a.lerp(b, along) + out * (0.45 + absf(rng.randfn(0.0, 0.45)))
				var world := pose * Vector3(local.x, box.position.y, local.y)
				_plant("wall", Vector2(world.x, world.z), rng, 1.0 + 0.3 * corner)

## Along the brook: ferns and grass at the water's edge, thinning up the bank.
func _grow_banks(rng: RandomNumberGenerator) -> void:
	var rows := terrain.course(VillageBrook.BROOK)
	for index in range(2, rows.size() - 6):
		var at: Vector3 = rows[index].at
		var next: Vector3 = rows[index + 1].at
		var ahead := Vector2(next.x - at.x, next.z - at.z).normalized()
		var side := ahead.orthogonal()
		var half: float = rows[index].half
		for hand: float in [-1.0, 1.0]:
			for k in 5:
				if rng.randf() > 0.62:
					continue
				var reach := half + 0.55 + absf(rng.randfn(0.0, 1.1))
				_plant("bank", Vector2(at.x, at.z) + side * hand * reach + ahead * rng.randf_range(-0.25, 0.25), rng, 1.0)

## The verges of the lanes: flowers and tufts a little off the trodden ground.
func _grow_verges(rng: RandomNumberGenerator) -> void:
	for lane: Dictionary in _lanes:
		var points: Array = lane.points
		for i in range(points.size() - 1):
			var a := Vector2(points[i][0], points[i][1])
			var b := Vector2(points[i + 1][0], points[i + 1][1])
			var side := (b - a).normalized().orthogonal()
			for k in int(a.distance_to(b) * 2.6):
				var hand := 1.0 if rng.randf() < 0.5 else -1.0
				_plant("verge", a.lerp(b, rng.randf()) + side * hand * rng.randf_range(1.7, 3.6), rng, 0.85)

## The green between the yards, in drifts rather than evenly.
func _grow_green(rng: RandomNumberGenerator) -> void:
	for drift in 300:
		var centre := GREEN.position + Vector2(rng.randf(), rng.randf()) * GREEN.size
		var spread := rng.randf_range(1.2, 3.8)
		for k in rng.randi_range(5, 13):
			_plant("green", centre + Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread)), rng, 1.0)

# --- one plant -------------------------------------------------------------------

func _plant(mix: String, at: Vector2, rng: RandomNumberGenerator, vigour: float) -> void:
	# Roll first: the stream of numbers stays the same whatever the ground says.
	var roll := rng.randf()
	var grow := rng.randf()
	var yaw := rng.randf() * TAU
	var pick := rng.randi()
	var tone := Color.from_hsv(rng.randf_range(0.2, 0.3), rng.randf_range(0.0, 0.16), rng.randf_range(0.8, 1.0))
	var plant := _pick(MIXES[mix], roll)
	var shrub: bool = plant == "shrub"
	if not _open(at, 0.9 if shrub else 0.25, mix == "bank"):
		return
	var list: Array = _variants[plant]
	if list.is_empty():
		return
	var variant: Dictionary = list[pick % list.size()]
	var spec: Dictionary = PLANTS[plant]
	var size: float = lerpf(spec.scale.x, spec.scale.y, grow) * vigour
	var y := terrain.height_at(at.x, at.y) - 0.03
	var pose := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(at.x, y, at.y)) * (variant.base as Transform3D)
	var tile := Vector2i(floori(at.x / TILE), floori(at.y / TILE))
	var key := "%s/%d/%s" % [plant, pick % list.size(), tile]
	if not _batches.has(key):
		_batches[key] = {"mesh": variant.mesh, "plant": plant, "origin": Vector3(tile.x * TILE, 0.0, tile.y * TILE),
			"poses": [], "tones": []}
	var batch: Dictionary = _batches[key]
	pose.origin -= batch.origin
	var poses: Array = batch.poses
	var tones: Array = batch.tones
	poses.append(pose)
	tones.append(tone)
	plant_count += 1

func _pick(odds: Dictionary, roll: float) -> String:
	var total := 0.0
	for plant: String in odds:
		total += odds[plant]
	roll *= total
	for plant: String in odds:
		roll -= odds[plant]
		if roll <= 0.0:
			return plant
	return odds.keys()[0]

## Open ground: dry land off the lanes, the paving, the water and the houses.
func _open(at: Vector2, clear: float, bank: bool) -> bool:
	if terrain.height_at(at.x, at.y) < terrain.water_level + 0.25:
		return false
	var cell := Vector2i(((at - _mask_origin) / _mask_cell).round())
	if cell.x < 0 or cell.y < 0 or cell.x >= _control.get_width() or cell.y >= _control.get_height():
		return false
	var control := _control.get_pixelv(cell)
	if control.r > 0.35 or (control.g > 0.55 and not bank):
		return false
	for row: Dictionary in terrain.course(VillageBrook.BROOK):
		if Vector2(row.at.x - at.x, row.at.z - at.y).length() < float(row.half) + 0.2 + clear * 0.5:
			return false
	for lane: Dictionary in _lanes:
		var points: Array = lane.points
		for i in range(points.size() - 1):
			var near := Geometry2D.get_closest_point_to_segment(at, Vector2(points[i][0], points[i][1]),
				Vector2(points[i + 1][0], points[i + 1][1]))
			if near.distance_to(at) < 1.25 + clear:
				return false
	for house: Dictionary in _houses:
		var local: Vector3 = (house.inverse as Transform3D) * Vector3(at.x, 0.0, at.y)
		var box: AABB = house.box
		if local.x > box.position.x - 0.2 and local.x < box.end.x + 0.2 and local.z > box.position.z - 0.2 and local.z < box.end.z + 0.2:
			return false
	# Nothing but the terrain underfoot: no paving, steps, stones or props.
	var y := terrain.height_at(at.x, at.y)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x, y + 12.0, at.y), Vector3(at.x, y - 0.4, at.y), PhysicsLayers.GROUND)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.collider != null and String(hit.collider.name).begins_with("TerrainBody")

func _build() -> void:
	for batch: Dictionary in _batches.values():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = batch.mesh
		var poses: Array = batch.poses
		multimesh.instance_count = poses.size()
		for i: int in poses.size():
			multimesh.set_instance_transform(i, poses[i])
			multimesh.set_instance_color(i, batch.tones[i])
		var node := MultiMeshInstance3D.new()
		node.name = "Flora_%s" % batch.plant
		node.multimesh = multimesh
		node.position = batch.origin
		var spec: Dictionary = PLANTS[batch.plant]
		node.visibility_range_end = spec.get("view", VIEW)
		node.visibility_range_end_margin = 8.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# With the trees and the grass: lamps leave swaying plants out of their
		# shadow maps, which they would otherwise draw again in every frame.
		node.layers = VegetationSystem.VISUAL_LAYER
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec.get("shadow", false) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
