extends RefCounted
## Chimney smoke: one particle plume per smoke point of the Blender map.
const VILLAGE_LAYOUT = preload("res://src/village/village_layout.gd")
const COTTAGE = preload("res://src/village/herbalist_cottage.gd")
const SMOKE_SHADER = preload("res://src/alpine/smoke.gdshader")

## Adds the plumes to the level as "ChimneySmoke" children, in manifest order.
static func build(level: Node3D, manifest: Dictionary, terrain: TerrainSystem) -> void:
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	quad.material = material
	for origin: Array in manifest.smoke:
		if COTTAGE.replaces_smoke(origin):
			continue
		var plume := CPUParticles3D.new()
		plume.name = "ChimneySmoke"
		plume.position = VILLAGE_LAYOUT.smoke_position(level.vector(origin), terrain)
		plume.mesh = quad
		plume.amount = 18
		plume.lifetime = 6.0
		plume.preprocess = 6.0
		plume.direction = Vector3(0.15, 1.0, 0.1)
		plume.spread = 9.0
		plume.initial_velocity_min = 0.6
		plume.initial_velocity_max = 0.95
		plume.gravity = Vector3(0.025, 0.04, 0.02)
		plume.scale_amount_min = 0.4
		plume.scale_amount_max = 1.0
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0.65))
		fade.set_color(1, Color(1, 1, 1, 0))
		plume.color_ramp = fade
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(plume)
