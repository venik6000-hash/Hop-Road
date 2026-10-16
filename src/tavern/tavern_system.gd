class_name TavernSystem
extends Node3D
## The refined tavern (tools/pipeline/tavern/build.py) in place of the Blender
## map's blockout one. The builder remakes the old tavern piece by piece in
## the same places; tavern.json names the old map objects the stages built so
## far replace. Their meshes go; their colliders stay where the new pieces
## fill the same volumes (the vegetation's obstacle scan keeps seeing them),
## and go too where the new pieces bring their own or nothing stands in their
## place (`drop_colliders`): the yard's old paving gave way to the terrain's
## trodden earth. A piece the builder stood elsewhere takes its part of the
## old collider with it (`moved_colliders`): the signpost left the middle of
## the trail to the beach for the corner where that trail leaves the lane.
##
## Materials: one per table entry, found by the name the glTF surfaces carry:
## tavern_surface.gdshader for the building, tavern_glass.gdshader for the
## windows, tavern_foliage.gdshader for the ivy and the flowers,
## tavern_flame.gdshader for the fires. Everything the tavern draws is on LAYER, the only layer its
## interior lights reach, so no light inside shines through a wall onto the
## ground outside. Reflection probes over the rooms hold their ambient light
## to the dim warm light of a room instead of the open sky's. The day comes
## into the ground floor through its openings (TavernDaylight), and through
## the openings of every floor the rooms see the outdoors (TavernPortals).
## The shadows right under small things, which the lamps' shadow maps leave
## out, are a pass on the picture (TavernContactShadows) for the level's
## compositor.

##
## The doorway: the porch ends above the vestibule's flags, and the stones
## that join the two are laid by tavern_threshold.gd; the ground under the
## stone floors is taken down by tavern_ground.gd as the terrain loads.

## The materials, the lights, the colliders and the dressing of the part
## scenes live in these helpers.
const TAVERN_MATERIALS = preload("res://src/tavern/tavern_materials.gd")
const TAVERN_LIGHTS = preload("res://src/tavern/tavern_lights.gd")
const TAVERN_COLLISION = preload("res://src/tavern/tavern_collision.gd")
const TAVERN_DRESSING = preload("res://src/tavern/tavern_dressing.gd")
const TAVERN_THRESHOLD = preload("res://src/tavern/tavern_threshold.gd")
const TAVERN_WEAR = preload("res://src/tavern/tavern_wear.gd")
const SURFACE := TAVERN_MATERIALS.SURFACE
const GLASS := TAVERN_MATERIALS.GLASS
const FLAME := TAVERN_MATERIALS.FLAME
const FOLIAGE := TAVERN_MATERIALS.FOLIAGE
const FUR := TAVERN_MATERIALS.FUR
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
## What never stands still outdoors and casts the sun's shadow: a mill's
## wheel, a goat. A lamp with a shadow draws its map again in every frame in
## which such a thing moves in its light, in the map or not. A village
## building's lamp outdoors that casts a shadow leaves this layer to a twin
## that casts none (VillageBuilding.twin_for_the_restless).
const RESTLESS_LAYER := 8192
## Metres from the building within which the rooms cast the sun's shadows.
const ROOM_SHADOW_REACH := 10.0
## A room's reflection probe is captured in at most this many drawn frames,
## one probe at a time: its six faces, then its roughness levels, the first
## of them face by face.
const PROBE_FRAMES := 24
## The floor of the tavern in the map (the builder's FLOOR), for the grime.
const GROUND := 6.6
const PROBE_PADDING := TAVERN_LIGHTS.PROBE_PADDING
const PROBE_BLEND := TAVERN_LIGHTS.PROBE_BLEND
const BUILDING_BOUNDS := TAVERN_LIGHTS.BUILDING_BOUNDS

var map: Node3D
## The tables of the exported parts (build.py GROUPS; RegionDef.tavern): the
## building's shell, then the interior. Set before the tavern enters the tree.
var parts: PackedStringArray = []
var sky_system: SkySystem
## For the daylight in the rooms: the ridges that take the sun (may be null).
var terrain: TerrainSystem
## The daylight of the rooms, once a table has named its openings.
var daylight: TavernDaylight
## The contact shadows of the rooms' lamps, for the compositor of whoever
## shows the rooms.
var contact_shadows := TavernContactShadows.new()
## What the rooms see of the outdoors, once a table has named the shell's
## openings.
var portals: TavernPortals
## The level's context, which the portals join; null in a tool that builds
## the tavern alone.
var world: WorldContext
var mesh_count := 0
var replaced := 0
var bodies := 0
var doors: Array[TavernDoor] = []
## The hall's cuckoo clock, which calls the game's hours. Made in _ready: a
## VillageBuilding has its own _ready and no clock.
var cuckoo: TavernCuckoo
## The rooms' lamps that burn day and night (TavernLights.add_light): the
## floors between hide them from an eye on another storey (TavernPortals).
var steady_lamps: Array[Light3D] = []
var seats: Array[Dictionary] = []

