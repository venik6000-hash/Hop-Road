class_name NpcOuting
extends Node
## Follow actual footsteps. No teleporting through the village or cliffs.

## How near the way to the place the person loves they must stand to join it
## where they are instead of going back by the road.
const JOIN_REACH := 4.0
## How much of a blocked second counts while it is a person who blocks, or
## while what blocks is being walked round.
const PATIENCE := 0.25
## The turn off the straight line to walk round what stands on it.
const ROUND := PI / 3.0
## A stone's bevel under the foot is no slope: it does not rise this much.
const BEVEL := 0.12
## The least share of a step left along a wall for the wall to be walked along.
const GLANCE := 0.5
## Half the width of a foot: what a gap in laid stone must be under to be stepped over.
const FOOT := 0.15
## Two stairs of the village's lanes stand closer than the look ahead. Going
## up, the ground ahead is looked for this high over the feet, and each stair
## is a step for the body when it meets it; going down, the ground ahead may
## lie this much lower.
const RISE := Player.STEP_HEIGHT * 2.0
const DROP := 0.6
## How much the ground may rise or fall per metre of a straight walk to the
## player (_make_for_player): more is a storey or a ledge, not a slope.
const STEEP := 0.5
## How near the player one who came unasked has come up to them.
const ARRIVED := 3.0
## A companion's pace, m/s: a stroll at the least, at the most a hurried walk
## that gains on a player who walks (Player.WALK_SPEED); one who runs is
## caught up with when they stop.
const PACE := Vector2(1.2, 3.5)
## How much the pace grows, 1/s, with every metre left to walk...
const HURRY := 1.8
## ...past this distance behind the player: nearer, the companion strolls.
const KEEP := 1.0
## How near a player who has come back stands for one the trail has shut out
## to make for them at once, and how long the way must have been shut, s.
const MEET := 4.0
const SHUT_SECONDS := 1.0
## The pace of one who steps out of the player's way, m/s, and for how long
## they keep stepping once the player has walked into them, s.
const ASIDE := 1.6
## m/s on the way to a place, when neither the camp nor the player sets the pace.
const WALK_SPEED := 2.7
const ASIDE_SECONDS := 0.6
## The height of a log by the fire over the feet, m.
const LOG_SEAT := 0.28
## Seconds a toast keeps the mug up, and food is held up to be eaten.
const TOAST_SECONDS := 1.5
const MEAL_SECONDS := 6.0

var actor: VillageNPC
var camping: CampSystem
## The person's voice on this outing (CampSystem feeds it).
var teller: Storyteller
var mode := "follow"
## A number that changes with every new halt: the companion sits down by a
## fire or gets up, or the player walks into another zone (CampSystem).
var halt := 0
## The companion and the player have been to the place the companion loves.
var reached_favorite := false
## The person set out for the player's fire by themselves (CAMP_SIGNS.join_fire)
## and has not yet come up to the player, sat down by the fire or been asked
## to lead: if the way is shut, they turn back.
var unasked := false
var points: Array[Vector3] = []
var walked: Array[Vector3] = []
var fire: Campfire
var camp_seat: Dictionary = {}
var mug: Node3D
var _model: Node3D
var _blocked := 0.0
## Seconds the next step of the trail has been shut with no way round it.
var _shut := 0.0
## The way the person steps out of the player's way, and for how long yet.
var _aside := Vector3.ZERO
var _aside_time := 0.0
## The last step was stopped by the player or by a villager.
var _met_person := false
## The side on which the last way round was found: it is tried first.
var _side := 1.0
var _last_player := Vector3.ZERO
var _last_actor := Vector3.ZERO
var _food: Node3D
var _food_time := 0.0
var _starting_route_point := 0
var _camp_trail: Array[Vector3] = []

func _ready() -> void:
	_model = actor.get_node("Model")
	actor.posed.connect(_sync_props)
	mug = NpcProps.mug(0.7)
	actor.add_child(mug)
	mug.visible = false
	_last_player = camping.player.global_position
	_last_actor = actor.global_position
	walked.append(actor.global_position)
	points.append(_last_player)
	_starting_route_point = actor.rounds.route_point

