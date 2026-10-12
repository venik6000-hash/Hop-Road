class_name VillagerPresence
extends Node
## The villagers' day in the level: once a second each villager whose sheet
## has a `day` is looked at, and one who is due elsewhere (VillagerDay.place)
## is put there — on their road, at their work, on their seat of the hall, on
## their spot of the yard, or out of the valley — when the player can see
## neither them nor the place they are due at; and at once for everybody at
## the start and after a night's sleep (apply_now). Nobody walks between
## places. A villager on an outing is left alone until it ends; one sent home
## as the player lies down is in their place by the morning. The valley's
## loop owns the node; a level without the loop has none, and its villagers
## keep to what their jobs say.

const CHECK_SECONDS := 1.0
## The villagers' meshes end this far from the camera.
const FAR := 65.0
## The heights over the feet at which a body is looked for: the chest and the
## head. One who shows either is seen.
const LOOKS: Array[float] = [0.9, 1.55]
## A look that ends at least this far short of the point has met a wall.
const SHORT := 0.5
## How near their place one who came back from an outing takes it in sight.
const SETTLE_REACH := 2.0
## The height of the yard's ground, and how far from it a place to stand may
## lie: the steps of the door and the top of a barrel are not the yard.
const YARD_LEVEL := 6.6
const YARD_STEP := 0.3
## The rings round a yard spot that are tried when the spot itself is taken.
const YARD_RINGS: Array[float] = [0.6, 1.2, 1.8]
## How near each other two in the yard stand to turn to each other.
const YARD_TALK := 6.0
## How near another body a villager is not put.
const ELBOW := 0.6
## How near another body a walker is not put on the road.
const ROAD_GAP := 3.0
## The centre of a villager's capsule over the feet, and the gap left under it
## for the unevenness of the ground.
const BODY_CENTRE := 0.83
const BODY_GAP := 0.1
## Where the jug stands on the counter, from the innkeeper's feet at work:
## beside the place of the mug he serves.
const JUG_AT := Vector3(0.25, 1.09, -0.79)

var population: NpcPopulation
var player: Player
var camera: Camera3D
var sky: SkySystem
var weather: WeatherSystem
var interactions: TavernInteractions
## While false nobody is moved: a tool that puts the villagers where it needs
## them switches the day off.
var active := true
## The jug on the counter while the innkeeper is away from the bar.
var jug: Node3D

var _clock := 0.0
## Those who sit in the hall: VillageNPC -> {seat, pose (CampPose), mug}.
var _seated: Dictionary = {}
## The names of the seats they sit on -> VillageNPC.
var _taken: Dictionary = {}
## Those who left their seat or their spot for an outing and have not taken
## it again: VillageNPC -> true.
var _unsettled: Dictionary = {}
## The height of the innkeeper's feet behind the bar; endless until seen.
var _bar_floor := INF
var _fit := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	var body := CapsuleShape3D.new()
	body.radius = 0.23
	body.height = 1.65
	_fit.shape = body
	_fit.collision_mask = 1

func _process(delta: float) -> void:
	_clock += delta
	if _clock < CHECK_SECONDS:
		return
	_clock = 0.0
	_look(false)

## Puts everybody where the hour has them, seen or not.
func apply_now() -> void:
	_clock = 0.0
	_look(true)

## Whether a villager sits on the seat of the tavern.
func seat_taken(seat: Dictionary) -> bool:
	return _taken.has(str(seat.get("name", "")))

## The villager is about to set out with the player: one who sits gets up and
## steps to the first way out of the seat where a body can stand, one who
## stands in the yard leaves their spot. They take the place again after the
## outing.
func release(actor: VillageNPC) -> void:
	if _seated.has(actor):
		var entry: Dictionary = _seated[actor]
		var seat: Dictionary = entry["seat"]
		_unseat(actor)
		var stepped := false
		var exits: Array = seat.get("exits", [])
		for exit: Variant in exits:
			if not exit is Array:
				continue
			var way: Array = exit
			var point := TavernInteractions.vector(way)
			if _fits(actor, point):
				actor.global_position = point + Vector3.UP * 0.015
				stepped = true
				break
		if not stepped:
			# Every way out is taken: anywhere round the seat with a floor and
			# room for a body.
			var origin := TavernInteractions.vector(seat.position)
			for radius: float in [0.8, 1.0, 1.25]:
				for index in range(16):
					var angle := TAU * float(index) / 16.0
					var around := origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
					if not stepped and interactions.can_stand(around) and _fits(actor, around):
						actor.global_position = around + Vector3.UP * 0.015
						stepped = true
		_unsettled[actor] = true
	elif actor.place == "yard" and actor.outing == null:
		_unsettled[actor] = true
		_face_yard()

