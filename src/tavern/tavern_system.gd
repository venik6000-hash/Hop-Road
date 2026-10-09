class_name TavernSystem
extends Node3D
## The refined tavern (tools/pipeline/tavern/build.py) in place of the Blender
## map's blockout one. The builder remakes the old tavern piece by piece in
## the same places; tavern.json names the old map objects the stages built so
## far replace. Their meshes go; their colliders stay where the new pieces
## fill the same volumes (the vegetation's obstacle scan keeps seeing them),
## and go too where the new pieces bring their own (`drop_colliders`).
##
## Materials: one per table entry, found by the name the glTF surfaces carry:
## tavern_surface.gdshader for the building, tavern_glass.gdshader for the
## windows, tavern_foliage.gdshader for the ivy and the flowers,
## tavern_flame.gdshader for the fires. Everything the tavern draws is on LAYER, the only layer its
## interior lights reach, so no light inside shines through a wall onto the
## ground outside. Reflection probes over the rooms hold their ambient light
## to the dim warm light of a room instead of the open sky's.

## The exported parts (build.py GROUPS): the building's shell, the interior.
const PARTS := ["res://assets/models/tavern/tavern.json", "res://assets/models/tavern/tavern_interior.json"]
## The materials, the lights, the colliders and the dressing of the part
## scenes live in these helpers.
const TAVERN_MATERIALS = preload("res://src/tavern/tavern_materials.gd")
const TAVERN_LIGHTS = preload("res://src/tavern/tavern_lights.gd")
const TAVERN_COLLISION = preload("res://src/tavern/tavern_collision.gd")
const TAVERN_DRESSING = preload("res://src/tavern/tavern_dressing.gd")
const SURFACE := TAVERN_MATERIALS.SURFACE
const GLASS := TAVERN_MATERIALS.GLASS
const FLAME := TAVERN_MATERIALS.FLAME
const FOLIAGE := TAVERN_MATERIALS.FOLIAGE
const LAYER := 512
## The still pieces, which alone go into the shadow maps of the tavern's lamps.
## A lamp keeps its shadow map while nothing in it moves, and draws all six
## faces of it again in every frame in which a caster in its reach moves or
## has an animated material. The fluttering ivy, the flames and the people are
## therefore on LAYER alone: lit by the lamps, not drawn into their shadows.
const SHADOW_LAYER := 1024
## The sun's shadow map leaves both layers above out and draws the tavern by
## these: the shell always, the rooms' pieces only while the eye is in or near
## the building. From the yard nobody sees the shadow a stool casts in a
## window's light, yet the rooms were four tenths of the tavern's triangles
## in every cascade.
const SUN_LAYER := 2048
const ROOM_SUN_LAYER := 4096
## Both are the sun's alone: a lantern's shadow map must leave them out, or
## the ivy they carry is drawn into it again in every frame.
const SUN_LAYERS := SUN_LAYER | ROOM_SUN_LAYER
## Metres from the building within which the rooms cast the sun's shadows.
const ROOM_SHADOW_REACH := 10.0
## The floor of the tavern in the map (the builder's FLOOR), for the grime.
const GROUND := 6.6
const PROBE_PADDING := TAVERN_LIGHTS.PROBE_PADDING
const PROBE_BLEND := TAVERN_LIGHTS.PROBE_BLEND
const BUILDING_BOUNDS := TAVERN_LIGHTS.BUILDING_BOUNDS

var map: Node3D
var sky_system: SkySystem
var mesh_count := 0
var replaced := 0
var bodies := 0
var doors: Array[TavernDoor] = []
var seats: Array[Dictionary] = []

var _materials := {}
var _flames: Array[Dictionary] = []   # {light, energy, seed, speed, amount, origin, sway}
var _lanterns: Array[Dictionary] = [] # {light, energy}: lit toward dusk
## What the lanterns and the lit windows are from far away, in the tavern's
## space: {at, color, radius, facing} (see FarLights.add_glow).
var far_glows: Array[Dictionary] = []
# _flames as typed columns (see _cache_flames).
var _flame_lights: Array[Light3D] = []
var _flame_energies := PackedFloat64Array()
var _flame_amounts := PackedFloat64Array()
var _flame_seeds := PackedFloat64Array()
var _flame_speeds := PackedFloat64Array()
var _flame_sways := PackedFloat64Array()
var _flame_origins := PackedVector3Array()
var _room_probes: Array[ReflectionProbe] = []
var _last_probe_hour := -1000.0
var _last_dark := -1.0
var _rooms_cast := -1
var _body: StaticBody3D
var _has_interior := false
var _shape_cache := {}

func _ready() -> void:
	var start := Time.get_ticks_usec()
	_body = StaticBody3D.new()
	_body.name = "Solid"
	add_child(_body)
	_has_interior = FileAccess.file_exists(PARTS[1])
	var parts := 0
	for path: String in PARTS:
		if FileAccess.file_exists(path):
			_load_part(JSON.parse_string(FileAccess.get_file_as_string(path)))
			parts += 1
	TAVERN_LIGHTS.add_hearth_fires(self)
	_process(0.0)
	var occlusion := preload("res://src/tavern/tavern_occlusion.gd").new()
	occlusion.name = "InteriorOcclusion"
	add_child(occlusion)
	print("TAVERN parts=%d meshes=%d replaced=%d materials=%d lights=%d bodies=%d load=%.2fs" % [parts,
		mesh_count, replaced, _materials.size(), _flames.size() + _lanterns.size(), bodies,
		(Time.get_ticks_usec() - start) / 1e6])