func drive(delta: float) -> void:
	if unasked and actor.global_position.distance_to(camping.player.global_position) <= ARRIVED:
		unasked = false
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
		_meet_player()
		var nearby := camping.nearby_fire(actor.global_position, 5.0)
		if nearby != null and camping.player.global_position.distance_to(nearby.global_position) < 4.5 and points.size() <= 2:
			var seat := camping.companion_seat(nearby, actor)
			if not seat.is_empty():
				fire = nearby
				camp_seat = seat
				points.assign([Values.vec3(seat.position)])
				_camp_trail.clear()
				_last_player = camping.player.global_position
				mode = "to_camp"
	if mode == "follow" and _give_way(delta):
		return
	if points.is_empty():
		actor.play("idle")
		if mode == "return":
			finish()
		elif mode == "guide":
			mode = "follow"
			_last_player = camping.player.global_position
			points.append(_last_player)
			if not reached_favorite:
				camping.reach_favorite(self)
		return
	var target := points[0]
	var flat := target - actor.global_position
	flat.y = 0.0
	var tolerance := 1.8 if mode == "follow" and points.size() == 1 else 0.28
	if flat.length() <= tolerance:
		if mode == "to_camp":
			mode = "rest"
			unasked = false
			halt += 1
			actor.poses.sit(LOG_SEAT)
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
	var speed := WALK_SPEED
	if mode == "to_camp":
		speed = clampf(flat.length() * HURRY, PACE.x, PACE.y)
	elif mode == "follow":
		# By how far behind the player the person is: the next footprint of
		# the trail is never more than a step away, and says nothing of it.
		var behind := actor.global_position.distance_to(camping.player.global_position)
		speed = clampf((behind - KEEP) * HURRY, PACE.x, PACE.y)
	var step := direction * speed * delta
	if _safe_step(step):
		_blocked = 0.0
		_shut = 0.0
	else:
		# A person in the way moves on, and what stands there may be walked
		# round: only a wall that leaves no way round counts in full.
		var person := _met_person
		var round := _way_round(step)
		_shut = _shut + delta if round == Vector3.ZERO and not person else 0.0
		# A player who has come back for one the trail has shut out is met at
		# once, without the wait and the word.
		if _shut >= SHUT_SECONDS and actor.global_position.distance_to(camping.player.global_position) <= MEET \
				and _make_for_player():
			_blocked = 0.0
			_shut = 0.0
			actor.play("idle")
			return
		_blocked += delta * (1.0 if round == Vector3.ZERO and not person else PATIENCE)
		if _blocked >= 5.0 and mode != "return":
			if mode == "guide":
				# The way is shut: the person stops leading and follows.
				mode = "follow"
				_last_player = camping.player.global_position
				points.assign([_last_player])
				camping.say(actor, camping.line_of(actor, "guide_lost"))
			elif unasked:
				# Nobody called them: they go back to their road without a word.
				_blocked = 0.0
				camping.turn_back(actor)
				return
			else:
				camping.say(actor, camping.line_of(actor, "blocked"))
				# Somebody in the way moves on; anything else that has held the
				# person this long has shut the trail.
				if not person:
					_make_for_player()
			_blocked = -10.0
			round = Vector3.ZERO
		if round == Vector3.ZERO:
			actor.play("idle")
			return
		direction = round.normalized()
	_face(target, delta)
	actor.velocity.x = direction.x * speed
	actor.velocity.z = direction.z * speed
	actor.stride(speed)
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

## The player stands nearer the companion than the trail's next footprint,
## in plain sight: they have come back or come up beside them, and the trail
## left behind would lead away from them. The companion makes for the player
## (_make_for_player), unless they stand a storey above or below.
func _meet_player() -> void:
	if points.is_empty():
		return
	var at := camping.player.global_position
	var apart := actor.global_position.distance_to(at)
	if apart <= MEET and apart < points[0].distance_to(at) and camping.sees(actor):
		_make_for_player()

## The trail is shut somewhere ahead: what is left of it is dropped, and the
## person makes straight for where the player stands now, step by safe step.
## A player who comes back for them is met; one out on the water, or a storey
## above or below, is waited for (false).
func _make_for_player() -> bool:
	var at := camping.player.global_position
	var away := at - actor.global_position
	if mode != "follow" or camping.player.water_surface > at.y + 0.1 \
			or absf(away.y) > maxf(1.0, Vector2(away.x, away.z).length() * STEEP):
		return false
	_last_player = at
	points.assign([at])
	return true

