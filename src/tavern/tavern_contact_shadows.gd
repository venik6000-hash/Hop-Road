class_name TavernContactShadows
extends CompositorEffect
## Contact shadows in the tavern's rooms: the last centimetres of shadow under
## a mug, a plate or a stool's leg, which a lamp's shadow map leaves out (its
## bias lifts the shadow off the thing that casts it), so that small things
## sit on what they stand on.
##
## A compositor pass on the lit picture after the opaque geometry and before
## the transparent (tavern_contact_shadows.glsl): each pixel inside the
## building finds where it is and how it faces from the depth buffer, weighs
## the lamps of its room by the light each sends it, and walks a short ray on
## the screen toward the two that weigh most. Where something stands in the
## ray's way the pixel loses that lamp's share of its light. The flames, the
## candles' halos, the sun's beams and the glass are drawn afterwards and stay
## as they are.
##
## The pass knows the lamps only by where they are and how bright: it does not
## read their shadow maps. Under a table, where a lamp's light is already
## gone, it still takes that lamp's share from a pixel beside a leg; `strength`
## is the knob for that. The sun is left to its own shadow map, whose first
## cascade is fine enough indoors.
##
## TavernSystem names the lamps once (watch) and calls prepare() once a frame
## on the main thread; the render thread only reads that snapshot. With the
## eye away from the building the pass does not run.

const RdUtil = preload("res://src/common/rd_util.gd")
const SHADER := "res://src/tavern/tavern_contact_shadows.glsl"
## The floats of the shader's parameter block, and those of them the render
## thread writes ahead of prepare()'s (three matrices and two rows).
const PARAM_FLOATS := 312
const HEAD_FLOATS := 56
## The lamps the shader weighs at a pixel (MAX_LAMPS there), and the floats of
## one: five rows.
const MAX_LAMPS := 12
const LAMP_FLOATS := 20
## How far toward a lamp a ray is walked, m: the gap a shadow map leaves under
## small things, with room to fade out before the map's own shadow begins.
const REACH := 0.25
## What is seen on the screen is taken to be this thick, m: a ray that passes
## further behind a thing than this is not shaded by it (a hand, a post in
## front of the far wall).
const THICKNESS := 0.08
## The light a room holds without its lamps (the probes' ambient light on a
## white wall), in the units of a lamp's weight: a wall a metre from a lamp of
## energy 1 weighs 1.
const AMBIENT := 0.06
## The pass runs while the eye is no further from the building than this, m.
const NEAR := 2.0
## A lamp counts while the eye is no further outside its room than this, m: in
## a doorway the lamps of both rooms.
const DOORWAY := 1.2
## A lamp whose light ends further from the eye than this is left out, m:
## beyond it a contact shadow is a pixel wide.
const VIEW := 5.0

## Off for an A/B and for tools that compare (every CompositorEffect has an
## `enabled` of its own; this one is the same for all).
static var on := true

## The share of a hidden lamp's light a pixel loses, 0..1.
@export_range(0.0, 1.0) var strength := 1.0
## Debug output instead of the picture: 1 the light left to each pixel (white
## where nothing is taken).
@export_range(0, 1) var debug_view := 0

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _nearest: RID
var _params: RID
var _lamps: Array[Light3D] = []
var _lamp_rooms: Array[AABB] = []
var _bounds := AABB()
var _frame := PackedFloat32Array()

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE
	RenderingServer.call_on_render_thread(_create)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		# Freeing the shader also frees its pipeline.
		RdUtil.free_rids(_rd, [_shader, _nearest, _params])

## Names the lamps that light the rooms, the rooms as boxes in world space and
## the building's box. A lamp is taken to light the rooms it stands in and
## nothing beyond their walls.
func watch(lamps: Array[Light3D], rooms: Array[AABB], bounds: AABB) -> void:
	_lamps = lamps
	_bounds = bounds
	_lamp_rooms.clear()
	for lamp in lamps:
		_lamp_rooms.append(room_of(lamp.global_position, rooms, bounds))

## Whether the pass will run in this frame.
func running() -> bool:
	return not _frame.is_empty()

