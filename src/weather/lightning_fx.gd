class_name LightningFx
extends Node3D
## What a strike of WeatherSystem does to the land: its light on the ground,
## and the bolt of those that reach it. (Its light inside the clouds is the
## sky shader's, its light in the fog the fog pass's.)
##
## The light is a lamp without a shadow: a strike lights a valley for a few
## hundredths of a second from clouds all over the sky, and four more shadow
## cascades for those frames would cost a stutter exactly when it shows.

const BOLT_SHADER := preload("res://src/weather/lightning_bolt.gdshader")
## The lamp's energy at a strike's full light; the ambient light's gain.
const FLASH_ENERGY := 2.6
const FLASH_AMBIENT := 1.5
## A bolt's half width, m, and the least it may measure in the picture, rad.
const BOLT_WIDTH := 1.6
const BOLT_ANGLE := 0.0011
## Times a bolt's path is halved, each time bent by a share of its length.
const BOLT_SPLITS := 7
const BOLT_BEND := 0.19

var weather: WeatherSystem
var terrain: TerrainSystem
var environment: Environment
## The rooms, as boxes in world space: the lamp does not shine in them.
var rooms: Array[AABB] = []

var _lamp: DirectionalLight3D
var _ambient := 1.0
## The bolts in the air: {strike, mesh instance, material}.
var _bolts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_lamp = DirectionalLight3D.new()
	_lamp.name = "Flash"
	_lamp.light_color = Color(0.74, 0.82, 1.0)
	_lamp.shadow_enabled = false
	_lamp.light_specular = 0.3
	_lamp.visible = false
	# The rooms keep their own light (see TavernSystem's layers).
	_lamp.light_cull_mask = 0xFFFFF & ~(TavernSystem.LAYER | TavernSystem.SHADOW_LAYER | TavernSystem.ROOM_SUN_LAYER)
	add_child(_lamp)
	if environment != null:
		_ambient = environment.ambient_light_energy
	if weather != null:
		weather.lightning_struck.connect(_on_strike)

func _process(_delta: float) -> void:
	if weather == null:
		return
	var light := weather.flash_light
	var camera := get_viewport().get_camera_3d()
	var outdoors := 1.0 - EyeAdaptation.indoors(camera.global_position, rooms) if camera != null else 1.0
	_lamp.visible = light * outdoors > 0.002
	if _lamp.visible:
		_lamp.light_energy = FLASH_ENERGY * light * outdoors
		if not weather.strikes.is_empty() and camera != null:
			# Down from the strike's part of the sky.
			var from: Vector3 = weather.strikes[-1].at - camera.global_position
			from.y = maxf(from.y, from.length() * 0.45)
			_lamp.global_basis = Basis.looking_at(-from.normalized(), Vector3.FORWARD)
	if environment != null:
		var ambient := _ambient * (1.0 + FLASH_AMBIENT * light)
		if not is_equal_approx(environment.ambient_light_energy, ambient):
			environment.ambient_light_energy = ambient
	for bolt: Dictionary in _bolts:
		(bolt.material as ShaderMaterial).set_shader_parameter("light", WeatherSystem.strike_light(bolt.strike))
	while not _bolts.is_empty() and _bolts[0].strike.age >= WeatherSystem.FLASH_SECONDS:
		(_bolts.pop_front().instance as Node).queue_free()

func _on_strike(strike: Dictionary) -> void:
	if not strike.ground or terrain == null:
		return
	_rng.seed = strike.seed
	var from: Vector3 = strike.at
	var to := from + Vector3(_rng.randf_range(-450.0, 450.0), 0.0, _rng.randf_range(-450.0, 450.0))
	to.y = maxf(terrain.height_at(to.x, to.z), terrain.water_level)
	var instance := MeshInstance3D.new()
	instance.name = "Bolt"
	instance.mesh = bolt_mesh(from, to, _rng)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var material := ShaderMaterial.new()
	material.shader = BOLT_SHADER
	material.set_shader_parameter("half_width", BOLT_WIDTH)
	material.set_shader_parameter("least_angle", BOLT_ANGLE)
	material.set_shader_parameter("light", WeatherSystem.strike_light(strike))
	instance.material_override = material
	add_child(instance)
	_bolts.append({"strike": strike, "instance": instance, "material": material})

## The channel from `from` to `to` and its forks, as ribbons the shader turns
## to the eye: NORMAL holds the way a ribbon runs, UV.x the side of it (-1, 1)
## and COLOR.r how bright it is (a fork is fainter than the channel).
static func bolt_mesh(from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var channel := bolt_path(from, to, BOLT_SPLITS, rng)
	_ribbon(channel, 1.0, vertices, normals, uvs, colors)
	var forks := rng.randi_range(2, 5)
	for fork in forks:
		var start := rng.randi_range(channel.size() / 8, channel.size() * 3 / 4)
		var along := (to - from) * rng.randf_range(0.12, 0.3)
		var aside := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * along.length() * 0.8
		_ribbon(bolt_path(channel[start], channel[start] + along + aside, BOLT_SPLITS - 2, rng), 0.35,
			vertices, normals, uvs, colors)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The ribbons are widened toward the eye in the shader.
	mesh.custom_aabb = AABB(from, Vector3.ZERO).expand(to).grow((to - from).length() * 0.5)
	return mesh

## A jagged path between two points: halved `splits` times, each new point
## thrown aside by a share of the piece it halves.
static func bolt_path(from: Vector3, to: Vector3, splits: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var points := PackedVector3Array([from, to])
	for split in splits:
		var next := PackedVector3Array()
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var piece := b - a
			var aside := piece.cross(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)))
			next.append(a)
			next.append(a + piece * 0.5 + aside.limit_length(piece.length()) * BOLT_BEND)
		next.append(points[points.size() - 1])
		points = next
	return points

static func _ribbon(path: PackedVector3Array, brightness: float, vertices: PackedVector3Array,
		normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray) -> void:
	for index in path.size() - 1:
		var a := path[index]
		var b := path[index + 1]
		var along := (b - a).normalized()
		# A fork thins toward its end.
		var fade := brightness * (1.0 if brightness >= 1.0 else 1.0 - float(index) / path.size())
		for corner: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(1, 1), Vector2(0, -1), Vector2(1, 1), Vector2(1, -1)]:
			vertices.append(a if corner.x < 0.5 else b)
			normals.append(along)
			uvs.append(Vector2(corner.y, corner.x))
			colors.append(Color(fade, fade, fade))
