extends Node3D
## Authored yards plus deterministic, batched forest details from the local pack.
const CollisionCache = preload("res://src/village/prop_collision_cache.gd")
const ImageUtil = preload("res://src/common/image_util.gd")
const LayoutStore = preload("res://src/layout/layout_store.gd")
const DIRECTORY := "res://assets/models/village_pack/"
const ACTOR = preload("res://src/wildlife/pack_animal.gd")
const FOLIAGE = preload("res://src/village/pack_foliage.gdshader")
const OutdoorScan = preload("res://src/render/outdoor_scan.gd")
## The forest floor's scans whose leaves are cut out of cards; the rest are solid.
const FOREST_LEAVES: Array[String] = ["fern", "clover"]
## Convex colliders of the solid forest pieces, baked by
## tools/pipeline/village_pack/bake_hulls.gd. Building them at load reads the
## mesh back from the GPU, which can time out on Metal while the level loads.
const HULL := "res://assets/generated/village_pack/%s_hull.tres"
const SOLID_FOREST: Array[String] = ["stump", "log", "roots"]
## Side of a forest batch (m). The engine picks one mesh LOD and one
## visibility for a whole MultiMesh, so small cells keep the full scans to
## the ground round the walker.
const FOREST_CELL := 12.0
## How far the forest floor's small scans and its wood show (m).
const FOREST_VIEW := 45.0
const FOREST_WOOD_VIEW := 80.0
const FOREST_WOOD: Array[String] = ["stump", "log", "roots", "branch"]
var terrain: TerrainSystem
var player: Player
var removed_labels: Array[String] = []
var props: Array[Node3D] = []
var animals: Array[Node3D] = []
var forest_instances := 0
var forest_ready := false
## The forest's stumps, logs, roots and branches as they lie: {asset, xform}.
## The layout bake writes them to LayoutStore.FOREST_WOOD; once that file is
## there, the wood comes from it and the scatter lays only the plants.
var forest_wood: Array[Dictionary] = []
var _scenes := {}
var _collision_cache := CollisionCache.new()
static var _prefetched_scenes: Dictionary[String, PackedScene] = {}
var _forest_batches := {}
var _forest_shapes := {}
var _forest_meshes := {}

## Keep loading on the main thread: asset workers can deadlock on Godot 4.7.2.
## The callback reports completed models and returns false to cancel loading.
static func prefetch_assets(tree: SceneTree, progress: Callable) -> bool:
	discard_prefetch()
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "layout.json"))
	if not layout is Array:
		return false
	var assets := {}
	for entry: Dictionary in layout:
		assets[entry.asset] = true
	for asset: String in ["fern", "clover", "bracken", "stump", "roots", "branch", "log"]:
		assets[asset] = true
	var completed := 0
	for asset: String in assets:
		if not progress.is_valid() or not progress.call(completed, assets.size()):
			discard_prefetch()
			return false
		var path := DIRECTORY + asset + ".glb"
		var scene := load(path) as PackedScene
		if scene == null:
			discard_prefetch()
			return false
		_prefetched_scenes[asset] = scene
		completed += 1
		await tree.process_frame
	if not progress.is_valid() or not progress.call(completed, assets.size()):
		discard_prefetch()
		return false
	return true

static func discard_prefetch() -> void:
	_prefetched_scenes.clear()

## The loader finished warming these scenes before instantiating the world.
func wait_for_prefetch() -> void:
	_scenes.merge(_prefetched_scenes, true)
	discard_prefetch()

func install(map: Node3D, scatter := true) -> void:
	_prepare_map(map)
	for entry: Dictionary in _layout():
		_place(entry)
	_finish_install(scatter)

func _layout() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "layout.json"))

func _prepare_map(map: Node3D) -> void:
	for item: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var label := RockField.label_of(item)
		var group: String = str(item.get_meta("extras", {}).get("alpine_group", ""))
		if group == "31":
			removed_labels.append(label)
			item.get_parent().remove_child(item)
			item.queue_free()
	_paint_working_ground()

func _finish_install(scatter := true) -> void:
	# Wait for all building/tree colliders before sampling the forest floor.
	if scatter:
		_scatter_forest.call_deferred()
	print("VILLAGE_PACK removed=%d props=%d" % [removed_labels.size(), props.size()])

