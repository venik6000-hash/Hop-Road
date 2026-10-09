extends RefCounted
## Sample the world at the wrist; the private viewport cannot see its walls.
const LOCAL_LIGHT_LIMIT := 4
const SAMPLE_SECONDS := 0.1
var _local_sources: Array[Light3D] = []
var _probes: Array[ReflectionProbe] = []
var _active_sources: Array[Light3D] = []
var _proxies: Array[Light3D] = []
var _sample_time := SAMPLE_SECONDS
var _sun_visible := true
var _moon_visible := true
var _room: ReflectionProbe
var _room_sky: Sky
var _room_material: ShaderMaterial
var _source_world: World3D
var _registry_tree: SceneTree
var _ray := PhysicsRayQueryParameters3D.new()

func sync(presentation: Node3D, world_camera: Camera3D, sky: SkySystem, delta: float) -> void:
	if world_camera == null or not world_camera.is_inside_tree(): return
	var world := world_camera.get_world_3d()
	if _source_world != world:
		_source_world = world
		_sample_time = SAMPLE_SECONDS
	if _registry_tree != world_camera.get_tree():
		_cache_sources(world_camera)
	_sample_time += delta
	if _sample_time >= SAMPLE_SECONDS:
		_sample_time = 0.0
		_sample(world_camera, sky, world_camera.to_global(presentation.pivot.position))
	var source := world_camera.environment
	if source == null: source = world.environment
	var indoors := is_instance_valid(_room)
	if source != null:
		var environment: Environment = presentation.environment
		if not indoors:
			_assign(environment, &"sky", source.sky)
		_assign(environment, &"sky_rotation", (world_camera.global_basis.inverse() * Basis.from_euler(source.sky_rotation)).get_euler())
		_assign(environment, &"tonemap_mode", source.tonemap_mode)
		_assign(environment, &"tonemap_exposure", source.tonemap_exposure)
		_assign(environment, &"tonemap_white", source.tonemap_white)
		if not indoors:
			_assign(environment, &"ambient_light_source", source.ambient_light_source)
			_assign(environment, &"ambient_light_color", source.ambient_light_color)
			_assign(environment, &"ambient_light_energy", source.ambient_light_energy)
			_assign(environment, &"ambient_light_sky_contribution", source.ambient_light_sky_contribution)
			_assign(environment, &"reflected_light_source", source.reflected_light_source)
	if indoors: _sync_room(presentation.environment)
	if sky != null and sky.sun != null and sky.moon != null:
		_sync_directional(presentation.key, sky.sun, world_camera, _sun_visible)
		_sync_directional(presentation.fill_light, sky.moon, world_camera, _moon_visible)
	_sync_local(presentation, world_camera)
	if presentation.fluid != null and presentation.fluid.material != null:
		var material: ShaderMaterial = presentation.fluid.material
		_uniform(material, &"physical_sky", sky != null and not indoors)
		_uniform(material, &"view_to_world", world_camera.global_basis)
		_uniform(material, &"indoor_lighting", indoors)
		if indoors:
			var ambient := _room.ambient_color.srgb_to_linear() * _room.ambient_color_energy
			_uniform(material, &"indoor_ambient", Vector3(ambient.r, ambient.g, ambient.b))

## One initial tree walk, then exact membership updates. Eligibility is checked
## when sampling so world, visibility and interior-property changes stay live.
func _cache_sources(viewer: Camera3D) -> void:
	if is_instance_valid(_registry_tree):
		_registry_tree.node_added.disconnect(_track_added)
		_registry_tree.node_removed.disconnect(_track_removed)
	_registry_tree = viewer.get_tree()
	_local_sources.clear()
	_probes.clear()
	var pending: Array[Node] = [_registry_tree.root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		_track_added(node)
		var children := node.get_children()
		children.reverse()
		pending.append_array(children)
	_registry_tree.node_added.connect(_track_added)
	_registry_tree.node_removed.connect(_track_removed)

func _track_added(node: Node) -> void:
	if node is Light3D and not node is DirectionalLight3D:
		_local_sources.append(node)
	elif node is ReflectionProbe:
		_probes.append(node)

func _track_removed(node: Node) -> void:
	if node is Light3D:
		_local_sources.erase(node)
		_active_sources.erase(node)
	elif node is ReflectionProbe:
		_probes.erase(node)

## Check the current target value, rather than a stale source cache: a different
## presentation, source environment or indoor override gets its full final state.
static func _assign(target: Object, property: StringName, value: Variant) -> void:
	if target.get(property) != value:
		target.set(property, value)

static func _uniform(target: ShaderMaterial, parameter: StringName, value: Variant) -> void:
	if target.get_shader_parameter(parameter) != value:
		target.set_shader_parameter(parameter, value)

static func probe_contains(probe: ReflectionProbe, point: Vector3, transform: Transform3D) -> bool:
	return AABB(-probe.size * 0.5, probe.size).has_point(transform.affine_inverse() * point)

static func local_strength(light: Light3D, point: Vector3, transform: Transform3D) -> float:
	var range_m := 0.0
	if light is OmniLight3D: range_m = light.omni_range
	elif light is SpotLight3D:
		range_m = light.spot_range
		var toward := (point - transform.origin).normalized()
		if toward.dot(-transform.basis.z.normalized()) < cos(deg_to_rad(light.spot_angle)): return 0.0
	var distance := transform.origin.distance_to(point)
	if range_m <= 0.0 or distance >= range_m: return 0.0
	return light.light_energy * (1.0 - distance / range_m) / maxf(distance * distance, 0.25)

func _sample(viewer: Camera3D, sky: SkySystem, point: Vector3) -> void:
	var exclude: Array[RID] = []
	var ancestor: Node = viewer
	while ancestor != null:
		if ancestor is CollisionObject3D: exclude.append(ancestor.get_rid())
		ancestor = ancestor.get_parent()
	_ray.collision_mask = 1
	_ray.exclude = exclude
	_room = null
	var room_volume := INF
	for probe in _probes:
		if not is_instance_valid(probe) or probe.get_world_3d() != _source_world \
				or not probe.interior or probe.ambient_mode != ReflectionProbe.AMBIENT_COLOR \
				or not probe.is_visible_in_tree() or not probe_contains(probe, point, probe.global_transform): continue
		var volume := probe.size.x * probe.size.y * probe.size.z
		if volume < room_volume:
			_room = probe
			room_volume = volume
	if sky != null and sky.sun != null and sky.moon != null:
		_sun_visible = not sky.sun.shadow_enabled or _unblocked(viewer, point, point + sky.sun.global_basis.z * 128.0)
		_moon_visible = not sky.moon.shadow_enabled or _unblocked(viewer, point, point + sky.moon.global_basis.z * 128.0)
	var ranked: Array[Dictionary] = []
	for light in _local_sources:
		if not is_instance_valid(light) or light.get_world_3d() != _source_world or not light.is_visible_in_tree(): continue
		var strength := local_strength(light, point, light.global_transform)
		if strength > 0.0: ranked.append({"light": light, "strength": strength})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.strength > b.strength)
	_active_sources.clear()
	for candidate in ranked:
		var light: Light3D = candidate.light
		if light.shadow_enabled and not _unblocked(viewer, point, light.global_position): continue
		_active_sources.append(light)
		if _active_sources.size() == LOCAL_LIGHT_LIMIT: break

