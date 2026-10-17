extends RefCounted
## The mesh LOD bands of VegetationSystem: one MultiMesh slot per band,
## species and tile, refilled from the TreeLodGrid around the camera. The
## system holds one (VegetationSystem.lod_slots); the slots' nodes are its
## children.

## The ground point the buffers were last filled around.
var last_eye := Vector2(INF, INF)

## Per band: selection distances, mesh LOD, shader fade range, shadow only.
var _bands := PackedVector2Array()
var _band_lods := PackedInt32Array()
var _band_fades := PackedVector4Array()
var _band_shadows := PackedByteArray()
var _window := 0
var _meshes: Array = []
var _slots: Array[MultiMeshInstance3D] = []
## What each slot's MultiMesh holds, and the scratch set the next selection
## fills; they swap after a refill, and tiles whose rows did not change are
## not uploaded again.
var _shown: Array[PackedFloat32Array] = []
var _spare: Array[PackedFloat32Array] = []
var _boxes: Array[AABB] = []

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

func make_bands(system: VegetationSystem) -> void:
	var ranges := system.lod_ranges()
	for lod in VegetationSystem.LOD_COUNT:
		var fade := ranges[lod]
		_bands.append(Vector2(maxf(fade.x - VegetationSystem.MARGIN, 0.0), fade.w + VegetationSystem.MARGIN))
		_band_lods.append(lod)
		_band_fades.append(fade)
		_band_shadows.append(0)
	for band: Array in VegetationSystem.SHADOW_BANDS:
		_bands.append(Vector2(Values.real(band[1]), Values.real(band[2])))
		_band_lods.append(Values.whole(band[0]))
		_band_fades.append(VegetationSystem.NO_FADE)
		_band_shadows.append(1)
	var reach := 0.0
	for band in _bands:
		reach = maxf(reach, band.y)
	_window = TreeLodGrid.window_tiles(reach)
	var count := _bands.size() * VegetationSystem.SPECIES.size() * _window * _window
	_slots.resize(count)
	_shown.resize(count)
	_spare.resize(count)
	_boxes.resize(count)
	for kind in VegetationSystem.SPECIES.size():
		_meshes.append(species_meshes(system, kind))

## The MultiMesh node of a slot, made the first time the slot has trees.
func slot_node(system: VegetationSystem, slot: int) -> MultiMeshInstance3D:
	if _slots[slot] != null:
		return _slots[slot]
	var per_band := VegetationSystem.SPECIES.size() * _window * _window
	var band := slot / per_band
	var kind := (slot % per_band) / (_window * _window)
	var item := MultiMeshInstance3D.new()
	item.name = "%s_band%d_%d" % [VegetationSystem.SPECIES[kind], band, slot % (_window * _window)]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _meshes[kind][_band_lods[band]]
	item.multimesh = multimesh
	item.set_instance_shader_parameter("lod_range", _band_fades[band])
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _band_shadows[band] \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	item.layers = VegetationSystem.VISUAL_LAYER
	system.add_child(item)
	_slots[slot] = item
	return item

## Moves the trees around `flat` into the band buffers; for an eye in the
## tavern's rooms those of them `sight` shows or needs the shadows of.
func refill(system: VegetationSystem, flat: Vector2, sight: InteriorSight.Sight = null) -> void:
	var start := Time.get_ticks_usec()
	last_eye = flat
	system.grid.select(flat, _bands, _spare, _boxes, sight, _band_shadows)
	system.select_usec = Time.get_ticks_usec() - start
	var uploads := 0
	for slot in _slots.size():
		var data := _spare[slot]
		if data == _shown[slot]:
			continue
		uploads += 1
		var count := data.size() / TreeLodGrid.STRIDE
		if count == 0:
			if _slots[slot] != null and _slots[slot].visible:
				_slots[slot].visible = false
				_slots[slot].multimesh.instance_count = 0
			continue
		var item := slot_node(system, slot)
		var multimesh := item.multimesh
		if multimesh.instance_count != count:
			multimesh.instance_count = count
		multimesh.buffer = data
		multimesh.custom_aabb = _boxes[slot]
		item.visible = true
	var shown := _shown
	_shown = _spare
	_spare = shown
	system.refill_usec = Time.get_ticks_usec() - start
	system.refill_stats += Vector4i(1, system.refill_usec, 0, uploads)
	system.refill_stats.z = maxi(system.refill_stats.z, system.refill_usec)
	var hidden := 0
	for chunk: MultiMeshInstance3D in system.impostor_chunks:
		var drawn := wanted(sight, chunk.multimesh.custom_aabb, false)
		hidden += int(not drawn)
		if chunk.visible != drawn:
			chunk.visible = drawn
	var interiors := system.world.interiors if system.world != null else null
	if interiors != null:
		var cells := system.grid.unseen
		interiors.counts[&"tree cells"] = Vector2i(cells.x, cells.y)
		interiors.counts[&"tree shadow cells"] = Vector2i(cells.z, cells.w)
		interiors.counts[&"impostor chunks"] = Vector2i(hidden, system.impostor_chunks.size())

## Whether trees within the bounds `box` are drawn for an eye that sees the
## outdoors as `sight` has it (null: all of it). Those of a visible band must
## be seen; those that only cast shadows must throw them into what is seen.
static func wanted(sight: InteriorSight.Sight, box: AABB, shadow_only: bool) -> bool:
	if sight == null or not sight.active:
		return true
	if shadow_only:
		return sight.shaded_by(box.get_center(), box.size * 0.5)
	return sight.sees_box(box)

## Trees in each band's buffers (supersets for the faded bands).
func band_counts() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(_bands.size())
	var per_band := VegetationSystem.SPECIES.size() * _window * _window
	for slot in _slots.size():
		if _slots[slot] != null:
			counts[slot / per_band] += _slots[slot].multimesh.instance_count
	return counts

## MultiMesh nodes currently drawn (tiles with trees).
func active_slots() -> int:
	var active := 0
	for item in _slots:
		if item != null and item.visible:
			active += 1
	return active