func _paint_working_ground() -> void:
	# The same control texture drives earth materials, grass and tree placement.
	# Stamp softly worn yards and links to the lane, with irregular edges.
	var image := ImageUtil.rgba8(terrain.material.get_shader_parameter("near_control"))
	var config: Dictionary = terrain.meta.masks
	var origin := Vector2(config.origin[0], config.origin[1])
	var cell: float = config.cell
	var yards := [Vector4(9, -31, 5.0, 3.8), Vector4(17, -41, 6.0, 5.0),
		Vector4(23, -33, 5.5, 6.0), Vector4(14, -61.5, 4.4, 4.4),
		Vector4(1, -19, 2.8, 3.4), Vector4(3, -30, 4.5, 1.4),
		Vector4(10, -36, 1.5, 5.0), Vector4(20, -37, 4.0, 1.5)]
	for yard in yards:
		var centre := Vector2(yard.x, yard.y)
		var reach := Vector2(yard.z, yard.w)
		var lo := Vector2i(((centre - reach * 1.2 - origin) / cell).floor())
		var hi := Vector2i(((centre + reach * 1.2 - origin) / cell).ceil())
		for iz in range(maxi(0, lo.y), mini(image.get_height(), hi.y + 1)):
			for ix in range(maxi(0, lo.x), mini(image.get_width(), hi.x + 1)):
				var point := origin + Vector2(ix, iz) * cell
				var distance := ((point - centre) / reach).length()
				distance += sin(point.x * 1.7) * cos(point.y * 1.3) * 0.055
				var wear := 1.0 - smoothstep(0.72, 1.12, distance)
				var color := image.get_pixel(ix, iz)
				color.r = maxf(color.r, wear)
				color.b *= 1.0 - wear
				color.a *= 1.0 - wear
				image.set_pixel(ix, iz, color)
	terrain.material.set_shader_parameter("near_control", ImageTexture.create_from_image(image))

func _scene(key: String) -> PackedScene:
	if not _scenes.has(key):
		_scenes[key] = load(DIRECTORY + key + ".glb")
	return _scenes[key]

func _place(entry: Dictionary) -> Node3D:
	var item := _scene(entry.asset).instantiate() as Node3D
	item.name = entry.name
	item.set_meta("pack_asset", entry.asset)
	item.set_meta("zone", entry.zone)
	var x: float = entry.x
	var z: float = entry.z
	item.position = Vector3(x, terrain.height_at(x, z) + float(entry.get("lift", 0.0)), z)
	item.rotation.y = deg_to_rad(entry.get("yaw", 0.0))
	# A prop leant by hand in the layout scene: degrees about x and z.
	var tilt: Array = entry.get("tilt", [0.0, 0.0])
	item.rotation.x = deg_to_rad(tilt[0])
	item.rotation.z = deg_to_rad(tilt[1])
	item.scale = Vector3.ONE * float(entry.size)
	add_child(item)
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		# A basket stops mattering long before a cart does: by the prop's size.
		var extent: float = (mesh.global_transform.basis * mesh.get_aabb().size).length()
		mesh.visibility_range_end = clampf(45.0 + extent * 22.0, 55.0, 110.0)
		mesh.visibility_range_end_margin = 12.0
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if entry.asset == "well":
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if material != null and material.resource_name == "Material_7":
					var water := material.duplicate() as StandardMaterial3D
					water.albedo_color = Color("182c28")
					water.metallic = 0.0
					water.roughness = 0.2
					mesh.set_surface_override_material(surface, water)
		if entry.get("solid", true):
			var body := StaticBody3D.new()
			body.name = mesh.name + "_col"
			var holder := CollisionShape3D.new()
			holder.shape = _collision_cache.shape(entry.asset, str(item.get_path_to(mesh)), mesh.mesh)
			body.add_child(holder)
			mesh.add_child(body)
	props.append(item)
	return item

func _scatter_forest() -> void:
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 3102026
	# Trail shoulders east/south of the village, away from the lake and yards.
	var habitats := [Vector2(38, 20), Vector2(55, -35), Vector2(32, -78), Vector2(-35, 35), Vector2(10, 52)]
	var placed := LayoutStore.placed(LayoutStore.FOREST_WOOD)
	for zone in habitats:
		for index in 85:
			var point: Vector2 = zone + Vector2.from_angle(rng.randf_range(0, TAU)) * sqrt(rng.randf()) * 19.0
			var y := terrain.height_at(point.x, point.y)
			if y < terrain.water_level + 1.0:
				continue
			var slope := Vector2(terrain.height_at(point.x + 0.6, point.y) - y,
				terrain.height_at(point.x, point.y + 0.6) - y).length() / 0.6
			if slope > 0.5:
				continue
			var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, y + 20, point.y), Vector3(point.x, y - 0.3, point.y), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or not String(hit.collider.name).begins_with("TerrainBody"):
				continue
			var asset: String = ["fern", "clover", "bracken"][index % 3]
			var size := rng.randf_range(0.55, 1.05)
			if index % 13 == 0:
				asset = ["stump", "roots", "branch", "log"][(index / 13) % 4]
				size = rng.randf_range(1.1, 2.5)
			var pose := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * size), Vector3(point.x, y - 0.045, point.y))
			if asset in FOREST_WOOD:
				if not placed.is_empty():
					continue
				forest_wood.append({"asset": asset, "xform": pose})
			_batch(asset, pose)
	for entry: Dictionary in placed:
		if entry.asset in FOREST_WOOD:
			var pose := LayoutStore.unpack(entry.xform)
			forest_wood.append({"asset": entry.asset, "xform": pose})
			_batch(entry.asset, pose)
	for batch: Dictionary in _forest_batches.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = batch.mesh
		mm.instance_count = batch.poses.size()
		for i in batch.poses.size():
			mm.set_instance_transform(i, batch.poses[i])
		var node := MultiMeshInstance3D.new()
		node.name = "Forest_" + batch.asset
		node.multimesh = mm
		node.position = batch.origin
		node.visibility_range_end = FOREST_WOOD_VIEW if batch.asset in FOREST_WOOD else FOREST_VIEW
		node.visibility_range_end_margin = 12.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	forest_ready = true
	print("PACK_FOREST instances=%d batches=%d" % [forest_instances, _forest_batches.size()])

