extends RefCounted
## Spray and mist where the falls of WaterfallSystem land (static functions
## that add GPUParticles3D nodes to the WaterfallSystem `system`).

## Spray thrown up where the water lands and the mist that rises off it.
static func add_mist(system: WaterfallSystem, at: Vector3, width: float, strength: float) -> void:
	var material := ShaderMaterial.new()
	material.shader = WaterfallSystem.MIST_SHADER
	material.render_priority = WaterfallSystem.MIST_PRIORITY
	material.set_shader_parameter("water_level", at.y)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	# Spray: droplets thrown up and out, falling back within a second or two.
	var spray := _particles(system, "Spray", at, quad, int(90 * strength), 1.6)
	var motion := spray.process_material as ParticleProcessMaterial
	motion.emission_box_extents = Vector3(width * 0.4, 0.3, 1.2)
	motion.direction = Vector3(0.0, 1.0, 0.25)
	motion.spread = 65.0
	motion.initial_velocity_min = 2.0
	motion.initial_velocity_max = 6.5
	motion.gravity = Vector3(0.0, -6.0, 0.0)
	motion.damping_min = 0.5
	motion.damping_max = 1.5
	motion.scale_min = 0.8
	motion.scale_max = 2.0
	motion.color_ramp = _fade(0.55)
	# Mist: large slow puffs drifting up and away from the fall.
	var mist := _particles(system, "Mist", at + Vector3(0.0, 0.5, 1.5), quad, int(36 * strength), 6.0)
	motion = mist.process_material as ParticleProcessMaterial
	motion.emission_box_extents = Vector3(width * 0.6, 0.6, 2.5)
	motion.direction = Vector3(0.0, 1.0, 0.6)
	motion.spread = 40.0
	motion.initial_velocity_min = 0.4
	motion.initial_velocity_max = 1.6
	motion.gravity = Vector3(0.15, 0.2, 0.25)
	motion.damping_min = 0.2
	motion.damping_max = 0.4
	motion.scale_min = 3.0
	motion.scale_max = 7.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	motion.scale_curve = grow_texture
	motion.color_ramp = _fade(0.22 * strength)

static func _particles(system: WaterfallSystem, label: String, at: Vector3, quad: QuadMesh, amount: int, lifetime: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.position = at
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-14.0, -3.0, -14.0), Vector3(28.0, 26.0, 28.0))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.angle_min = 0.0
	motion.angle_max = 360.0
	motion.angular_velocity_min = -12.0
	motion.angular_velocity_max = 12.0
	particles.process_material = motion
	system.add_child(particles)
	return particles

## White, fading in and out over a particle's life, `peak` at most opaque.
static func _fade(peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.92, 0.94, 0.95, 0.0))
	gradient.set_color(1, Color(0.92, 0.94, 0.95, 0.0))
	gradient.add_point(0.15, Color(0.92, 0.94, 0.95, peak))
	gradient.add_point(0.6, Color(0.92, 0.94, 0.95, peak * 0.6))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
