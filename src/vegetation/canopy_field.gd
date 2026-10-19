extends RefCounted
## Where the crowns of the trees close the sky over the ground, as a field the
## shaders look up.
##
## The sun's shadow map says where a tree's shadow falls, out to its reach.
## The sky's light took no notice of the trees at all: it lit the floor of a
## wood as it lit the open meadow, so under an overcast sky, with no shadows
## to speak of, a wood was no darker than the field beside it. This is the
## top-down cover map of open-world games: every tree that has a mesh leaves
## a soft disc the size of its crown, as dark as its kind shades the ground
## (VegetationSystem.CROWN_SHADE), and where crowns overlap they close more
## of the sky than either alone.
##
## One texel a metre, coarser views of it in the mips, over the square the
## mesh trees stand in (GrassField.canopy_of). Published as the global shader
## parameters `canopy_cover` and `canopy_rect` (origin x, origin z, cell,
## samples); src/vegetation/shaders/canopy.gdshaderinc reads them. Beyond the
## field, where only impostors stand, the shaders take the terrain's forest
## mask.
##
## The field is also what says where a wood is: the ground under the crowns
## is a wood's floor and its grass is thin (wooded_at, canopy_floor() in the
## shaders), and under a single crown the plants are those of its shade
## (cover_at). The terrain and the grass's jobs read the same numbers, the
## one from the texture and the others from its bytes.
##
## The field follows the eye (follow(), FieldWindow) from where it was made,
## inside the land its crowns are known for: a field made over a whole forest
## (GrassField.canopy_of) has nowhere to go, as beyond it a shader must take
## the terrain's forest mask and not a field with no crowns. A move is worked out on a worker thread: the texels the two places share
## are kept and only the crowns over the strips the move uncovers are laid
## (moved()), which gives what the whole field made at the new place would.
## The texture, the bytes and `canopy_rect` change together, in one frame.
## Worker threads read a view() of the field, which a move leaves alone.

const CanopyField = preload("res://src/vegetation/canopy_field.gd")
const CELL := 1.0
## Crown radii are rounded to this (m): trees of one size share a stamp.
const RADIUS_STEP := 0.25
## The mip in which single crowns and the gaps between them run together
## into a stand: four metres to a texel. CANOPY_WIDE_LEVEL in the shaders.
const WIDE_LEVEL := 2
## The cover of a stand between which the ground under it turns from meadow
## to a wood's floor of needles and leaves. canopy_floor() in the shaders.
const FLOOR := Vector2(0.12, 0.45)
## How far (m) along an axis the eye may stray from the middle of the field
## before it moves (FieldWindow).
const REACH := 192.0

var texture: ImageTexture
## The middle of the first texel (x, z), and texels to a side.
var origin := Vector2.ZERO
var samples := 0
## Trees in the field, and the time it took to make (us).
var tree_count := 0
var build_usec := 0
## The field's bytes with its mips, as the texture holds them, where the
## WIDE_LEVEL mip starts among them and its texels to a side.
var bytes := PackedByteArray()
var wide_start := 0
var wide_samples := 0
## The crowns the field is made of, kept for the strips a move uncovers.
var crowns := PackedFloat32Array()
## Where the field stands: steps from where it was made.
var window: FieldWindow
## Moves so far: a view() older than this is of the field's last place.
var revision := 0
## The longest move so far: on its worker thread, and on the main thread in
## the frame it is shown (us).
var move_usec := Vector2i.ZERO

var _published := false
var _task := -1
var _next: Image
var _next_bytes := PackedByteArray()
var _next_steps := Vector2i.ZERO
var _next_usec := 0

## The field of `trees` (x, z, the crown's radius in metres and how deep its
## shade is, 0..1, of each, one after another) over the square of `side`
## texels whose first has its middle at `from` (x, z). `known` is the land
## those trees are all the crowns of (world x, z), which the field does not
## leave as it follows the eye; empty: its own square.
func _init(trees: PackedFloat32Array, from: Vector2, side: int, known := Rect2()) -> void:
	if side <= 0:
		return
	var start := Time.get_ticks_usec()
	origin = from
	samples = side
	crowns = trees
	tree_count = trees.size() / 4
	window = FieldWindow.new(origin, samples * CELL, REACH)
	window.bounds = known if known.has_area() else Rect2(origin, Vector2.ONE * samples * CELL)
	var image := cover(trees, origin, samples)
	image.generate_mipmaps()
	texture = ImageTexture.create_from_image(image)
	bytes = image.get_data()
	if image.get_mipmap_count() >= WIDE_LEVEL:
		wide_start = image.get_mipmap_offset(WIDE_LEVEL)
		wide_samples = samples >> WIDE_LEVEL
	build_usec = Time.get_ticks_usec() - start

