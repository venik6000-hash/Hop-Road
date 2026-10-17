class_name InteriorLamps
extends Node3D
## The lamps of a building from its tables, the halos of its candles and the
## reflection probes over its rooms (docs/LEVEL.md, «Свет помещений»). The
## node stands at the building's origin: the tables' places are its own.
##
## A row of `lights` that names its `room` is a lamp of that room: it lights
## the rooms' layer (LightLayers.ROOMS) alone, casts the shadows of what
## stands still (LightLayers.LAMP_CASTERS), burns day and night, and takes its
## shadow and the size of its light from its `kind` (LightProfile.lamp_kind).
## A row without one says where it shines itself (`layer`) and whether it is
## a lantern lit toward dusk (`night`). A lamp that flickers (`flicker`) does
## so every frame, and one that sways (`sway`) moves about its place.
##
## A probe takes its room's box grown by the walls, and the ambient light of
## the room's profile: dimmer at night. It captures its room again every half
## hour of the game's day while the eye is in the building (a capture keeps the
## air it was made in), and the first time in clear air (Interiors).

## Keep the sky/room blend inside the wall thickness, below the floor and
## above the ceiling, including the recessed mortar between the stones.
const PROBE_BLEND := 0.1
## A room's reflection probe is captured in at most this many drawn frames,
## one probe at a time: its six faces, then its roughness levels, the first
## of them face by face.
const PROBE_FRAMES := 24
## Hours of the game's day between two captures and two changes of the probes' ambient light.
const PROBE_HOURS := 0.5
const HALO := preload("res://src/light/candle_halo.gdshader")
## The rooms' candle flames carry this material; a flame taller than
## HALO_TALLEST is no candle's.
const CANDLE_FLAME := "tav_flame"
const HALO_TALLEST := 0.14
## A halo's half-width for a flame's height, and its bounds, m.
const HALO_PER_HEIGHT := 5.0
const HALO_RADIUS := Vector2(0.14, 0.3)
## Vertices this near each other (across, up) are one flame's, m.
const ONE_FLAME := Vector2(0.035, 0.12)
## Halos are not drawn from further than this, m.
const HALO_REACH := 40.0
## An omni lamp's shadow bias is metres along the ray: 3 mm a metre of its
## range (the map's texels widen with the distance), within these limits. Its
## normal bias turns the lookup away from a surface by up to 10/512 of the
## value in radians (a texel is 0.004-0.008), the more the surface leans from
## the lamp, which holds a floor lit at a grazing angle clear of its own map
## without the depth bias that eats the shadows of small things on a table. A
## lamp with an area (light_size) hangs low over such a floor.
const BIAS_PER_RANGE := 0.003
const BIAS_LIMITS := Vector2(0.008, 0.02)
const NORMAL_BIAS := 0.6
const NORMAL_BIAS_AREA := 0.8

var sky: SkySystem
## The building's rooms: whether the eye is in one, for the captures.
var interior: Interior
## {light, energy, seed, speed, amount, origin, sway}
var flames: Array[Dictionary] = []
## {light, energy}: lit toward dusk.
var lanterns: Array[Dictionary] = []
## The rooms' candle flames, in the building's space: x, y, z and the flame's
## height (find_candles()), for their halos.
var candles: Array[Vector4] = []
## What the lanterns and the lit windows are from far away, in the building's
## space: {at, color, radius, facing} (see FarLights.add_glow).
var far_glows: Array[Dictionary] = []
## The rooms' lamps, which burn day and night.
var steady: Array[Light3D] = []
var probes: Array[ReflectionProbe] = []

var _probe_rooms: Array[Interior.Room] = []
# flames as typed columns (see _cache_flames).
var _flame_lights: Array[Light3D] = []
var _flame_energies := PackedFloat64Array()
var _flame_amounts := PackedFloat64Array()
var _flame_seeds := PackedFloat64Array()
var _flame_speeds := PackedFloat64Array()
var _flame_sways := PackedFloat64Array()
var _flame_origins := PackedVector3Array()
## The share of its energy each flame burns at (set_strength()), by its light.
var _strengths := {}
var _last_probe_hour := -1000.0
var _last_ambient_hour := -1000.0
var _probes_captured := false
## The probes were told to capture and may not be done before the frame
## counted here is drawn (see await_probes()).
var _probes_awaited := false
var _probes_done_at := 0
var _last_dark := -1.0

