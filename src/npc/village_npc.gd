class_name VillageNPC
extends CharacterBody3D
## Imported skeletal clips drive the visible model; collision drives routes.
const SceneUtil = preload("res://src/common/scene_util.gd")
const BodyPace = preload("res://src/common/body_pace.gd")
const SPEED := 0.85
## The body capsule, m.
const RADIUS := 0.23
## The farthest a hall walk leaves the navigation grid for its last steps to
## the place of work, metres.
const HALL_LAST_STEP := 0.6
const HEIGHT := 1.65
const GRAVITY := 18.0
## Seconds between checks of whether the actor stands inside the tavern.
const LAMP_ZONE_SECONDS := 0.25
## How far behind a face that was met its top is looked for.
const LIP := 0.06
## Seconds one who walks about their work stands on once a story they tell no
## longer holds them (stop_to_talk).
const TALK_HOLD := 1.5
## Seconds the one who keeps the hall wipes the bar when her round brings her
## to it: one pass of the recorded wiping.
const WIPE_SECONDS := 8.5
## The ground speed, m/s, the "walk" clip is drawn for: measured from the
## planted foot, 1.0 to 1.5 over the four models.
const WALK_STRIDE := 1.1
## The clip is played no faster than this many times its own pace: the feet
## of one who hurries more than that slide.
const WALK_HASTE := 2.0
## Recorded clips are named by their library (NpcMotion.LIBRARY).
const MOTION := "motion/"
## What the hand holds, by occupation: the clips in which it is in the hand.
## In the others it lies where UTENSIL_REST puts it.
const HELD := {"chop": ["chop", "chop_quick", "slice"], "stir": ["stir"]}
## Where the tool lies when the hand is busy with something else, from the
## villager's place of work: the knife on the board, the spoon in the pot.
const UTENSIL_REST := {
	"chop": Transform3D(Basis(Vector3.UP, 1.1), Vector3(0.21, 0.997, -0.4)),
	"stir": Transform3D(Basis(Vector3(0.7412, 0.0, -0.6713), 0.28), Vector3(0.08, 0.98, -0.42)),
}
## Clips whose handwork is done on the thing itself, not in the air as
## recorded: the body plays the clip named here and NpcWipe moves the hands.
const HANDWORK := {"wipe": "idle"}
## The innkeeper wipes the back edge of his counter, between the brewed keg's
## place and his keg, one hand: NpcWipe's strip in his own space.
const BAR_WIPE := {"middle": 0.05, "across": 0.15, "near": 0.39, "far": 0.46, "rest": Vector3.ZERO}
var model_path := ""
var job := "wander"
var title := "Житель"
## The villager's sheet in PeopleBook; "" for a passer-by without one.
var person_id := ""
var route: Array[Vector3] = []
var animation: AnimationPlayer
var skeleton: Skeleton3D
var state := "working"
var utensil: Node3D
var _point := 0
var _direction := 1
var _wait := 0.0
var _blocked := 0.0
var _cleaning := false
var _left_hand := -1
var _right_hand := -1
var outing: NpcOuting
## Where the villager's day has them (VillagerPresence): "" as the job says,
## else one of VillagerDay.PLACES.
var place := ""
## Where the villager works and which way they face there (NpcPopulation.settle).
var work_point := Vector3.ZERO
var work_yaw := 0.0
## Sits on a seat of the hall (VillagerPresence): the body has no collision
## and is not moved.
var seated := false
var _hall_navigation: TavernNavigation
var _hall_path := PackedVector3Array()
var _hall_target := -1
var _hall_ready := false
var _route_probe: PhysicsShapeQueryParameters3D
# 1 inside the tavern, 0 outside, -1 before the first check.
var _lamp_zone := -1
## Within reach of a lit lantern outdoors (LampShadowGuard sets it): no shadow
## there either, or the lantern draws its shadow map again in every frame.
var near_lit_lamp := false:
	set(value):
		if value != near_lit_lamp:
			near_lit_lamp = value
			_light_for_zone(self)
