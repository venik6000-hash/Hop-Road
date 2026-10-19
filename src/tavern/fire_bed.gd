class_name FireBed
extends Node3D
## The bed of a wood fire in a hearth, named by a row of a table's `fires`
## (`bed`): split logs charred to an alligator crust on a bed of embers and
## ash (tools/pipeline/fire_bed/fire_bed.py), flames that grow from the logs
## and lick up the back of the hearth, a spark now and then. The wood burns
## the logs away one by one; the embers glow on a while after the flames are
## out. The row's lamps light the room (HearthFire.burn).
## Cost: seven draw calls (four logs and the bed on two materials, one
## MultiMesh of flames, a CPUParticles3D of a few sparks), 23 k triangles;
## nothing casts a shadow; nothing is allocated per frame.

const EMBERS := preload("res://src/tavern/fire_bed_embers.gdshader")
const FLAME := preload("res://src/tavern/fire_bed_flame.gdshader")
const FLAME_ATLAS := preload("res://assets/effects/fire/flame03.png")
## How fast the embers' glow follows the fire up, and dies after it, per second.
const GLOW_RISE := 0.4
const GLOW_FALL := 0.012

## The flames, for a draught that flares them (HearthFire.flare).
var flames: MultiMeshInstance3D
var _logs: Array[MeshInstance3D] = []
## Flames of logs 0..i, for MultiMesh.visible_instance_count.
var _flames_up_to: Array[int] = []
var _sparks: CPUParticles3D
var _flame_material: ShaderMaterial
var _log_material: ShaderMaterial
var _bed_material: ShaderMaterial
var _fire := 0.0
var _wood := -1.0
var _glow := 0.0
var _shown_glow := -1.0
var _shown_fire := -1.0

## The bed tables the `fires` of the table at `path` name.
static func beds_of(path: String) -> Array[String]:
	var beds: Array[String] = []
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (table is Dictionary):
		return beds
	var rows: Dictionary = table
	for row: Variant in Values.list(rows.get("fires", [])):
		var config := Values.table(row)
		if config.has("bed") and not beds.has(str(config.bed)):
			beds.append(str(config.bed))
	return beds

## The bed of the table at `path` (BuildingSchemas.fire_bed()) laid in a
## hearth `width` across its opening along `along` and `height` to its crown,
## at the parent's origin; the hearth runs back from the opening along
## `along` × UP, as deep as the bed's own hearth is for its width.
static func lay(path: String, along: Vector3, width: float, height: float) -> FireBed:
	var bed := FireBed.new()
	bed.name = "Bed"
	bed._build(Values.table(JSON.parse_string(FileAccess.get_file_as_string(path))), along, width, height)
	return bed

func _build(table: Dictionary, along: Vector3, width: float, height: float) -> void:
	# The bed's hearth: width, depth and height to the crown (the generator's
	# Blender axes).
	var box := Values.vec3(table.firebox)
	var back := along.cross(Vector3.UP).normalized()
	var depth := width * box.y / box.x
	transform = Transform3D(Basis(along.normalized() * width / box.x, Vector3.UP * height / box.z,
			back * depth / box.y), Vector3.ZERO)
	var maps := Values.table(table.maps)
	_log_material = _embers(Values.table(maps.logs), 6.0, 1.0)
	_bed_material = _embers(Values.table(maps.embers), 7.0, 0.1)
	var model := (load(str(table.model)) as PackedScene).instantiate() as Node3D
	add_child(model)
	for item: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		item.layers = LightLayers.ROOMS
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		item.material_override = _bed_material if item.name == &"bed" else _log_material
	var logs := Values.list(table.logs)
	for row: Variant in logs:
		_logs.append(model.find_child(str(Values.table(row).name), true, false) as MeshInstance3D)
	_build_flames(logs, box.y, box.z)
	_build_sparks()
	# A cold, empty hearth until it is told otherwise.
	burn(0.0, 0.0)

## The fire's strength 0..1 and the wood in the hearth as a share of a full
## one, 0..1: log i of the bed's `logs` (the last thrown on top) is there
## while the wood is more than i of their count.
func burn(fire: float, wood: float) -> void:
	if fire == _fire and wood == _wood:
		return
	_fire = clampf(fire, 0.0, 1.0)
	_wood = clampf(wood, 0.0, 1.0)
	var logs := 0
	for index in _logs.size():
		var present := _wood > float(index) / _logs.size() + 0.001
		_logs[index].visible = present
		if present:
			logs = index + 1
	flames.multimesh.visible_instance_count = _flames_up_to[logs - 1] if logs > 0 else 0
	flames.visible = _fire > HearthFire.OUT and logs > 0
	_sparks.emitting = _fire > 0.45
	_apply()