## What `canopy_rect` holds: origin x, origin z, cell (m), samples.
func rect() -> Vector4:
	return Vector4(origin.x, origin.y, CELL, samples)

func publish() -> void:
	if texture == null:
		return
	_published = true
	RenderingServer.global_shader_parameter_set("canopy_cover", texture)
	RenderingServer.global_shader_parameter_set("canopy_rect", rect())

## Materials must stop reading the field before its texture goes.
func withdraw() -> void:
	finish_move()
	if texture == null:
		return
	_published = false
	RenderingServer.global_shader_parameter_set("canopy_cover", null)
	RenderingServer.global_shader_parameter_set("canopy_rect", Vector4.ZERO)

## The field follows the eye at `at` (world x, z); call it every frame. A
## move worked out shows in this frame; the eye's next one starts.
func follow(at: Vector2) -> void:
	if texture == null:
		return
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		finish_move()
	var to := window.offset_for(at)
	if to != window.offset:
		_next_steps = to
		_task = WorkerThreadPool.add_task(_work_out.bind(bytes, origin, window.corner_at(to)), false, "Canopy move")

## Shows the move under way at once (waiting for its thread); none, nothing.
func finish_move() -> void:
	if _task == -1:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var start := Time.get_ticks_usec()
	window.offset = _next_steps
	origin = window.corner()
	texture.update(_next)
	bytes = _next_bytes
	_next = null
	_next_bytes = PackedByteArray()
	revision += 1
	if _published:
		RenderingServer.global_shader_parameter_set("canopy_rect", rect())
	move_usec = Vector2i(maxi(move_usec.x, _next_usec), maxi(move_usec.y, Time.get_ticks_usec() - start))

## Whether a move is being worked out.
func moving() -> bool:
	return _task != -1

func _work_out(field: PackedByteArray, from: Vector2, to: Vector2) -> void:
	var start := Time.get_ticks_usec()
	_next = moved(crowns, field, samples, from, to)
	_next_bytes = _next.get_data()
	_next_usec = Time.get_ticks_usec() - start

## The field as it is now, for worker threads: a move gives the field new
## bytes and leaves the view's alone.
func view() -> CanopyField:
	var seen := CanopyField.new(PackedFloat32Array(), origin, 0)
	seen.origin = origin
	seen.samples = samples
	seen.tree_count = tree_count
	seen.bytes = bytes
	seen.wide_start = wide_start
	seen.wide_samples = wide_samples
	seen.revision = revision
	return seen

## The cover (0..1) of the texel a point of the ground falls in: the crowns
## right over it. None outside the field. Grass grows well inside it, so the
## metres over which the shaders let the field give way (CANOPY_EDGE) are not
## followed here.
func cover_at(x: float, z: float) -> float:
	var column := floori((x - origin.x) / CELL + 0.5)
	var row := floori((z - origin.y) / CELL + 0.5)
	if column < 0 or row < 0 or column >= samples or row >= samples:
		return 0.0
	return bytes[row * samples + column] / 255.0

## How wooded the ground round a point is (0..1): the cover blurred over a
## stand, as canopy_at() reads the WIDE_LEVEL mip in the shaders. None
## outside the field.
func wooded_at(x: float, z: float) -> float:
	if wide_samples < 2:
		return 0.0
	var texels := float(1 << WIDE_LEVEL)
	var column := (x - origin.x) / CELL
	var row := (z - origin.y) / CELL
	if column < -0.5 or row < -0.5 or column > samples - 0.5 or row > samples - 0.5:
		return 0.0
	# A texel of the mip has its middle over the middle of the four by four
	# it was made of.
	var fx := clampf((column + 0.5) / texels - 0.5, 0.0, wide_samples - 1.001)
	var fz := clampf((row + 0.5) / texels - 0.5, 0.0, wide_samples - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var at := wide_start + iz * wide_samples + ix
	var top := lerpf(bytes[at], bytes[at + 1], fx - ix)
	var bottom := lerpf(bytes[at + wide_samples], bytes[at + wide_samples + 1], fx - ix)
	return lerpf(top, bottom, fz - iz) / 255.0

## How much of the ground is a wood's floor (0..1) where the stand round it
## is `wooded`.
static func floor_of(wooded: float) -> float:
	return smoothstep(FLOOR.x, FLOOR.y, wooded)

## How deep the shade of a crown of `radius` metres is `away` metres from its
## trunk, where it is `shade` deep under the middle.
static func shade_at(radius: float, shade: float, away: float) -> float:
	return (1.0 - smoothstep(radius * 0.5, radius * 1.05, away)) * shade

## A crown seen from above, CELL metres to a texel and the trunk in the
## middle one: white, as opaque as the crown's shade is deep.
static func stamp(radius: float, shade: float) -> Image:
	var half := ceili(radius * 1.05 / CELL)
	var side := half * 2 + 1
	var pixels := PackedByteArray()
	pixels.resize(side * side * 4)
	pixels.fill(255)
	for j in side:
		for i in side:
			var away := Vector2(i - half, j - half).length() * CELL
			pixels[(j * side + i) * 4 + 3] = roundi(shade_at(radius, shade, away) * 255.0)
	return Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, pixels)