var _lamp_zone_clock := 0.0
var _pace := BodyPace.new()
## The clip the body plays now, by its plain name: "chop", "idle_look", "walk".
var activity := ""
## The gait this villager walks by when their speed allows (NpcMotion.gait).
var gait_own := ""
## The model has recorded motion (NpcMotion), and what the body does with it.
var _recorded := false
var _acting: NpcActing
var _gaze: NpcGaze
## Seconds since the villager came to be; the acting keeps its time by it.
var _age := 0.0
## Seconds for which the villager is still telling someone a story.
var _telling := 0.0
var _ground_ray: PhysicsRayQueryParameters3D
## Who bends the legs, arms and head over the clip (docs/LIFE.md, «Части тела»).
var body := NpcBody.new()
## The frame's pose is final: what the hands hold follows them. Emitted after
## the last pose modifier, from the first sit() or gesture() on.
signal posed
## The seat's hips and legs, and the arms: made when first needed.
var _seat_pose: CampPose
var _arm_poses: Array[NpcArmPose] = []
## The anatomical limits, the skeleton's last modifier (JointLimitModifier3D).
var limits: JointLimitModifier3D
## The feet on the ground (NpcFooting): before the seat, the arms and the
## stumble.
var footing: NpcFooting
## The ragdoll after a bump (NpcStumble): made at the first bump.
var _stumble: NpcStumble
## The level's ragdolls at once (NpcPopulation sets it); without it the
## villager never stumbles.
var ragdolls: RagdollBudget
## The trunk and the hands at work (NpcReach): made with the seat's pose.
var reach: NpcReach
## The innkeeper's bar (NpcPopulation sets it): the keg, the tankard, the draw.
var bar: NpcBarWork
## Wipes the top in front (the maid and the innkeeper).
var wipe: NpcWipe
## The maid's stops where she wipes: route point -> {yaw: the way she faces
## there, across: how far her strip goes to either side (NpcWipe.across),
## rest: where her other hand rests (NpcWipe.rest)}.
var wipes: Dictionary[int, Dictionary] = {}
## The way to face before the work at a stop begins, NAN for none.
var _face_to := NAN