func _process(delta: float) -> void:
	_glow = minf(_fire, _glow + GLOW_RISE * delta) if _glow < _fire else maxf(_fire, _glow - GLOW_FALL * delta)
	_apply()

func _apply() -> void:
	if absf(_glow - _shown_glow) > 0.004:
		_shown_glow = _glow
		_log_material.set_shader_parameter("heat", _glow)
		_bed_material.set_shader_parameter("heat", _glow)
	if _fire != _shown_fire:
		_shown_fire = _fire
		_flame_material.set_shader_parameter("fire", _fire)

func _embers(maps: Dictionary, energy: float, shade: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EMBERS
	material.set_shader_parameter("albedo_tex", load(str(maps.albedo)))
	material.set_shader_parameter("normal_tex", load(str(maps.normal)))
	material.set_shader_parameter("mask_tex", load(str(maps.mask)))
	material.set_shader_parameter("energy", energy)
	material.set_shader_parameter("albedo_scale", shade)
	return material

## Cards on each log's roots, set a little behind them so the logs stand
## dark against their own flames: a main flame, two smaller ones beside it,
## and from the back roots a tall tongue up the back wall to the crown.
func _build_flames(logs: Array, depth: float, crown: float) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 7
	var cards: Array[Transform3D] = []
	var custom: Array[Color] = []
	var behind := Vector3(0.0, -0.01, 0.035)
	for row: Variant in logs:
		for root: Variant in Values.list(Values.table(row).roots):
			var at := Values.vec3(root) + behind
			var tall := random.randf_range(0.13, 0.22)
			_card(cards, custom, random, at, random.randf_range(0.08, 0.11), tall, 0.0, 0.95)
			for side in 2:
				var beside := Vector3(random.randf_range(-0.05, 0.05), 0.0, random.randf_range(-0.02, 0.04))
				_card(cards, custom, random, at + beside, random.randf_range(0.05, 0.08), tall * random.randf_range(0.4, 0.7),
						0.15 + 0.25 * side, 0.75)
			if at.z > depth * 0.1:
				var wall := Vector3(at.x, at.y, depth * 0.5 - 0.07)
				_card(cards, custom, random, wall, random.randf_range(0.1, 0.14), (crown - at.y) * 1.2, 0.5, 0.7)
		_flames_up_to.append(cards.size())
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	multimesh.mesh = quad
	multimesh.instance_count = cards.size()
	for index in cards.size():
		multimesh.set_instance_transform(index, cards[index])
		multimesh.set_instance_custom_data(index, custom[index])
	_flame_material = ShaderMaterial.new()
	_flame_material.shader = FLAME
	_flame_material.set_shader_parameter("fire_atlas", FLAME_ATLAS)
	flames = MultiMeshInstance3D.new()
	flames.name = "Flames"
	flames.multimesh = multimesh
	flames.material_override = _flame_material
	flames.layers = LightLayers.ROOMS
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cards turn to the eye in the shader: the box holds them at any turn.
	flames.custom_aabb = AABB(Vector3(-0.4, -0.05, -0.4), Vector3(0.8, crown + 0.3, 0.8))
	add_child(flames)

func _card(cards: Array[Transform3D], custom: Array[Color], random: RandomNumberGenerator, at: Vector3,
		width: float, height: float, needs: float, bright: float) -> void:
	cards.append(Transform3D(Basis.from_scale(Vector3(width, height, 1.0)), at))
	var flip := 1.0 if random.randf() < 0.5 else -1.0
	custom.append(Color(random.randf_range(0.0, 64.0), random.randf_range(20.0, 30.0), needs, flip * bright))

func _build_sparks() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.007, 0.007)
	quad.material = material
	var colours := Gradient.new()
	colours.set_color(0, Color(3.0, 1.6, 0.5, 1.0))
	colours.set_color(1, Color(0.6, 0.08, 0.0, 0.0))
	colours.add_point(0.4, Color(2.0, 0.6, 0.08, 1.0))
	_sparks = CPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.mesh = quad
	_sparks.amount = 6
	_sparks.lifetime = 0.8
	_sparks.randomness = 1.0
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_sparks.emission_box_extents = Vector3(0.16, 0.03, 0.14)
	_sparks.position = Vector3(0.0, 0.2, 0.0)
	_sparks.direction = Vector3.UP
	_sparks.spread = 30.0
	_sparks.initial_velocity_min = 0.25
	_sparks.initial_velocity_max = 0.6
	_sparks.gravity = Vector3(0.0, 0.15, 0.0)
	_sparks.damping_min = 0.2
	_sparks.damping_max = 0.6
	_sparks.color_ramp = colours
	_sparks.layers = LightLayers.ROOMS
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.emitting = false
	add_child(_sparks)
