class_name BrewStream
extends MeshInstance3D
## A stream in the brewery: water, wort or grain falling from a nozzle, a
## tipped sack or a bucket to where it lands. A ribbon the shader bends and
## turns to the camera (brew_stream.gdshader); there is no fluid.

const SHADER := preload("res://src/brewing/brew_stream.gdshader")
## Pieces down the ribbon.
const PIECES := 16

## What it pours now: how much (0 while it does not run), from where (world
## space), and whether it is grain.
var flow := 0.0
var from_point := Vector3.ZERO
var grain := false

var _material := ShaderMaterial.new()
var _strip := ArrayMesh.new()

func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = TavernSystem.LAYER
	_material.shader = SHADER
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	for index in PIECES + 1:
		var t := float(index) / PIECES
		for side in 2:
			points.append(Vector3(side, -t, 0.0))
			uvs.append(Vector2(side, t))
	var faces := PackedInt32Array()
	for index in PIECES:
		var a := index * 2
		faces.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = faces
	_strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_strip.surface_set_material(0, _material)
	mesh = _strip
	visible = false

## Pours from `from` to `to` (world space) at `amount` (0..1, 0 stops it),
## `width` metres wide at the top, of colour `tint`; grains when `grains`.
func pour(from: Vector3, to: Vector3, amount: float, width: float, tint: Color, grains := false) -> void:
	visible = amount > 0.01 and from.y > to.y
	flow = amount if visible else 0.0
	from_point = from
	grain = grains
	if not visible:
		return
	_material.set_shader_parameter("from", from)
	_material.set_shader_parameter("to", to)
	_material.set_shader_parameter("flow", amount)
	_material.set_shader_parameter("width", width)
	_material.set_shader_parameter("tint", tint)
	_material.set_shader_parameter("grain", 1.0 if grains else 0.0)
	_strip.custom_aabb = AABB(from, Vector3.ZERO).expand(to).grow(width + 0.1)

## The stream runs no more.
func stop() -> void:
	visible = false
	flow = 0.0