func _load_part(table: Dictionary) -> void:
	for seat: Dictionary in table.get("seats", []):
		seats.append(seat)
	TAVERN_MATERIALS.build(table, GROUND, _materials)
	TAVERN_COLLISION.replace_old(self, table.get("replaces", []), table.get("drop_colliders", []))
	for path: String in table.get("scenes", []):
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		scene.name = path.get_file().get_basename().to_pascal_case()
		add_child(scene)
		for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			TAVERN_DRESSING.dress(self, item, "interior" in path)
		TAVERN_DRESSING.remove_replaced_fire(scene)
		_batch(scene, "interior" in path)
	var lights: Array = table.get("lights", [])
	for config: Dictionary in lights:
		TAVERN_LIGHTS.add_light(self, config)
	for config: Dictionary in table.get("probes", []):
		TAVERN_LIGHTS.add_probe(self, config)
	# Once the rooms have lights of their own, the level's two stand-in
	# lanterns (manifest lights hung in the hall) go.
	if lights.any(func(config: Dictionary) -> bool: return config.get("layer", "interior") == "interior"):
		for lamp: Node in get_tree().get_nodes_in_group(&"tavern_lantern"):
			lamp.queue_free()

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if _flame_lights.size() != _flames.size():
		_cache_flames()
	# Flicker and sway change every frame, so every flame is written every frame.
	for index: int in _flame_lights.size():
		var s := _flame_seeds[index]
		var k := _flame_speeds[index]
		var wave := 0.55 * sin(t * 7.3 * k + s) + 0.3 * sin(t * 13.1 * k + s * 2.1) + 0.15 * sin(t * 23.7 * k + s * 3.7)
		var light := _flame_lights[index]
		light.light_energy = _flame_energies[index] * (1.0 + _flame_amounts[index] * wave)
		var sway := _flame_sways[index]
		if sway > 0.0:
			light.position = _flame_origins[index] + Vector3(sin(t * 5.1 + s), sin(t * 3.3 + s * 1.7) * 0.5,
				cos(t * 4.4 + s * 0.6)) * sway
	if sky_system != null and not _lanterns.is_empty():
		# Lanterns outside are lit toward dusk and burn through the night.
		var dark := 1.0 - smoothstep(-0.02, 0.18, sky_system.sun_direction.y)
		# Day/night plateaus do not need identical RenderingServer updates.
		if dark != _last_dark:
			_last_dark = dark
			for lantern: Dictionary in _lanterns:
				(lantern.light as Light3D).light_energy = lantern.energy * dark
				(lantern.light as Light3D).visible = dark > 0.01
	_update_room_lighting()
	_update_sun_casters()

## The rooms' pieces are in the sun's shadow map only for an eye that can see
## what they shade (see ROOM_SUN_LAYER).
func _update_sun_casters() -> void:
	if sky_system == null:
		return
	var camera := get_viewport().get_camera_3d()
	var near := camera == null or (global_transform * BUILDING_BOUNDS).grow(ROOM_SHADOW_REACH).has_point(camera.global_position)
	if int(near) == _rooms_cast:
		return
	_rooms_cast = int(near)
	var mask := 0xFFFFFFFF & ~LAYER & ~SHADOW_LAYER
	if not near:
		mask &= ~ROOM_SUN_LAYER
	sky_system.sun.shadow_caster_mask = mask
	sky_system.moon.shadow_caster_mask = mask

## Copies _flames into typed arrays for _process (the same values, no
## per-frame Dictionary lookups). _flames stays the record tools read.
func _cache_flames() -> void:
	_flame_lights.clear()
	_flame_energies.clear()
	_flame_amounts.clear()
	_flame_seeds.clear()
	_flame_speeds.clear()
	_flame_sways.clear()
	_flame_origins.clear()
	for flame: Dictionary in _flames:
		_flame_lights.append(flame.light)
		_flame_energies.append(flame.energy)
		_flame_amounts.append(flame.amount)
		_flame_seeds.append(flame.seed)
		_flame_speeds.append(flame.speed)
		_flame_sways.append(flame.sway)
		_flame_origins.append(flame.origin)

func _update_room_lighting() -> void:
	if sky_system == null:
		return
	var hour := sky_system.time_of_day
	if absf(hour - _last_probe_hour) < 0.5:
		return
	_last_probe_hour = hour
	var sun_height := SkySystem.solar_direction(hour, sky_system.latitude_deg, sky_system.day_of_year).y
	var daylight := smoothstep(-0.08, 0.3, sun_height)
	for probe: ReflectionProbe in _room_probes:
		probe.ambient_color_energy = lerpf(0.65, 1.6, daylight)
		# Requeue one capture when the sun changes, rather than keeping daytime
		# reflections at night or rendering eight cubemaps every frame.
		probe.update_mode = ReflectionProbe.UPDATE_ONCE

## The lanterns outdoors that cast shadows.
func shadowed_lanterns() -> Array[Light3D]:
	var lamps: Array[Light3D] = []
	for lantern: Dictionary in _lanterns:
		if (lantern.light as Light3D).shadow_enabled:
			lamps.append(lantern.light)
	return lamps

## The rooms as boxes in world space (the reach of their reflection probes).
func room_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for probe: ReflectionProbe in _room_probes:
		boxes.append(AABB(probe.global_position - probe.size * 0.5, probe.size))
	return boxes

## Spatial batches retain local culling and the dressed surface materials.
func _batch(root: Node3D, interior := false) -> void:
	preload("res://src/tavern/tavern_batching.gd").apply(root, self, SURFACE, interior)
