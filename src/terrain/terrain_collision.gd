extends RefCounted
## The physics body of TerrainSystem: a 1 m HeightMapShape3D over the walkable
## near field, in a StaticBody3D named "TerrainBody" (PhysicsLayers.hit_terrain
## matches the name).

static func build(terrain: TerrainSystem) -> void:
	# 1 m physics grid from every second near sample; walkable area only.
	var half := terrain.near_size / 2
	var data := _collision_heights(terrain, half)
	var shape := HeightMapShape3D.new()
	shape.map_width = half
	shape.map_depth = half
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var holder := CollisionShape3D.new()
	holder.shape = shape
	var step := terrain.near_cell * 2.0
	holder.scale = Vector3(step, 1.0, step)
	holder.position = Vector3(terrain.near_origin.x + (half - 1) * step * 0.5, 0.0, terrain.near_origin.y + (half - 1) * step * 0.5)
	body.add_child(holder)
	terrain.add_child(body)

## Every second near sample in x and z (rows z * 2, columns x * 2), `half` a
## side, without a GDScript loop over a million samples. The same bytes read
## as two-channel pixels of `half` rows: each such row holds two source rows,
## its first `half` pixels the even one, and each pixel's red channel the
## even column. Region copy and channel drop copy the 32-bit floats unchanged.
static func _collision_heights(terrain: TerrainSystem, half: int) -> PackedFloat32Array:
	if half * 2 == terrain.near_size and terrain.near_image.get_format() == Image.FORMAT_RF and not terrain.near_image.has_mipmaps():
		var pairs := Image.create_from_data(terrain.near_size, half, false, Image.FORMAT_RGF, terrain.near_image.get_data())
		var even := pairs.get_region(Rect2i(0, 0, half, half))
		even.convert(Image.FORMAT_RF)
		return even.get_data().to_float32_array()
	# An odd size or another format does not pair up this way: walk the samples.
	var data := PackedFloat32Array()
	data.resize(half * half)
	var source := terrain.near_image.get_data().to_float32_array()
	for z: int in half:
		var row := z * 2 * terrain.near_size
		var out := z * half
		for x: int in half:
			data[out + x] = source[row + x * 2]
	return data
