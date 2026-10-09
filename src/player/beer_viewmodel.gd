class_name BeerViewmodel
extends CanvasLayer
signal sipped
## A true 3D tankard rendered in its own transparent viewport. The existing
## player/NPC interface is kept so shared movement and interaction files stay untouched.
const Presentation = preload("res://src/player/beer/mug_presentation.gd")
const Crop = preload("res://src/player/beer/viewmodel_crop.gd")
const FILL_LEVEL := 0.86
const SIP := 0.13
const SIP_SECONDS := 0.85
@export var layer_index := 20
var _fill := FILL_LEVEL
var _sip_phase := 0.0
var _idle_time := 0.0
var _offset := Vector2.ZERO
var _offset_velocity := Vector2.ZERO
var _tilt := 0.0
var _tilt_velocity := 0.0
var _look_velocity := Vector2.ZERO
var _impact_pitch := 0.0
var _impact_velocity := 0.0
var _hand_visible := true
var _hand_resolution := "native"
# Same pixel density; crop grows to include each pose and the entire fluid domain.
var crop_enabled := true
var _full_target := Vector2i.ZERO
var _crop_rect := Rect2i()
var _crop_meshes: Array[MeshInstance3D] = []
var presentation: MugPresentation
var fluid: BeerFluid
var _rig: CameraRig
var _sky: SkySystem
@onready var root: SubViewportContainer = $Root
@onready var viewport: SubViewport = $Root/MugViewport

func _ready() -> void:
	layer = layer_index
	presentation = Presentation.new()
	presentation.name = "MugPresentation"
	viewport.add_child(presentation)
	fluid = presentation.fluid
	fluid.amount_changed.connect(_set_fill)
	fluid.refill(_fill)
	_rig = get_parent().get_node_or_null("CameraRig") as CameraRig
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		_hand_resolution = settings.hand_resolution
		settings.hand_resolution_changed.connect(set_hand_resolution)
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)

func _apply_layout() -> void:
	var main := get_viewport()
	var logical := main.get_visible_rect().size
	# Canvas scaling includes letterboxing; texture metadata is not the framebuffer.
	var physical := main.get_stretch_transform().basis_xform(logical)
	_apply_layout_size(logical, physical)

func _apply_layout_size(logical: Vector2, physical: Vector2) -> void:
	if logical.x < 2.0 or logical.y < 2.0:
		return
	var target := Vector2i(logical)
	if _hand_resolution == "native":
		# Keep the original aspect and never allocate more pixels than Maximum.
		var scale := minf(1.0, minf(physical.x / logical.x, physical.y / logical.y))
		target = Vector2i(maxi(roundi(logical.x * scale), 2), maxi(roundi(logical.y * scale), 2)).min(target)
	_full_target = target
	_crop_rect = Rect2i()
	root.position = Vector2.ZERO
	viewport.size = target
	root.size = logical if _hand_resolution == "maximum" else Vector2(target)
	# Non-stretching container: preserve its visible logical rectangle at any size.
	root.scale = Vector2.ONE if _hand_resolution == "maximum" else logical / Vector2(target)
	_update_crop()

func set_crop_enabled(value: bool) -> void:
	crop_enabled = value
	_apply_layout()

func _update_crop() -> void:
	if presentation == null or _full_target.x < 2: return
	var rect := Rect2i(Vector2i.ZERO, _full_target)
	if crop_enabled:
		if _crop_meshes.is_empty():
			for mesh in presentation.pivot.find_children("*", "MeshInstance3D", true, false):
				_crop_meshes.append(mesh)
		var points := PackedVector3Array()
		for mesh in _crop_meshes:
			if not is_instance_valid(mesh) or mesh.mesh == null: continue
			var transform := presentation.camera.global_transform.affine_inverse() * mesh.global_transform
			var bounds := mesh.mesh.get_aabb()
			for index in 8: points.append(transform * bounds.get_endpoint(index))
		rect = Crop.project_bounds(points, _full_target, 62.0, presentation.camera.near)
		# Grow immediately for a new pose, never churn render targets while walking.
		if _crop_rect.has_area(): rect = rect.merge(_crop_rect)
	if rect == _crop_rect: return
	_crop_rect = rect
	viewport.size = rect.size
	root.size = Vector2(rect.size)
	root.position = Vector2(rect.position) * root.scale
	Crop.apply_camera(presentation.camera, _full_target, rect, 62.0)
	if fluid != null and fluid.material != null:
		fluid.material.set_shader_parameter("crop_scale", Vector2(rect.size) / Vector2(_full_target))
		fluid.material.set_shader_parameter("crop_offset", Vector2(rect.position) / Vector2(_full_target))

func set_hand_resolution(mode: String) -> void:
	_hand_resolution = "maximum" if mode == "maximum" else "native"
	if root != null and viewport != null:
		_apply_layout()

func _set_fill(value: float) -> void:
	_fill = value

func fill() -> float:
	return _fill

func drinking() -> bool:
	return _sip_phase > 0.0

## A user preference, independent of the temporary fishing stow (.visible).
func set_hand_visible(value: bool) -> void:
	_hand_visible = value
	_sync_visibility()

func hand_visible() -> bool:
	return _hand_visible

func hand_is_shown() -> bool:
	return _hand_visible and visible

