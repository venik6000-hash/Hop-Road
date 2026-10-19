class_name FarLights
extends MultiMeshInstance3D
## Lamps and lit windows as glows once they are far away. A light costs every
## pixel in its reach, and a room's lamps shine for nobody across the lake, so
## the lights themselves fade out with distance (Light3D.distance_fade_*) and
## these small quads, one draw call for all of them, keep the village lit in
## the night's view. They burn from dusk, as the lanterns do. The glows are
## those of the content's lamps (WorldContext.lamps, LampSet); the quads are
## drawn again in the frame after a building comes or goes.

const SHADER := preload("res://src/render/far_lights.gdshader")

## Where a kind of light gives way with distance, m: its shadow first, then
## the light over `length`; the glow comes up over `glow`.
const FADES := {
	"lantern": {"shadow": 45.0, "begin": 90.0, "length": 20.0},
	"spill": {"shadow": 45.0, "begin": 80.0, "length": 20.0},
	"interior": {"shadow": 40.0, "begin": 55.0, "length": 15.0},
}
const GLOW_RISE := Vector2(30.0, 60.0)

## The content's lamps (WorldContext.lamps): Callable() -> LampSet. None in a
## tool that draws no glows.
var lamps: ContentRegistry

## {at, color, radius, facing, lit}, as LampSet.glows.
var _glows: Array[Dictionary] = []
## The first of `_glows` of each LampSet, by its instance id.
var _firsts := {}

func _init() -> void:
	name = "FarLights"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED

## Lets `light` fade out with distance as its `kind` does.
static func fade(light: Light3D, kind: String) -> void:
	var range: Dictionary = FADES[kind]
	light.distance_fade_enabled = true
	light.distance_fade_begin = range.begin
	light.distance_fade_length = range.length
	light.distance_fade_shadow = range.shadow

func _ready() -> void:
	set_process(false)
	if lamps == null:
		return
	lamps.added.connect(_changed)
	lamps.removed.connect(_changed)
	_gather()

## A building came or went: the glows are drawn again in the next frame.
func _changed(_entry: Variant) -> void:
	set_process(true)

func _process(_delta: float) -> void:
	set_process(false)
	_gather()

## Takes the glows of every LampSet of the registry and draws them; none
## without lamps.
func _gather() -> void:
	_glows.clear()
	_firsts.clear()
	for entry: Variant in lamps.entries():
		var lamps_for: Callable = entry
		var given: LampSet = lamps_for.call()
		_firsts[given.get_instance_id()] = _glows.size()
		_glows.append_array(given.glows)
		if not given.lit_changed.is_connected(_set_lit):
			given.lit_changed.connect(_set_lit)
	if _glows.is_empty():
		multimesh = null
	else:
		build()

## The glow `index` of `given` goes out or is lit again: a fire that is kept
## for a part of the day only.
func _set_lit(given: LampSet, index: int, lit: bool) -> void:
	var first: int = _firsts.get(given.get_instance_id(), -1)
	if first < 0 or multimesh == null:
		return
	var color: Color = _glows[first + index].color
	multimesh.set_instance_color(first + index, color if lit else Color.BLACK)

func build() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("rise", GLOW_RISE)
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = _glows.size()
	var bounds := AABB()
	for index in _glows.size():
		var glow: Dictionary = _glows[index]
		var at: Vector3 = glow.at
		var local: Vector3 = to_local(at) if is_inside_tree() else at
		# Not a pose (see the shader): x carries the radius, z the facing.
		var facing: Vector3 = glow.facing
		var basis := Basis(Vector3(Values.real(glow.radius), 0.0, 0.0), Vector3.UP, facing.normalized() if facing != Vector3.ZERO else Vector3.ZERO)
		multimesh.set_instance_transform(index, Transform3D(basis, local))
		var color: Color = glow.color
		multimesh.set_instance_color(index, color if glow.lit else Color.BLACK)
		bounds = AABB(local, Vector3.ZERO) if index == 0 else bounds.expand(local)
	# The quads are sized on the screen: no box around them holds them all.
	multimesh.custom_aabb = bounds.grow(6.0)
