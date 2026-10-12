@tool
extends Node3D
## The level as the game builds it, in the editor's 3D view, with every
## hand-placed object as a node to move (scenes/alpine/layout.tscn).
##
## The game's level is put together by code when it starts, so its own scene
## shows only the Blender map it began from. This scene builds the same
## ground (TerrainSystem with the game's heights and shader) and stands the
## houses, the yard props, the stones and the forest's wood on it, each under
## a LayoutItem that keeps it on the ground while it is dragged. The tavern
## and the rest of the Blender map are shown in place and cannot be picked.
##
## Nothing built here is stored in the scene file. Saving the scene writes
## the objects back to the files the game reads (LayoutStore): houses and
## cottages to village_plan.json, props to the village pack's layout.json,
## stones to rocks.json, wood to forest_wood.json. A duplicated prop, stone
## or piece of wood becomes a new record and a deleted one is dropped;
## houses can only be moved and turned.

const LayoutStore = preload("res://src/layout/layout_store.gd")
const LayoutItem = preload("res://src/layout/layout_item.gd")
const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
const VILLAGE_MATERIALS = preload("res://src/village/village_materials.gd")
const VILLAGE_BUILDINGS = preload("res://src/village/village_buildings.gd")
const TAVERN_MATERIALS = preload("res://src/tavern/tavern_materials.gd")
const VILLAGE_PACK = preload("res://src/village/village_pack.gd")
const MAP := "res://assets/models/alpine/alpine_map.glb"
const PACK := "res://assets/models/village_pack/"
const HOUSE_LABEL := "Village house "
const COTTAGES := {
	"herbalist": {"name": "HerbalistCottage", "scene": "res://assets/generated/layout/herbalist_placed.glb",
		"table": "res://assets/models/cottage/herbalist.json"},
	"potter": {"name": "PotterCottage", "scene": "res://assets/generated/layout/potter_placed.glb",
		"table": "res://assets/models/potter/potter.json"},
}
## Groups of movable objects, in the order of the scene tree.
const GROUPS := ["Houses", "Props", "Rocks", "ForestWood"]
const PREVIEW := "Preview"

@export_tool_button("Перечитать с диска", "Reload") var reload_action := rebuild
@export_tool_button("Записать и обновить рельеф", "Save") var refresh_action := save_and_refresh
## The game's sky and sun instead of the editor's preview light.
@export var game_lighting := true:
	set(value):
		game_lighting = value
		_apply_lighting()
@export var show_lake := true:
	set(value):
		show_lake = value
		if _lake != null:
			_lake.visible = value
## Model of the village pack the button below puts in front of the camera.
@export var new_prop := "barrel"
@export_tool_button("Добавить проп перед камерой", "Add") var add_prop_action := add_prop

var terrain: TerrainSystem
var _preview: Node3D
var _lake: MeshInstance3D
var _sky: SkySystem
var _view := []
var _complete := false
var _scenes := {}
var _rock_shapes := {}
var _rock_material: ShaderMaterial
var _plan_text := ""

func _ready() -> void:
	rebuild()

func _validate_property(property: Dictionary) -> void:
	if property.name == "new_prop":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(_pack_assets())

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		save_layout()
		_own(null)
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_own(self)
		var plan := FileAccess.get_file_as_string(LayoutStore.PLAN)
		if _complete and plan != _plan_text:
			_refresh_terrain.call_deferred()

## The built objects belong to the scene only between saves: owned, they can
## be picked and show in the scene tree; unowned, the scene file leaves them out.
func _own(holder: Node) -> void:
	for group_name: String in GROUPS:
		var group := get_node_or_null(group_name)
		if group == null:
			continue
		for item: Node in group.get_children():
			item.owner = holder
		group.owner = holder

func _process(_delta: float) -> void:
	if terrain == null:
		return
	var camera := _camera()
	if camera == null:
		return
	# The terrain picks its patches for the camera; nothing to do while it rests.
	var view := [camera, camera.global_transform, camera.get_camera_projection()]
	if view != _view:
		_view = view
		terrain.camera = camera
		terrain._process(0.0)
		if _sky != null:
			_sky.viewer = camera

func _camera() -> Camera3D:
	if Engine.is_editor_hint():
		return Engine.get_singleton(&"EditorInterface").get_editor_viewport_3d(0).get_camera_3d()
	return get_viewport().get_camera_3d()

## Height of the game's ground at a point, for LayoutItem.
func ground_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0

