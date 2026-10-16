class_name Tankard
extends Node3D
## An iron tankard with beer in it, as villagers hold it, set on a counter or
## drink from it: the player's own tankard model (docs/PLAYER.md) and a level
## surface of beer and foam that stays level when the tankard tilts. The iron
## is the player's wet iron, wet as far as the tankard is full. The
## origin is the middle of the tankard's foot; its handle is on +x.
const MODEL := preload("res://assets/models/beer/iron_tankard.glb")
const SURFACE := preload("res://src/npc/tankard_beer.gdshader")
## The tankard's measures in its own space, metres.
const RIM := 0.239
const BOTTOM := 0.016
const INNER_RADIUS := 0.087
## The middle of the handle's upright bar; its outer face is 0.018 m further out.
const HANDLE := Vector3(0.163, 0.122, 0.0)

## How full it is, 0..1 of the inside.
var fill := 0.0:
	set(value):
		fill = clampf(value, 0.0, 1.0)
		_surface.visible = fill > 0.001
		for wet in _wet:
			wet.set_shader_parameter("wetness", fill)
## How much of the surface is foam, 0..1.
var foam := 1.0
var _surface: MeshInstance3D
var _material: ShaderMaterial
var _wet: Array[ShaderMaterial] = []

func _init() -> void:
	name = "Tankard"
	var model := MODEL.instantiate() as Node3D
	model.name = "Iron"
	add_child(model)
	_wet = MugPresentation.wet_tankard(model)
	for wet in _wet:
		wet.set_shader_parameter("wetness", 0.0)
	_material = ShaderMaterial.new()
	_material.shader = SURFACE
	_material.set_shader_parameter("inner_radius", INNER_RADIUS)
	_material.set_shader_parameter("rim", RIM)
	var disc := PlaneMesh.new()
	disc.size = Vector2(INNER_RADIUS * 3.0, INNER_RADIUS * 3.0)
	disc.subdivide_width = 8
	disc.subdivide_depth = 8
	_surface = MeshInstance3D.new()
	_surface.name = "Beer"
	_surface.mesh = disc
	_surface.material_override = _material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.top_level = true
	_surface.visible = false
	add_child(_surface)

## The point of the beer's surface on the tankard's axis, world. Beer keeps
## its volume as the tankard tilts: the surface stays at the height along the
## axis it has upright.
func surface_point() -> Vector3:
	return level_point(global_transform, fill)

## The point of the surface on the axis of a tankard placed at `frame`, `fill`
## full.
static func level_point(frame: Transform3D, full: float) -> Vector3:
	return frame * Vector3(0.0, BOTTOM + (RIM - BOTTOM - 0.01) * full, 0.0)

func _process(_delta: float) -> void:
	if not _surface.visible:
		return
	_surface.global_transform = Transform3D(Basis.IDENTITY, surface_point())
	_material.set_shader_parameter("to_tankard", global_transform.affine_inverse())
	_material.set_shader_parameter("foam", foam)
