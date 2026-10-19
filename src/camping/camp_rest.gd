class_name CampRest
extends RefCounted
## The villagers at rest — at their work, and wherever else they keep still —
## and the player who comes up to them (CampTalk.rest): the visits
## (CampVisit), the moment their storytellers take, who stands beside whom,
## and who is near enough to be talked to, toasted and treated.

## How near a teller another villager stands to be in their company.
const COMPANY_REACH := 6.0

var camp: CampSystem
## The player's visits to the villagers at rest: person id -> CampVisit.
var visits: Dictionary = {}

func _init(of_camp: CampSystem) -> void:
	camp = of_camp

## Whether the villager has a sheet, is in the valley and is at rest.
func resting(actor: VillageNPC) -> bool:
	return camp.population.people.knows(actor.person_id) and actor.present() and actor.at_rest()

## Whether the villager stands in the zone the player is in; anywhere does in
## a level without the loop.
func in_players_zone(actor: VillageNPC) -> bool:
	return camp.valley == null or camp.valley.zones.zone_at(actor.global_position) == camp.valley.zone

## The record of the player's visits to the villager with the sheet `person`.
func record(person: String) -> CampVisit:
	if not visits.has(person):
		visits[person] = CampVisit.new()
	return visits[person]

## Whether the player is on a visit to the villager now.
func visited(actor: VillageNPC) -> bool:
	return resting(actor) and record(actor.person_id).near

## A frame of the villagers who are not on an outing: the visits begin and
## end, a seat of the tavern beside one of them warms, and each speaks when it
## is their turn. `speaker` is the storyteller telling a story now, if any.
func keep(delta: float, speaker: Storyteller) -> void:
	var talk := camp.talk
	var seated: bool = not camp.interactions.seated.is_empty()
	var at_table := talk.at_table()
	for actor in camp.population.actors:
		if actor.outing != null or not camp.population.people.knows(actor.person_id):
			continue
		var teller := camp.population.people.teller(actor.person_id)
		var visit := record(actor.person_id)
		var within := resting(actor) \
			and camp.player.global_position.distance_to(actor.global_position) <= CampTalk.TALK_REACH
		var near := within and in_players_zone(actor)
		if visit.frame(delta, near, seated):
			teller.begin_outing()
		if within and at_table:
			talk.spend(actor, "sit", delta, CampTalk.SIT_SECONDS)
		# One who walks about their work does not walk away from their own story.
		if near and not teller.telling.is_empty():
			actor.stop_to_talk(camp.player.global_position, delta)
		# A story the player walked away from is heard out to its breaking off.
		if near or not teller.telling.is_empty():
			talk.voice_line(actor, teller.advance(delta, moment(actor), speaker == null or speaker == teller,
				near and not camp.hud.speaking()))

## The moment as the storyteller of a villager at rest takes it (Storyteller).
func moment(actor: VillageNPC) -> Dictionary:
	var talk := camp.talk
	var now: Dictionary = camp.valley.moment() if camp.valley != null else ValleyLoop.STILL.duplicate()
	var visit := record(actor.person_id)
	var seated: bool = not camp.interactions.seated.is_empty()
	var still := talk.player_still()
	var barkeeper: bool = actor == camp.population.bartender and actor.at_work()
	var bond := camp.population.people.bond(actor.person_id)
	now["activity"] = CampVisit.activity(barkeeper, talk.at_table(), seated, still,
		camp.player.global_position.distance_to(actor.global_position))
	now["listening"] = visit.near and (seated or still)
	now["halt"] = visit.halt
	now["company"] = company(actor)
	now["gift"] = bond.gift(camp.current_day()) if bond != null else ""
	now["can_guide"] = false
	return now

## The ids of the other villagers with a sheet who are in the valley within
## COMPANY_REACH of `actor`, and in the same zone where the level has zones.
func company(actor: VillageNPC) -> Array[String]:
	var ids: Array[String] = []
	var zoned := false
	var zone := ""
	for other in camp.population.actors:
		if other == actor or not other.present() or not camp.population.people.knows(other.person_id) \
				or other.global_position.distance_to(actor.global_position) > COMPANY_REACH:
			continue
		if camp.valley != null:
			if not zoned:
				zoned = true
				zone = camp.valley.zones.zone_at(actor.global_position)
			if camp.valley.zones.zone_at(other.global_position) != zone:
				continue
		ids.append(other.person_id)
	return ids

## The nearest villager at rest within `reach` of the player, in the player's
## zone; null for none.
func nearest(reach: float) -> VillageNPC:
	var closest: VillageNPC = null
	for actor in camp.population.actors:
		var distance := camp.player.global_position.distance_to(actor.global_position)
		if distance < reach and resting(actor) and in_players_zone(actor):
			reach = distance
			closest = actor
	return closest

## The nearest villager at rest the player is on a visit to; null for none.
func nearest_visited() -> VillageNPC:
	var closest: VillageNPC = null
	var best := INF
	for actor in camp.population.actors:
		var distance := camp.player.global_position.distance_to(actor.global_position)
		if distance < best and visited(actor):
			best = distance
			closest = actor
	return closest

## The player took a sip: it is a toast with every villager at rest they are
## on a visit to from a seat of the tavern or at the bar. Returns the nearest
## of them, null when the sip was nobody's toast.
func toast() -> VillageNPC:
	var closest: VillageNPC = null
	var best := INF
	var at_table := camp.talk.at_table()
	for actor in camp.population.actors:
		if not visited(actor):
			continue
		var at_bar: bool = moment(actor).activity == PeopleIds.ACTIVITY_BAR
		if not at_table and not at_bar:
			continue
		camp.talk.warm(actor, "toast")
		var distance := camp.player.global_position.distance_to(actor.global_position)
		if distance < best:
			best = distance
			closest = actor
	return closest

## Whether E may be for the villager: a companion who has not been sent home,
## one who can be asked along, or one at rest. The innkeeper at work is not:
## E on him is for the beer (TavernInteractions).
func approachable(actor: VillageNPC) -> bool:
	if actor.outing != null:
		return actor.outing.along
	if not actor.present():
		return false
	return actor.invitable() or (actor != camp.population.bartender and resting(actor))
