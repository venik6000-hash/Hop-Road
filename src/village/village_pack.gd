extends Node3D
## Authored yards plus deterministic, batched forest details from the local pack.
const CollisionCache = preload("res://src/village/prop_collision_cache.gd")
const LayoutStore = preload("res://src/layout/layout_store.gd")
const DIRECTORY := WorldSchemas.PACK_DIRECTORY
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
## Yard props of cloth and straw: the rain soaks them and leaves no shine.
const SOAKING_PROPS: Array[String] = ["sack", "hay"]
## Side of a forest batch (m). The engine picks one mesh LOD and one
## visibility for a whole MultiMesh, so small cells keep the full scans to
## the ground round the walker.
const FOREST_CELL := 12.0
## How far the forest floor's small scans and its wood show (m).
const FOREST_VIEW := 45.0
const FOREST_WOOD_VIEW := 80.0
const FOREST_WOOD: Array[String] = ["stump", "log", "roots", "branch"]
## The material a model of the pack names its still water with (the well's):
## it gets the look of dark standing water.
const WATER_MATERIAL := "water"
var terrain: TerrainSystem
var player: Player
## Its yard props, the forest's wood and floor and the animals
## (RegionDef.props, forest_wood, forest_floor, animals).
var region: RegionDef
var removed_labels: Array[String] = []
var props: Array[Node3D] = []
var animals: Array[Node3D] = []
var forest_instances := 0
var forest_ready := false
var _scenes := {}
var _collision_cache := CollisionCache.new()
static var _prefetched_scenes: Dictionary[String, PackedScene] = {}
var _forest_batches := {}
var _forest_shapes := {}
var _forest_meshes := {}

## Keep loading on the main thread: asset workers can deadlock on Godot 4.7.2.
## The callback reports completed models and returns false to cancel loading.
static func prefetch_assets(tree: SceneTree, progress: Callable, layout_path: String) -> bool:
	discard_prefetch()
	var layout: Variant = DataFile.read(layout_path, WorldSchemas.props())
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
	return DataFile.read(region.props, WorldSchemas.props())

func _prepare_map(map: Node3D) -> void:
	var index := MapIndex.of(map)
	for item: MeshInstance3D in index.pieces():
		var label := RockField.label_of(item)
		var extras: Dictionary = item.get_meta("extras", {})
		var group: String = str(extras.get("alpine_group", ""))
		if group == "31":
			removed_labels.append(label)
			index.drop(item)

func _finish_install(scatter := true) -> void:
	# Wait for all building/tree colliders before sampling the forest floor.
	if scatter:
		scatter_forest.call_deferred()
	print("VILLAGE_PACK removed=%d props=%d" % [removed_labels.size(), props.size()])

func _scene(key: String) -> PackedScene:
	if not _scenes.has(key):
		_scenes[key] = load(DIRECTORY + key + ".glb")
	return _scenes[key]

func _place(entry: Dictionary) -> Node3D:
	var item := _scene(str(entry.asset)).instantiate() as Node3D
	item.name = entry.name
	item.set_meta("pack_asset", entry.asset)
	item.set_meta("zone", entry.zone)
	var x: float = entry.x
	var z: float = entry.z
	item.position = Vector3(x, terrain.height_at(x, z) + Values.real(entry.get("lift", 0.0)), z)
	item.rotation.y = deg_to_rad(Values.real(entry.get("yaw", 0.0)))
	# A prop leant by hand in the layout scene: degrees about x and z.
	var tilt: Array = entry.get("tilt", [0.0, 0.0])
	item.rotation.x = deg_to_rad(Values.real(tilt[0]))
	item.rotation.z = deg_to_rad(Values.real(tilt[1]))
	item.scale = Vector3.ONE * Values.real(entry.size)
	add_child(item)
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		# A basket stops mattering long before a cart does: by the prop's size.
		var extent: float = (mesh.global_transform.basis * mesh.get_aabb().size).length()
		mesh.visibility_range_end = clampf(45.0 + extent * 22.0, 55.0, 110.0)
		mesh.visibility_range_end_margin = 12.0
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.resource_name == WATER_MATERIAL:
				var water := material.duplicate() as StandardMaterial3D
				water.albedo_color = Color("182c28")
				water.metallic = 0.0
				water.roughness = 0.2
				mesh.set_surface_override_material(surface, water)
		if entry.get("solid", true):
			var body := StaticBody3D.new()
			body.name = mesh.name + "_col"
			var holder := CollisionShape3D.new()
			holder.shape = _collision_cache.shape(str(entry.asset), str(item.get_path_to(mesh)), mesh.mesh)
			body.add_child(holder)
			mesh.add_child(body)
	# The yard stands in the weather: the rain wets it, the clouds and the
	# crowns shade it.
	OutdoorScan.dress(item, OutdoorScan.SOAKED_SHINE if str(entry.asset) in SOAKING_PROPS else OutdoorScan.PROP_SHINE)
	props.append(item)
	return item