## A moved house takes its wall grime from the ground it now stands on.
func item_moved(item: Node3D) -> void:
	if item.kind != "house" or terrain == null:
		return
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		var level: Variant = mesh.get_instance_shader_parameter(&"ground_level")
		if level != null and level > -99.0:
			var centre := (mesh.global_transform * mesh.get_aabb()).get_center()
			mesh.set_instance_shader_parameter(&"ground_level", terrain.height_at(centre.x, centre.z))

# --- building ----------------------------------------------------------------

func rebuild() -> void:
	var start := Time.get_ticks_msec()
	_complete = false
	_view = []
	for child_name: String in GROUPS + [PREVIEW]:
		var child := get_node_or_null(child_name)
		if child != null:
			remove_child(child)
			child.free()
	terrain = null
	_sky = null
	_preview = Node3D.new()
	_preview.name = PREVIEW
	add_child(_preview)
	_build_terrain()
	_build_lake()
	_apply_lighting()
	var groups := {}
	for group_name: String in GROUPS:
		var group := Node3D.new()
		group.name = group_name
		add_child(group)
		group.owner = self
		groups[group_name] = group
	_build_map(groups.Houses)
	_build_props(groups.Props)
	_build_rocks(groups.Rocks)
	_build_wood(groups.ForestWood)
	VILLAGE_LAYOUT.paint_aprons(self, terrain)
	_plan_text = FileAccess.get_file_as_string(LayoutStore.PLAN)
	_complete = true
	print("LAYOUT houses=%d props=%d rocks=%d wood=%d load=%.1fs" % [groups.Houses.get_child_count(),
		groups.Props.get_child_count(), groups.Rocks.get_child_count(), groups.ForestWood.get_child_count(),
		(Time.get_ticks_msec() - start) / 1000.0])

func _build_terrain() -> void:
	terrain = TerrainSystem.new()
	terrain.name = "Terrain"
	terrain.collision_enabled = false
	_preview.add_child(terrain)
	# _process above drives it, and only when the camera moves.
	terrain.set_process(false)
	VillageBrook.paint(terrain)
	# The worn yards of the village pack, painted as its install does.
	var pack := VILLAGE_PACK.new()
	pack.terrain = terrain
	pack._paint_working_ground()
	pack.free()
	_view = []

func _build_lake() -> void:
	_lake = MeshInstance3D.new()
	_lake.name = "Lake"
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(6000.0, 6000.0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.16, 0.36, 0.42, 0.62)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.12
	sheet.material = water
	_lake.mesh = sheet
	_lake.position.y = terrain.water_level
	_lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lake.visible = show_lake
	_preview.add_child(_lake)

## The game's afternoon sky and sun, or the editor's own preview light.
func _apply_lighting() -> void:
	if _preview == null:
		return
	for node_name: String in ["Sky", "WorldEnvironment"]:
		var node := _preview.get_node_or_null(node_name)
		if node != null:
			_preview.remove_child(node)
			node.free()
	_sky = null
	# The sky's tables are computed on the GPU: not in a headless editor.
	if not game_lighting or RenderingServer.get_rendering_device() == null:
		return
	_sky = SkySystem.new()
	_sky.name = "Sky"
	_sky.day_of_year = 225
	_sky.time_of_day = 14.6
	_preview.add_child(_sky)
	# A still afternoon: moving clouds would redraw the view all the time.
	_sky.set_process(false)
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = RealismEnvironment.build(_sky.make_sky())
	_preview.add_child(world)
	_view = []

