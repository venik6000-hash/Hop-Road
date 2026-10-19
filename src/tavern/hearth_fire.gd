class_name HearthFire
extends Node3D
## CC0 Houdini flame frames, with independent timing across the burning logs;
## or, for a row with a `bed`, the modelled logs and embers of that bed with
## their own flames (FireBed). The air over them shimmers: a burning fire is a
## column of hot air to RefractionPost (HearthFire.heating).
const SHADER := preload("res://src/tavern/fire_flipbook.gdshader")
const ATLAS := preload("res://assets/effects/fire/flame03.png")
## Strength below which a fire is out.
const OUT := 0.02
static var _material: ShaderMaterial
## The fires whose hot air shimmers (RefractionPost): each burning fire in the
## tree keeps itself here, so no frame looks for them through the tree.
static var heating: Array[HearthFire] = []
var _flames: Array[MeshInstance3D] = []
## The modelled bed of logs and embers; null for flames alone.
var bed: FireBed
## The fire's strength, 0..1 (burn).
var strength := 1.0
## The flames' size by the fire's strength, and by a draught's flare.
var _grown := 1.0
var _flared := 1.0
var _last_camera_position := Vector3(INF, INF, INF)
var _last_transform := Transform3D.IDENTITY
## The column of hot air: its radius at the foot and its height, m, how high
## above the logs it begins, and how strongly it bends the light (1 a hearth).
var haze_radius := 0.4
var haze_height := 1.6
var haze_lift := 0.2
var haze_strength := 1.0
## The fire's air shimmers while it is in the tree (heating).
var _heats := false

## The fire of a row of a table's `fires` (BuildingSchemas.hearth()): flames
## along `along` at `at`, `width` across and `height` tall; with a `bed`, that
## bed laid in a hearth `width` across and `height` to its crown. It burns,
## but a `tended` fire is cold until its work stokes it.
static func from_table(config: Dictionary) -> HearthFire:
	var fire := HearthFire.new()
	fire.name = str(config.name).to_pascal_case() + "Flames"
	var at := Values.vec3(config.at)
	var along := Values.vec3(config.along)
	var width := Values.real(config.width)
	var height := Values.real(config.height)
	if config.has("bed"):
		fire.lay_bed(str(config.bed), at, along, width, height)
	else:
		fire.configure(at, along, width, height)
	fire.burn(0.0 if Values.flag(config.get("tended", false)) else 1.0)
	return fire

func configure(origin: Vector3, along: Vector3, width: float, flame_height: float) -> void:
	position = origin
	_last_camera_position = Vector3(INF, INF, INF)
	haze_radius = width * 0.5
	haze_lift = flame_height * 0.35
	haze_height = flame_height * 2.0 + 0.5
	_heat(true)
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

## Lays the bed of the table at `path` (FireBed.lay) in a hearth whose floor
## centre is `origin`, `width` across its opening along `along` and `height`
## to its crown. It is cold until it burns.
func lay_bed(path: String, origin: Vector3, along: Vector3, width: float, height: float) -> void:
	position = origin
	haze_radius = width * 0.35
	haze_lift = height * 0.2
	haze_height = height * 1.4
	bed = FireBed.lay(path, along, width, height)
	add_child(bed)
	burn(0.0, 0.0)

## The fire burns at `strength` 0..1 with `wood` of a full hearth in it
## (0..1): a bed shows its logs and its glow, and its flames by the strength;
## flames alone grow with the strength and are gone when it is out.
func burn(fire_strength: float, wood := 1.0) -> void:
	strength = fire_strength
	var burning := strength > OUT
	if bed != null:
		bed.burn(strength, wood)
		haze_strength = 0.7 * strength
	else:
		visible = burning
		_grown = lerpf(0.4, 1.0, strength)
		scale = Vector3.ONE * _grown * _flared
	if burning != _heats:
		_heat(burning)

func _enter_tree() -> void:
	if _heats and not heating.has(self):
		heating.append(self)

func _exit_tree() -> void:
	heating.erase(self)

## The air over the fire shimmers (`on`) or not.
func _heat(on: bool) -> void:
	_heats = on
	if not on:
		heating.erase(self)
	elif is_inside_tree() and not heating.has(self):
		heating.append(self)

## Whether it burns: a cold bed still shows its logs and glowing embers.
func burning() -> bool:
	return strength > OUT

## A draught flares the flames `amount` times their size (1 for none).
func flare(amount: float) -> void:
	_flared = amount
	if bed != null:
		bed.flames.scale = Vector3.ONE * amount
	else:
		scale = Vector3.ONE * _grown * _flared

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