var _materials := {}
var _flames: Array[Dictionary] = []   # {light, energy, seed, speed, amount, origin, sway}
var _lanterns: Array[Dictionary] = [] # {light, energy}: lit toward dusk
## The rooms' candle flames, in the tavern's space: x, y, z and the flame's
## height (TavernLights.find_candles), for their halos.
var _candles: Array[Vector4] = []
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
## The other buildings whose rooms cast the sun's shadows as the tavern's do
## (world space; see ROOM_SUN_LAYER).
var room_shadow_bounds: Array[AABB] = []
var _room_probes: Array[ReflectionProbe] = []
var _last_probe_hour := -1000.0
var _last_ambient_hour := -1000.0
var _probes_captured := false
## The probes were told to capture and may not be done before the frame
## counted here is drawn (see await_probes()).
var _probes_awaited := false
var _probes_done_at := 0
var _last_dark := -1.0
var _rooms_cast := -1
var _body: StaticBody3D
var _has_interior := false
## The boards the ground floor is walked on, once a table has told how the
## rooms have aged (its `indoor`); NAN until then.
var _walked_floor := NAN
var _shape_cache := {}

func _ready() -> void:
	var start := Time.get_ticks_usec()
	_body = StaticBody3D.new()
	_body.name = "Solid"
	add_child(_body)
	cuckoo = TavernCuckoo.new()
	cuckoo.name = "Cuckoo"
	cuckoo.tavern = self
	add_child(cuckoo)
	_has_interior = parts.size() > 1 and FileAccess.file_exists(parts[1])
	var loaded := 0
	for path: String in parts:
		if FileAccess.file_exists(path):
			_load_part(DataFile.read(path, BuildingSchemas.tavern_part()))
			loaded += 1
	TAVERN_THRESHOLD.build(self)
	_wear_floors()
	TAVERN_LIGHTS.add_hearth_fires(self)
	TAVERN_LIGHTS.add_halos(self)
	contact_shadows.watch(room_lamps(), room_boxes(), global_transform * BUILDING_BOUNDS)
	if portals != null:
		portals.watch_lamps(steady_lamps)
	await_probes()
	_process(0.0)
	var occlusion := preload("res://src/tavern/tavern_occlusion.gd").new()
	occlusion.name = "InteriorOcclusion"
	add_child(occlusion)
	print("TAVERN parts=%d meshes=%d replaced=%d materials=%d lights=%d bodies=%d load=%.2fs" % [loaded,
		mesh_count, replaced, _materials.size(), _flames.size() + _lanterns.size(), bodies,
		(Time.get_ticks_usec() - start) / 1e6])

func _load_part(table: Dictionary) -> void:
	for seat: Dictionary in table.get("seats", []):
		seats.append(seat)
	TAVERN_MATERIALS.build(table, GROUND, _materials)
	TAVERN_MATERIALS.age_indoors(table, _materials, global_transform)
	if table.has("indoor"):
		_walked_floor = float((table.indoor as Dictionary).get("walked", GROUND))
	TAVERN_COLLISION.replace_old(self, table.get("replaces", []), table.get("drop_colliders", []),
		table.get("moved_colliders", []))
	for path: String in table.get("scenes", []):
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		scene.name = path.get_file().get_basename().to_pascal_case()
		add_child(scene)
		for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			TAVERN_DRESSING.dress(self, item, "interior" in path)
		TAVERN_DRESSING.remove_replaced_fire(scene)
		if "interior" in path:
			TAVERN_LIGHTS.find_candles(self, scene)
		_batch(scene, "interior" in path)
	var lights: Array = table.get("lights", [])
	for config: Dictionary in lights:
		TAVERN_LIGHTS.add_light(self, config)
	for config: Dictionary in table.get("probes", []):
		TAVERN_LIGHTS.add_probe(self, config)
	var windows: Array = table.get("windows", [])
	if not windows.is_empty():
		if daylight == null:
			daylight = TavernDaylight.new()
			daylight.name = "Daylight"
			daylight.tavern = self
			daylight.terrain = terrain
			add_child(daylight)
		daylight.add(windows)
	var openings: Array = table.get("portals", [])
	if not openings.is_empty():
		if portals == null:
			portals = TavernPortals.new()
			portals.name = "Portals"
			portals.tavern = self
			portals.world = world
			add_child(portals)
		portals.add(openings, table.get("portal_floors", []))
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
	if _probes_awaited and Engine.get_frames_drawn() > _probes_done_at:
		_probes_awaited = false
		_probes_captured = true
		for probe: ReflectionProbe in _room_probes:
			RenderingServer.instance_set_ignore_culling(probe.get_instance(), false)
	_update_sun_casters()
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		contact_shadows.prepare(camera.global_position)