## The Blender map as the loaded level shows it: the houses as items, the rest
## (bridge, campanile, market, paving) and the refined tavern as scenery.
func _build_map(houses: Node3D) -> void:
	var map := _scene(MAP).instantiate() as Node3D
	map.name = "Map"
	_preview.add_child(map)
	VILLAGE_MATERIALS.apply(map, terrain)
	var shown := {}
	var context: Variant = LayoutStore.read(LayoutStore.MAP_CONTEXT)
	if context is Array:
		for path: String in context:
			shown[path] = true
	var parts := {}
	var dropped: Array[Node] = []
	var replaced := VILLAGE_BUILDINGS.replaced()
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		for body: Node in mesh.get_children():
			if body is CollisionObject3D:
				dropped.append(body)
		if not shown.has(str(map.get_path_to(mesh))):
			dropped.append(mesh)
			continue
		var label := RockField.label_of(mesh)
		if VILLAGE_BUILDINGS.begins(label, replaced):
			# A building of VillageBuildings.TABLES stands on this house's lot.
			dropped.append(mesh)
		elif label.begins_with(HOUSE_LABEL):
			var id := label.substr(HOUSE_LABEL.length(), 2).to_int()
			if not parts.has(id):
				parts[id] = []
			parts[id].append(mesh)
	var plan := VILLAGE_LAYOUT.plan()
	var specs := {}
	for spec: Dictionary in plan.houses:
		specs[int(spec.id)] = spec
	var ids := parts.keys()
	ids.sort()
	for id: int in ids:
		var spec: Dictionary = specs.get(id, {})
		if spec.is_empty():
			# A house the plan never moved: its pivot is the middle of its rooms.
			var centre := Vector3.ZERO
			for mesh: MeshInstance3D in parts[id]:
				if RockField.label_of(mesh).ends_with("limewashed rooms"):
					centre = (mesh.global_transform * mesh.get_aabb()).get_center()
			var at := [snappedf(centre.x, 0.1), snappedf(centre.z, 0.1)]
			spec = {"id": id, "source": at, "position": at.duplicate(), "yaw": 0}
		var source := Vector3(spec.source[0], VILLAGE_LAYOUT.source_ground(spec, terrain), spec.source[1])
		var lift := float(spec.get("lift", 0.0))
		var visual := Node3D.new()
		visual.name = "Visual"
		visual.position = -source
		for mesh: MeshInstance3D in parts[id]:
			var pose := mesh.global_transform
			mesh.get_parent().remove_child(mesh)
			visual.add_child(mesh)
			mesh.transform = pose
		var at := Vector3(spec.position[0], terrain.height_at(spec.position[0], spec.position[1]) + lift, spec.position[1])
		_add_item(houses, "House%02d" % id, "house", spec, Transform3D(Basis(Vector3.UP, deg_to_rad(spec.yaw)), at), visual, lift)
	for key: String in COTTAGES:
		_build_cottage(houses, key, plan.cottages[key])
	for node: Node in dropped:
		if is_instance_valid(node):
			node.free()
	VILLAGE_LAYOUT.settle_landmarks(map, terrain)
	_lock(map)
	for path: String in TavernSystem.PARTS:
		var table: Variant = LayoutStore.read(path)
		if table is Dictionary:
			var materials := {}
			TAVERN_MATERIALS.build(table, TavernSystem.GROUND, materials)
			for scene_path: String in table.get("scenes", []):
				var scene := _scene(scene_path).instantiate() as Node3D
				scene.name = "Tavern" + scene_path.get_file().get_basename().to_pascal_case()
				_dress(scene, materials)
				_lock(scene)
				_preview.add_child(scene)

func _build_cottage(houses: Node3D, key: String, spec: Dictionary) -> void:
	var config: Dictionary = COTTAGES[key]
	var table: Dictionary = LayoutStore.read(config.table)
	var built: Dictionary = spec.get("built", spec)
	var was := Transform3D(Basis(Vector3.UP, deg_to_rad(built.yaw)), Vector3(built.position[0], built.position[1], built.position[2]))
	var now := Transform3D(Basis(Vector3.UP, deg_to_rad(spec.yaw)), Vector3(spec.position[0], spec.position[1], spec.position[2]))
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.transform = was.affine_inverse()
	var scene := _scene(config.scene).instantiate() as Node3D
	var origin := Vector3(table.origin[0], table.origin[1], table.origin[2])
	var materials := {}
	TAVERN_MATERIALS.build(table, (VILLAGE_LAYOUT.cottage_pose(key) * origin).y, materials)
	_dress(scene, materials)
	visual.add_child(scene)
	_add_item(houses, config.name, "cottage", {"key": key}, now, visual, now.origin.y - terrain.height_at(now.origin.x, now.origin.z))

## Scenery is not for picking: the editor's lock keeps a click from taking it.
func _lock(scenery: Node) -> void:
	for node: Node in scenery.find_children("*", "Node3D", true, false):
		node.set_meta(&"_edit_lock_", true)

## The game's materials on a scene exported by the tavern builder, by name.
func _dress(scene: Node3D, materials: Dictionary) -> void:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material != null and materials.has(material.resource_name):
				mesh.set_surface_override_material(surface, materials[material.resource_name])

func _build_props(props: Node3D) -> void:
	var layout: Variant = LayoutStore.read(LayoutStore.PROPS)
	if not layout is Array:
		return
	for entry: Dictionary in layout:
		props.add_child(_prop(entry))
		props.get_child(-1).owner = self

func _prop(entry: Dictionary) -> Node3D:
	var x: float = entry.x
	var z: float = entry.z
	var lift := float(entry.get("lift", 0.0))
	var tilt: Array = entry.get("tilt", [0.0, 0.0])
	var basis := Basis.from_euler(Vector3(deg_to_rad(tilt[0]), deg_to_rad(entry.get("yaw", 0.0)), deg_to_rad(tilt[1])))
	var pose := Transform3D(basis.scaled(Vector3.ONE * float(entry.size)), Vector3(x, terrain.height_at(x, z) + lift, z))
	return _item(str(entry.name), "prop", entry, pose, _scene(PACK + str(entry.asset) + ".glb").instantiate(), lift)

