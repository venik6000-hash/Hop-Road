extends RefCounted
## The terrain material of TerrainSystem: heightfields, masks, layer textures
## and grades (terrain.gdshader, terrain_fields.gdshaderinc), and the arrays
## of the tiles (TerrainTiles).

## `baked` are the baked masks of the near field (TerrainBake.read_masks):
## the wear and the cinder fields are read from there. The tiles' arrays are
## made empty; TerrainSystem fills their layers (fill_layer()).
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
	terrain.material.set_shader_parameter("far_height", far_texture)
	terrain.material.set_shader_parameter("far_rect", Vector4(terrain.far_origin.x, terrain.far_origin.y, terrain.far_cell, terrain.far_size))
	# The lake's field: the frozen WaterSystem copies these two from here.
	# terrain_fields.gdshaderinc does not read them.
	terrain.material.set_shader_parameter("near_height", ImageTexture.create_from_image(terrain.near_image))
	terrain.material.set_shader_parameter("near_rect", Vector4(terrain.near_origin.x, terrain.near_origin.y, terrain.near_cell, terrain.near_size))
	_make_tiles(terrain)
	if baked.is_empty():
		push_error("TerrainMaterial: no settled masks for %s; run tools/run/rebuild.sh --only terrain-ground"
			% terrain.region.id)
	else:
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
	# The moss of the region's buildings, trees and stones is a layer of its
	# own terrain's array: one texture global, set once per terrain.
	RenderingServer.global_shader_parameter_set(&"moss_albedo", terrain.material.get_shader_parameter("layer_albedo"))
	terrain.material.set_shader_parameter("macro_noise", load(SkySystem.WEATHER_MAP))
	# The look of the layers is the region's (EnvironmentDef).
	terrain.material.set_shader_parameter("layer_tile", terrain.region.environment.layer_tiles)
	terrain.material.set_shader_parameter("layer_grade", terrain.region.environment.layer_grades)
	# The lake's surface for every shader that draws under or by it.
	RenderingServer.global_shader_parameter_set(&"lake_level", terrain.water_level)

## The arrays of the tiles (one layer each, empty until fill_layer()), the
## map of their layers and the mid field, as terrain_fields.gdshaderinc reads them.
static func _make_tiles(terrain: TerrainSystem) -> void:
	var tiles := terrain.tiles
	var count := tiles.coords.size()
	var blank_heights := Image.create_empty(tiles.samples, tiles.samples, false, Image.FORMAT_RF)
	var blank_masks := Image.create_empty(tiles.mask_samples, tiles.mask_samples, true, Image.FORMAT_RGBA8)
	for parameter: String in ["tile_heights", "tile_control", "tile_extra"]:
		var blank := blank_heights if parameter == "tile_heights" else blank_masks
		var layers: Array[Image] = []
		for layer in count:
			layers.append(blank)
		var array := Texture2DArray.new()
		array.create_from_images(layers)
		terrain.material.set_shader_parameter(parameter, array)
	terrain.material.set_shader_parameter("tile_slots", ImageTexture.create_from_image(tiles.slot_image()))
	terrain.material.set_shader_parameter("tile_rect", Vector4(tiles.origin.x, tiles.origin.y, tiles.tile, TerrainTiles.MAP_SIZE))
	terrain.material.set_shader_parameter("tile_cells", Vector4(tiles.cell, tiles.samples, tiles.mask_cell, tiles.mask_samples))
	var mid := Image.create_empty(1, 1, false, Image.FORMAT_RF)
	if tiles.mid_size > 0:
		mid = Image.create_from_data(tiles.mid_size, tiles.mid_size, false, Image.FORMAT_RF, tiles.mid.to_byte_array())
	terrain.material.set_shader_parameter("mid_height", ImageTexture.create_from_image(mid))
	# No mid field: w = 0 puts every point outside it.
	terrain.material.set_shader_parameter("mid_rect", Vector4(tiles.mid_origin.x, tiles.mid_origin.y, tiles.mid_cell, tiles.mid_size))

## Layer `layer` of the arrays takes the heights the tiles hold there and the
## masks `control` and `extra` (RGBA8, the tiles' mask size squared); the map
## is drawn again.
static func fill_layer(terrain: TerrainSystem, layer: int, control: PackedByteArray, extra: PackedByteArray) -> void:
	var tiles := terrain.tiles
	var heights := Image.create_from_data(tiles.samples, tiles.samples, false, Image.FORMAT_RF,
		tiles.heights[layer].to_byte_array())
	var array: Texture2DArray = terrain.material.get_shader_parameter("tile_heights")
	array.update_layer(heights, layer)
	for pair: Array in [["tile_control", control], ["tile_extra", extra]]:
		var bytes: PackedByteArray = pair[1]
		var mask := Image.create_from_data(tiles.mask_samples, tiles.mask_samples, false, Image.FORMAT_RGBA8, bytes)
		# The masks are read blurred from far off: their smaller copies follow.
		mask.generate_mipmaps()
		var masks: Texture2DArray = terrain.material.get_shader_parameter(str(pair[0]))
		masks.update_layer(mask, layer)
	var slots: ImageTexture = terrain.material.get_shader_parameter("tile_slots")
	slots.update(tiles.slot_image())