## Lays the forest floor's plants and wood. The plants' rays meet the
## terrain once the ground under the first place stands.
func scatter_forest() -> void:
	var rng := RandomNumberGenerator.new()
	# The region's places of the forest floor: none without the file.
	var scatter := {} if region.forest_floor.is_empty() else Values.table(DataFile.read(region.forest_floor, WorldSchemas.forest_floor()))
	var places := Values.list(scatter.get("places", []))
	if not places.is_empty():
		var first := Values.vec2(places[0])
		await PhysicsLayers.ground_stands(self, Vector3(first.x, terrain.height_at(first.x, first.y), first.y))
		if not is_inside_tree():
			return
	rng.seed = Values.whole(scatter.get("seed", 0))
	var radius := Values.real(scatter.get("radius", 0.0))
	for place: Variant in places:
		var zone := Values.vec2(place)
		for index in Values.whole(scatter.get("count", 0)):
			var point: Vector2 = zone + Vector2.from_angle(rng.randf_range(0, TAU)) * sqrt(rng.randf()) * radius
			var y := terrain.height_at(point.x, point.y)
			if y < terrain.water_level + 1.0:
				continue
			var slope := Vector2(terrain.height_at(point.x + 0.6, point.y) - y,
				terrain.height_at(point.x, point.y + 0.6) - y).length() / 0.6
			if slope > 0.5:
				continue
			var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, y + 20, point.y), Vector3(point.x, y - 0.3, point.y), PhysicsLayers.GROUND)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not PhysicsLayers.hit_terrain(hit):
				continue
			if index % 13 == 0:
				# This slot held a piece of wood, now in the list. It still draws
				# its three numbers so that the plants lie where they always lay.
				for _draw in 3:
					rng.randf()
				continue
			var asset: String = ["fern", "clover", "bracken"][index % 3]
			var size := rng.randf_range(0.55, 1.05)
			var pose := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * size), Vector3(point.x, y - 0.045, point.y))
			_batch(asset, pose)
	for entry: Dictionary in LayoutStore.placed(region.forest_wood, WorldSchemas.forest_wood()):
		if entry.asset in FOREST_WOOD:
			_batch(str(entry.asset), LayoutStore.unpack(Values.list(entry.xform)))
	for batch: Dictionary in _forest_batches.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = batch.mesh
		var poses: Array = batch.poses
		mm.instance_count = poses.size()
		for i: int in poses.size():
			var pose: Transform3D = poses[i]
			mm.set_instance_transform(i, pose)
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
		transform = (parent as Node3D).transform * transform
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
	var poses: Array = batch.poses
	poses.append(pose * batch.transform)
	if asset in SOLID_FOREST:
		if not _forest_shapes.has(asset):
			var mesh: Mesh = batch.mesh
			_forest_shapes[asset] = _forest_hull(asset, mesh)
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

## The region's animals in their yards (RegionDef.animals).
func add_animals() -> void:
	if region.animals.is_empty():
		return
	var data: Variant = DataFile.read(region.animals, WorldSchemas.animals())
	var table: Dictionary = data if data is Dictionary else {}
	var listed: Array = table.get("animals", [])
	for entry: Dictionary in listed:
		var animal := ACTOR.new()
		animal.kind = str(entry.kind)
		animal.home = Values.vec2(entry.at)
		animal.height = Values.real(entry.height)
		animal.clip = str(entry.clip)
		animal.radius = Values.real(entry.radius)
		animal.terrain = terrain
		animal.player = player
		animal.phase = animals.size() * 1.8
		add_child(animal)
		animals.append(animal)
