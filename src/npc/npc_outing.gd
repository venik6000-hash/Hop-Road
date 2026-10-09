class_name NpcOuting
extends Node
## Follow actual footsteps. No teleporting through the village or cliffs.
var actor: VillageNPC
var camping: CampSystem
var mode := "follow"
var points: Array[Vector3] = []
var walked: Array[Vector3] = []
var fire: Campfire
var camp_seat: Dictionary = {}
var pose: CampPose
var mug: Node3D
var _model: Node3D
var _blocked := 0.0
var _remark := 14.0
var _toast := 0.0
var _last_player := Vector3.ZERO
var _last_actor := Vector3.ZERO
var _reached_favorite := false
var _food: Node3D
var _food_time := 0.0
var _starting_route_point := 0
var _camp_trail: Array[Vector3] = []

func _ready() -> void:
	_model = actor.get_node("Model")
	pose = CampPose.new()
	pose.actor = actor
	if actor.skeleton != null:
		actor.skeleton.add_child(pose)
		pose.modification_processed.connect(_sync_props)
	mug = NpcProps.mug()
	actor.add_child(mug)
	mug.visible = false
	(mug.get_node("Beer") as Node3D).position.y = 0.11
	_last_player = camping.player.global_position
	_last_actor = actor.global_position
	walked.append(actor.global_position)
	points.append(_last_player)
	_starting_route_point = actor._point

func drive(delta: float) -> void:
	_toast = maxf(0.0, _toast - delta)
	pose.toast_weight = sin(_toast / 1.5 * PI)
	pose.food_weight = sin(minf(_food_time, 6.0) / 6.0 * PI) * 0.5
	_remark -= delta
	if mode != "return" and _remark <= 0.0:
		_remark = 32.0
		camping.companion_remark(self)
	if mode == "rest":
		_record_camp_trail()
		if not is_instance_valid(fire) or not fire.burning or camping.player.global_position.distance_to(fire.global_position) > 7.0:
			leave_seat()
		else:
			_face(fire.global_position, delta)
			actor.play("idle")
			return
	if mode == "to_camp":
		if not is_instance_valid(fire) or not fire.burning:
			leave_seat()
		_record_camp_trail()
	if mode == "follow":
		_record_player()
		var nearby := camping.nearby_fire(actor.global_position, 5.0)
		if nearby != null and camping.player.global_position.distance_to(nearby.global_position) < 4.5 and points.size() <= 2:
			var seat := camping.companion_seat(nearby, actor)
			if not seat.is_empty():
				fire = nearby
				camp_seat = seat
				points.assign([TavernInteractions.vector(seat.position)])
				_camp_trail.clear()
				_last_player = camping.player.global_position
				mode = "to_camp"
	if points.is_empty():
		actor.play("idle")
		if mode == "return":
			_finish()
		elif mode == "guide":
			mode = "follow"
			_reached_favorite = true
			_last_player = camping.player.global_position
			points.append(_last_player)
			camping.say(actor, camping.favorite_line(actor))
		return
	var target := points[0]
	var flat := target - actor.global_position
	flat.y = 0.0
	var tolerance := 1.8 if mode == "follow" and points.size() == 1 else 0.28
	if flat.length() <= tolerance:
		if mode == "to_camp":
			mode = "rest"
			pose.seated = true
			_model.position.y = 0.0
			mug.visible = true
			camping.arrive_at_fire(self)
		points.pop_front()
		actor.play("idle")
		return
	if mode == "guide" and actor.global_position.distance_to(camping.player.global_position) > 7.0:
		actor.play("idle")
		return
	var direction := flat.normalized()
	var speed := 2.7
	if mode == "follow" or mode == "to_camp":
		speed = clampf(flat.length() * 1.8, 1.2, 5.3)
	var step := direction * speed * delta
	if not _safe_step(step):
		_blocked += delta
		actor.play("idle")
		if _blocked >= 5.0 and mode != "return":
			camping.say(actor, "Здесь тесно. Я подожду — выйди на тропу, и пойдём дальше.")
			_blocked = -10.0
		return
	_blocked = 0.0
	_face(target, delta)
	actor.velocity.x = direction.x * speed
	actor.velocity.z = direction.z * speed
	actor.play("source_walk" if actor.animation.has_animation("source_walk") else "walk")
	if actor.global_position.distance_to(_last_actor) > 1.0 and mode != "return":
		walked.append(actor.global_position)
		_last_actor = actor.global_position

func _record_player() -> void:
	var at := camping.player.global_position
	if at.distance_to(_last_player) < 0.7:
		return
	# Debug fast travel must not create a path through walls or across the lake.
	if at.distance_to(_last_player) > 8.0:
		return
	if camping.player.water_surface > at.y + 0.1:
		return
	points.append(at)
	_last_player = at