func _sync_visibility() -> void:
	var shown := hand_is_shown()
	if root != null: root.visible = shown
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if fluid != null: fluid.set_simulation_active(shown)
	if not shown:
		_sip_phase = 0.0
		_look_velocity = Vector2.ZERO
		_offset_velocity = Vector2.ZERO
		_tilt_velocity = 0.0
		_impact_velocity = 0.0
		_apply()

func drink() -> bool:
	if not hand_is_shown() or _sip_phase > 0.0 or _fill <= 0.0: return false
	_sip_phase = 0.0001
	sipped.emit()
	return true

func refill() -> void:
	_sip_phase = 0.0
	_fill = FILL_LEVEL
	if fluid != null: fluid.refill(FILL_LEVEL)

func _process(delta: float) -> void:
	if viewport == null or not hand_is_shown(): return
	_idle_time += delta
	if _sip_phase > 0.0:
		_sip_phase += delta / SIP_SECONDS
		if _sip_phase >= 1.0:
			_sip_phase = 0.0
			_fill = maxf(0.0, _fill - SIP)
			fluid.consume(SIP)
	_apply()

func _physics_process(delta: float) -> void:
	if not hand_is_shown() or delta <= 0.0: return
	_sync_world(delta)
	# Sitting stops body movement; the wrist, lighting and drink still run.
	var player := get_parent() as Player
	if player != null and not player.is_physics_processing():
		var look := _rig.last_look if _rig != null else Vector2.ZERO
		var phase := _rig.walk_phase if _rig != null else 0.0
		update_motion(0.0, phase, look, Vector3.ZERO, delta)
		if _rig != null: _rig.last_look = Vector2.ZERO

func _sync_world(delta: float) -> void:
	if _sky == null:
		var ancestor := get_parent()
		while ancestor != null:
			_sky = ancestor.get_node_or_null("Sky") as SkySystem
			if _sky != null: break
			ancestor = ancestor.get_parent()
	if presentation != null:
		presentation.sync_world(get_viewport().get_camera_3d(), _sky, delta)

## Called once per player physics frame. Acceleration includes take-off, falling
## and landing; no changes to player.gd are necessary.
func update_motion(speed_ratio: float, walk_phase: float, look_delta: Vector2,
		local_acceleration: Vector3, delta: float) -> void:
	if not hand_is_shown() or delta <= 0.0: return
	var target := ViewmodelMotion.walk_offset(walk_phase, speed_ratio)
	target += ViewmodelMotion.idle_offset(_idle_time) * (1.0 - clampf(speed_ratio, 0.0, 1.0))
	target += ViewmodelMotion.look_lag(look_delta)
	var moved := ViewmodelMotion.spring_vector(_offset, _offset_velocity, target, delta)
	_offset = moved[0]
	_offset_velocity = moved[1]
	var tilted := ViewmodelMotion.spring(_tilt, _tilt_velocity,
		clampf(-look_delta.x * 0.012 - local_acceleration.x * 0.006, -0.28, 0.28), delta)
	_tilt = tilted[0]
	_tilt_velocity = tilted[1]
	var previous_impact_velocity := _impact_velocity
	if local_acceleration.y > 40.0:
		# A landing also jars the wrist. Keep its visible rotation and the
		# fluid's rotational inertia coupled, rather than spawning fake drops.
		_impact_velocity = minf(_impact_velocity + local_acceleration.y * delta * 0.9, 6.0)
	var impact := ViewmodelMotion.spring(_impact_pitch, _impact_velocity, 0.0, delta)
	_impact_pitch = impact[0]
	_impact_velocity = impact[1]
	_apply()
	if fluid == null: return
	var sensitivity := _rig.sensitivity if _rig != null else 0.12
	var angular_speed := look_delta * deg_to_rad(sensitivity) / maxf(delta, 0.001)
	angular_speed = angular_speed.limit_length(14.0)
	var angular_acceleration := (angular_speed - _look_velocity) / maxf(delta, 0.001)
	_look_velocity = angular_speed
	# The hand is about 40 cm from the camera's axis of rotation.
	var turn_acceleration := Vector3(angular_acceleration.x * 0.40,
		-angular_acceleration.y * 0.30, -angular_speed.length_squared() * 0.15)
	turn_acceleration = turn_acceleration.limit_length(45.0)
	turn_acceleration.z += (_impact_velocity - previous_impact_velocity) / delta * 0.12
	var body_acceleration := local_acceleration.limit_length(180.0)
	var effective := Vector3(0, -22, 0) - body_acceleration - turn_acceleration
	# The resting presentation angle represents our view of an upright mug.
	# Only motion/sip rotations tilt the mug relative to physical gravity.
	var view_basis := Basis.from_euler(presentation.base_rotation)
	fluid.advance(delta, presentation.pivot.basis.inverse() * view_basis * effective / BeerFluid.UNIT)

func _apply() -> void:
	if presentation == null: return
	var sip := ViewmodelMotion.sip_curve(_sip_phase)
	presentation.pivot.position = presentation.base_position + Vector3(
		_offset.x * 0.0015 - sip * 0.10,
		-_offset.y * 0.0015 + sip * 0.09 - absf(_impact_pitch) * 0.06, sip * 0.06)
	presentation.pivot.rotation = presentation.base_rotation + Vector3(
		sip * 0.48 + _impact_pitch, _tilt * 0.30, _tilt - sip * 0.14)
	_update_crop()