## Whether a villager sits in the hall within `reach` of the point: they have
## no collision, so whoever looks for room to stand asks.
func sits_near(point: Vector3, reach := 0.5) -> bool:
	for key: Variant in _seated:
		if not is_instance_valid(key):
			continue
		var actor: VillageNPC = key
		if Vector2(actor.global_position.x - point.x, actor.global_position.z - point.z).length() < reach:
			return true
	return false

## Whether the player sees nothing at `point` (the feet of a body, or of the
## place for one): it is farther than the villagers are drawn, out of the
## picture, or behind something. `body` is the villager who stands there.
func unseen(point: Vector3, body: VillageNPC = null) -> bool:
	var eye := _eye()
	if eye == null:
		return true
	for height: float in LOOKS:
		if _shows(eye, point + Vector3.UP * height, body):
			return false
	return true

## Whether the camera has the point in the picture with nothing solid before
## it. `body` is looked through.
func _shows(eye: Camera3D, at: Vector3, body: VillageNPC) -> bool:
	var from := eye.global_position
	if from.distance_to(at) > FAR or not eye.is_position_in_frustum(at):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, at, 1)
	var passed: Array[RID] = [player.get_rid()]
	if body != null:
		passed.append(body.get_rid())
	query.exclude = passed
	var hit := _space().intersect_ray(query)
	if hit.is_empty():
		return true
	var met: Vector3 = hit.position
	return met.distance_to(at) <= SHORT

## A look at everybody. `forced` moves those who are due elsewhere at once.
func _look(forced: bool) -> void:
	if not active or not is_instance_valid(population) or not population.is_inside_tree():
		return
	var hour := sky.time_of_day
	var kind: String = weather.kind
	for actor in population.actors:
		if not is_instance_valid(actor) or not population.people.knows(actor.person_id):
			continue
		if actor.outing != null:
			# One sent home as the player lay down is where the hour has them
			# by the morning; any other outing is left alone.
			var outing := actor.outing as NpcOuting
			if not forced or outing == null or outing.mode != "return":
				continue
			outing._finish()
			_unsettled[actor] = true
		var sheet := population.people.sheet(actor.person_id)
		if sheet.day.is_empty():
			continue
		var fallback := _fallback(actor)
		var due := VillagerDay.place(sheet.day, hour, kind, sheet.shelter, fallback)
		if actor.place.is_empty() and due == fallback:
			# The first look finds them where the job has put them.
			actor.place = due
			continue
		var back := _unsettled.has(actor) and due == actor.place
		if due == actor.place and not back:
			continue
		if not forced and _in_a_story(actor):
			continue
		var hidden := forced or actor.place == "home" or unseen(actor.global_position, actor)
		if not hidden and not back:
			continue
		var goal := _goal(actor, sheet, due)
		if goal.is_empty():
			continue
		var at: Vector3 = goal["at"]
		var allowed := forced or (hidden and (due == "home" or unseen(at, actor)))
		if not allowed and back:
			var offset := at - actor.global_position
			allowed = absf(offset.y) < 1.5 and Vector2(offset.x, offset.z).length() <= SETTLE_REACH
		if allowed:
			_move(actor, due, goal)
	_keep_jug()

## Whether the villager is telling a story now, or is the second voice of one
## that another is telling: nobody leaves in the middle of it.
func _in_a_story(actor: VillageNPC) -> bool:
	var book := population.people
	for other in population.actors:
		if not is_instance_valid(other) or not book.knows(other.person_id):
			continue
		var teller := book.teller(other.person_id)
		if teller == null or teller.telling.is_empty():
			continue
		if other == actor:
			return true
		var story := book.sheet(other.person_id).story(teller.telling)
		var partner: String = story.get("with", "")
		if partner == actor.person_id:
			return true
	return false

## The place of one whose day names none for the hour.
func _fallback(actor: VillageNPC) -> String:
	return "road" if actor.job == "wander" else "work"

## Where the villager would be put for `due`: {at: Vector3} with the seat
## ("seat") or the road's point ("index") beside it; {} when there is no
## place for them now.
func _goal(actor: VillageNPC, sheet: PersonSheet, due: String) -> Dictionary:
	match due:
		"home":
			return {"at": actor.global_position}
		"work":
			return {"at": actor.work_point}
		"road":
			return _road_goal(actor)
		"hall":
			return _seat_goal(actor, sheet)
		"yard":
			return _yard_goal(actor, sheet)
	return {}