func _ready() -> void:
	collision_layer = PhysicsLayers.VILLAGERS
	collision_mask = PhysicsLayers.mask_of(PhysicsLayers.VILLAGERS)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(48.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	_pace.max_step = RADIUS
	var solid := CollisionShape3D.new()
	solid.shape = capsule
	solid.position.y = 0.83
	add_child(solid)
	var model := (load(model_path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI # glTF is +Z forward; actors face -Z.
	add_child(model)
	animation = SceneUtil.animation_player(model)
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		node.visibility_range_end = 65.0
	if animation == null and skeleton != null:
		# A model that carries no clips of its own plays the recorded ones.
		animation = AnimationPlayer.new()
		animation.name = "AnimationPlayer"
		model.add_child(animation)
	if skeleton != null:
		_left_hand = skeleton.find_bone("Hand_L")
		_right_hand = skeleton.find_bone("Hand_R")
	_recorded = animation != null and NpcMotion.attach(model_path, animation, skeleton)
	if _recorded:
		_acting = NpcActing.new(name)
		if NpcMotion.WOMEN.has(NpcMotion.model_name(model_path)):
			gait_own = NpcMotion.WOMANS_GAIT
		var library := animation.get_animation_library(NpcMotion.LIBRARY)
		for clip in library.get_animation_list():
			_acting.lengths[String(clip)] = library.get_animation(clip).length
		_gaze = NpcGaze.new()
		_gaze.actor = self
		skeleton.add_child(_gaze)
	if skeleton != null:
		footing = NpcFooting.new()
		footing.actor = self
		footing.influence = 0.0
		skeleton.add_child(footing)
		limits = JointLimitModifier3D.new("villager")
		skeleton.add_child(limits)
	_setup_props()
	# What the actor is handed later (a mug, a meal) follows the same rule.
	child_entered_tree.connect(_light_for_zone)
	_update_lamp_zone()
	play("idle")
	if job == "maid":
		_prepare_hall_navigation.call_deferred()

func _prepare_hall_navigation() -> void:
	await get_tree().physics_frame
	_hall_navigation = TavernNavigation.new()
	_hall_navigation.build(self)
	_route_probe = PhysicsShapeQueryParameters3D.new()
	var probe := CapsuleShape3D.new()
	probe.radius = 0.25
	probe.height = 1.6
	_route_probe.shape = probe
	_route_probe.collision_mask = collision_mask
	_route_probe.exclude = [get_rid()]
	_hall_ready = true

func _setup_props() -> void:
	if job in ["chop", "stir"]:
		utensil = NpcProps.knife() if job == "chop" else NpcProps.spoon()
		add_child(utensil)
	elif job in ["bartender", "maid"] and skeleton != null:
		wipe = NpcWipe.new()
		wipe.name = "Wipe"
		wipe.actor = self
		if job == "bartender":
			wipe.set_strip(BAR_WIPE)
		add_child(wipe)

## The tavern's lamps keep their shadow maps while nothing they light moves
## (TavernSystem.SHADOW_LAYER); a body that could cast a shadow has every lamp
## in whose reach it is animated drawn again in each frame. So an actor is on
## the tavern's layer, lit by its lamps, only inside the building, and casts no
## shadow there. Outdoors it is lit by the sun and casts the sun's shadow.
func _update_lamp_zone() -> void:
	var zone := int(TavernSystem.BUILDING_BOUNDS.grow(0.3).has_point(global_position + Vector3.UP * 0.9))
	if zone == _lamp_zone:
		return
	_lamp_zone = zone
	_light_for_zone(self)

func _light_for_zone(root: Node) -> void:
	if _lamp_zone < 0:
		return
	var items: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		items.append(root)
	for item: GeometryInstance3D in items:
		# The setting the piece came with is the one it has in the open.
		if not item.has_meta(&"outdoor_shadow"):
			item.set_meta(&"outdoor_shadow", item.cast_shadow)
		set_layers(item, (1 | TavernSystem.LAYER) if _lamp_zone == 1 else 1)
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _lamp_zone == 1 or near_lit_lamp \
			else item.get_meta(&"outdoor_shadow")

## Puts a piece on other render layers. Godot 4.7.2 keeps a piece paired with
## the lights in whose reach it stands while its layers change (Forward+), yet
## counts a pair only where the light's cull mask meets the layers. A piece
## that takes the tavern's layer under a lamp is therefore missing from the
## engine's count of the lights that give it a soft shadow, and the engine
## prints "geom->softshadow_count==0 - BUG!" when it leaves the lamp or is
## hidden. So the server holds the piece hidden over the change: hidden it has
## no pairs, and shown again it is paired by its new layers. The engine's
## master does the same on its own (53ec17a1d).
static func set_layers(item: GeometryInstance3D, layers: int) -> void:
	if item.layers == layers:
		return
	var instance := item.get_instance()
	RenderingServer.instance_set_visible(instance, false)
	item.layers = layers
	RenderingServer.instance_set_visible(instance, item.is_visible_in_tree())

## Plays a clip, or what the occupation of that name has the body do now
## (NpcActing.SETS). A recorded clip is taken before the model's own.
func play(clip: String, loop := true) -> void:
	if animation == null: return
	if _telling > 0.0 and clip in ["idle", "bar"]:
		clip = "talk"
	if _acting != null and _acting.knows(clip):
		clip = _acting.choose(clip, _age)
		loop = _acting.repeats
	else:
		clip = NpcActing.FALLBACK.get(clip, clip)
	clip = _handwork(clip)
	var named := ""
	var blend := 0.18
	# The recorded clip, the model's own, or standing still in either.
	for known: String in [MOTION + clip, clip, MOTION + "idle", "idle"]:
		if animation.has_animation(known):
			named = known
			break
	if named == "":
		return
	if named.begins_with(MOTION):
		blend = NpcMotion.BLEND
	clip = named.trim_prefix(MOTION)
	activity = clip
	animation.speed_scale = 1.0
	if animation.current_animation == named and animation.is_playing(): return
	animation.get_animation(named).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	animation.play(named, blend)

## The clip the body plays for `clip`: a handwork clip (HANDWORK) becomes the
## wiping of the top in front, over a calm clip; any other ends the wiping.
func _handwork(clip: String) -> String:
	if wipe == null:
		return clip
	if HANDWORK.has(clip) and at_work() and not body.has(NpcBody.POUR):
		if not wipe.wiping() and _make_poses() and body.blocker(NpcBody.WIPE) == &"" and wipe.start():
			body.claim(NpcBody.WIPE, wipe.wiping)
		return HANDWORK[clip]
	_stop_wiping()
	return clip

func _stop_wiping() -> void:
	if wipe != null and wipe.wiping():
		wipe.stop()
		body.release(NpcBody.WIPE)

## Walks at `speed`, m/s: the gait drawn nearest that pace, played as fast as
## the feet need.
func stride(speed: float) -> void:
	var gait := NpcMotion.gait(model_path, speed, gait_own) if _recorded else {}
	if not gait.is_empty():
		play(str(gait.clip))
		animation.speed_scale = float(gait.scale)
		return
	play("walk" if animation != null and animation.has_animation("walk") else "source_walk")
	if animation != null:
		animation.speed_scale = clampf(speed / WALK_STRIDE, 1.0, WALK_HASTE)

func _physics_process(delta: float) -> void:
	delta = _pace.begin(delta)
	if delta == 0.0:
		return
	_age += delta
	_telling = maxf(0.0, _telling - delta)
	_lamp_zone_clock -= delta
	if _lamp_zone_clock <= 0.0:
		_lamp_zone_clock = LAMP_ZONE_SECONDS
		_update_lamp_zone()
	velocity.y = -0.3 if is_on_floor() else velocity.y - GRAVITY * delta
	velocity.x = 0.0
	velocity.z = 0.0
	if outing != null:
		outing.drive(delta)
	elif place in ["hall", "yard"]:
		play("idle")
	elif job == "bartender" and at_work():
		_update_bar()
	elif not route.is_empty():
		_walk_route(delta)
	else:
		play(job)
	if body.has(NpcBody.STUMBLE):
		# The bumped stand where they were hit and find their feet.
		velocity.x = 0.0
		velocity.z = 0.0
		play("idle")
	if seated:
		return
	var step := Vector3(velocity.x, 0.0, velocity.z) * delta
	_pace.slide(self, delta)
	# The lane has kerbs and stairs: a walker held by one steps onto it.
	if outing == null and job == "wander" and step != Vector3.ZERO and is_on_wall():
		for index in get_slide_collision_count():
			var met := get_slide_collision(index)
			if met.get_normal().y < 0.7 and not met.get_collider() is CharacterBody3D and step_onto(met, step):
				break

## A kerb, a stair, the edge of a cobble: what stands no higher than a step is
## stepped on, if the `step` over it is free. Its top is found just behind the
## face that was met.
func step_onto(collision: KinematicCollision3D, step: Vector3) -> bool:
	if _ground_ray == null:
		_ground_ray = PhysicsRayQueryParameters3D.new()
		_ground_ray.collision_mask = PhysicsLayers.GROUND
		_ground_ray.exclude = [get_rid()]
	var behind := collision.get_position() - collision.get_normal() * LIP
	_ground_ray.from = Vector3(behind.x, global_position.y + Player.STEP_HEIGHT + 0.05, behind.z)
	_ground_ray.to = Vector3(behind.x, global_position.y - 0.1, behind.z)
	var top := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	if top.is_empty():
		return false
	var rise: float = top.position.y - global_position.y + 0.03
	if rise <= 0.03 or test_move(global_transform, Vector3.UP * rise):
		return false
	var elevated := global_transform
	elevated.origin.y += rise
	if test_move(elevated, step):
		return false
	global_position.y += rise
	return true

func _walk_route(delta: float) -> void:
	if job == "maid" and not _hall_ready:
		return
	_wait = maxf(0.0, _wait - delta)
	if _wait > 0.0:
		# She turns to the top first, then wipes it.
		if _cleaning and not is_nan(_face_to) and absf(angle_difference(rotation.y, _face_to)) > 0.04:
			rotation.y = rotate_toward(rotation.y, _face_to, delta * 2.5)
			play("idle")
			return
		play("wipe" if _cleaning else "idle")
		return
	var destination := route[_point]
	if _hall_navigation != null:
		if _hall_target != _point:
			_hall_path = _hall_navigation.path(global_position, destination)
			_hall_target = _point
		if _hall_path.is_empty():
			# No reachable path: wait and retry, never walk straight through furniture.
			_hall_target = -1
			_wait = 1.0
			play("idle")
			return
		while _hall_path.size() > 1 and Vector2(global_position.x - _hall_path[0].x,
				global_position.z - _hall_path[0].z).length() < 0.1:
			_hall_path.remove_at(0)
		destination = _hall_path[0]
		# The grid keeps a wide berth of furniture; the last few steps go
		# straight to the place of work, which may stand nearer a top.
		if _hall_path.size() == 1 and Vector2(route[_point].x - destination.x, route[_point].z - destination.z).length() < HALL_LAST_STEP:
			destination = route[_point]
	var offset := destination - global_position
	offset.y = 0.0
	if offset.length() < (0.12 if _hall_navigation != null else 0.22) and (_hall_navigation == null or _hall_path.size() == 1):
		_cleaning = job == "maid" and wipes.has(_point)
		_face_to = float(wipes[_point].yaw) if _cleaning else NAN
		if _cleaning:
			wipe.set_strip(wipes[_point])
		_wait = WIPE_SECONDS if _cleaning else 1.2 + float(_point % 3) * 0.8
		_next_point()
		play("idle")
		return
	var direction := offset.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 5.0, 1.0))
	# A moving neighbour or the player has priority. Avoid pushing them.
	if _route_obstructed(direction, offset.length()):
		_blocked += delta
		play("idle")
		if _blocked > 3.0:
			_direction *= -1
			_next_point()
			_hall_target = -1
			_blocked = 0.0
		return
	_blocked = 0.0
	var speed := SPEED if _hall_navigation == null else minf(SPEED, offset.length() / maxf(delta, 0.001))
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if _recorded:
		stride(speed)
	else:
		play("source_walk" if animation.has_animation("source_walk") else "walk")

func _route_obstructed(direction: Vector3, distance: float) -> bool:
	var space := get_world_3d().direct_space_state
	if _route_probe != null:
		_route_probe.transform.origin = global_position + Vector3.UP * 0.85
		_route_probe.motion = direction * minf(0.42, distance)
		return space.cast_motion(_route_probe)[0] < 1.0
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8,
		global_position + Vector3.UP * 0.8 + direction * 0.65, collision_mask)
	ray.exclude = [get_rid()]
	return not space.intersect_ray(ray).is_empty()

