class_name HearthFire
extends Node3D
## CC0 Houdini flame frames, with independent timing across the burning logs.
## The air over them shimmers: a visible fire is a column of hot air to
## RefractionPost (its HEAT_GROUP).
const SHADER := preload("res://src/tavern/fire_flipbook.gdshader")
const ATLAS := preload("res://assets/effects/fire/flame03.png")
static var _material: ShaderMaterial
var _flames: Array[MeshInstance3D] = []
var _last_camera_position := Vector3(INF, INF, INF)
var _last_transform := Transform3D.IDENTITY
## The column of hot air: its radius at the foot and its height, m, how high
## above the logs it begins, and how strongly it bends the light (1 a hearth).
var haze_radius := 0.4
var haze_height := 1.6
var haze_lift := 0.2
var haze_strength := 1.0

## The fire of a row of a table's `fires` (BuildingSchemas.fire()): flames
## along `along` at `at`, `width` across and `height` tall.
static func from_table(config: Dictionary) -> HearthFire:
	var fire := HearthFire.new()
	fire.name = str(config.name).to_pascal_case() + "Flames"
	fire.configure(Values.vec3(config.at), Values.vec3(config.along), Values.real(config.width), Values.real(config.height))
	return fire

func configure(origin: Vector3, along: Vector3, width: float, flame_height: float) -> void:
	position = origin
	_last_camera_position = Vector3(INF, INF, INF)
	haze_radius = width * 0.5
	haze_lift = flame_height * 0.35
	haze_height = flame_height * 2.0 + 0.5
	add_to_group(RefractionPost.HEAT_GROUP)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("fire_atlas", ATLAS)
		_material.set_shader_parameter("intensity", 2.0)
	for index in range(5):
		var quad := QuadMesh.new()
		quad.size = Vector2(width * 0.36, flame_height * (0.8 + 0.08 * (index % 3)))
		quad.material = _material
		var flame := MeshInstance3D.new()
		flame.mesh = quad
		flame.set_instance_shader_parameter("phase", index * 11.7)
		flame.set_instance_shader_parameter("speed", 21.0 + index * 1.1)
		flame.position = along * width * (float(index) / 4.0 - 0.5) * 0.75 + Vector3.UP * quad.size.y * 0.5
		flame.layers = LightLayers.ROOMS
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
		_flames.append(flame)

## Where the column of hot air begins (world space).
func haze_foot() -> Vector3:
	return global_position + Vector3.UP * haze_lift

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var transform_now := global_transform
	if eye == _last_camera_position and transform_now == _last_transform:
		return
	_last_camera_position = eye
	_last_transform = transform_now
	for flame: MeshInstance3D in _flames:
		var direction := eye - flame.global_position
		var yaw := atan2(direction.x, direction.z)
		if flame.rotation.y != yaw:
			flame.rotation.y = yaw