func _record_camp_trail() -> void:
	var at := camping.player.global_position
	if at.distance_to(_last_player) >= 0.7 and at.distance_to(_last_player) <= 8.0 and camping.player.water_surface <= at.y + 0.1:
		_camp_trail.append(at)
		_last_player = at

func _safe_step(step: Vector3) -> bool:
	var origin := actor.global_position
	var ahead := origin + step.normalized() * maxf(0.35, step.length())
	var ground := camping.ground_at(ahead, 0.65, 1.0)
	if ground.is_empty():
		return false
	var feet: Vector3 = ground.position
	if ground.normal.y < 0.7 or feet.y < origin.y - Player.STEP_HEIGHT or feet.y > origin.y + Player.STEP_HEIGHT:
		return false
	if feet.y <= camping.water_level + 0.12:
		return false
	var collision := KinematicCollision3D.new()
	if actor.test_move(actor.global_transform, step, collision):
		# move_and_slide handles walkable floor contacts; they are not a wall.
		if collision.get_normal().y >= 0.7:
			return true
		var rise := maxf(0.0, feet.y - origin.y) + 0.03
		if rise <= 0.03 or actor.test_move(actor.global_transform, Vector3.UP * rise):
			return false
		var elevated := actor.global_transform
		elevated.origin.y += rise
		if actor.test_move(elevated, step):
			return false
		actor.global_position.y += rise
	return true

func _face(point: Vector3, delta: float) -> void:
	var offset := point - actor.global_position
	actor.rotation.y = lerp_angle(actor.rotation.y, atan2(-offset.x, -offset.z), minf(delta * 4.0, 1.0))

func _process(delta: float) -> void:
	_food_time = maxf(0.0, _food_time - delta)
	if is_instance_valid(_food):
		_food.visible = _food_time > 0.0
	if mode != "rest":
		_sync_props()

func _sync_props() -> void:
	# Read modified hand bones before SkeletonModifier restores the animation pose.
	if is_instance_valid(_food):
		_food.global_transform = Transform3D(actor.global_basis,
			actor.hand_position(actor._left_hand) + actor.global_basis * Vector3(0, 0.015, -0.035))
	if not is_instance_valid(mug) or not mug.visible:
		return
	# Own mug rests beside the hand, and is raised for shared toasts.
	var at := actor.hand_position(actor._right_hand) + actor.global_basis * Vector3(-0.085, -0.078, 0)
	mug.global_transform = Transform3D(actor.global_basis, at)

func toast() -> void:
	if mode == "rest":
		_toast = 1.5

func receive_food(portion: Node3D = null) -> void:
	if is_instance_valid(_food):
		_food.queue_free()
	_food = portion if portion != null else CampProps.potato(true)
	actor.add_child(_food)
	_food_time = 6.0

func leave_seat() -> void:
	pose.seated = false
	_model.position.y = 0.0
	mug.visible = false
	fire = null
	camp_seat = {}
	mode = "follow"
	points.assign(_camp_trail)
	_camp_trail.clear()
	_last_player = camping.player.global_position
	if points.is_empty():
		points.append(_last_player)

func guide() -> void:
	leave_seat()
	mode = "guide"
	points.clear()
	var nearest := 0
	var distance := INF
	for index in actor.route.size():
		var point := actor.route[index]
		var candidate := Vector2(point.x - actor.position.x, point.z - actor.position.z).length()
		if candidate < distance:
			distance = candidate
			nearest = index
	var destination := camping.favorite_index(actor)
	# Away from the road, retrace the safe walk before showing the ordinary route.
	if distance > 3.0 and not walked.is_empty():
		points.assign(walked)
		points.reverse()
		nearest = clampi(_starting_route_point, 0, actor.route.size() - 1)
	var stride := 1 if destination >= nearest else -1
	for index in range(nearest, destination + stride, stride):
		var source := actor.route[index]
		var ground := camping.ground_at(Vector3(source.x, 35, source.z), 5.0, 50.0)
		if not ground.is_empty():
			points.append(ground.position)

func dismiss() -> void:
	leave_seat()
	mode = "return"
	points.assign(walked)
	points.reverse()
	# Return by the route actually walked rather than a straight line home.
	if not points.is_empty() and actor.global_position.distance_to(points[0]) < 0.35:
		points.pop_front()

func _finish() -> void:
	actor._point = clampi(_starting_route_point, 0, maxi(0, actor.route.size() - 1))
	actor.outing = null
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(_model):
		_model.position.y = 0.0
	if is_instance_valid(pose):
		pose.queue_free()
	if is_instance_valid(mug):
		mug.queue_free()
	if is_instance_valid(_food):
		_food.queue_free()