## Adds the lamp of a row of `lights`. A point lamp outdoors whose light
## reaches `near` (the building's box in its space, none when empty) casts
## the shadows of the walls it lights.
func add_light(config: Dictionary, near := AABB()) -> Light3D:
	var light: Light3D
	var color: Array = config.color
	if config.type == "spot":
		var spot := SpotLight3D.new()
		spot.spot_range = config.range
		spot.spot_angle = config.get("angle", 50.0)
		spot.spot_attenuation = 1.0
		spot.spot_angle_attenuation = 1.6
		light = spot
	else:
		var omni := OmniLight3D.new()
		omni.omni_range = config.range
		omni.omni_attenuation = 1.0
		light = omni
	light.name = config.name
	light.light_color = Color(Values.real(color[0]), Values.real(color[1]), Values.real(color[2]))
	light.light_energy = config.energy
	var p: Array = config.position
	light.position = Values.vec3(p)
	var of_room := config.has("room")
	var layer := "interior" if of_room else str(config.get("layer", "interior"))
	if of_room:
		var kind := LightProfile.lamp_kind(str(config.kind))
		light.shadow_enabled = Values.flag(kind.shadow)
		light.light_size = Values.real(kind.size) if light.shadow_enabled else 0.0
	else:
		# A shared render layer does not stop light crossing floors or
		# partitions: a point lamp outdoors that reaches the building casts
		# the shadows of its walls.
		var reaches := near.has_volume() and near.grow(Values.real(config.range)).has_point(light.position)
		light.shadow_enabled = config.shadow or layer == "interior" or (config.type == "point" and reaches)
		# Costly area-shadow filtering for the authored large sources only.
		light.light_size = config.get("size", 0.05) if config.shadow else 0.0
	if light is OmniLight3D:
		light.shadow_bias = omni_shadow_bias(Values.real(config.range))
		light.shadow_normal_bias = NORMAL_BIAS_AREA if light.light_size > 0.0 else NORMAL_BIAS
	else:
		light.shadow_bias = 0.02
		light.shadow_normal_bias = 0.2
	add_child(light)
	if config.type == "spot":
		var d: Array = config.direction
		var forward := Values.vec3(d).normalized()
		var up := Vector3.UP if absf(forward.y) < 0.95 else Vector3.FORWARD
		light.look_at(light.position + forward, up)
	var night: float = 0.0 if of_room else config.get("night", 0.0)
	match layer:
		"interior":
			light.light_cull_mask = LightLayers.ROOMS
			light.shadow_caster_mask = LightLayers.LAMP_CASTERS
			FarLights.fade(light, "interior")
			if night <= 0.5:
				steady.append(light)
		"exterior":
			FarLights.fade(light, "spill" if config.type == "spot" else "lantern")
			# Outside: the ground and the building's own still walls, not the
			# trees and not the ivy (see LightLayers.LAMP_CASTERS).
			light.shadow_caster_mask = 0xFFFFFFFF & ~VegetationSystem.VISUAL_LAYER & ~LightLayers.ROOMS \
				& ~LightLayers.SUN_ONLY
	var amount: float = config.get("flicker", 0.0)
	if night > 0.5:
		lanterns.append({"light": light, "energy": config.energy})
		# A lantern has a halo in the fog; a window's spill has none.
		if config.type != "spot":
			light.add_to_group(AtmosphereFog.LAMP_GROUP)
		# Far away the lantern is a glow, and so is the window a spot spills from.
		far_glows.append({"at": light.position, "color": light.light_color,
			"radius": 0.3 if config.type == "spot" else 0.22,
			"facing": -light.basis.z if config.type == "spot" else Vector3.ZERO})
	elif amount > 0.0:
		flames.append({"light": light, "energy": config.energy, "amount": amount,
			"seed": float(hash(config.name) % 1000) * 0.37, "speed": config.get("speed", 1.0),
			"origin": light.position, "sway": config.get("sway", 0.0)})
	return light

