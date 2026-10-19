class_name LakeDragon
extends Node3D
## A constant-speed circuit over the region's lake: an oval round `centre`
## with half axes `radii` (x, z), tilted along z by `slope` per metre along x
## (RegionDef.dragon, WorldSchemas.dragon).
const SceneUtil = preload("res://src/common/scene_util.gd")
const SPEED := 8.0
## The region's file of the circuit.
var circuit := ""
var centre := Vector3.ZERO
var radii := Vector2.ONE
var slope := 0.0
var phase := 0.0
var animation: AnimationPlayer

func _ready() -> void:
	var data: Variant = DataFile.read(circuit, WorldSchemas.dragon())
	if data is Dictionary:
		var file: Dictionary = data
		centre = Values.vec3(file.centre)
		radii = Values.vec2(file.radii)
		slope = Values.real(file.slope)
	animation = SceneUtil.animation_player($Model)
	animation.get_animation("Flying").loop_mode = Animation.LOOP_LINEAR
	animation.play("Flying")
	animation.advance(0.0)
	update_pose()

func _process(delta: float) -> void:
	phase = fposmod(phase + SPEED * delta / route_tangent(phase).length(), TAU)
	update_pose()

func route_position(angle: float) -> Vector3:
	var x := radii.x * cos(angle)
	return centre + Vector3(x, 3.0 * sin(angle * 2.0), radii.y * sin(angle) + slope * x)

func route_tangent(angle: float) -> Vector3:
	var x := -radii.x * sin(angle)
	return Vector3(x, 6.0 * cos(angle * 2.0), radii.y * cos(angle) + slope * x)

func update_pose() -> void:
	position = route_position(phase)
	var tangent := route_tangent(phase)
	# The imported rig faces +Z. Lean into the turn, most at the oval's ends.
	basis = Basis.looking_at(tangent.normalized(), Vector3.UP, true)
	var horizontal_speed := Vector2(tangent.x, tangent.z).length()
	var curvature := radii.x * radii.y / pow(horizontal_speed, 3.0)
	rotate_object_local(Vector3.BACK, atan(SPEED * SPEED * curvature / 9.81))
