extends RefCounted
## Image helpers shared by the code that paints the terrain's masks.

## An editable RGBA8 copy of `texture`'s image (decompressed first).
static func rgba8(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image