## The shadow bias of an omni lamp of `reach` metres.
static func omni_shadow_bias(reach: float) -> float:
	return clampf(BIAS_PER_RANGE * reach, BIAS_LIMITS.x, BIAS_LIMITS.y)

## Adds the reflection probe over `room`, called `title`.
func add_probe(room: Interior.Room, title: String) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = title
	probe.position = room.probe_centre()
	probe.size = room.probe_size()
	probe.interior = true
	probe.box_projection = true
	probe.enable_shadows = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	# Interpret the table's small ambient values as linear irradiance. Color
	# properties are decoded from sRGB by the renderer, so encode them first.
	probe.ambient_color = room.ambient.linear_to_srgb()
	probe.ambient_color_energy = 1.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	# Both layers: a capture draws the lamps' shadows only from casters it sees.
	probe.cull_mask = LightLayers.ROOMS | LightLayers.LAMP_CASTERS
	probe.reflection_mask = LightLayers.ROOMS
	probe.blend_distance = PROBE_BLEND
	add_child(probe)
	probes.append(probe)
	_probe_rooms.append(room)
	return probe

## Notes where the candle flames of `scene` burn (in the building's space)
## and how tall they are, before its meshes are batched: `candles` gets a
## Vector4 (x, y, z, height) for each.
func find_candles(scene: Node3D) -> void:
	var to_building := global_transform.affine_inverse()
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface)
			if material == null or material.resource_name != CANDLE_FLAME:
				continue
			var placed := to_building * item.global_transform
			var found: Array[AABB] = []
			for vertex: Vector3 in item.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var at := placed * vertex
				var known := false
				for index in found.size():
					var middle := found[index].get_center()
					if Vector2(at.x - middle.x, at.z - middle.z).length() < ONE_FLAME.x and absf(at.y - middle.y) < ONE_FLAME.y:
						found[index] = found[index].expand(at)
						known = true
						break
				if not known:
					found.append(AABB(at, Vector3.ZERO))
			for flame: AABB in found:
				if flame.size.y <= HALO_TALLEST:
					var middle := flame.get_center()
					candles.append(Vector4(middle.x, middle.y, middle.z, flame.size.y))

## The glow round every candle flame found (candle_halo.gdshader), in one
## MultiMesh inside `bounds` (the building's box in its space).
func add_halos(bounds: AABB) -> void:
	if candles.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = HALO
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = candles.size()
	for index in candles.size():
		var candle := candles[index]
		var radius := clampf(candle.w * HALO_PER_HEIGHT, HALO_RADIUS.x, HALO_RADIUS.y)
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * radius),
			Vector3(candle.x, candle.y, candle.z)))
	multimesh.custom_aabb = bounds
	var halos := MultiMeshInstance3D.new()
	halos.name = "CandleHalos"
	halos.multimesh = multimesh
	halos.layers = LightLayers.ROOMS
	halos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halos.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	halos.visibility_range_end = HALO_REACH + bounds.get_longest_axis_size()
	add_child(halos)

## The flickering lamp of the table called `lamp` burns at `strength` of its
## energy from now on: a fire stoked, let die or blown by the bellows.
func set_strength(lamp: String, strength: float) -> void:
	for flame: Dictionary in flames:
		var light: Light3D = flame.light
		if str(light.name) == lamp:
			_strengths[light] = strength
	for index in _flame_lights.size():
		var light := _flame_lights[index]
		if _strengths.has(light):
			_flame_energies[index] = Values.real(flames[index].energy) * Values.real(_strengths[light])

## The lanterns outdoors that cast shadows.
func shadowed_lanterns() -> Array[Light3D]:
	var lamps: Array[Light3D] = []
	for lantern: Dictionary in lanterns:
		var light: Light3D = lantern.light
		if light.shadow_enabled:
			lamps.append(light)
	return lamps