## The rooms' pieces are in the sun's shadow map only for an eye that can see
## what they shade (see ROOM_SUN_LAYER).
func _update_sun_casters() -> void:
	if sky_system == null:
		return
	var camera := get_viewport().get_camera_3d()
	var near := camera == null or (global_transform * BUILDING_BOUNDS).grow(ROOM_SHADOW_REACH).has_point(camera.global_position)
	for bounds: AABB in room_shadow_bounds:
		near = near or bounds.grow(ROOM_SHADOW_REACH).has_point(camera.global_position)
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
	if absf(hour - _last_ambient_hour) >= 0.5:
		_last_ambient_hour = hour
		var sun_height := SkySystem.solar_direction(hour, sky_system.latitude_deg, sky_system.day_of_year).y
		var daylight := smoothstep(-0.08, 0.3, sun_height)
		for probe: ReflectionProbe in _room_probes:
			probe.ambient_color_energy = lerpf(0.45, 1.6, daylight)
	if absf(hour - _last_probe_hour) < 0.5:
		return
	# A capture keeps the air it was made in, and for an eye outdoors the
	# valley's haze lies over the rooms as well (EyeAdaptation.haze): the first
	# capture has clear air, the later ones wait for an eye in a room.
	if _probes_captured and not _eye_in_a_room():
		return
	_last_probe_hour = hour
	# Requeue one capture when the sun changes, rather than keeping daytime
	# reflections at night or rendering eight cubemaps every frame.
	for probe: ReflectionProbe in _room_probes:
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
	await_probes()

func _eye_in_a_room() -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera != null and EyeAdaptation.indoors(camera.global_position, room_boxes()) > 0.999

## The probes are to capture their rooms. The engine captures a probe only
## once a camera's culling has let it through, so until all have had their
## frames none of them is culled, and probes_awaited() tells whoever hides a
## lamp of the rooms to leave it burning.
## The material of table entry `name` (TavernMaterials), null when the table has none.
func material(name: String) -> Material:
	return _materials.get(name) as Material

func await_probes() -> void:
	_probes_awaited = true
	_probes_done_at = Engine.get_frames_drawn() + PROBE_FRAMES * _room_probes.size()
	for probe: ReflectionProbe in _room_probes:
		RenderingServer.instance_set_ignore_culling(probe.get_instance(), true)

func probes_awaited() -> bool:
	return _probes_awaited

## The rooms' probes have captured their rooms at least once.
func probes_captured() -> bool:
	return _probes_captured

## Hands the worn floors their map of where the ground floor is walked
## (tavern_wear.gd), once every part's colliders, doors and seats are in.
func _wear_floors() -> void:
	if is_nan(_walked_floor):
		return
	var at_doors := PackedVector3Array()
	for door: TavernDoor in doors:
		at_doors.append(door.global_position)
	var at_seats := PackedVector3Array()
	for seat: Dictionary in seats:
		var p: Array = seat.position
		at_seats.append(global_transform * Vector3(p[0], p[1], p[2]))
	var map: Dictionary = TAVERN_WEAR.build(_body, global_transform * BUILDING_BOUNDS,
		_walked_floor + global_position.y, at_doors, at_seats)
	for material: ShaderMaterial in _materials.values():
		var worn: Variant = material.get_shader_parameter("wear")
		if material.shader == SURFACE and worn != null and float(worn) > 0.0:
			material.set_shader_parameter("floor_wear", map.texture)
			material.set_shader_parameter("floor_wear_rect", map.rect)

## The lanterns outdoors that cast shadows.
func shadowed_lanterns() -> Array[Light3D]:
	var lamps: Array[Light3D] = []
	for lantern: Dictionary in _lanterns:
		if (lantern.light as Light3D).shadow_enabled:
			lamps.append(lantern.light)
	return lamps

## The lamps that light the rooms and nothing outdoors.
func room_lamps() -> Array[Light3D]:
	var lamps: Array[Light3D] = []
	for lamp: Light3D in find_children("*", "Light3D", true, false):
		if lamp.light_cull_mask == LAYER:
			lamps.append(lamp)
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
