class_name CampCompany
extends Node
## The villagers who walk with the player (CampSystem): who may be asked
## along, the companions (NpcOuting), their seats by a fire, the passers-by
## who ask to sit by one, the farewell. The part reads G and Q in GAME: Q
## only while the player aims at a companion.

## How many villagers walk with the player at once.
const COMPANIONS := 3
## Seconds between looks for a passer-by near the player's fire.
const GUEST_SECONDS := 3.0

var camp: CampSystem
var companions: Array[NpcOuting] = []
var _guest_clock := 0.0
## The passers-by who asked to sit by a fire: "<node name><fire key>" -> true.
var _guest_requests: Dictionary = {}

func _process(delta: float) -> void:
	_guest_clock += delta
	if _guest_clock > GUEST_SECONDS and camp.in_play():
		_guest_clock = 0.0
		_check_passersby()

func _input(event: InputEvent) -> void:
	if not camp.in_play() or event.is_echo():
		return
	if InputActions.takes_in(event, &"camp_secondary", InputActions.GAME):
		var actor := targeted_companion()
		if actor != null:
			dismiss(actor)
			get_viewport().set_input_as_handled()
	elif InputActions.takes_in(event, &"guide_outing", InputActions.GAME):
		var actor := targeted_companion()
		if actor == null:
			actor = nearest_companion(3.5)
		if actor == null:
			return
		if favorite_path(actor).is_empty():
			camp.say(actor, camp.talk.line_of(actor, "guide_none"))
		else:
			actor.outing.guide()
			camp.say(actor, camp.talk.line_of(actor, "guide"))
		get_viewport().set_input_as_handled()

## What E would do nearest within `best` metres among the villagers: {distance,
## target}; {} when nothing.
func find_target(best: float) -> Dictionary:
	var result: Dictionary = {}
	for actor in camp.population.actors:
		if not camp.talk.rest.approachable(actor):
			continue
		var distance := camp.interactions.target_distance(actor.global_position + Vector3.UP * 1.15, null, false, actor)
		if distance < best:
			best = distance
			result = {"distance": best, "target": actor}
	return result

func interaction_text(actor: VillageNPC) -> String:
	if actor.outing != null:
		return "{interact} — поговорить · {camp_secondary} — попрощаться · {guide_outing} — любимое место"
	if actor.invitable():
		return tr("{interact} — позвать гулять · %s") % tr(actor.title)
	return tr("{interact} — поговорить · %s") % tr(actor.title)

## E on a villager: a companion or one at rest is talked to, one who may be
## asked along sets out, while there is room in the company.
func interact_npc(actor: VillageNPC) -> void:
	var talk := camp.talk
	if actor.outing != null or not actor.invitable():
		talk.talk(actor)
		return
	if companions.size() >= COMPANIONS:
		camp.say(actor, talk.line_of(actor, "company_full"))
		return
	take_along(actor)
	var again: bool = talk.memory(actor).get("shared", 0) > 0
	camp.say(actor, talk.line_of(actor, "accept_again" if again and talk.circle_of(actor) < CampSigns.NEAR_CIRCLE else "accept"))

## The villager sets out with the player as a companion.
func take_along(actor: VillageNPC) -> void:
	if camp.valley != null and camp.valley.presence != null:
		camp.valley.presence.release(actor)
	var outing := NpcOuting.new()
	outing.actor = actor
	outing.camping = camp
	outing.teller = camp.population.people.teller(actor.person_id)
	if outing.teller == null:
		outing.teller = camp.population.people.passerby()
	outing.teller.begin_outing()
	actor.outing = outing
	actor.add_child(outing)
	companions.append(outing)

## The way to the place the person loves, as [x, z] points from their road.
func favorite_path(actor: VillageNPC) -> Array[Vector2]:
	return camp.population.people.sheet(actor.person_id).favorite_path

## The companion the player aims at, not one sent home; null for none.
func targeted_companion() -> VillageNPC:
	if camp.interactions.selected is VillageNPC:
		var actor: VillageNPC = camp.interactions.selected
		if actor.outing != null and actor.outing.along:
			return actor
	return null

## The companion nearest the player within `reach`, in plain sight; null for none.
func nearest_companion(reach: float) -> VillageNPC:
	var closest: VillageNPC
	for outing in companions:
		if not is_instance_valid(outing) or not outing.along:
			continue
		var distance := camp.player.global_position.distance_to(outing.actor.global_position)
		if distance < reach and sees(outing.actor):
			reach = distance
			closest = outing.actor
	return closest

## Whether nothing solid stands between the player and the villager, `height`
## over the feet of each: at the waist a counter or a table is in the way, at
## the eyes it is not.
func sees(actor: VillageNPC, height := 0.65) -> bool:
	var player := camp.player
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * height,
		actor.global_position + Vector3.UP * height, PhysicsLayers.GROUND)
	query.exclude = [player.get_rid(), actor.get_rid()]
	return camp.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## The companion goes home with a farewell.
func dismiss(actor: VillageNPC) -> void:
	var outing := actor.outing
	companions.erase(outing)
	outing.dismiss()
	camp.say(actor, camp.talk.line_of(actor, "farewell"))

## A villager who set out for the fire by themselves and found no way to it
## goes back as they came, without a farewell.
func turn_back(actor: VillageNPC) -> void:
	var outing := actor.outing
	companions.erase(outing)
	outing.dismiss()

## Every companion goes home (the player sleeps, boards the boat).
func dismiss_all() -> void:
	for outing: NpcOuting in companions.duplicate():
		if is_instance_valid(outing):
			dismiss(outing.actor)

## Whether a companion sits on, or makes for, the seat by a fire.
func holds_seat(seat: Dictionary) -> bool:
	for outing in companions:
		if is_instance_valid(outing) and outing.camp_seat == seat:
			return true
	return false

## The free seat by the fire the companion takes: the nearest to them, and
## for one who is near enough to the player, the nearest to the player.
func companion_seat(fire: Campfire, actor: VillageNPC) -> Dictionary:
	var player := camp.player
	var from: Vector3 = player.global_position if camp.talk.circle_of(actor) >= CampSigns.NEAR_CIRCLE else actor.global_position
	var best := INF
	var result: Dictionary = {}
	for seat: Dictionary in fire.seats:
		var at := Values.vec3(seat.position)
		if camp.campfires.seat_occupied(seat) or at.distance_to(player.global_position) < 0.9:
			continue
		var distance := at.distance_to(from)
		if distance < best:
			best = distance
			result = seat
	return result

## A passer-by on the road near the burning fire the player is at asks to sit
## by it, once a fire; a villager who is close comes unasked (CampSigns.join_fire).
func _check_passersby() -> void:
	var fire := camp.campfires.nearby_fire(camp.player.global_position, 4.0)
	if fire == null or camp.hud.speaking() or camp.talk.signs.join_fire(fire):
		return
	for actor in camp.population.actors:
		var key := actor.name + CampFires.fire_key(fire)
		if actor.present() and actor.on_road() and actor.global_position.distance_to(fire.global_position) < 4.5 and not _guest_requests.has(key):
			_guest_requests[key] = true
			actor.rounds.wait_time = 8.0
			camp.say(actor, camp.talk.line_of(actor, "warm_by_fire"))
			return
