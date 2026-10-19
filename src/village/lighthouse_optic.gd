class_name LighthouseOptic
extends Node3D
## The turning light of the lighthouse. The builder
## (tools/pipeline/lighthouse/build.py) marks the pieces of the optic that
## turn (`lh_turning`) and gives its table an `optic`: the pivot, the period
## of a turn and the beams its lenses throw. The pieces go round on the pivot
## day and night, as the clockwork drives them. From dusk each lens throws a
## beam: a narrow light that reaches far over the lake and the shore, a shaft
## of it seen in the air, and a flash for the eye the lens sweeps over.

const SHAFT := preload("res://src/village/lighthouse_shaft.gdshader")
const FLASH := preload("res://src/village/lighthouse_flash.gdshader")
## A beam on what it falls on. It thins with distance slower than a lamp's
## light does: the lens gathers it.
const BEAM_ENERGY := 8.0
const BEAM_FALLOFF := 0.6
## Metres of a beam's shaft that are seen in the air.
const SHAFT_LENGTH := 120.0
## A lens: its radius, and how far from the pivot its face goes round, m.
const LENS := 0.32
const LENS_REACH := 0.5
## Metres outside a room's box over which the beams' light comes back to an
## eye that leaves the room: less than a wall is thick.
const THRESHOLD := 0.4

var sky_system: SkySystem
## The level's rooms. A beam casts no shadow and the walls of a house are lit
## by it on both their faces, the one to the room with the one to the
## weather: for an eye in a room the beams light nothing, and are only seen in
## the air beyond the windows. Null: the eye is never in a room.
var interiors: Interiors
## Seconds a turn takes.
var period := 12.0

var _turn: Node3D
var _beams: Array[SpotLight3D] = []
## The shafts and the flashes: drawn from dusk only.
var _seen: Array[MeshInstance3D] = []
var _last_dark := -1.0
var _last_light := -1.0

## `optic` is the table's section; the node stands in the building's frame.
func configure(optic: Dictionary) -> void:
	var pivot: Array = optic.pivot
	position = Values.vec3(pivot)
	period = optic.period
	_turn = Node3D.new()
	_turn.name = "Turning"
	add_child(_turn)
	for beam: Dictionary in optic.beams:
		_add_beam(beam)

## Takes the turning pieces of a part scene onto the pivot.
func take(scene: Node3D) -> void:
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = item.get_meta("extras", {})
		if Values.whole(extras.get("lh_turning", 0)) == 1:
			item.reparent(_turn, true)
			# The optic never stands: casting a shadow, it would have the
			# candle on the landing below draw its map again in every frame.
			item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_beam(beam: Dictionary) -> void:
	var d: Array = beam.direction
	var c: Array = beam.color
	var color := Color(Values.real(c[0]), Values.real(c[1]), Values.real(c[2]))
	var spread: float = beam.spread
	var holder := Node3D.new()
	holder.name = "Beam%d" % _beams.size()
	_turn.add_child(holder)
	# The beam leaves along the holder's -z.
	holder.basis = Basis.looking_at(Values.vec3(d).normalized(), Vector3.UP)
	var light := SpotLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.light_energy = BEAM_ENERGY
	light.spot_range = beam.range
	light.spot_angle = spread
	light.spot_attenuation = BEAM_FALLOFF
	light.spot_angle_attenuation = 1.0
	light.position = Vector3(0.0, 0.0, -LENS_REACH)
	# The walls of the houses and the land, not what stands in the rooms
	# behind the walls (see LightLayers): the beam casts no shadow.
	# The walls' own faces to the rooms are on the walls' layers: see `rooms`.
	light.light_cull_mask = 0xFFFFF & ~(LightLayers.ROOMS | LightLayers.LAMP_CASTERS | LightLayers.ROOM_SUN)
	holder.add_child(light)
	_beams.append(light)
	var cone := CylinderMesh.new()
	cone.top_radius = LENS
	cone.bottom_radius = LENS + SHAFT_LENGTH * tan(deg_to_rad(spread))
	cone.height = SHAFT_LENGTH
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var shaft_material := ShaderMaterial.new()
	shaft_material.shader = SHAFT
	shaft_material.set_shader_parameter("beam_color", color)
	shaft_material.set_shader_parameter("shaft_length", SHAFT_LENGTH)
	cone.material = shaft_material
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	shaft.mesh = cone
	# The cylinder's axis is y; its top, the narrow end, stays at the lens.
	shaft.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, 0.0, -LENS_REACH - SHAFT_LENGTH / 2.0))
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	holder.add_child(shaft)
	_seen.append(shaft)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var flash_material := ShaderMaterial.new()
	flash_material.shader = FLASH
	flash_material.set_shader_parameter("beam_color", color)
	flash_material.set_shader_parameter("radius", LENS)
	flash_material.set_shader_parameter("spread", deg_to_rad(spread))
	quad.material = flash_material
	var flash := MeshInstance3D.new()
	flash.name = "Flash"
	flash.mesh = quad
	flash.position = Vector3(0.0, 0.0, -LENS_REACH)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Sized on the screen: no box round the quad holds it from afar.
	flash.custom_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
	holder.add_child(flash)
	_seen.append(flash)

func _process(delta: float) -> void:
	_turn.rotate_y(-TAU / period * delta)
	if sky_system == null:
		return
	# Lit toward dusk, as the lanterns are.
	var dark := sky_system.lamp_dusk
	var camera := get_viewport().get_camera_3d()
	shine(dark, light_for(camera.global_position) if camera != null else 1.0)

## How much of their light the beams throw for an eye at `eye`: none in a
## room, all of it outdoors, and between the two over THRESHOLD in a doorway.
func light_for(eye: Vector3) -> float:
	var deepest := interiors.depth_of(eye) if interiors != null else -INF
	return 1.0 - smoothstep(-THRESHOLD, 0.0, deepest)

## Lights the beams as dark as the evening is (0..1): the shafts and the
## flashes are drawn for every eye, the light on what the beams fall on is
## `light` of its strength (light_for()).
func shine(dark: float, light: float) -> void:
	light *= dark
	if dark == _last_dark and light == _last_light:
		return
	_last_dark = dark
	_last_light = light
	for beam: SpotLight3D in _beams:
		beam.light_energy = BEAM_ENERGY * light
		beam.visible = light > 0.01
	for item: MeshInstance3D in _seen:
		item.visible = dark > 0.01