func _unblocked(_viewer: Camera3D, from: Vector3, to: Vector3) -> bool:
	_ray.from = from
	_ray.to = to
	return _source_world.direct_space_state.intersect_ray(_ray).is_empty()

func _sync_directional(target: DirectionalLight3D, source: DirectionalLight3D,
		viewer: Camera3D, unblocked: bool) -> void:
	_assign(target, &"basis", viewer.global_basis.inverse() * source.global_basis)
	_assign(target, &"light_color", source.light_color)
	_assign(target, &"light_energy", source.light_energy if unblocked and source.is_visible_in_tree() else 0.0)

func _sync_room(environment: Environment) -> void:
	if _room_sky == null:
		_room_sky = Sky.new()
		_room_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type sky; uniform vec3 room_color; void sky() { COLOR = room_color; }"
		_room_material.shader = shader
		_room_sky.sky_material = _room_material
	var color := _room.ambient_color.srgb_to_linear() * _room.ambient_color_energy
	_uniform(_room_material, &"room_color", Vector3(color.r, color.g, color.b))
	_assign(environment, &"sky", _room_sky)
	_assign(environment, &"ambient_light_source", Environment.AMBIENT_SOURCE_COLOR)
	_assign(environment, &"ambient_light_color", _room.ambient_color)
	_assign(environment, &"ambient_light_energy", _room.ambient_color_energy)
	_assign(environment, &"ambient_light_sky_contribution", 0.0)
	_assign(environment, &"reflected_light_source", Environment.REFLECTION_SOURCE_SKY)

func _sync_local(presentation: Node3D, viewer: Camera3D) -> void:
	for index in LOCAL_LIGHT_LIMIT:
		if index >= _active_sources.size():
			if index < _proxies.size(): _assign(_proxies[index], &"visible", false)
			continue
		var source := _active_sources[index]
		if not is_instance_valid(source):
			if index < _proxies.size(): _assign(_proxies[index], &"visible", false)
			continue
		var is_spot := source is SpotLight3D
		if index >= _proxies.size(): _proxies.append(null)
		if _proxies[index] == null or (_proxies[index] is SpotLight3D) != is_spot:
			if _proxies[index] != null: _proxies[index].queue_free()
			_proxies[index] = SpotLight3D.new() if is_spot else OmniLight3D.new()
			_proxies[index].name = "WorldLight%d" % index
			presentation.add_child(_proxies[index])
		var proxy := _proxies[index]
		_assign(proxy, &"transform", viewer.global_transform.affine_inverse() * source.global_transform)
		_assign(proxy, &"visible", source.is_visible_in_tree())
		_assign(proxy, &"light_color", source.light_color)
		_assign(proxy, &"light_energy", source.light_energy)
		_assign(proxy, &"light_specular", source.light_specular)
		_assign(proxy, &"light_size", source.light_size)
		_assign(proxy, &"shadow_enabled", source.shadow_enabled)
		if is_spot:
			_assign(proxy, &"spot_range", source.spot_range)
			_assign(proxy, &"spot_attenuation", source.spot_attenuation)
			_assign(proxy, &"spot_angle", source.spot_angle)
			_assign(proxy, &"spot_angle_attenuation", source.spot_angle_attenuation)
		else:
			_assign(proxy, &"omni_range", source.omni_range)
			_assign(proxy, &"omni_attenuation", source.omni_attenuation)
