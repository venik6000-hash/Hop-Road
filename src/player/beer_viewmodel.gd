class_name BeerViewmodel
extends CanvasLayer
signal sipped
## A true 3D tankard rendered in its own transparent viewport. The existing
## player/NPC interface is kept so shared movement and interaction files stay untouched.
const Presentation = preload("res://src/player/beer/mug_presentation.gd")
const Crop = preload("res://src/player/beer/viewmodel_crop.gd")
const GameSettingsScript = preload("res://src/settings/game_settings.gd")
const FILL_LEVEL := PlayerState.MUG_FULL
const SIP := 0.13
## The tavern's old beer, which the shader draws by default: its absorption
## per simulation unit (beer_surface.gdshader), its scatter, its colour (EBC)
## and its foam (BrewTaste.profile). How much a hazy beer scatters more.
const OLD_ABSORPTION := Vector3(0.12, 0.45, 3.0)
const OLD_SCATTER := 0.12
const OLD_EBC := 12.0
const OLD_FOAM := 0.65
const HAZE_SCATTER := 0.5
## What the player has (Player.state): the mug's beer and level are its own
## (PlayerState.mug_beer, mug_fill). A mug without a body has one of its own.
var state := PlayerState.new()
## The beer in the mug (BrewTaste.profile), {} for the tavern's old beer.
var beer: Dictionary:
	get:
		return state.mug_beer
	set(value):
		state.mug_beer = value
## The player's hands and mouth (Player.hands); null for a mug without a body.
var channels: BodyChannels
@export var layer_index := 20
## The beer's level in the mug (PlayerState.mug_fill).
var _fill: float:
	get:
		return state.mug_fill
	set(value):
		state.mug_fill = value
## Seconds into the drink (DrinkMotion), 0 when the mug is in the hand.
var _drink_time := 0.0
var _drink_fill := 0.0
var _swallowed := 0
var _head := 0.0
var _idle_time := 0.0
var hand_offset := Vector2.ZERO
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
	_show_beer()
	_rig = get_parent().get_node_or_null("CameraRig") as CameraRig
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()
	var settings: GameSettingsScript = get_node_or_null("/root/GameSettings")
	if settings != null:
		_hand_resolution = settings.hand_resolution
		settings.hand_resolution_changed.connect(set_hand_resolution)
		set_hand_visible(settings.show_hand)
		settings.hand_visibility_changed.connect(set_hand_visible)
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
	# At the mouth the tankard fills the view: no crop while drinking.
	if crop_enabled and _drink_time <= 0.0:
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

## The mug takes the player's beer and level from `of` (Player.state): it
## shows what `of` holds now and whenever a save fills it.
func use_state(of: PlayerState) -> void:
	state = of
	if not of.mug_filled.is_connected(_pour_state):
		of.mug_filled.connect(_pour_state)
	_pour_state()

## The mug shows the beer and the level of its state: no drink, no fluid
## left over from before.
func _pour_state() -> void:
	var level := _fill
	_end_drink()
	if fluid != null:
		fluid.refill(level)
	_fill = level
	_show_beer()

func fill() -> float:
	return _fill

func drinking() -> bool:
	return _drink_time > 0.0

## Seconds into the drink (DrinkMotion), 0 when the mug is in the hand.
func drink_seconds() -> float:
	return _drink_time

## An empty mug: the drink stops and the beer is gone.
func drain() -> void:
	_end_drink()
	if fluid != null:
		fluid.refill(0.0)
	_fill = 0.0

## A user preference, independent of the right hand given to a doer
## (.visible, set by Player from its hands).
func set_hand_visible(value: bool) -> void:
	_hand_visible = value
	_sync_visibility()

func hand_is_shown() -> bool:
	return _hand_visible and visible

func _sync_visibility() -> void:
	var shown := hand_is_shown()
	if root != null: root.visible = shown
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if fluid != null: fluid.set_simulation_active(shown)
	if not shown:
		_end_drink()
		_look_velocity = Vector2.ZERO
		_offset_velocity = Vector2.ZERO
		_tilt_velocity = 0.0
		_impact_velocity = 0.0
		_apply()

func drink() -> bool:
	if not hand_is_shown() or _drink_time > 0.0 or _fill <= 0.0: return false
	if channels != null and not channels.claim(BodyChannels.DRINK, drinking): return false
	_drink_time = 0.0001
	_drink_fill = _fill
	_swallowed = 0
	sipped.emit()
	_update_crop()
	return true

## A full mug of `poured` (BrewTaste.profile; {} for the tavern's old beer).
func refill(poured: Dictionary = {}) -> void:
	_end_drink()
	_fill = FILL_LEVEL
	beer = poured
	if fluid != null: fluid.refill(FILL_LEVEL)
	_show_beer()

