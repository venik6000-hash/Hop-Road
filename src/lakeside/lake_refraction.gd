class_name LakeRefraction
extends Node
## Tidewater's underwater-only, guard-band refraction pass adapted to Godot.
## Layer 19 is private to the capture camera; shared materials clip at the water.
const LAYER := 1 << 18
const GUARD := 1.25
## For an eye in the tavern's rooms (TavernPortals): the lake is looked for
## in squares down to this side (m), this far over and under its level (m),
## where the ground lies no higher over the level than SHORE (m).
const WATER_SQUARE := 32.0
const WATER_SWELL := 2.0
const SHORE := 1.5
var water: WaterSystem
var viewport: SubViewport
var camera: Camera3D
var capture := RefractionCapture.new()
var enabled := true
var _bound := false
## The TavernPortals.revision the lake was last looked for by, and whether
## an opening of the tavern showed it.
var _portal_revision := -1
var _water_seen := true

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "UnderwaterRefraction"
	viewport.size = Vector2i(640,360)
	viewport.world_3d = (get_parent() as Node3D).get_world_3d()
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The capture sees every lamp (see _register_geometry) and would keep a
	# second shadow map for each. Under the lake only the sun's shadows show.
	viewport.positional_shadow_atlas_size = 0
	add_child(viewport)
	camera = Camera3D.new()
	camera.cull_mask = LAYER
	camera.near = 0.05
	camera.far = 200
	var source := get_parent().get_node("WorldEnvironment") as WorldEnvironment
	camera.environment = source.environment.duplicate()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	camera.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	camera.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment.glow_enabled = false
	camera.environment.ssao_enabled = false
	camera.environment.adjustment_enabled = false
	var compositor := Compositor.new()
	compositor.compositor_effects = [capture]
	camera.compositor = compositor
	viewport.add_child(camera)
	camera.current = true
	for main: Camera3D in get_parent().find_children("*","Camera3D",true,false):
		if main != camera: main.cull_mask &= ~LAYER
	_register_geometry.call_deferred()
	water.material.set_shader_parameter("lake_refraction_frame", viewport.get_texture())
	water.material.set_shader_parameter("refraction_guard", GUARD)

func _register_geometry() -> void:
	# Lights are VisualInstance3D too: the private camera must see the sun and
	# local lights, while their light_cull_mask still limits affected geometry.
	for light: Light3D in get_parent().find_children("*", "Light3D", true, false):
		light.layers |= LAYER
	# Only shaders that implement the refraction clip can enter this pass.
	for node in get_parent().find_children("*","GeometryInstance3D",true,false):
		var geometry := node as GeometryInstance3D
		var material := geometry.material_override as ShaderMaterial
		if material == null and geometry is MeshInstance3D and geometry.mesh != null:
			material = geometry.get_active_material(0) as ShaderMaterial
		if material != null and material.shader != null and material.shader.resource_path in [
			"res://src/terrain/terrain.gdshader", "res://src/rocks/rock.gdshader",
			"res://src/rocks/rock_cliff.gdshader", "res://src/wildlife/underwater_life.gdshader",
			"res://src/wildlife/reed.gdshader"]:
			geometry.layers |= LAYER

func _process(_delta: float) -> void:
	if not _bound and capture.frames > 0:
		water.material.set_shader_parameter("lake_refraction", capture.texture)
		_bound = true
	var main := get_viewport().get_camera_3d()
	if main == null: return
	var active := enabled and main.global_position.y > water.water_level + 0.08 and main.global_position.y < water.water_level + 35
	var warm := _bound and capture.frames > 1
	# Only the lake surface samples this capture. WaterSystem (an earlier
	# sibling, so it runs first) has already chosen this frame's surface
	# patches; with none selected no water pixel is drawn and the pass can rest.
	# Until the capture is warm the pass runs as before, so the first water
	# frame always finds a texture of this frame. Nor is any drawn for an eye
	# in the tavern's rooms that no opening shows the lake.
	var render := active and ((water.selected_nodes > 0 and _through_portals()) or not warm)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if render else SubViewport.UPDATE_DISABLED
	water.material.set_shader_parameter("refraction_ready", active and warm)
	if not active: return
	# Half the pixels the scene itself is shaded in: a window larger than the
	# render tier's budget is enlarged from them, and the lake's bed needs no
	# more than the lake.
	var size := Vector2i(Vector2(get_viewport().size) * (get_viewport().scaling_3d_scale * 0.5))
	size.x = clampi(size.x,320,960)
	size.y = clampi(size.y,180,540)
	if viewport.size != size:
		viewport.size = size
		# The capture's target follows the viewport. Resized here, ahead of the
		# draw, the lake's material is bound to it again as the frame begins;
		# left to the render callback, the lake would miss this frame.
		RenderingServer.call_on_render_thread(capture.prepare.bind(size))
	camera.global_transform = main.global_transform
	camera.keep_aspect = main.keep_aspect
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(main.fov)*0.5)*GUARD))
	camera.near = main.near

## Whether the lake can be seen at all: always from outdoors, and from the
## tavern's rooms when an opening shows a square of the ground that has water.
func _through_portals() -> bool:
	var portals := TavernPortals.current
	if portals == null or not portals.sight.active:
		return true
	if portals.revision != _portal_revision:
		_portal_revision = portals.revision
		var terrain := water.terrain
		var level := water.water_level
		_water_seen = portals.sight.sees_ground(terrain.far_origin, WaterSystem.LOD0_SIZE * pow(2.0, WaterSystem.LEVELS - 1),
			level - WATER_SWELL, level + WATER_SWELL, WATER_SQUARE,
			func(x: float, z: float, size: float) -> bool: return terrain.height_bounds(x, z, size).x < level + SHORE)
		portals.counts[&"lake capture"] = Vector2i(int(not _water_seen), 1)
	return _water_seen