func _next_point() -> void:
	var next := _point + _direction
	if next < 0 or next >= route.size():
		_direction *= -1
		next = _point + _direction
	_point = clampi(next, 0, route.size() - 1)

func _update_bar() -> void:
	match state:
		"working":
			play("bar")
		"pouring", "serving":
			play("idle")
			if bar == null:
				state = "working"
			elif bar.clock >= NpcBarWork.T_CLOSE:
				state = "serving"
			if bar != null and bar.served:
				state = "ready"
		"ready":
			play("idle")

## Sits down on what is `height` m over the feet, eased over NpcBody.FADE.
func sit(height: float) -> void:
	if not _make_poses():
		return
	_seat_pose.seat_height = height
	body.claim(NpcBody.SEAT)

## Gets up from the seat, eased as the sitting down.
func stand() -> void:
	body.release(NpcBody.SEAT)

## Gives `doer` its parts (NpcBody.DOERS) for `seconds`. False when a doer
## of the same or a higher layer has one of them.
func gesture(doer: StringName, seconds: float) -> bool:
	return _make_poses() and body.claim_for(doer, seconds)

## The player ran into the villager at `push`, m/s along the ground, from
## `from`: they stumble in an active ragdoll (NpcStumble) for
## NpcStumble.SECONDS. False when they sit, stumble already, or the ragdoll
## budget is spent or missing (`ragdolls`).
func bump(push: Vector3, from: Vector3) -> bool:
	if ragdolls == null or seated or not _make_poses() or body.blocker(NpcBody.STUMBLE) != &"":
		return false
	if _stumble == null:
		_stumble = NpcStumble.new()
		_stumble.actor = self
		_stumble.ragdolls = ragdolls
		skeleton.add_child(_stumble)
		skeleton.move_child(limits, -1)
	if not _stumble.start(push, global_position.distance_to(from)):
		return false
	return body.claim_for(NpcBody.STUMBLE, NpcStumble.SECONDS)