## The player has walked into the companion: they step out of the way, to a
## side that is free, else on the way the player is going. True while they do.
func _give_way(delta: float) -> bool:
	var player := camping.player
	for index in player.get_slide_collision_count():
		var met := player.get_slide_collision(index)
		if met.get_collider() != actor:
			continue
		var push := -met.get_normal()
		push.y = 0.0
		if push.length() < 0.5:
			continue
		push = push.normalized()
		for way: Vector3 in [push.rotated(Vector3.UP, PI * 0.5 * _side), push.rotated(Vector3.UP, -PI * 0.5 * _side), push]:
			if _safe_step(way * ASIDE * delta):
				_aside = way
				_aside_time = ASIDE_SECONDS
				break
	if _aside_time <= 0.0:
		return false
	_aside_time -= delta
	if not _safe_step(_aside * ASIDE * delta):
		_aside_time = 0.0
		return false
	_face(actor.global_position + _aside, delta)
	actor.velocity.x = _aside.x * ASIDE
	actor.velocity.z = _aside.z * ASIDE
	actor.stride(ASIDE)
	return true

func _record_camp_trail() -> void:
	var at := camping.player.global_position
	if at.distance_to(_last_player) >= 0.7 and at.distance_to(_last_player) <= 8.0 and camping.player.water_surface <= at.y + 0.1:
		_camp_trail.append(at)
		_last_player = at

func _safe_step(step: Vector3) -> bool:
	_met_person = false
	if not _ground_holds(step):
		return false
	var collision := KinematicCollision3D.new()
	if not actor.test_move(actor.global_transform, step, collision):
		return true
	# move_and_slide handles walkable floor contacts; they are not a wall.
	if collision.get_normal().y >= 0.7:
		return true
	_met_person = collision.get_collider() == camping.player or collision.get_collider() is VillageNPC
	# The trail's footprints say how high the way goes: a ledge more than a step
	# over the next one is a wall the player went round. Climbed, it may drop
	# away deeper than a step down on every side.
	var ceiling := points[0].y + Player.STEP_HEIGHT if not points.is_empty() else INF
	if not _met_person and actor.step_onto(collision, step, ceiling):
		return true
	# A wall or a person met at a glancing angle is passed by, as
	# move_and_slide does.
	var along := step.slide(collision.get_normal())
	along.y = 0.0
	if along.length() < step.length() * GLANCE or not _ground_holds(along):
		return false
	return not actor.test_move(actor.global_transform, along)

## The step turned to the side that is free, zero when neither is.
func _way_round(step: Vector3) -> Vector3:
	for side: float in [_side, -_side]:
		var round := step.rotated(Vector3.UP, ROUND * side)
		if _safe_step(round):
			_side = side
			return round
	return Vector3.ZERO

## The ground a step ahead can be walked: it is there, and is no drop, no
## water and no slope. What rises there is for the step to meet.
func _ground_holds(step: Vector3) -> bool:
	var origin := actor.global_position
	var ahead := origin + step.normalized() * maxf(0.35, step.length())
	var ground := camping.ground_at(ahead, RISE, DROP + 0.4)
	# A foot does not go down the gap between two cobbles: the stone beside it holds.
	if ground.is_empty() or ground.position.y < origin.y - DROP:
		for side: Vector3 in [Vector3(FOOT, 0.0, 0.0), Vector3(-FOOT, 0.0, 0.0), Vector3(0.0, 0.0, FOOT), Vector3(0.0, 0.0, -FOOT)]:
			var beside := camping.ground_at(ahead + side, RISE, DROP + 0.4)
			if not beside.is_empty() and (ground.is_empty() or beside.position.y > ground.position.y):
				ground = beside
	if ground.is_empty():
		return false
	var feet: Vector3 = ground.position
	if feet.y < origin.y - DROP or feet.y <= camping.water_level + 0.12:
		return false
	# The terrain's normal is its slope. On laid stone the ray may land on the
	# bevel of a flagstone or a cobble: a slope also rises.
	if ground.normal.y >= 0.7:
		return true
	if PhysicsLayers.hit_terrain(ground):
		return false
	if absf(feet.y - origin.y) <= BEVEL:
		return true
	# A stone that was stepped on (VillageNPC.step_onto) falls away under the
	# feet on every side: its flank is no slope when the ground a pace on can
	# be stood on, and is stepped down to.
	if feet.y > origin.y:
		return false
	var beyond := camping.ground_at(origin + (ahead - origin) * 2.0, RISE, DROP + 0.4)
	if beyond.is_empty():
		return false
	var landing: Vector3 = beyond.position
	return beyond.normal.y >= 0.7 and landing.y >= origin.y - DROP and landing.y > camping.water_level + 0.12

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
			actor.hand_position(actor.left_hand) + actor.global_basis * Vector3(0, 0.015, -0.035))
	if not is_instance_valid(mug) or not mug.visible:
		return
	# Own mug rests beside the hand, and is raised for shared toasts.
	var at := actor.hand_position(actor.right_hand) + actor.global_basis * Vector3(-0.085, -0.078, 0)
	mug.global_transform = Transform3D(actor.global_basis, at)

