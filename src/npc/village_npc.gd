class_name VillageNPC
extends CharacterBody3D
## Imported skeletal clips drive the visible model; collision drives routes.
## The round of the route is NpcRounds's, the poses over the clip NpcPoses's,
## the choice of lights NpcLampZone's, the work the job's (NpcJob), how often
## the body is brought up to date NpcTier's.
const SceneUtil = preload("res://src/common/scene_util.gd")
const BodyPace = preload("res://src/common/body_pace.gd")
## The body capsule, m.
const RADIUS := 0.23
const HEIGHT := 1.65
const GRAVITY := 18.0
## How far behind a face that was met its top is looked for.
const LIP := 0.06
## Seconds one who walks about their work stands on once a story they tell no
## longer holds them (stop_to_talk).
const TALK_HOLD := 1.5
## The ground speed, m/s, the "walk" clip is drawn for: measured from the
## planted foot, 1.0 to 1.5 over the four models.
const WALK_STRIDE := 1.1
## The clip is played no faster than this many times its own pace: the feet
## of one who hurries more than that slide.
const WALK_HASTE := 2.0
## Recorded clips are named by their library (NpcMotion.LIBRARY).
const MOTION := "motion/"
## Clips whose handwork is done on the thing itself, not in the air as
## recorded: the body plays the clip named here and NpcWipe moves the hands.
const HANDWORK := {"wipe": "idle"}
var model_path := ""
## The id of the villager's job (NpcJob): the stem of its script.
var job := "wander"
## The villager's job, made for the id `job` when first asked.
var duty: NpcJob:
	get:
		if _duty == null or _duty.id != job:
			_duty = NpcJob.make(job)
		return _duty
var title := "Житель"
## The villager's sheet in PeopleBook; "" for a passer-by without one.
var person_id := ""
var animation: AnimationPlayer
var skeleton: Skeleton3D
## The tool of a cook's trade (NpcCookJob); null for the others.
var utensil: Node3D
var left_hand := -1
var right_hand := -1
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
## The rooms' lamps or the sun on the meshes.
var lamp_zone: NpcLampZone
var _pace := BodyPace.new()
var _duty: NpcJob
## How often the clip and the modifiers run, by the distance to the camera.
var tier := NpcTier.new()
## The clip the body plays now, by its plain name: "chop", "idle_look", "walk".
var activity := ""
## The gait this villager walks by when their speed allows (NpcMotion.gait).
var gait_own := ""
var _recorded := false
var _acting: NpcActing
var _gaze: NpcGaze
## Whether the model plays recorded motion (NpcMotion).
var recorded: bool:
	get:
		return _recorded
## The clip the body plays in its occupation (NpcActing); null without
## recorded motion.
var acting: NpcActing:
	get:
		return _acting
## Turns the head to the camera and to what is about (NpcGaze); null without
## recorded motion.
var gaze: NpcGaze:
	get:
		return _gaze
## Seconds since the villager came to be; the acting keeps its time by it.
var _age := 0.0
## Seconds for which the villager is still telling someone a story.
var _telling := 0.0
var _ground_ray: PhysicsRayQueryParameters3D
## Who bends the legs, arms and head over the clip (docs/LIFE.md, «Части тела»).
var body := NpcBody.new()
## The frame's pose is final: what the hands hold follows them. Emitted after
## the last pose modifier, once the poses are made (NpcPoses.prepare).
signal posed
## The anatomical limits, the skeleton's last modifier (JointLimitModifier3D).
var limits: JointLimitModifier3D
## The feet on the ground (NpcFooting): before the seat, the arms and the
## stumble.
var footing: NpcFooting
## The seat, the arms, the hands at work and the stumble over the clip.
var poses: NpcPoses
## The round of the route, its stops and the maid's wiping at them.
var rounds: NpcRounds
## The innkeeper's bar (NpcPopulation sets it): the keg, the tankard, the draw.
var bar: NpcBarWork
## Wipes the top in front (the maid and the innkeeper).
var wipe: NpcWipe


func _init() -> void:
	lamp_zone = NpcLampZone.new(self)
	poses = NpcPoses.new(self)
	rounds = NpcRounds.new(self)

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
		node.visibility_range_end = NpcTier.MESH_REACH
	if animation == null and skeleton != null:
		# A model that carries no clips of its own plays the recorded ones.
		animation = AnimationPlayer.new()
		animation.name = "AnimationPlayer"
		model.add_child(animation)
	if skeleton != null:
		left_hand = skeleton.find_bone("Hand_L")
		right_hand = skeleton.find_bone("Hand_R")
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
	duty.setup(self)
	# What the actor is handed later (a mug, a meal) follows the same rule.
	child_entered_tree.connect(lamp_zone.light)
	lamp_zone.check()
	play("idle")

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
		if not wipe.wiping() and poses.prepare() and body.blocker(NpcBody.WIPE) == &"" and wipe.start():
			body.claim(NpcBody.WIPE, wipe.wiping)
		return HANDWORK[clip]
	stop_wiping()
	return clip