## Whether the villager stumbles, or is still finding their feet.
func stumbles() -> bool:
	return _stumble != null and _stumble.running()

## Whether the villager sits, or is still sitting down.
func sits() -> bool:
	return body.has(NpcBody.SEAT)

func _make_poses() -> bool:
	if skeleton == null:
		return false
	if _seat_pose != null:
		return true
	# Modifiers run in the order of the skeleton's children: hips before arms.
	_seat_pose = CampPose.new()
	_seat_pose.actor = self
	_seat_pose.influence = 0.0
	skeleton.add_child(_seat_pose)
	for side: String in ["L", "R"]:
		var arm := NpcArmPose.new()
		arm.actor = self
		arm.side = side
		arm.part = NpcBody.LEFT_ARM if side == "L" else NpcBody.RIGHT_ARM
		arm.seat = _seat_pose
		arm.influence = 0.0
		skeleton.add_child(arm)
		_arm_poses.append(arm)
	reach = NpcReach.new()
	reach.actor = self
	reach.model = NpcMotion.model_name(model_path)
	reach.influence = 0.0
	skeleton.add_child(reach)
	# The limits stay last, and the hands are read once they have clamped.
	skeleton.move_child(limits, -1)
	limits.modification_processed.connect(posed.emit)
	return true

## Each pose modifier bends the clip as far as its doers drive its part. The
## feet keep to the ground where no doer holds the legs, near the camera.
func _update_poses(delta: float) -> void:
	if _seat_pose != null:
		body.step(delta)
		_seat_pose.influence = body.weight(NpcBody.SEAT, NpcBody.LEGS)
		for arm in _arm_poses:
			arm.influence = body.total(arm.part)
		# The work's share of each arm; the trunk bends as far as the more driven one.
		for side: String in ["L", "R"]:
			var part := NpcBody.LEFT_ARM if side == "L" else NpcBody.RIGHT_ARM
			var share := 0.0
			for doer in NpcBody.WORKERS:
				share += body.weight(doer, part)
			reach.arms[side] = minf(share, 1.0)
		reach.influence = maxf(float(reach.arms.L), float(reach.arms.R))
		if _stumble != null:
			_stumble.follow(body.weight(NpcBody.STUMBLE, NpcBody.LEGS), body.has(NpcBody.STUMBLE))
	if footing != null:
		var camera := get_viewport().get_camera_3d()
		var near := 1.0 if camera == null else NpcFooting.reach(camera.global_position.distance_to(global_position))
		footing.influence = 0.0 if seated else (1.0 - body.total(NpcBody.LEGS)) * near