## The cover (red, 0..1) over the square of `samples` texels whose first
## texel has its middle at `origin` (x, z), or over the part `region` of it
## (texels). `trees` holds x, z, the crown's radius (m) and how deep its
## shade is (0..1) of each, one after another.
##
## Each crown is screened onto the field, which Image.blend_rect() does in
## the engine: white laid over what is there by the stamp's alpha leaves
## 1 - (1 - cover) * (1 - shade). The bytes are rounded down at every crown,
## so the order of the trees moves a texel by a few 255ths at most. A texel
## takes the crowns over it in the same order whatever the region.
static func cover(trees: PackedFloat32Array, origin: Vector2, samples: int, region := Rect2i()) -> Image:
	if not region.has_area():
		region = Rect2i(0, 0, samples, samples)
	var image := Image.create_empty(region.size.x, region.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var stamps := {}
	for at in range(0, trees.size(), 4):
		var bucket := maxi(roundi(trees[at + 2] / RADIUS_STEP), 1)
		# A stamp is made of the first tree of its kind in the whole list,
		# inside the region or not: its shade is that tree's own.
		var key := Vector2i(bucket, roundi(trees[at + 3] * 255.0))
		var crown: Image = stamps.get(key)
		if crown == null:
			crown = stamp(bucket * RADIUS_STEP, trees[at + 3])
			stamps[key] = crown
		var side := crown.get_width()
		# Half a texel rounds up on both sides of the origin: a trunk falls in
		# the same texel of the ground wherever the field stands.
		var trunk := Vector2i(floori((trees[at] - origin.x) / CELL + 0.5), floori((trees[at + 1] - origin.y) / CELL + 0.5)) \
			- region.position
		if not Rect2i(trunk - Vector2i.ONE * (side / 2), Vector2i.ONE * side).intersects(Rect2i(Vector2i.ZERO, region.size)):
			continue
		image.blend_rect(crown, Rect2i(0, 0, side, side), trunk - Vector2i.ONE * (side / 2))
	image.convert(Image.FORMAT_R8)
	return image

## The field of `samples` texels a side (R8 with its mips) whose first texel
## has its middle at `to`, from the bytes `field` of the same field at `from`
## (a whole number of texels away): the texels both share are taken over,
## the crowns of `trees` are laid over the rest.
static func moved(trees: PackedFloat32Array, field: PackedByteArray, samples: int, from: Vector2, to: Vector2) -> Image:
	var by := Vector2i(((to - from) / CELL).round())
	var whole := Rect2i(0, 0, samples, samples)
	var image := Image.create_empty(samples, samples, false, Image.FORMAT_R8)
	var kept := whole.intersection(Rect2i(by, whole.size))
	if kept.has_area():
		var before := Image.create_from_data(samples, samples, false, Image.FORMAT_R8, field.slice(0, samples * samples))
		image.blit_rect(before, kept, kept.position - by)
	for strip: Rect2i in uncovered(samples, Rect2i(kept.position - by, kept.size)):
		image.blit_rect(cover(trees, to, samples, strip), Rect2i(Vector2i.ZERO, strip.size), strip.position)
	image.generate_mipmaps()
	return image

## The parts of a field of `samples` texels a side outside `kept` (texels).
static func uncovered(samples: int, kept: Rect2i) -> Array[Rect2i]:
	var side := samples
	if not kept.has_area():
		return [Rect2i(0, 0, side, side)]
	var strips: Array[Rect2i] = []
	if kept.position.y > 0:
		strips.append(Rect2i(0, 0, side, kept.position.y))
	if kept.end.y < side:
		strips.append(Rect2i(0, kept.end.y, side, side - kept.end.y))
	if kept.position.x > 0:
		strips.append(Rect2i(0, kept.position.y, kept.position.x, kept.size.y))
	if kept.end.x < side:
		strips.append(Rect2i(kept.end.x, kept.position.y, side - kept.end.x, kept.size.y))
	return strips