func toast() -> void:
	if mode == "rest":
		actor.poses.gesture(NpcBody.TOAST, TOAST_SECONDS)

func receive_food(portion: Node3D = null) -> void:
	if is_instance_valid(_food):
		_food.queue_free()
	_food = portion if portion != null else CampProps.potato(true)
	actor.add_child(_food)
	_food_time = MEAL_SECONDS
	actor.poses.gesture(NpcBody.MEAL, MEAL_SECONDS)

func leave_seat() -> void:
	halt += 1
	actor.poses.stand()
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

## Leads to the place the person loves (PersonSheet.favorite_path): from
## beside the way to it, straight along the way; from anywhere else, by the
## person's road to where the way leaves it, and then along the way.
func guide() -> void:
	unasked = false
	leave_seat()
	var way := camping.favorite_path(actor)
	if way.is_empty():
		return
	mode = "guide"
	points.clear()
	var joined := join_index(way, Vector2(actor.global_position.x, actor.global_position.z), JOIN_REACH)
	if joined < 0:
		joined = 0
		_take_road(way[0])
	for index in range(joined, way.size()):
		_lead_to(way[index])

## The point of `way` to make for from `here`: the far end of its nearest
## stretch when that is within `reach`, -1 when the way is farther off.
static func join_index(way: Array[Vector2], here: Vector2, reach: float) -> int:
	var joined := -1
	var nearest := reach
	if here.distance_to(way[0]) <= nearest:
		nearest = here.distance_to(way[0])
		joined = 0
	for index in range(1, way.size()):
		var distance := Geometry2D.get_closest_point_to_segment(here, way[index - 1], way[index]).distance_to(here)
		if distance <= nearest:
			nearest = distance
			joined = index
	return joined

## Queues the person's road up to its point nearest `to`.
func _take_road(to: Vector2) -> void:
	if actor.rounds.route.is_empty():
		return
	var here := Vector2(actor.position.x, actor.position.z)
	var nearest := _road_index(here)
	# Away from the road, retrace the safe walk before showing the ordinary route.
	if here.distance_to(Vector2(actor.rounds.route[nearest].x, actor.rounds.route[nearest].z)) > 3.0 and not walked.is_empty():
		points.assign(walked)
		points.reverse()
		nearest = clampi(_starting_route_point, 0, actor.rounds.route.size() - 1)
	var destination := _road_index(to)
	var stride := 1 if destination >= nearest else -1
	for index in range(nearest, destination + stride, stride):
		_lead_to(Vector2(actor.rounds.route[index].x, actor.rounds.route[index].z))

## The index of the road's point nearest `to`.
func _road_index(to: Vector2) -> int:
	var nearest := 0
	var distance := INF
	for index in actor.rounds.route.size():
		var candidate := to.distance_to(Vector2(actor.rounds.route[index].x, actor.rounds.route[index].z))
		if candidate < distance:
			distance = candidate
			nearest = index
	return nearest

## Queues the ground under [x, z] `at`.
func _lead_to(at: Vector2) -> void:
	var ground := camping.ground_at(Vector3(at.x, 35, at.y), 5.0, 50.0)
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

func finish() -> void:
	actor.rounds.route_point = clampi(_starting_route_point, 0, maxi(0, actor.rounds.route.size() - 1))
	actor.outing = null
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(_model):
		_model.position.y = 0.0
	if is_instance_valid(actor):
		actor.poses.stand()
		if actor.posed.is_connected(_sync_props):
			actor.posed.disconnect(_sync_props)
	if is_instance_valid(mug):
		mug.queue_free()
	if is_instance_valid(_food):
		_food.queue_free()
