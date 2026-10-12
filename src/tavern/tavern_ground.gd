extends RefCounted
## The ground under the tavern's stone floors. The builder laid the flags of
## the vestibule and of the kitchen at the level of the yard (6.6 m), where
## the terrain's pad lies too: it lay over the vestibule's flags and showed
## in the joints of the kitchen's. Under those floors the ground is taken
## down below the flags' bed.

## The floors (x, z): the vestibule with the doorway before it, as far as the
## back of the porch's last step; the kitchen. Inner faces of the rooms,
## tools/pipeline/tavern/ilayout.py (VESTIBULE, KITCHEN; z is its -y).
const FLOORS: Array[Rect2] = [Rect2(9.2, -1.85, 3.6, 2.42), Rect2(18.31, -11.775, 8.465, 10.55)]
## Metres the ground is taken down by: under the flags, which are 7 cm thick.
const DROP := 0.09

## Lowers the heights `image` (texel (0, 0) at `origin`, `cell` metres apart)
## under the floors. The ground between two heights is a straight line, so
## every height whose cells reach under a floor goes down.
static func settle(image: Image, origin: Vector2, cell: float) -> void:
	for floor_rect: Rect2 in FLOORS:
		var lo := Vector2i(((floor_rect.position - origin) / cell).floor())
		var hi := Vector2i(((floor_rect.end - origin) / cell).ceil())
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				image.set_pixel(ix, iz, Color(image.get_pixel(ix, iz).r - DROP, 0.0, 0.0))
