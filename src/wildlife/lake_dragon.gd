extends Node3D
## A constant-speed circuit over the open lake, west of the island.
const SceneUtil = preload("res://src/common/scene_util.gd")
const CENTRE := Vector3(-155.0, 29.0, -78.0)
const RADII := Vector2(65.0, 28.0)
const SPEED := 8.0
const LAKE_SLOPE := 0.16
var phase := 0.0
var animation: AnimationPlayer

func _ready() -> void:
	animation = SceneUtil.animation_player($Model)
	animation.get_animation("Flying").loop_mode = Animation.LOOP_LINEAR
	animation.play("Flying")
	animation.advance(0.0)
	update_pose()

func _process(delta: float) -> void:
	phase = fposmod(phase + SPEED * delta / route_tangent(phase).length(), TAU)
	update_pose()

static func route_position(angle: float) -> Vector3:
	var x := RADII.x * cos(angle)
	return CENTRE + Vector3(x, 3.0 * sin(angle * 2.0), RADII.y * sin(angle) + LAKE_SLOPE * x)

static func route_tangent(angle: float) -> Vector3:
	var x := -RADII.x * sin(angle)
	return Vector3(x, 6.0 * cos(angle * 2.0), RADII.y * cos(angle) + LAKE_SLOPE * x)

func update_pose() -> void:
	position = route_position(phase)
	var tangent := route_tangent(phase)
	# The imported rig faces +Z. Lean into the turn, most at the oval's ends.
	basis = Basis.looking_at(tangent.normalized(), Vector3.UP, true)
	var horizontal_speed := Vector2(tangent.x, tangent.z).length()
	var curvature := RADII.x * RADII.y / pow(horizontal_speed, 3.0)
	rotate_object_local(Vector3.BACK, atan(SPEED * SPEED * curvature / 9.81))