## The point of the villager's road farthest from the player among those the
## player does not see; the farthest of all when every one is seen.
func _road_goal(actor: VillageNPC) -> Dictionary:
	var out_of_sight: Dictionary = {}
	var in_sight: Dictionary = {}
	var farthest_hidden := -1.0
	var farthest_seen := -1.0
	for index in actor.route.size():
		var ground := _ground(actor.route[index].x, actor.route[index].z, 40.0, -10.0)
		if ground.is_empty():
			continue
		var at: Vector3 = ground.position
		if _crowded(actor, at, ROAD_GAP):
			continue
		var distance := at.distance_to(player.global_position)
		if unseen(at, actor):
			if distance > farthest_hidden:
				farthest_hidden = distance
				out_of_sight = {"at": at, "index": index}
		elif distance > farthest_seen:
			farthest_seen = distance
			in_sight = {"at": at, "index": index}
	return out_of_sight if not out_of_sight.is_empty() else in_sight

## The villager's seat of the hall, when nobody sits on it.
func _seat_goal(actor: VillageNPC, sheet: PersonSheet) -> Dictionary:
	if sheet.hall_seat.is_empty():
		return {}
	if str(interactions.seated.get("name", "")) == sheet.hall_seat:
		return {}
	if _taken.has(sheet.hall_seat) and _taken[sheet.hall_seat] != actor:
		return {}
	for seat: Dictionary in interactions.seats:
		if str(seat.get("name", "")) == sheet.hall_seat:
			return {"at": TavernInteractions.vector(seat.position), "seat": seat}
	return {}

## The villager's spot of the yard, or the nearest place round it where a
## body can stand.
func _yard_goal(actor: VillageNPC, sheet: PersonSheet) -> Dictionary:
	if not sheet.has_yard_spot():
		return {}
	var tries: Array[Vector2] = [sheet.yard_spot]
	for radius: float in YARD_RINGS:
		for index in range(8):
			var angle := TAU * float(index) / 8.0
			tries.append(sheet.yard_spot + Vector2(cos(angle), sin(angle)) * radius)
	for spot: Vector2 in tries:
		var ground := _ground(spot.x, spot.y, YARD_LEVEL + 1.9, YARD_LEVEL - 1.0)
		if ground.is_empty():
			continue
		var normal: Vector3 = ground.normal
		var feet: Vector3 = ground.position
		if normal.y >= 0.7 and absf(feet.y - YARD_LEVEL) <= YARD_STEP and _fits(actor, feet):
			return {"at": feet}
	return {}

## Takes the villager out of the place they are in and puts them into `due`.
func _move(actor: VillageNPC, due: String, goal: Dictionary) -> void:
	if actor == population.bartender and actor.global_position.distance_to(actor.work_point) < 0.3:
		_bar_floor = actor.global_position.y
	if _seated.has(actor):
		_unseat(actor)
	if actor.place == "home":
		actor.visible = true
		actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.clear_bar()
	# The knife, the spoon and the cloth stay at work.
	if actor.job != "bartender" and actor.utensil != null:
		actor.utensil.visible = due == "work"
	var at: Vector3 = goal["at"]
	actor.velocity = Vector3.ZERO
	match due:
		"home":
			actor.visible = false
			actor.process_mode = Node.PROCESS_MODE_DISABLED
		"work":
			actor.global_position = at
			actor.rotation.y = actor.work_yaw
			# The hall's paths are found anew from here.
			actor._hall_target = -1
			actor._blocked = 0.0
			actor._wait = 0.0
		"road":
			var index: int = goal["index"]
			actor.global_position = at + Vector3.UP * 0.03
			actor._point = index
			actor._blocked = 0.0
			actor._wait = 0.0
		"hall":
			var seat: Dictionary = goal["seat"]
			_sit(actor, seat)
		"yard":
			actor.global_position = at + Vector3.UP * 0.03
	actor.place = due
	_unsettled.erase(actor)
	_face_yard()

## Seats the villager: on the seat's place on the floor, turned as the seat
## is, without collision, in a sitting pose of the seat's height, with a mug.
func _sit(actor: VillageNPC, seat: Dictionary) -> void:
	var facing := TavernInteractions.vector(seat.facing)
	actor.global_position = TavernInteractions.vector(seat.position)
	actor.rotation.y = atan2(-facing.x, -facing.z)
	actor.seated = true
	var solid := _solid(actor)
	if solid != null:
		solid.disabled = true
	var entry: Dictionary = {"seat": seat, "pose": null, "mug": null}
	if actor.skeleton != null:
		var pose := CampPose.new()
		pose.actor = actor
		pose.seat_height = float(seat.height)
		pose.seated = true
		actor.skeleton.add_child(pose)
		var mug := NpcProps.mug()
		actor.add_child(mug)
		(mug.get_node("Beer") as Node3D).position.y = 0.11
		pose.modification_processed.connect(_hold_mug.bind(actor, mug))
		entry["pose"] = pose
		entry["mug"] = mug
	_seated[actor] = entry
	_taken[str(seat.get("name", ""))] = actor