func _build_rocks(rocks: Node3D) -> void:
	# The shapes and the material as RockField makes them, without its stones.
	var field := RockField.new()
	field.terrain = terrain
	field._load_shapes()
	field._make_materials()
	_rock_shapes.clear()
	for info: Dictionary in field._shapes:
		_rock_shapes[info.name] = info
	_rock_material = field._boulder_material
	field.free()
	# RockField draws MultiMeshes and its shader takes the scan and the moss of
	# a stone from the instance's custom data. A stone drawn alone gets the
	# same values through an instance uniform.
	var code := RockField.SHADER.code
	if code.contains("rock = INSTANCE_CUSTOM;"):
		var single := Shader.new()
		single.code = code.replace("rock = INSTANCE_CUSTOM;", "rock = single_rock;").replace(
			"void vertex()", "instance uniform vec4 single_rock;\nvoid vertex()")
		_rock_material.shader = single
	var index := 0
	for entry: Dictionary in LayoutStore.placed(LayoutStore.ROCKS):
		if not _rock_shapes.has(entry.shape):
			continue
		var pose := LayoutStore.unpack(entry.xform)
		var item := _item("Rock%04d" % index, "rock", entry, pose, _rock_visual(entry),
			pose.origin.y - terrain.height_at(pose.origin.x, pose.origin.z))
		rocks.add_child(item)
		item.owner = self
		index += 1

func _rock_visual(entry: Dictionary) -> MeshInstance3D:
	var info: Dictionary = _rock_shapes[entry.shape]
	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	mesh.mesh = info.mesh
	mesh.material_override = _rock_material
	mesh.set_instance_shader_parameter(&"single_rock", Vector4(info.layer, entry.moss, entry.tone, 0.0))
	return mesh

func _build_wood(wood: Node3D) -> void:
	var index := 0
	for entry: Dictionary in LayoutStore.placed(LayoutStore.FOREST_WOOD):
		var pose := LayoutStore.unpack(entry.xform)
		var item := _item("%s%02d" % [str(entry.asset).capitalize(), index], "wood", entry, pose,
			_scene(PACK + str(entry.asset) + ".glb").instantiate(), pose.origin.y - terrain.height_at(pose.origin.x, pose.origin.z))
		wood.add_child(item)
		item.owner = self
		index += 1

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

func _item(item_name: String, kind: String, entry: Dictionary, pose: Transform3D, visual: Node3D, offset: float) -> Node3D:
	var item := LayoutItem.new()
	item.name = item_name
	item.kind = kind
	item.entry = entry
	item.transform = pose
	item.placed = pose
	item.ground_offset = offset
	if visual.name != &"Visual":
		visual.name = "Visual"
	item.add_child(visual)
	return item

func _add_item(group: Node3D, item_name: String, kind: String, entry: Dictionary, pose: Transform3D, visual: Node3D, offset: float) -> void:
	var item := _item(item_name, kind, entry, pose, visual, offset)
	group.add_child(item)
	item.owner = self
	item_moved(item)

func _pack_assets() -> PackedStringArray:
	var assets := PackedStringArray()
	for file: String in DirAccess.get_files_at(PACK):
		if file.ends_with(".glb"):
			assets.append(file.get_basename())
	return assets

## A new prop where the camera looks at the ground, sized as its kind already is.
func add_prop() -> void:
	var props := get_node_or_null("Props")
	var camera := _camera()
	if props == null or camera == null or not _complete:
		return
	var eye := camera.global_position
	var along := -camera.global_transform.basis.z
	var at := eye + along * 10.0
	for metres in range(1, 400):
		var point := eye + along * float(metres)
		if point.y <= terrain.height_at(point.x, point.z):
			at = point
			break
	var size := 1.0
	for item: Node3D in props.get_children():
		if item.entry.get("asset", "") == new_prop:
			size = item.entry.size
			break
	var entry := {"name": new_prop, "asset": new_prop, "x": snappedf(at.x, 0.01), "z": snappedf(at.z, 0.01),
		"size": size, "yaw": 0.0, "lift": 0.0, "solid": true, "zone": "yards"}
	var item := _prop(entry)
	# Not yet on disk: the save must write it even where it was put.
	item.placed = Transform3D.IDENTITY
	props.add_child(item, true)
	item.owner = self
	if Engine.is_editor_hint():
		var selection: Object = Engine.get_singleton(&"EditorInterface").get_selection()
		selection.clear()
		selection.add_node(item)