func _process(delta: float) -> void:
	if wipe != null and wipe.wiping():
		wipe.step(delta)
	if bar != null and bar.drawing():
		bar.step(delta)
	_update_poses(delta)
	if utensil != null and HELD.has(job) and _recorded:
		_hold_utensil()

## The tool of the trade is in the hand while the body works with it; else it
## lies by the work, or is put away where the work has no place for it.
func _hold_utensil() -> void:
	var held: Array = HELD[job]
	if held.has(activity):
		utensil.visible = true
		utensil.global_transform = Transform3D(global_basis, hand_position(_right_hand))
	elif UTENSIL_REST.has(job) and at_work():
		var rest: Transform3D = UTENSIL_REST[job]
		utensil.visible = true
		utensil.global_transform = Transform3D(Basis(Vector3.UP, work_yaw), work_point) * rest
	else:
		utensil.visible = false

func hand_position(index: int) -> Vector3:
	if skeleton == null or index < 0: return global_position + Vector3.UP
	return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin

func interaction_point() -> Vector3:
	return global_position + global_basis * Vector3(0, 1.3, -0.6)

## The prompt at the innkeeper, translated.
func interaction_text() -> String:
	match state:
		"pouring": return tr("%s наливает пиво…") % tr(title)
		"serving": return tr("%s подаёт кружку…") % tr(title)
		"ready": return tr("{interact} — взять пиво · %s") % tr(title)
	return tr("{interact} — заказать пиво · %s") % tr(title)

