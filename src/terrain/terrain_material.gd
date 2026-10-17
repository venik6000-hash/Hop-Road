extends RefCounted
## The terrain material of TerrainSystem: heightfields, masks, layer textures
## and grades (terrain.gdshader, terrain_fields.gdshaderinc).

## `baked` are the baked masks of the near field (TerrainBake.read_masks).
static func setup(terrain: TerrainSystem, baked: Dictionary) -> void:
	terrain.material.shader = TerrainSystem.SHADER
	# The opaque pass is drawn in the order of the materials' priorities and
	# then of their shaders' ids; how far a thing stands comes after both. A
	# shader that can discard takes no part in the GPU's hidden surface
	# removal, so in the depth prepass the ground, drawn in its shader's
	# turn, was shaded whole (its normals want all of fragment()) under the
	# trees, houses and stones drawn after it. Last, it is shaded where it
	# shows.
	terrain.material.render_priority = Material.RENDER_PRIORITY_MAX
	var far_texture := ImageTexture.create_from_image(terrain.far_image)
	var near_texture := ImageTexture.create_from_image(terrain.near_image)
	terrain.material.set_shader_parameter("near_height", near_texture)
	terrain.material.set_shader_parameter("far_height", far_texture)
	terrain.material.set_shader_parameter("near_rect", Vector4(terrain.near_origin.x, terrain.near_origin.y, terrain.near_cell, terrain.near_size))
	terrain.material.set_shader_parameter("far_rect", Vector4(terrain.far_origin.x, terrain.far_origin.y, terrain.far_cell, terrain.far_size))
	var masks: Dictionary = terrain.meta.masks
	terrain.material.set_shader_parameter("mask_rect", Vector4(Values.real(masks.origin[0]), Values.real(masks.origin[1]), Values.real(masks.cell), Values.real(masks.size)))
	if baked.is_empty():
		push_error("TerrainMaterial: no settled masks for %s; run tools/run/rebuild.sh --only terrain-ground"
			% terrain.region.id)
	else:
		# The masks are read blurred from far off: their smaller copies follow.
		for mask: String in ["control", "extra"]:
			var image: Image = baked[mask]
			image.generate_mipmaps()
			terrain.material.set_shader_parameter("near_" + mask, ImageTexture.create_from_image(image))
		if baked.has("wear"):
			var rect: Rect2 = baked.rect
			var wear: Image = baked.wear
			terrain.material.set_shader_parameter("wear_field", ImageTexture.create_from_image(wear))
			terrain.material.set_shader_parameter("wear_rect", Vector4(rect.position.x, rect.position.y, 1.0 / rect.size.x,
				1.0 / rect.size.y))
		if baked.has("cinder"):
			var cinder: Image = baked.cinder
			terrain.material.set_shader_parameter("cinder_field", ImageTexture.create_from_image(cinder))
	terrain.material.set_shader_parameter("far_masks", load(terrain.region.terrain_dir.path_join("far_masks.png")))
	terrain.material.set_shader_parameter("far_detail", load(terrain.region.terrain_dir.path_join("far_detail.png")))
	terrain.material.set_shader_parameter("high_detail", terrain.high_detail)
	terrain.material.set_shader_parameter("layer_albedo", load(terrain.region.terrain_dir.path_join("terrain_albedo.jpg")))
	terrain.material.set_shader_parameter("layer_normal", load(terrain.region.terrain_dir.path_join("terrain_normal.jpg")))
	terrain.material.set_shader_parameter("layer_rah", load(terrain.region.terrain_dir.path_join("terrain_rah.jpg")))
	var weather := load("res://assets/generated/sky/cloud_weather.png")
	terrain.material.set_shader_parameter("macro_noise", weather)
	terrain.material.set_shader_parameter("cloud_weather", weather)
	terrain.material.set_shader_parameter("layer_tile", PackedFloat32Array(TerrainSystem.LAYER_TILES))
	terrain.material.set_shader_parameter("layer_grade", TerrainSystem.LAYER_GRADES)
	terrain.material.set_shader_parameter("water_level", terrain.water_level)
