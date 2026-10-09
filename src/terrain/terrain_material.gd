extends RefCounted
## The terrain material of TerrainSystem: heightfields, masks, layer textures
## and grades (terrain.gdshader, terrain_fields.gdshaderinc).

static func setup(terrain: TerrainSystem) -> void:
	terrain.material.shader = TerrainSystem.SHADER
	var far_texture := ImageTexture.create_from_image(terrain.far_image)
	var near_texture := ImageTexture.create_from_image(terrain.near_image)
	terrain.material.set_shader_parameter("near_height", near_texture)
	terrain.material.set_shader_parameter("far_height", far_texture)
	terrain.material.set_shader_parameter("near_rect", Vector4(terrain.near_origin.x, terrain.near_origin.y, terrain.near_cell, terrain.near_size))
	terrain.material.set_shader_parameter("far_rect", Vector4(terrain.far_origin.x, terrain.far_origin.y, terrain.far_cell, terrain.far_size))
	var masks: Dictionary = terrain.meta.masks
	terrain.material.set_shader_parameter("mask_rect", Vector4(masks.origin[0], masks.origin[1], masks.cell, masks.size))
	terrain.material.set_shader_parameter("near_control", load(TerrainSystem.DATA + "near_control.png"))
	terrain.material.set_shader_parameter("near_extra", load(TerrainSystem.DATA + "near_extra.png"))
	terrain.material.set_shader_parameter("far_masks", load(TerrainSystem.DATA + "far_masks.png"))
	terrain.material.set_shader_parameter("layer_albedo", load(TerrainSystem.DATA + "terrain_albedo.jpg"))
	terrain.material.set_shader_parameter("layer_normal", load(TerrainSystem.DATA + "terrain_normal.jpg"))
	terrain.material.set_shader_parameter("layer_rah", load(TerrainSystem.DATA + "terrain_rah.jpg"))
	var weather := load("res://assets/generated/sky/cloud_weather.png")
	terrain.material.set_shader_parameter("macro_noise", weather)
	terrain.material.set_shader_parameter("cloud_weather", weather)
	terrain.material.set_shader_parameter("layer_tile", PackedFloat32Array(TerrainSystem.LAYER_TILES))
	terrain.material.set_shader_parameter("layer_grade", TerrainSystem.LAYER_GRADES)
	terrain.material.set_shader_parameter("water_level", terrain.water_level)