## The seated villager gets up where they sit: the pose and the mug go, the
## body is solid again and the seat is free.
func _unseat(actor: VillageNPC) -> void:
	var entry: Dictionary = _seated[actor]
	var seat: Dictionary = entry["seat"]
	_seated.erase(actor)
	_taken.erase(str(seat.get("name", "")))
	var pose: CampPose = entry["pose"]
	if is_instance_valid(pose):
		pose.seated = false
		pose.queue_free()
	var mug: Node3D = entry["mug"]
	if is_instance_valid(mug):
		mug.queue_free()
	actor.seated = false
	actor.velocity = Vector3.ZERO
	var solid := _solid(actor)
	if solid != null:
		solid.disabled = false

## The mug rests beside the right hand of the seated pose (as NpcOuting's).
func _hold_mug(actor: VillageNPC, mug: Node3D) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(mug):
		return
	var at := actor.hand_position(actor._right_hand) + actor.global_basis * Vector3(-0.085, -0.078, 0.0)
	mug.global_transform = Transform3D(actor.global_basis, at)

## Two who stand in the yard turn to each other; one alone looks away from
## the tavern.
func _face_yard() -> void:
	var standing: Array[VillageNPC] = []
	for actor in population.actors:
		if is_instance_valid(actor) and actor.place == "yard" and actor.outing == null and not _unsettled.has(actor):
			standing.append(actor)
	for actor in standing:
		var toward := Vector3.BACK
		var nearest := YARD_TALK
		for other in standing:
			if other == actor:
				continue
			var offset := other.global_position - actor.global_position
			offset.y = 0.0
			if offset.length() > 0.01 and offset.length() < nearest:
				nearest = offset.length()
				toward = offset
		actor.rotation.y = atan2(-toward.x, -toward.z)

## Shows the jug on the counter while the innkeeper's day has him elsewhere.
func _keep_jug() -> void:
	var keeper := population.bartender
	if not is_instance_valid(keeper):
		return
	var away := not keeper.place.is_empty() and not keeper.at_work()
	if away and jug == null:
		jug = NpcProps.jug()
		add_child(jug)
		var base := keeper.work_point
		if is_finite(_bar_floor):
			base.y = _bar_floor
		jug.position = base + Basis(Vector3.UP, keeper.work_yaw) * JUG_AT
		jug.rotation.y = keeper.work_yaw
	if jug != null:
		jug.visible = away

## The camera the player looks through now; null when there is none.
func _eye() -> Camera3D:
	if is_instance_valid(camera) and camera.is_inside_tree() and camera.current:
		return camera
	return get_viewport().get_camera_3d()

func _space() -> PhysicsDirectSpaceState3D:
	return population.get_world_3d().direct_space_state

## The ground under (x, z) between two heights, through the people.
func _ground(x: float, z: float, top: float, bottom: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, bottom, z), 1)
	var passed: Array[RID] = [player.get_rid()]
	for actor in population.actors:
		if is_instance_valid(actor):
			passed.append(actor.get_rid())
	query.exclude = passed
	return _space().intersect_ray(query)

## Whether the villager's body can stand with its feet at `feet`: nothing
## solid is in its way and nobody stands there.
func _fits(actor: VillageNPC, feet: Vector3) -> bool:
	_fit.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (BODY_CENTRE + BODY_GAP))
	var passed: Array[RID] = [actor.get_rid()]
	_fit.exclude = passed
	if not _space().intersect_shape(_fit, 1).is_empty():
		return false
	return not _crowded(actor, feet, ELBOW)

## Whether the player or another villager who is in the valley stands within
## `reach` of `at`.
func _crowded(actor: VillageNPC, at: Vector3, reach: float) -> bool:
	if player.global_position.distance_to(at) < reach:
		return true
	for other in population.actors:
		if other != actor and is_instance_valid(other) and other.visible and other.global_position.distance_to(at) < reach:
			return true
	return false

func _solid(actor: VillageNPC) -> CollisionShape3D:
	for child in actor.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null

## The loop is leaving the level: the villagers go back to what their jobs
## say, as in a level that never had it.
func _exit_tree() -> void:
	if not is_instance_valid(population) or not population.is_inside_tree() or not is_instance_valid(player) \
			or not player.is_inside_tree():
		return
	for actor in population.actors:
		if not is_instance_valid(actor) or actor.place.is_empty():
			continue
		var fallback := _fallback(actor)
		if actor.outing == null and (actor.place != fallback or _unsettled.has(actor)):
			var goal := _goal(actor, population.people.sheet(actor.person_id), fallback)
			if not goal.is_empty():
				_move(actor, fallback, goal)
		if _seated.has(actor):
			_unseat(actor)
		if actor.place == "home":
			actor.visible = true
			actor.process_mode = Node.PROCESS_MODE_INHERIT
		actor.place = ""
	_unsettled.clear()
