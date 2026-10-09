extends RefCounted
## The tavern's lights from its tables, the reflection probes over the rooms
## and the hearth fires. `tavern` is the TavernSystem node they go under.

## Keep the sky/room blend inside the wall thickness, below the floor and
## above the ceiling, including the recessed mortar between the stones.
const PROBE_PADDING := 0.45
const PROBE_BLEND := 0.1
const BUILDING_BOUNDS := AABB(Vector3(3.6, 6.6, -14.4), Vector3(23.8, 14.2, 14.8))

static func add_light(tavern: TavernSystem, config: Dictionary) -> void:
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
	light.light_color = Color(color[0], color[1], color[2])
	light.light_energy = config.energy
	# A shared render layer does not stop light crossing floors or partitions.
	# Include nearby outdoor point lamps, but leave the outward window spots
	# and distant road lamps on their authored settings.
	var p: Array = config.position
	light.position = Vector3(p[0], p[1], p[2])
	var near_building := BUILDING_BOUNDS.grow(config.range).has_point(light.position)
	light.shadow_enabled = config.shadow or config.get("layer", "interior") == "interior" \
		or (config.type == "point" and near_building)
	# Keep costly area-shadow filtering for the authored large sources.
	# Candles and small lanterns use the shadow atlas's regular PCF filter.
	light.light_size = config.get("size", 0.05) if config.shadow else 0.0
	light.shadow_bias = 0.02
	light.shadow_normal_bias = 0.2
	tavern.add_child(light)
	if config.type == "spot":
		var d: Array = config.direction
		var forward := Vector3(d[0], d[1], d[2]).normalized()
		var up := Vector3.UP if absf(forward.y) < 0.95 else Vector3.FORWARD
		light.look_at(light.position + forward, up)
	match str(config.get("layer", "interior")):
		"interior":
			light.light_cull_mask = TavernSystem.LAYER
			light.shadow_caster_mask = TavernSystem.SHADOW_LAYER
			FarLights.fade(light, "interior")
		"exterior":
			FarLights.fade(light, "spill" if config.type == "spot" else "lantern")
			# Outside: the ground and the tavern's own still walls, not the
			# trees and not the ivy (see TavernSystem.SHADOW_LAYER).
			light.shadow_caster_mask = 0xFFFFFFFF & ~VegetationSystem.VISUAL_LAYER & ~TavernSystem.LAYER \
				& ~TavernSystem.SUN_LAYERS
	var amount: float = config.get("flicker", 0.0)
	if config.get("night", 0.0) > 0.5:
		tavern._lanterns.append({"light": light, "energy": config.energy})
		# A lantern has a halo in the fog; a window's spill has none.
		if config.type != "spot":
			light.add_to_group(AtmosphereFog.LAMP_GROUP)
		# Far away the lantern is a glow, and so is the window a spot spills from.
		tavern.far_glows.append({"at": light.position, "color": light.light_color,
			"radius": 0.3 if config.type == "spot" else 0.22,
			"facing": -light.basis.z if config.type == "spot" else Vector3.ZERO})
	elif amount > 0.0:
		tavern._flames.append({"light": light, "energy": config.energy, "amount": amount,
			"seed": float(hash(config.name) % 1000) * 0.37, "speed": config.get("speed", 1.0),
			"origin": light.position, "sway": config.get("sway", 0.0)})

static func add_probe(tavern: TavernSystem, config: Dictionary) -> void:
	var probe := ReflectionProbe.new()
	probe.name = config.name
	var p: Array = config.position
	var e: Array = config.extents
	probe.position = Vector3(p[0], p[1], p[2])
	var padding := Vector3.ONE * PROBE_PADDING
	# The boards closing the roof eaves sit beyond the room's wall faces.
	if config.get("room", "") in ["attic", "kitchen"]:
		padding.x = 0.65
	probe.size = (Vector3(e[0], e[1], e[2]) + padding) * 2.0
	probe.interior = true
	probe.box_projection = true
	probe.enable_shadows = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	var a: Array = config.ambient
	# Interpret the table's small ambient values as linear irradiance. Color
	# properties are decoded from sRGB by the renderer, so encode them first.
	probe.ambient_color = Color(a[0], a[1], a[2]).linear_to_srgb()
	probe.ambient_color_energy = 1.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	# Both layers: a capture draws the lamps' shadows only from casters it sees.
	probe.cull_mask = TavernSystem.LAYER | TavernSystem.SHADOW_LAYER
	probe.reflection_mask = TavernSystem.LAYER
	probe.blend_distance = PROBE_BLEND
	tavern.add_child(probe)
	tavern._room_probes.append(probe)

static func add_hearth_fires(tavern: TavernSystem) -> void:
	for config: Array in [[Vector3(6.32, 7.21, -10.3), Vector3.FORWARD, 0.95, 0.75],
			[Vector3(24.5, 7.26, -11.05), Vector3.RIGHT, 0.9, 0.68],
			[Vector3(25.6, 7.42, -9.75), Vector3.RIGHT, 0.45, 0.47],
			[Vector3(6.59, 11.09, -10.3), Vector3.FORWARD, 0.45, 0.42]]:
		var fire := HearthFire.new()
		fire.name = "HearthFire%d" % tavern.get_child_count()
		tavern.add_child(fire)
		fire.configure(config[0], config[1], config[2], config[3])
