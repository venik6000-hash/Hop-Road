extends RefCounted
## The mesh LOD bands of VegetationSystem: one MultiMesh slot per band,
## species and tile, refilled from the TreeLodGrid around the camera (static
## functions over the VegetationSystem `system`, which holds the slots).

# --- mesh LODs ----------------------------------------------------------------

static func species_meshes(system: VegetationSystem, kind: int) -> Array[Mesh]:
	var scene: Node = (load("res://assets/models/vegetation/%s.glb" % VegetationSystem.SPECIES[kind]) as PackedScene).instantiate()
	var meshes: Array[Mesh] = []
	var group: int = TreePlacer.SPECIES_GROUP[kind]
	for lod in VegetationSystem.LOD_COUNT:
		var item := scene.find_child("%s_lod%d" % [VegetationSystem.SPECIES[kind], lod], true, false) as MeshInstance3D
		var mesh := item.mesh
		for surface in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface)
			var slot := source.resource_name if source != null else ""
			var material: ShaderMaterial = system.bark_materials[group]
			if slot == "foliage":
				material = system.foliage_materials[group]
			elif slot == "trunk":
				material = system.trunk_materials[kind]
			mesh.surface_set_material(surface, material)
		meshes.append(mesh)
	scene.free()
	return meshes

static func make_bands(system: VegetationSystem) -> void:
	var ranges := system.lod_ranges()
	for lod in VegetationSystem.LOD_COUNT:
		var fade := ranges[lod]
		system._bands.append(Vector2(maxf(fade.x - VegetationSystem.MARGIN, 0.0), fade.w + VegetationSystem.MARGIN))
		system._band_lods.append(lod)
		system._band_fades.append(fade)
		system._band_shadows.append(0)
	for band: Array in VegetationSystem.SHADOW_BANDS:
		system._bands.append(Vector2(band[1], band[2]))
		system._band_lods.append(band[0])
		system._band_fades.append(VegetationSystem.NO_FADE)
		system._band_shadows.append(1)
	var reach := 0.0
	for band in system._bands:
		reach = maxf(reach, band.y)
	system._window = TreeLodGrid.window_tiles(reach)
	var count := system._bands.size() * VegetationSystem.SPECIES.size() * system._window * system._window
	system._slots.resize(count)
	system._shown.resize(count)
	system._spare.resize(count)
	system._boxes.resize(count)
	for kind in VegetationSystem.SPECIES.size():
		system._meshes.append(species_meshes(system, kind))

## The MultiMesh node of a slot, made the first time the slot has trees.
static func slot_node(system: VegetationSystem, slot: int) -> MultiMeshInstance3D:
	if system._slots[slot] != null:
		return system._slots[slot]
	var per_band := VegetationSystem.SPECIES.size() * system._window * system._window
	var band := slot / per_band
	var kind := (slot % per_band) / (system._window * system._window)
	var item := MultiMeshInstance3D.new()
	item.name = "%s_band%d_%d" % [VegetationSystem.SPECIES[kind], band, slot % (system._window * system._window)]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = system._meshes[kind][system._band_lods[band]]
	item.multimesh = multimesh
	item.set_instance_shader_parameter("lod_range", system._band_fades[band])
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if system._band_shadows[band] \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	item.layers = VegetationSystem.VISUAL_LAYER
	system.add_child(item)
	system._slots[slot] = item
	return item

## Moves the trees around `flat` into the band buffers; for an eye in the
## tavern's rooms those of them `sight` shows or needs the shadows of.
static func refill(system: VegetationSystem, flat: Vector2, sight: TavernPortals.Sight = null) -> void:
	var start := Time.get_ticks_usec()
	system._last_eye = flat
	system.grid.select(flat, system._bands, system._spare, system._boxes, sight, system._band_shadows)
	system.select_usec = Time.get_ticks_usec() - start
	var uploads := 0
	for slot in system._slots.size():
		var data := system._spare[slot]
		if data == system._shown[slot]:
			continue
		uploads += 1
		var count := data.size() / TreeLodGrid.STRIDE
		if count == 0:
			if system._slots[slot] != null and system._slots[slot].visible:
				system._slots[slot].visible = false
				system._slots[slot].multimesh.instance_count = 0
			continue
		var item := slot_node(system, slot)
		var multimesh := item.multimesh
		if multimesh.instance_count != count:
			multimesh.instance_count = count
		multimesh.buffer = data
		multimesh.custom_aabb = system._boxes[slot]
		item.visible = true
	var shown := system._shown
	system._shown = system._spare
	system._spare = shown
	system.refill_usec = Time.get_ticks_usec() - start
	system.refill_stats += Vector4i(1, system.refill_usec, 0, uploads)
	system.refill_stats.z = maxi(system.refill_stats.z, system.refill_usec)
	var hidden := 0
	for chunk: MultiMeshInstance3D in system._impostor_chunks:
		var drawn := wanted(sight, chunk.multimesh.custom_aabb, false)
		hidden += int(not drawn)
		if chunk.visible != drawn:
			chunk.visible = drawn
	var portals := system.world.portals if system.world != null else null
	if portals != null:
		var cells := system.grid.unseen
		portals.counts[&"tree cells"] = Vector2i(cells.x, cells.y)
		portals.counts[&"tree shadow cells"] = Vector2i(cells.z, cells.w)
		portals.counts[&"impostor chunks"] = Vector2i(hidden, system._impostor_chunks.size())

## Whether trees within the bounds `box` are drawn for an eye that sees the
## outdoors as `sight` has it (null: all of it). Those of a visible band must
## be seen; those that only cast shadows must throw them into what is seen.
static func wanted(sight: TavernPortals.Sight, box: AABB, shadow_only: bool) -> bool:
	if sight == null or not sight.active:
		return true
	if shadow_only:
		return sight.shaded_by(box.get_center(), box.size * 0.5)
	return sight.sees_box(box)

## Trees in each band's buffers (supersets for the faded bands).
static func band_counts(system: VegetationSystem) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(system._bands.size())
	var per_band := VegetationSystem.SPECIES.size() * system._window * system._window
	for slot in system._slots.size():
		if system._slots[slot] != null:
			counts[slot / per_band] += system._slots[slot].multimesh.instance_count
	return counts

## MultiMesh nodes currently drawn (tiles with trees).
static func active_slots(system: VegetationSystem) -> int:
	var active := 0
	for item in system._slots:
		if item != null and item.visible:
			active += 1
	return active