func interact(player: Player) -> bool:
	if state == "working":
		if bar == null or not bar.start():
			return false
		_stop_wiping()
		gesture(NpcBody.POUR, NpcBarWork.LENGTH)
		state = "pouring"
		return true
	if state == "ready":
		player.viewmodel.refill(BrewHouse.draw_beer(get_tree()))
		bar.take()
		state = "working"
		return true
	return false

## One who walks about their work is telling a story to someone at `listener`:
## they stand where they are and turn to them, and walk on `hold` seconds
## after the last call. Those who keep to one place do not turn from it.
func stop_to_talk(listener: Vector3, delta: float, hold := TALK_HOLD) -> void:
	_telling = maxf(_telling, hold)
	if job != "maid" or not at_work() or seated:
		return
	_wait = maxf(_wait, hold)
	_cleaning = false
	var offset := listener - global_position
	if Vector2(offset.x, offset.z).length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(delta * 4.0, 1.0))

## Puts the bar back in order when the innkeeper leaves it: nothing is being
## poured and nothing stands ready.
func clear_bar() -> void:
	if job != "bartender":
		return
	state = "working"
	if bar != null:
		bar.clear()
	body.release(NpcBody.POUR)

## Whether the villager is in the valley, not away at home.
func present() -> bool:
	return place != "home"

## Whether the villager keeps to one place, where the player may come up and
## talk to them.
func at_rest() -> bool:
	return outing == null and (place in ["work", "hall", "yard"] or (place == "" and job != "wander"))

## Whether the villager is free to be asked along on an outing.
func invitable() -> bool:
	return outing == null and (place in ["road", "yard", "hall"] or (place == "" and job == "wander"))

## Whether the villager is at their work: behind the bar, in the kitchen, about
## the hall.
func at_work() -> bool:
	return outing == null and (place == "work" or (place == "" and job != "wander"))

## Whether the villager walks their road.
func on_road() -> bool:
	return outing == null and job == "wander" and place in ["", "road"]
