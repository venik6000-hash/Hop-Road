class_name RainFall
extends MultiMeshInstance3D
## The drops of WeatherSystem's rain: streaks in a box of air that follows the
## eye (rain_fall.gdshader moves them; this node only tells it how many fall,
## which way, and how far they have come).

const SHADER := preload("res://src/weather/rain_fall.gdshader")
const DROPS := 9000
## The box of air around the eye the drops are kept in, m.
const BOX := Vector3(26.0, 18.0, 26.0)
## A 2-3 mm drop's speed, m/s, and the share of the wind it takes near the
## ground; the wind it takes at most, m/s.
const FALL_SPEED := 9.0
const WIND_SHARE := 0.45
const WIND_LIMIT := 7.5
## The drops' way is wrapped by this many boxes: the shader's three paces
## (0.8, 1.0, 1.2) each come to a whole number of boxes over it.
const TRAVEL_WRAP := 5.0
## The share of the drops a plain rain shows; a storm shows them all.
const RAIN_SHARE := 0.6

var weather: WeatherSystem
## The wind over the ground, m/s (x, z).
var wind := Vector2.ZERO
## The building no rain falls in.
var building := AABB()
var water_level := -1000.0

var _material: ShaderMaterial
var _travelled := Vector3.ZERO

func _ready() -> void:
	name = "RainFall"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("box", BOX)
	_material.set_shader_parameter("room_min", building.position)
	_material.set_shader_parameter("room_max", building.end)
	_material.set_shader_parameter("roofed", 1.0 if building.has_volume() else 0.0)
	_material.set_shader_parameter("water_level", water_level)
	quad.material = _material
	var drops := MultiMesh.new()
	drops.transform_format = MultiMesh.TRANSFORM_3D
	drops.mesh = quad
	drops.instance_count = DROPS
	var rng := RandomNumberGenerator.new()
	rng.seed = 7411
	for drop in DROPS:
		drops.set_instance_transform(drop, Transform3D(Basis.IDENTITY, Vector3(rng.randf(), rng.randf(), rng.randf())))
	# The shader places the drops around the eye, wherever that is.
	drops.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
	multimesh = drops
	visible = false

func _process(delta: float) -> void:
	var share := amount(weather.state.rain, weather.state.storm) if weather != null else 0.0
	visible = share > 0.004
	if not visible:
		return
	var velocity := fall_velocity(wind)
	_travelled = wrap_travel(_travelled + velocity * delta)
	_material.set_shader_parameter("velocity", velocity)
	_material.set_shader_parameter("travelled", _travelled)
	_material.set_shader_parameter("amount", share)

## The share of the drops that fall in a rain of `rain` 0..1 under a storm of
## `storm` 0..1.
static func amount(rain: float, storm: float) -> float:
	return clampf(rain, 0.0, 1.0) * lerpf(RAIN_SHARE, 1.0, clampf(storm, 0.0, 1.0))

## A drop's velocity in a wind of `over_ground` m/s (x, z).
static func fall_velocity(over_ground: Vector2) -> Vector3:
	var carried := (over_ground * WIND_SHARE).limit_length(WIND_LIMIT)
	return Vector3(carried.x, -FALL_SPEED, carried.y)

## The way wrapped so that every pace of the shader lands on the same drops.
static func wrap_travel(travelled: Vector3) -> Vector3:
	var span := BOX * TRAVEL_WRAP
	return Vector3(fposmod(travelled.x, span.x), fposmod(travelled.y, span.y), fposmod(travelled.z, span.z))
