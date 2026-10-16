class_name VegetationSystem
extends Node3D
## Trees over the generated terrain.
##
## Placement comes from TreePlacer through VegetationCache (seconds the first
## time, then read from disk). Trees near the camera are drawn with their
## three mesh LODs, refilled from a TreeLodGrid whenever the camera has moved
## a few metres: one MultiMesh per distance band, species and 64 m tile (made
## when first needed). Every tree also has an impostor in a static 1 km chunk.
## The shaders cross-fade neighbouring LODs tree by tree with a screen dither
## that TAA resolves, from the distance to `lod_camera`.
##
## The visible LODs cast no sun shadow. Two shadow-only bands draw the trees
## that cast one with a coarser mesh, split exactly by distance: LOD1 near,
## LOD2 out to the end of the shadow map. The lanterns ignore the trees
## (VISUAL_LAYER is left out of their shadow caster mask).
##
## Trunks inside the walkable near field get cylinder colliders.
##
## Grass around the camera is a GrassField child, kept off the same building
## footprints as the trees.
##
## For an eye in the tavern's rooms the trees no opening shows are left out
## of the buffers, cell by cell (TavernPortals; TreeLodGrid.select), and the
## buffers are filled again whenever what that eye sees has changed.

const TreeMaterials = preload("res://src/vegetation/tree_materials.gd")
const TreeLodSlots = preload("res://src/vegetation/tree_lod_slots.gd")
const TreeImpostors = preload("res://src/vegetation/tree_impostors.gd")
const TreeColliders = preload("res://src/vegetation/tree_colliders.gd")

const SPECIES := TreePlacer.SPECIES_NAMES
const LOD_COUNT := 3
## Per LOD but the last: fade-in start, fade-in end, fade-out start,
## fade-out end (m). The last fades out over mesh_reach, where the impostor
## fades in (lod_ranges).
const NEAR_LOD_RANGES: Array[Vector4] = [
	Vector4(0.0, 0.0, 20.0, 26.0),
	Vector4(20.0, 26.0, 60.0, 70.0),
]
## Shadow casters: [mesh LOD, near (m), far (m)]; the sun's shadow map ends at 160 m.
const SHADOW_BANDS := [[1, 0.0, 26.0], [2, 26.0, 160.0]]
const NO_FADE := Vector4(0.0, 0.0, 1e9, 1e9)
## Render layer of every tree node (lanterns leave it out of their shadows).
const VISUAL_LAYER := 2
## Buffers are refilled once the camera has moved this far (m); the selection
## bands are widened by MARGIN so no tree misses its LOD in between.
const REFILL_STEP := 3.0
const MARGIN := 6.0
const CHUNK := 1024.0
## Trunk radius (m) at scale 1, from tools/pipeline/vegetation/build_trees.py
## and, for the trees built on scans, assets/models/source/vegetation/trees_summary.json.
const TRUNK_RADIUS := [0.17, 0.16, 0.13, 0.035, 0.3, 0.24, 0.14, 0.11, 0.12]
const TRUNK_HEIGHT := 3.0
## How deep the shade under a crown is for what grows on the ground, by look
## group: spruces and firs hold their branches down to it, a beech lets
## little through, a pine stands high and open.
const CROWN_SHADE := [1.0, 0.8, 0.35]
const COLLIDER_CELL := 128.0

@export var terrain: TerrainSystem
## The Blender map whose colliders keep trees off buildings (placement only).
@export var map: Node3D
@export var camera: Camera3D
## Bodies the obstacle rays pass through besides the terrain (the player).
var exclude: Array[RID] = []
## The level's context (its tavern's portals); null in a tool that builds
## a part of the level alone.
var world: WorldContext

## Where the last mesh LOD gives way to the impostor, m: the quality
## profile's (QualityProfile.tree_mesh_reach) as the forest is built.
var mesh_reach := Vector2.ZERO
var trees: TreeSet
var obstacles: ObstacleMap
## The key of the placement (VegetationCache.prepare), where it came from
## ("stored" or "placed") and what the terrain scan and the key took (ms).
var placement_key := ""
var placement_source := ""
var scan_msec := 0.0
var digest_msec := 0.0
var grid: TreeLodGrid
var grass: GrassField
## Per look group (TreePlacer.SPECIES_GROUP).
var bark_materials: Array[ShaderMaterial] = []
var foliage_materials: Array[ShaderMaterial] = []
## Species index -> material of its scanned trunk (TreeMaterials.TRUNKS).
var trunk_materials := {}
var impostor_material := ShaderMaterial.new()
## Per species: impostor frame width, height and bottom (m at scale 1), look group.
var impostor_frames := PackedVector4Array()
## Per species: the crown's radius (m at scale 1) and CROWN_SHADE.
var crowns := PackedVector2Array()
## Wind on the ground: x, z direction (unit), strength, gust speed (m/s).
var wind := Vector4(0.57, 0.82, 0.5, 6.0)
var load_seconds := 0.0
var refill_usec := 0
var select_usec := 0
## Refill statistics: count, total and worst time (us), uploads.
var refill_stats := Vector4i.ZERO

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
var _last_eye := Vector2(INF, INF)
var _impostor_chunks: Array[MultiMeshInstance3D] = []
var _bodies: Array[RID] = []
var _shapes: Array[RID] = []
## _all_materials() for the per-frame uniforms, and the values they last got.
var _frame_materials: Array[ShaderMaterial] = []
var _sent_eye := Vector3.ZERO
var _sent_wind := Vector4.ZERO
var _sent := false
## The TavernPortals.revision the buffers were last filled by.
var _portal_revision := 0

