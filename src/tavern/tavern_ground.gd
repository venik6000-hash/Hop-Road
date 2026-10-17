extends RefCounted
## The ground under the tavern's stone floors. The builder laid the flags of
## the vestibule and of the kitchen at the level of the yard (6.6 m), where
## the terrain's pad lies too: it lay over the vestibule's flags and showed
## in the joints of the kitchen's. Under those floors the ground is taken
## down below the flags' bed.
##
## The floors lie in the region's file (RegionDef.tavern_ground,
## BuildingSchemas.tavern_ground): the vestibule with the doorway before it,
## as far as the back of the porch's last step, and the kitchen, by the inner
## faces of the rooms (tools/pipeline/tavern/ilayout.py: VESTIBULE, KITCHEN;
## z is its -y). The ground goes down by `drop`: under the flags, which are
## 7 cm thick.

## The floors of the file `path` (x, z) and the drop (m): {floors:
## Array[Rect2], drop}; {} for "" or a file that does not read.
static func read(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var data: Variant = DataFile.read(path, BuildingSchemas.tavern_ground())
	if not data is Dictionary:
		return {}
	var file: Dictionary = data
	var floors: Array[Rect2] = []
	var listed: Array = file.floors
	for entry: Dictionary in listed:
		floors.append(Rect2(Values.vec2(entry.at), Values.vec2(entry.size)))
	return {"floors": floors, "drop": Values.real(file.drop)}

## Lowers the heights `image` (texel (0, 0) at `origin`, `cell` metres apart)
## under the floors of `ground` (read). The ground between two heights is a
## straight line, so every height whose cells reach under a floor goes down.
static func settle(image: Image, origin: Vector2, cell: float, ground: Dictionary) -> void:
	if ground.is_empty():
		return
	var floors: Array[Rect2] = ground.floors
	var drop: float = ground.drop
	for floor_rect: Rect2 in floors:
		var lo := Vector2i(((floor_rect.position - origin) / cell).floor())
		var hi := Vector2i(((floor_rect.end - origin) / cell).ceil())
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				image.set_pixel(ix, iz, Color(image.get_pixel(ix, iz).r - drop, 0.0, 0.0))