# --- saving ------------------------------------------------------------------

## Writes the objects to the files the game reads. A file is rewritten only
## when something in it changed: the vegetation's placement cache is keyed
## by their contents.
func save_layout() -> void:
	if not _complete:
		return
	_save_plan()
	_save_props()
	_save_rows("Rocks", LayoutStore.ROCKS)
	_save_rows("ForestWood", LayoutStore.FOREST_WOOD)

func save_and_refresh() -> void:
	save_layout()
	_refresh_terrain()

## The ground again from the files (a moved cottage levels its new yard), and
## every object set on it.
func _refresh_terrain() -> void:
	if not _complete:
		return
	_preview.remove_child(terrain)
	terrain.free()
	_build_terrain()
	_preview.move_child(terrain, 0)
	for group_name: String in GROUPS:
		for item: Node in get_node(group_name).get_children():
			if item.has_method(&"settle"):
				item.settle()
	VILLAGE_LAYOUT.paint_aprons(self, terrain)
	_plan_text = FileAccess.get_file_as_string(LayoutStore.PLAN)

func _save_plan() -> void:
	var houses := get_node_or_null("Houses")
	var plan: Variant = LayoutStore.read(LayoutStore.PLAN)
	if houses == null or not plan is Dictionary:
		return
	var listed := {}
	for index: int in plan.houses.size():
		listed[int(plan.houses[index].id)] = index
	for item: Node3D in houses.get_children():
		if not item.has_method(&"moved") or not item.moved():
			continue
		var at := item.position
		var yaw := snappedf(rad_to_deg(item.rotation.y), 0.01)
		if item.kind == "cottage":
			var spec: Dictionary = plan.cottages.get(item.entry.get("key", ""), {})
			if spec.is_empty():
				continue
			if not spec.has("built"):
				spec.built = {"position": spec.position, "yaw": spec.yaw}
			spec.position = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
			spec.yaw = yaw
		elif item.kind == "house" and item.entry.has("id"):
			var spec: Dictionary = item.entry.duplicate(true)
			spec.position = [snappedf(at.x, 0.01), snappedf(at.z, 0.01)]
			spec.yaw = yaw
			var lift := snappedf(at.y - terrain.height_at(spec.position[0], spec.position[1]), 0.01)
			if absf(lift) > 0.005:
				spec.lift = lift
			else:
				spec.erase("lift")
			var id := int(spec.id)
			if listed.has(id):
				plan.houses[listed[id]] = spec
			else:
				listed[id] = plan.houses.size()
				plan.houses.append(spec)
	_write(LayoutStore.PLAN, JSON.stringify(plan, "  ", false, true) + "\n")

func _save_props() -> void:
	var props := get_node_or_null("Props")
	if props == null:
		return
	var layout := []
	for item: Node3D in props.get_children():
		if not item.has_method(&"moved") or item.kind != "prop":
			continue
		var entry: Dictionary = item.entry.duplicate(true)
		entry.name = str(item.name)
		if item.moved():
			var turn := item.basis.get_euler()
			entry.x = snappedf(item.position.x, 0.001)
			entry.z = snappedf(item.position.z, 0.001)
			entry.size = snappedf(item.basis.get_scale().x, 0.001)
			entry.yaw = snappedf(rad_to_deg(turn.y), 0.01)
			entry.lift = snappedf(item.position.y - terrain.height_at(entry.x, entry.z), 0.001)
			if absf(turn.x) > 0.001 or absf(turn.z) > 0.001:
				entry.tilt = [snappedf(rad_to_deg(turn.x), 0.01), snappedf(rad_to_deg(turn.z), 0.01)]
			else:
				entry.erase("tilt")
		layout.append(entry)
	_write(LayoutStore.PROPS, JSON.stringify(layout, " ", false, true) + "\n")

## Stones and wood: one record per line, with the transform as it stands.
func _save_rows(group_name: String, path: String) -> void:
	var group := get_node_or_null(group_name)
	if group == null:
		return
	var rows := []
	for item: Node3D in group.get_children():
		if not item.has_method(&"moved"):
			continue
		var entry: Dictionary = item.entry.duplicate(true)
		if item.moved():
			entry.xform = LayoutStore.pack(item.transform)
		rows.append(entry)
	_write(path, LayoutStore.rows_text(rows))

func _write(path: String, text: String) -> void:
	if FileAccess.get_file_as_string(path) == text:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("LAYOUT saved ", path)
