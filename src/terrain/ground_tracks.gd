extends Node
## The prints feet leave in soft ground. The walker's footfalls are kept as a
## list (where, which way, when, which foot) and given to the terrain shader
## as two small textures: the prints, and a grid of cells that names the
## prints touching each cell. The shader draws a boot's print from those
## numbers (terrain.gdshader, boot()), so its outline is as sharp a hand from
## the eye as ten metres off. How deep a print shows is the ground's
## business there: soft earth and sand take one, mud after rain a deep one,
## turf and stone none.

## Prints kept at once: a cell names a print by a byte, and 0 is "none".
const PRINTS := 255
## Metres to a cell of the grid and cells to its side. The grid wraps: a print
## is drawn by its own place, so the cell it shares 32 m away draws nothing.
const CELL := 0.5
const CELLS := 64
## Metres from a print's middle that it can touch.
const REACH := 0.2
## Seconds a print lasts; it fades over the last part of them.
const LIFE := 240.0
## Metres between footfalls at a walk and at a run, and the speeds (m/s) those
## are (PlayerMotion.WALK_SPEED, RUN_SPEED).
const STRIDE := Vector2(0.68, 0.95)
const PACE := Vector2(3.0, 5.0)
## Metres a foot falls to the side of the walker's line.
const GAIT := 0.11
## Slower than this nobody is walking, m/s.
const STILL := 0.4
## The walker's soles within this of the terrain stand on it, metres.
const ON_GROUND := 0.08

var terrain: TerrainSystem
var walker: Player

## Rows of the prints' texture: where (x, z) and which way (x, z); when
## (seconds of this node's clock) and which foot (-1 left, 1 right).
var prints: Image
## The grid: up to four prints to a cell, a byte each.
var cells: Image
var clock := 0.0
var _prints_texture: ImageTexture
var _cells_texture: ImageTexture
var _next := 1
var _born := PackedFloat32Array()
var _cells_of: Array[PackedVector2Array] = []
var _travelled := 0.0
var _left := false

func _init() -> void:
	prints = Image.create(PRINTS + 1, 2, false, Image.FORMAT_RGBAF)
	cells = Image.create(CELLS, CELLS, false, Image.FORMAT_RGBA8)
	_born.resize(PRINTS + 1)
	_born.fill(-INF)
	_cells_of.resize(PRINTS + 1)

func _ready() -> void:
	_prints_texture = ImageTexture.create_from_image(prints)
	_cells_texture = ImageTexture.create_from_image(cells)
	terrain.material.set_shader_parameter("track_prints", _prints_texture)
	terrain.material.set_shader_parameter("track_cells", _cells_texture)

func _physics_process(delta: float) -> void:
	clock += delta
	terrain.material.set_shader_parameter("track_clock", Vector2(clock, LIFE))
	var feet := walker.global_position
	var on_ground := not walker.swimming and feet.y > terrain.water_level \
		and absf(feet.y - terrain.height_at(feet.x, feet.z)) < ON_GROUND
	var ahead := -walker.global_basis.z
	if walk(Vector2(feet.x, feet.z), Vector2(walker.velocity.x, walker.velocity.z), on_ground, delta, Vector2(ahead.x, ahead.z)):
		_prints_texture.update(prints)
		_cells_texture.update(cells)

## Metres between two footfalls at `speed` m/s.
static func stride(speed: float) -> float:
	return lerpf(STRIDE.x, STRIDE.y, smoothstep(PACE.x, PACE.y, speed))

## The walker `delta` seconds on, at `at` (x, z), moving by `velocity` (x, z)
## and facing `facing` (x, z; the way they move when none is given). A foot
## falls each stride of ground covered, toes where the walker faces: a step to
## the side or back leaves prints that still point ahead. True when one fell.
func walk(at: Vector2, velocity: Vector2, on_ground: bool, delta: float, facing := Vector2.ZERO) -> bool:
	var speed := velocity.length()
	if not on_ground or speed < STILL:
		# The next step from here is a first step: a foot falls half a stride on.
		_travelled = maxf(_travelled, STRIDE.x * 0.5)
		return false
	_travelled += speed * delta
	if _travelled < stride(speed):
		return false
	_travelled = 0.0
	_left = not _left
	var heading := facing.normalized() if facing.length_squared() > 1e-6 else velocity / speed
	add_print(at + Vector2(-heading.y, heading.x) * (-GAIT if _left else GAIT), heading, _left)
	return true

## Keeps a print at `at` (x, z) of a foot pointing along `heading`; the oldest
## kept gives way once there are PRINTS of them.
func add_print(at: Vector2, heading: Vector2, left: bool) -> void:
	var slot := _next
	_next = slot % PRINTS + 1
	_forget(slot)
	_born[slot] = clock
	prints.set_pixel(slot, 0, Color(at.x, at.y, heading.x, heading.y))
	prints.set_pixel(slot, 1, Color(clock, -1.0 if left else 1.0, 0.0, 0.0))
	var low := ((at - Vector2.ONE * REACH) / CELL).floor()
	var high := ((at + Vector2.ONE * REACH) / CELL).floor()
	var touched := PackedVector2Array()
	for z in range(int(low.y), int(high.y) + 1):
		for x in range(int(low.x), int(high.x) + 1):
			var cell := Vector2(posmod(x, CELLS), posmod(z, CELLS))
			_note(cell, slot)
			touched.append(cell)
	_cells_of[slot] = touched

## The prints a cell names, a byte each.
func named(cell: Vector2) -> PackedByteArray:
	var held := cells.get_pixelv(Vector2i(cell))
	return PackedByteArray([held.r8, held.g8, held.b8, held.a8])

## Names `slot` in `cell`: in a free place, or in place of its oldest print.
func _note(cell: Vector2, slot: int) -> void:
	var held := named(cell)
	var place := held.find(0)
	if place < 0:
		place = 0
		for i in range(1, 4):
			if _born[held[i]] < _born[held[place]]:
				place = i
	held[place] = slot
	cells.set_pixelv(Vector2i(cell), Color8(held[0], held[1], held[2], held[3]))

## Takes `slot` out of the cells that name it.
func _forget(slot: int) -> void:
	for cell: Vector2 in _cells_of[slot]:
		var held := named(cell)
		for i in 4:
			if held[i] == slot:
				held[i] = 0
		cells.set_pixelv(Vector2i(cell), Color8(held[0], held[1], held[2], held[3]))
	_cells_of[slot] = PackedVector2Array()