## What a beer of `profile` looks like in the mug: {absorption, scatter, head
## (the head's height against the old beer's)}. Its colour scales the
## absorption, its haze the scatter, its foam the head.
static func beer_look(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return {"absorption": OLD_ABSORPTION, "scatter": OLD_SCATTER, "head": 1.0}
	var ebc := clampf(Values.real(profile.get("color", OLD_EBC)), 2.0, 160.0)
	var clarity := clampf(Values.real(profile.get("clarity", 1.0)), 0.0, 1.0)
	return {"absorption": OLD_ABSORPTION * ebc / OLD_EBC, "scatter": OLD_SCATTER + HAZE_SCATTER * (1.0 - clarity),
		"head": clampf(Values.real(profile.get("foam", OLD_FOAM)) / OLD_FOAM, 0.4, 1.6)}

func _show_beer() -> void:
	if fluid == null or fluid.material == null:
		return
	var look := beer_look(beer)
	fluid.material.set_shader_parameter("absorption", look.absorption)
	fluid.material.set_shader_parameter("scatter", look.scatter)
	fluid.head_scale = look.head

func _end_drink() -> void:
	_drink_time = 0.0
	if channels != null: channels.release(BodyChannels.DRINK)
	_swallowed = 0
	if fluid != null: fluid.mouth = false
	_set_head(0.0)
	# The next crop is measured afresh round the hand at rest.
	_crop_rect = Rect2i()

func _sip() -> float:
	return minf(SIP, _drink_fill)

func _process(delta: float) -> void:
	if viewport == null or not hand_is_shown(): return
	_idle_time += delta
	if _drink_time > 0.0:
		_drink_time += delta
		# Each swallow takes its share of the sip; beer the tilt brings over
		# the rim between swallows is drunk by the lips (BeerFluid.mouth).
		while _swallowed < DrinkMotion.swallows_done(_drink_time):
			_swallowed += 1
			var gulp := _sip() / DrinkMotion.SWALLOWS.size()
			# consume() reports the new level back through amount_changed.
			if fluid != null: fluid.consume(gulp)
			else: _fill = maxf(0.0, _fill - gulp)
		if fluid != null: fluid.mouth = DrinkMotion.lips_on(_drink_time)
		if _drink_time >= DrinkMotion.SECONDS: _end_drink()
	_apply()

## Head tilt of the world camera while drinking; the hand's camera stays put.
## The fluid takes the tilt the camera really got (it stops at the pitch limit).
func _set_head(radians: float) -> void:
	_head = _rig.set_drink_tilt(radians) if _rig != null else radians

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
	var moved := ViewmodelMotion.spring_vector(hand_offset, _offset_velocity, target, delta)
	hand_offset = moved[0]
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
	# The arm's own swing to the mouth and back, damped: a drinker lifts gently.
	var rest := Transform3D(Basis.from_euler(presentation.base_rotation), presentation.base_position)
	var lift := DrinkMotion.lift_acceleration(_drink_time, rest, _drink_fill, _sip()).limit_length(15.0)
	var effective := Vector3(0, -22, 0) - body_acceleration - turn_acceleration - lift * 0.5
	# The resting presentation angle represents our view of an upright mug.
	# At the mouth the pose is literal: the view is the head, tilted back.
	var raise := clampf(DrinkMotion.raise_weight(_drink_time), 0.0, 1.0)
	var view_basis := Basis.from_euler(presentation.base_rotation).slerp(Basis.IDENTITY, raise)
	var down := Basis(Vector3.RIGHT, -_head) * effective
	fluid.advance(delta, presentation.pivot.basis.inverse() * view_basis * down / BeerFluid.UNIT)

## Holds the full mug at `seconds` into a drink, swayed by `tilt` (radians),
## and draws it: a still of one moment for checks. The next frame moves on.
func hold_drink_pose(seconds: float, tilt: float) -> void:
	_drink_fill = FILL_LEVEL
	_drink_time = seconds
	_tilt = tilt
	_apply()

func _apply() -> void:
	if presentation == null: return
	var rest := Transform3D(Basis.from_euler(presentation.base_rotation + Vector3(
		_impact_pitch, _tilt * 0.30, _tilt)), presentation.base_position + Vector3(
		hand_offset.x * 0.0015, -hand_offset.y * 0.0015 - absf(_impact_pitch) * 0.06, 0.0))
	presentation.pivot.transform = DrinkMotion.pose(_drink_time, rest, _drink_fill, _sip())
	if _drink_time > 0.0:
		_set_head(DrinkMotion.head_tilt(_drink_time, _drink_fill, _sip()))
	_update_crop()