## Takes this frame's state for the render thread. Call once a frame with the
## eye's place.
func prepare(eye: Vector3) -> void:
	if not on or strength <= 0.0 or not _bounds.grow(NEAR).has_point(eye):
		_frame = PackedFloat32Array()
		return
	var lit: Array[Dictionary] = []
	for index in _lamps.size():
		var lamp := _lamps[index]
		if not is_instance_valid(lamp) or not lamp.is_visible_in_tree() or lamp.light_energy < 0.01:
			continue
		if _lamp_rooms[index].grow(DOORWAY).has_point(eye):
			lit.append(record_of(lamp, _lamp_rooms[index]))
	var rows := lamp_rows(chosen(eye, lit))
	if rows.is_empty():
		_frame = PackedFloat32Array()
		return
	var values := PackedFloat32Array([
		REACH, THICKNESS, AMBIENT, strength,
		rows.size() / LAMP_FLOATS, float(debug_view), 0.0, 0.0,
		_bounds.position.x, _bounds.position.y, _bounds.position.z, 0.0,
		_bounds.end.x, _bounds.end.y, _bounds.end.z, 0.0,
	])
	values.append_array(rows)
	values.resize(PARAM_FLOATS - HEAD_FLOATS)
	_frame = values

## What the pass knows of `lamp`, which lights `room`.
static func record_of(lamp: Light3D, room: AABB) -> Dictionary:
	var colour := lamp.light_color.srgb_to_linear()
	var energy := lamp.light_energy * (colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722)
	if lamp is SpotLight3D:
		var spot := lamp as SpotLight3D
		return record(spot.global_position, energy, spot.spot_range, spot.spot_attenuation, spot.shadow_enabled, room,
			-spot.global_basis.z, cos(deg_to_rad(spot.spot_angle)), spot.spot_angle_attenuation)
	var omni := lamp as OmniLight3D
	return record(omni.global_position, energy, omni.omni_range, omni.omni_attenuation, omni.shadow_enabled, room)

## A lamp at `at` (world space) of `energy` (its light's luminance), whose
## light ends `reach` metres away and falls off with the distance to the
## power of `decay`; `shadowed` when it casts shadows (a lamp that casts none
## gets no contact shadows either, but its light still fills those of the
## others). A spot shines along `axis` inside a cone whose half angle has the
## cosine `cone`, dimming toward the rim by `cone_decay`.
static func record(at: Vector3, energy: float, reach: float, decay: float, shadowed: bool, room: AABB,
		axis := Vector3.ZERO, cone := -2.0, cone_decay := 1.0) -> Dictionary:
	return {"at": at, "energy": energy, "reach": reach, "decay": decay, "shadowed": shadowed, "room": room,
		"axis": axis, "cone": cone, "cone_decay": cone_decay}

## The box a lamp at `at` lights: the rooms it stands in, as one box, or
## `whole` when it stands in none.
static func room_of(at: Vector3, rooms: Array[AABB], whole: AABB) -> AABB:
	var lit := AABB()
	var found := false
	for room in rooms:
		if room.has_point(at):
			lit = lit.merge(room) if found else room
			found = true
	return lit if found else whole

## The engine's falloff of an omni or a spot lamp's light `distance` metres
## from it (get_omni_attenuation in the renderer's light shader).
static func omni_share(distance: float, reach: float, decay: float) -> float:
	var edge := pow(distance / reach, 4.0)
	edge = maxf(1.0 - edge, 0.0)
	return edge * edge * pow(maxf(distance, 0.0001), -decay)

## The engine's falloff of a spot's light toward the rim of its cone:
## `cos_off_axis` is the cosine of the angle between the spot's axis and the
## way to the lit point.
static func cone_share(cos_off_axis: float, cone: float, cone_decay: float) -> float:
	var rim := maxf(0.0001, (1.0 - maxf(cos_off_axis, cone)) / (1.0 - cone))
	return 1.0 - pow(rim, cone_decay)

## What `lamp` (a record) sends a white surface at `at` that faces along
## `normal`, shadows aside: 1 a metre from a lamp of energy 1 that it faces.
## The shader's lamp_weight.
static func weight(lamp: Dictionary, at: Vector3, normal: Vector3) -> float:
	var room: AABB = lamp.room
	if not room.has_point(at):
		return 0.0
	var to_lamp: Vector3 = lamp.at - at
	var away := maxf(to_lamp.length(), 0.0001)
	var facing := normal.dot(to_lamp) / away
	if facing <= 0.0:
		return 0.0
	var share := omni_share(away, lamp.reach, lamp.decay)
	var cone: float = lamp.cone
	if cone > -1.5:
		var axis: Vector3 = lamp.axis
		share *= cone_share(-to_lamp.dot(axis) / away, cone, lamp.cone_decay)
	var energy: float = lamp.energy
	return energy * share * facing

