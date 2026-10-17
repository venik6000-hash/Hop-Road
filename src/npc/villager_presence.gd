class_name VillagerPresence
extends Node
## The villagers' day in the level: once a second each villager whose sheet
## has a `day` is looked at, and one who is due elsewhere (VillagerDay.place)
## is put there — on their road, at their work, on their seat of the hall, on
## their spot of the yard, or out of the valley — when the player can see
## neither them nor the place they are due at; and at once for everybody at
## the start and after a night's sleep (apply_now, GameEvents.night_slept). Nobody walks between
## places. A villager on an outing is left alone until it ends; one sent home
## as the player lies down is in their place by the morning. The valley's
## loop owns the node; a level without the loop has none, and its villagers
## keep to what their jobs say. What the player sees is VillagerSight's
## question, where a body can stand VillagerSpots's.

const CHECK_SECONDS := 1.0
## How near their place one who came back from an outing takes it in sight.
const SETTLE_REACH := 2.0
## How near each other two in the yard stand to turn to each other.
const YARD_TALK := 6.0
## Where the jug stands on the counter, from the innkeeper's feet at work:
## where he serves the tankard (NpcBarWork.SERVE).
const JUG_AT := Vector3(-0.11, 1.06, -0.98)

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
## Those who sit in the hall: VillageNPC -> {seat, mug, hold (the Callable
## that keeps the mug by the hand)}.
var _seated: Dictionary = {}
## The names of the seats they sit on -> VillageNPC.
var _taken: Dictionary = {}
## Those who left their seat or their spot for an outing and have not taken
## it again: VillageNPC -> true.
var _unsettled: Dictionary = {}
## The height of the innkeeper's feet behind the bar; endless until seen.
var _bar_floor := INF
var _sight: VillagerSight
var _spots: VillagerSpots

func _ready() -> void:
	_sight = VillagerSight.new(population, player, camera)
	_spots = VillagerSpots.new(population, player, interactions, _sight)
	GameEvents.night_slept.connect(_night_slept)

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

## The night slept away (GameEvents.night_slept): everybody is where the
## morning has them.
func _night_slept(_hours: float) -> void:
	apply_now()

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
		_spots.step_out(actor, seat)
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
			outing.finish()
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
		var hidden := forced or actor.place == "home" or _sight.unseen(actor.global_position, actor)
		if not hidden and not back:
			continue
		var goal := _goal(actor, sheet, due)
		if goal.is_empty():
			continue
		var at: Vector3 = goal["at"]
		var allowed := forced or (hidden and (due == "home" or _sight.unseen(at, actor)))
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
			return _spots.road_goal(actor)
		"hall":
			return _seat_goal(actor, sheet)
		"yard":
			return _spots.yard_goal(actor, sheet)
	return {}

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
			return {"at": Values.vec3(seat.position), "seat": seat}
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
			actor.rounds.begin_at(actor.rounds.route_point)
		"road":
			var index: int = goal["index"]
			actor.global_position = at + Vector3.UP * 0.03
			actor.rounds.begin_at(index)
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
	var facing := Values.vec3(seat.facing)
	actor.global_position = Values.vec3(seat.position)
	actor.rotation.y = atan2(-facing.x, -facing.z)
	actor.seated = true
	var solid := _solid(actor)
	if solid != null:
		solid.disabled = true
	var entry: Dictionary = {"seat": seat, "mug": null, "hold": Callable()}
	if actor.skeleton != null:
		actor.poses.sit(Values.real(seat.height))
		var mug := NpcProps.mug(0.7)
		actor.add_child(mug)
		var hold := _hold_mug.bind(actor, mug)
		actor.posed.connect(hold)
		entry["mug"] = mug
		entry["hold"] = hold
	_seated[actor] = entry
	_taken[str(seat.get("name", ""))] = actor

## The seated villager gets up where they sit: the pose and the mug go, the
## body is solid again and the seat is free.
func _unseat(actor: VillageNPC) -> void:
	var entry: Dictionary = _seated[actor]
	var seat: Dictionary = entry["seat"]
	_seated.erase(actor)
	_taken.erase(str(seat.get("name", "")))
	actor.poses.stand()
	var hold: Callable = entry["hold"]
	if hold.is_valid() and actor.posed.is_connected(hold):
		actor.posed.disconnect(hold)
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
	var at := actor.hand_position(actor.right_hand) + actor.global_basis * Vector3(-0.085, -0.078, 0.0)
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