func _ready() -> void:
	var start := Time.get_ticks_usec()
	mesh_reach = QualityProfile.of(world).tree_mesh_reach
	_load_placement()
	TreeMaterials.make(self)
	grid = TreeLodGrid.new(trees, SPECIES.size())
	grid.measure(impostor_frames)
	TreeLodSlots.make_bands(self)
	TreeImpostors.make(self)
	TreeColliders.make(self)
	_make_grass()
	load_seconds = (Time.get_ticks_usec() - start) / 1e6
	print("VEGETATION trees=%d detail=%d chunks=%d load=%.2fs placement=%s scan=%.0fms digest=%.0fms key=%s" % [trees.size(),
		grid.tree_count(), _impostor_chunks.size(), load_seconds, placement_source, scan_msec, digest_msec,
		placement_key.left(12)])

func _exit_tree() -> void:
	TreeColliders.free_all(self)

## Per mesh LOD: fade-in start, fade-in end, fade-out start, fade-out end (m).
func lod_ranges() -> Array[Vector4]:
	var ranges: Array[Vector4] = []
	ranges.append_array(NEAR_LOD_RANGES)
	var last := NEAR_LOD_RANGES[-1]
	ranges.append(Vector4(last.z, last.w, mesh_reach.x, mesh_reach.y))
	return ranges

## The impostor's fade-in and fade-out (m).
func impostor_range() -> Vector4:
	return Vector4(mesh_reach.x, mesh_reach.y, 1e9, 1e9)

## The terrain and the obstacle grid are built every time: their digest is the
## key of the placement (VegetationCache), which is read from the baked file or
## the runtime cache when one carries it, and placed only when none does.
func _load_placement() -> void:
	var prepared := VegetationCache.prepare(terrain, map, exclude)
	placement_key = prepared.key
	scan_msec = prepared.scan_msec
	digest_msec = prepared.digest_msec
	var cache := VegetationCache.stored(terrain.region, prepared.key, world != null and world.place_trees_anew)
	if cache != null:
		placement_source = "stored"
	else:
		print("VEGETATION placing trees (cached for later runs)...")
		prepared.place()
		cache = prepared
		placement_source = "placed"
		if not prepared.key.is_empty():
			var error := cache.write()
			if error != OK:
				push_warning("Vegetation placement not cached: %s" % error_string(error))
	trees = cache.trees
	obstacles = prepared.obstacles

## Applies [wrap, transmission, tint, ambient] per group to the mesh foliage
## and the impostors alike, so both LOD families light the same.
func set_foliage_look(look: Array) -> void:
	TreeMaterials.set_foliage_look(self, look)

func _eye() -> Vector3:
	var view := camera if camera != null else get_viewport().get_camera_3d()
	return view.global_position if view != null else Vector3.ZERO

func _process(_delta: float) -> void:
	var eye := _eye()
	# A uniform set to the value it already holds changes nothing; skip those.
	if _frame_materials.is_empty():
		_frame_materials = TreeMaterials.all_materials(self)
	var eye_changed := not _sent or eye != _sent_eye
	var wind_changed := not _sent or wind != _sent_wind
	if eye_changed or wind_changed:
		for material: ShaderMaterial in _frame_materials:
			if eye_changed:
				material.set_shader_parameter("lod_camera", eye)
			if wind_changed:
				material.set_shader_parameter("wind", wind)
		_sent = true
		_sent_eye = eye
		_sent_wind = wind
	grass.follow(eye, wind)
	var flat := Vector2(eye.x, eye.z)
	var portals := world.portals if world != null else null
	var revision := portals.revision if portals != null else 0
	if flat.distance_to(_last_eye) >= REFILL_STEP or revision != _portal_revision:
		_portal_revision = revision
		TreeLodSlots.refill(self, flat, portals.sight if portals != null and portals.sight.active else null)

## Trees in each band's buffers (supersets for the faded bands).
func band_counts() -> PackedInt32Array:
	return TreeLodSlots.band_counts(self)

## MultiMesh nodes currently drawn (tiles with trees).
func active_slots() -> int:
	return TreeLodSlots.active_slots(self)

# --- grass --------------------------------------------------------------------

func _make_grass() -> void:
	grass = GrassField.new()
	grass.name = "Grass"
	grass.terrain = terrain
	grass.world = world
	grass.obstacles = obstacles
	grass.woods = grid
	grass.crowns = crowns
	add_child(grass)