## One mesh per asset, shared by every cell's MultiMesh: a copy per cell would
## hold the same vertex buffers many times over.
func _forest_mesh(asset: String) -> Dictionary:
	var source := _scene(asset).instantiate() as Node3D
	var instance: MeshInstance3D = source.find_children("*", "MeshInstance3D", true, false)[0]
	var transform := instance.transform
	var parent := instance.get_parent()
	while parent != source:
		transform = parent.transform * transform
		parent = parent.get_parent()
	var mesh := instance.mesh.duplicate() as ArrayMesh
	# Every scan takes the light of the ground it lies on, whatever material
	# it came with: some are unlit photogrammetry.
	for i in mesh.get_surface_count():
		var old := mesh.surface_get_material(i) as StandardMaterial3D
		if old == null or old.albedo_texture == null:
			continue
		if asset not in FOREST_LEAVES:
			# Bracken soaks as leaves do and takes no shine from the rain; dead
			# wood a little: a wet mirror of the whole sky on it stands pale
			# in the dim light under a closed one.
			mesh.surface_set_material(i, OutdoorScan.material(old, 0.0 if asset == "bracken" else 0.3))
			continue
		var mat := ShaderMaterial.new()
		mat.shader = FOLIAGE
		mat.set_shader_parameter("albedo_map", old.albedo_texture)
		mat.set_shader_parameter("tint", old.albedo_color)
		mat.set_shader_parameter("cloud_weather", load("res://assets/generated/sky/cloud_weather.png"))
		mesh.surface_set_material(i, mat)
	source.free()
	return {"mesh": mesh, "transform": transform}

func _forest_hull(asset: String, mesh: Mesh) -> Shape3D:
	var path := HULL % asset
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("Forest hull %s is not baked; building it from the mesh" % asset)
	return mesh.create_convex_shape(true, true)

func _batch(asset: String, pose: Transform3D) -> void:
	var cell := Vector2i(floori(pose.origin.x / FOREST_CELL), floori(pose.origin.z / FOREST_CELL))
	var key := "%s_%s" % [asset, cell]
	if not _forest_batches.has(key):
		if not _forest_meshes.has(asset):
			_forest_meshes[asset] = _forest_mesh(asset)
		var shared: Dictionary = _forest_meshes[asset]
		_forest_batches[key] = {"asset": asset, "mesh": shared.mesh, "transform": shared.transform, "poses": [], "origin": Vector3(cell.x * FOREST_CELL, 0, cell.y * FOREST_CELL)}
	var batch: Dictionary = _forest_batches[key]
	pose.origin -= batch.origin
	batch.poses.append(pose * batch.transform)
	if asset in SOLID_FOREST:
		if not _forest_shapes.has(asset):
			_forest_shapes[asset] = _forest_hull(asset, batch.mesh)
		var body := StaticBody3D.new()
		body.name = "ForestSolid_" + asset + str(forest_instances)
		var holder := CollisionShape3D.new()
		holder.shape = _forest_shapes[asset]
		body.add_child(holder)
		var world_pose := pose
		world_pose.origin += batch.origin
		body.transform = world_pose * batch.transform
		add_child(body)
	forest_instances += 1

func populate_life(population: NpcPopulation) -> void:
	for entry in [
		["dog", Vector2(3.0, 6.5), 0.65, "0|standing_0", 0.0],
		["horse", Vector2(23, -35), 1.7, "Skeleton|6 Eat", 0.0],
		["goat", Vector2(20, -61), 0.95, "rigAction", 0.0],
		["goat", Vector2(23, -62), 0.8, "rigAction", 0.0],
		["duck", Vector2(-31, 10), 0.45, "walk", 2.4],
		["duck", Vector2(-33, 12), 0.4, "walk", 2.0],
		["goose", Vector2(38, 22), 1.0, "Wings Flapping", 20.0],
		["goose", Vector2(41, 24), 1.0, "Wings Flapping", 22.0],
	]:
		var animal := ACTOR.new()
		animal.kind = entry[0]
		animal.home = entry[1]
		animal.height = entry[2]
		animal.clip = entry[3]
		animal.radius = entry[4]
		animal.terrain = terrain
		animal.player = player
		animal.phase = animals.size() * 1.8
		add_child(animal)
		animals.append(animal)
	# Keep the established cobbled route, with staggered starts and pauses.
	var template: VillageNPC
	for actor in population.actors:
		if actor.job == "wander":
			template = actor
			break
	if template != null:
		for i in 2:
			var actor := population.spawn(["monk", "civilian_1"][i], "wander",
				["Путник", "Дровосек"][i], template.route[7 + i * 3])
			actor.route.assign(template.route)
			actor._wait = 3.3 + i * 2.0
		population._place_walkers.call_deferred()