## The lamps that light the rooms and nothing outdoors.
func room_lamps() -> Array[Light3D]:
	var lamps: Array[Light3D] = []
	for lamp: Light3D in find_children("*", "Light3D", true, false):
		if lamp.light_cull_mask == LightLayers.ROOMS:
			lamps.append(lamp)
	return lamps

## The probes are to capture their rooms. The engine captures a probe only
## once a camera's culling has let it through, so until all have had their
## frames none of them is culled, and probes_awaited() tells whoever hides a
## lamp of the rooms to leave it burning.
func await_probes() -> void:
	_probes_awaited = true
	_probes_done_at = Engine.get_frames_drawn() + PROBE_FRAMES * probes.size()
	for probe: ReflectionProbe in probes:
		RenderingServer.instance_set_ignore_culling(probe.get_instance(), true)

func probes_awaited() -> bool:
	return _probes_awaited

## The rooms' probes have captured their rooms at least once.
func probes_captured() -> bool:
	return _probes_captured

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if _flame_lights.size() != flames.size():
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
	if sky != null and not lanterns.is_empty():
		# Lanterns outside are lit toward dusk and burn through the night.
		var dark := 1.0 - smoothstep(-0.02, 0.18, sky.sun_direction.y)
		# Day/night plateaus do not need identical RenderingServer updates.
		if dark != _last_dark:
			_last_dark = dark
			for lantern: Dictionary in lanterns:
				var light: Light3D = lantern.light
				light.light_energy = lantern.energy * dark
				light.visible = dark > 0.01
	_update_probes()
	if _probes_awaited and Engine.get_frames_drawn() > _probes_done_at:
		_probes_awaited = false
		_probes_captured = true
		for probe: ReflectionProbe in probes:
			RenderingServer.instance_set_ignore_culling(probe.get_instance(), false)

## Copies flames into typed arrays for _process (the same values, no
## per-frame Dictionary lookups). `flames` stays the record tools read.
func _cache_flames() -> void:
	_flame_lights.clear()
	_flame_energies.clear()
	_flame_amounts.clear()
	_flame_seeds.clear()
	_flame_speeds.clear()
	_flame_sways.clear()
	_flame_origins.clear()
	for flame: Dictionary in flames:
		var light: Light3D = flame.light
		_flame_lights.append(light)
		_flame_energies.append(Values.real(flame.energy) * Values.real(_strengths.get(light, 1.0)))
		_flame_amounts.append(Values.real(flame.amount))
		_flame_seeds.append(Values.real(flame.seed))
		_flame_speeds.append(Values.real(flame.speed))
		_flame_sways.append(Values.real(flame.sway))
		var origin: Vector3 = flame.origin
		_flame_origins.append(origin)

func _update_probes() -> void:
	if sky == null:
		return
	var hour := sky.time_of_day
	if absf(hour - _last_ambient_hour) >= PROBE_HOURS:
		_last_ambient_hour = hour
		var sun_height := SkySystem.solar_direction(hour, sky.latitude_deg, sky.day_of_year).y
		var daylight := smoothstep(-0.08, 0.3, sun_height)
		for index in probes.size():
			var ambient := _probe_rooms[index].profile.ambient
			probes[index].ambient_color_energy = lerpf(ambient.y, ambient.x, daylight)
	if absf(hour - _last_probe_hour) < PROBE_HOURS:
		return
	# A capture keeps the air it was made in, and for an eye outdoors the
	# valley's haze lies over the rooms as well (EyeAdaptation.haze): the first
	# capture has clear air, the later ones wait for an eye in a room.
	if _probes_captured and not _eye_in_a_room():
		return
	_last_probe_hour = hour
	# Requeue one capture when the sun changes, rather than keeping daytime
	# reflections at night or rendering every room's cubemap every frame.
	for probe: ReflectionProbe in probes:
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
	await_probes()

func _eye_in_a_room() -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera != null and interior != null and Interiors.share(interior.depth_of(camera.global_position)) > 0.999