## The light left to a pixel that the lamps send `total` (the sum of their
## weights), of which `hidden` is behind something on the screen: 1 none
## taken. The shader's last step.
static func light_left(total: float, hidden: float, taken: float) -> float:
	return 1.0 - taken * hidden / (total + AMBIENT)

## The lamps of `lamps` (records) that matter to an eye at `eye`, the one that
## weighs most there first, MAX_LAMPS at most; none when no lamp among them
## casts a shadow.
static func chosen(eye: Vector3, lamps: Array[Dictionary]) -> Array[Dictionary]:
	var scored: Array[Array] = []
	for lamp in lamps:
		var at: Vector3 = lamp.at
		var away := eye.distance_to(at)
		var reach: float = lamp.reach
		if away > reach + VIEW:
			continue
		var energy: float = lamp.energy
		scored.append([energy / maxf(away * away, 1.0), lamp])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var picked: Array[Dictionary] = []
	var shadows := false
	for entry: Array in scored.slice(0, MAX_LAMPS):
		var lamp: Dictionary = entry[1]
		picked.append(lamp)
		shadows = shadows or bool(lamp.shadowed)
	if not shadows:
		picked.clear()
	return picked

## The shader's rows for `lamps` (records), LAMP_FLOATS numbers a lamp: where
## it is and its reach; its axis and cone; energy, decay, the cone's decay and
## whether it casts shadows; the two corners of the box it lights.
static func lamp_rows(lamps: Array[Dictionary]) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for lamp in lamps:
		var at: Vector3 = lamp.at
		var axis: Vector3 = lamp.axis
		var room: AABB = lamp.room
		rows.append_array([at.x, at.y, at.z, lamp.reach,
			axis.x, axis.y, axis.z, lamp.cone,
			lamp.energy, lamp.decay, lamp.cone_decay, 1.0 if lamp.shadowed else 0.0,
			room.position.x, room.position.y, room.position.z, 0.0,
			room.end.x, room.end.y, room.end.z, 0.0])
	return rows

func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	# No device in a headless run (the tests).
	if _rd == null:
		return
	var spirv := RdUtil.compute_spirv(SHADER, "Contact shadows")
	if spirv == null:
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	_nearest = _rd.sampler_create(RDSamplerState.new())
	var zero := PackedByteArray()
	zero.resize(PARAM_FLOATS * 4)
	_params = _rd.uniform_buffer_create(zero.size(), zero)

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	var frame := _frame
	if callback_type != EFFECT_CALLBACK_TYPE_POST_OPAQUE or frame.is_empty() or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var data := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or data == null or buffers.get_view_count() != 1:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var camera := data.get_cam_transform()
	var projection := AtmosphereFog.image_projection(data.get_view_projection(0))
	# A view without perspective has no depth of this kind, nor the hall's eye.
	if projection.z.w == 0.0:
		return
	var values := PackedFloat32Array()
	RdUtil.append_projection(values, projection.inverse())
	RdUtil.append_projection(values, Projection(camera))
	RdUtil.append_projection(values, projection * Projection(camera.affine_inverse()))
	# Reversed depth of a perspective view: raw = z.w / depth - z.z.
	values.append_array([size.x, size.y, projection.w.z, projection.z.z])
	# The metres a pixel spans a metre from the eye, and this frame's noise.
	values.append_array([2.0 / (absf(projection.y.y) * size.y), (Engine.get_frames_drawn() % 64) / 64.0, 0.0, 0.0])
	values.append_array(frame)
	var bytes := values.to_byte_array()
	_rd.buffer_update(_params, 0, bytes.size(), bytes)
	var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [
		RdUtil.uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_params]),
		RdUtil.image(1, buffers.get_color_layer(0)),
		RdUtil.sampled(2, _nearest, buffers.get_depth_layer(0))])
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()
