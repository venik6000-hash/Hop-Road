class_name FarLights
extends MultiMeshInstance3D
## Lamps and lit windows as glows once they are far away. A light costs every
## pixel in its reach, and a room's lamps shine for nobody across the lake, so
## the lights themselves fade out with distance (Light3D.distance_fade_*) and
## these small quads, one draw call for all of them, keep the village lit in
## the night's view. They burn from dusk, as the lanterns do.

const SHADER := preload("res://src/render/far_lights.gdshader")

## Where a kind of light gives way with distance, m: its shadow first, then
## the light over `length`; the glow comes up over `glow`.
const FADES := {
	"lantern": {"shadow": 45.0, "begin": 90.0, "length": 20.0},
	"spill": {"shadow": 45.0, "begin": 80.0, "length": 20.0},
	"interior": {"shadow": 40.0, "begin": 55.0, "length": 15.0},
}
const GLOW_RISE := Vector2(30.0, 60.0)

var _glows: Array[Dictionary] = []

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

## A glow of `radius` metres at `at` (world space). `facing` is the way a
## window looks; a lamp, seen from all round, leaves it zero.
func add_glow(at: Vector3, color: Color, radius: float, facing := Vector3.ZERO) -> void:
	_glows.append({"at": at, "color": color, "radius": radius, "facing": facing})

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
		var local: Vector3 = to_local(glow.at) if is_inside_tree() else glow.at
		# Not a pose (see the shader): x carries the radius, z the facing.
		var facing: Vector3 = glow.facing
		var basis := Basis(Vector3(glow.radius, 0.0, 0.0), Vector3.UP, facing.normalized() if facing != Vector3.ZERO else Vector3.ZERO)
		multimesh.set_instance_transform(index, Transform3D(basis, local))
		multimesh.set_instance_color(index, glow.color)
		bounds = AABB(local, Vector3.ZERO) if index == 0 else bounds.expand(local)
	# The quads are sized on the screen: no box around them holds them all.
	multimesh.custom_aabb = bounds.grow(6.0)