## Puts the rag away: the hands go back to the clip.
func stop_wiping() -> void:
	if wipe != null and wipe.wiping():
		wipe.stop()
		body.release(NpcBody.WIPE)

## Walks at `speed`, m/s: the gait drawn nearest that pace, played as fast as
## the feet need.
func stride(speed: float) -> void:
	var gait := NpcMotion.gait(model_path, speed, gait_own) if _recorded else {}
	if not gait.is_empty():
		play(str(gait.clip))
		animation.speed_scale = Values.real(gait.scale)
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
	lamp_zone.tick(delta)
	velocity.y = -0.3 if is_on_floor() else velocity.y - GRAVITY * delta
	velocity.x = 0.0
	velocity.z = 0.0
	if outing != null:
		outing.drive(delta)
	elif place in ["hall", "yard"]:
		play("idle")
	else:
		duty.tick(self, delta)
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
	if outing == null and duty.walks and step != Vector3.ZERO and is_on_wall():
		for index in get_slide_collision_count():
			var met := get_slide_collision(index)
			if met.get_normal().y < 0.7 and not met.get_collider() is CharacterBody3D and step_onto(met, step):
				break

## A kerb, a stair, the edge of a cobble: what stands no higher than a step is
## stepped on, if the `step` over it is free and its top is no higher than
## `ceiling`. Its top is found just behind the face that was met.
func step_onto(collision: KinematicCollision3D, step: Vector3, ceiling := INF) -> bool:
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
	if rise <= 0.03 or global_position.y + rise > ceiling or test_move(global_transform, Vector3.UP * rise):
		return false
	var elevated := global_transform
	elevated.origin.y += rise
	if test_move(elevated, step):
		return false
	global_position.y += rise
	return true

## The tier of the frame first (NpcTier): near, the wiping goes on; farther,
## the clip and the modifiers step when it is due. The draw at the bar and the
## body's claims go on at any distance.
func _process(delta: float) -> void:
	tier.update(self, delta)
	if wipe != null and wipe.wiping() and tier.near():
		wipe.step(delta)
	if bar != null and bar.drawing():
		bar.step(delta)
	poses.update(delta)
	duty.frame(self, delta)

func hand_position(index: int) -> Vector3:
	if skeleton == null or index < 0: return global_position + Vector3.UP
	return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin

func interaction_point() -> Vector3:
	return global_position + global_basis * Vector3(0, 1.3, -0.6)

## The prompt at the villager at work, translated (NpcJob.interaction_text).
func interaction_text() -> String:
	return duty.interaction_text(self)

## E on the villager at work (NpcJob.interact).
func interact(player: Player) -> bool:
	return duty.interact(self, player)

## One who walks about their work is telling a story to someone at `listener`:
## they stand where they are and turn to them, and walk on `hold` seconds
## after the last call. Those who keep to one place do not turn from it.
func stop_to_talk(listener: Vector3, delta: float, hold := TALK_HOLD) -> void:
	_telling = maxf(_telling, hold)
	if not duty.keeps_hall or not at_work() or seated:
		return
	rounds.pause(hold)
	var offset := listener - global_position
	if Vector2(offset.x, offset.z).length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(delta * 4.0, 1.0))

## The villager leaves the place of work: what was under way there is put
## back in order (NpcJob.leave).
func leave_work() -> void:
	duty.leave(self)

## Whether the villager is in the valley, not away at home.
func present() -> bool:
	return place != "home"

## Whether the villager keeps to one place, where the player may come up and
## talk to them.
func at_rest() -> bool:
	return outing == null and (place in ["work", "hall", "yard"] or (place == "" and not duty.walks))

## Whether the villager is free to be asked along on an outing.
func invitable() -> bool:
	return outing == null and (place in ["road", "yard", "hall"] or (place == "" and duty.walks))

## Whether the villager is at their work: behind the bar, in the kitchen, about
## the hall.
func at_work() -> bool:
	return outing == null and (place == "work" or (place == "" and not duty.walks))

## Whether the villager walks their road.
func on_road() -> bool:
	return outing == null and duty.walks and place in ["", "road"]
