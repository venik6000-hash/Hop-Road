class_name CampSigns
extends RefCounted
## The signs of closeness (CampTalk.signs): what a villager does unasked once
## the player has come to know them. They greet first, the innkeeper pours
## the usual, a companion brings a potato to the fire, and one who is close
## comes to the player's fire by themselves.

## How near the player passes for a villager to greet them.
const GREET_REACH := 4.0
## The height at which the two see each other: over the bar and the tables.
const EYES := 1.45
## How far from the innkeeper the player goes before the usual is poured anew.
const USUAL_REARM := 5.0
## How near the player's fire a villager passes to come and sit by it.
const JOIN_REACH := 12.0
## The circles from which the innkeeper pours unasked and a companion brings a
## treat and sits nearer, and from which a villager comes to the fire.
const NEAR_CIRCLE := 2
const CLOSE_CIRCLE := 3

var camp: CampSystem
## The innkeeper may pour the usual: the player has come up to him anew.
var usual_due := true

func _init(of_camp: CampSystem) -> void:
	camp = of_camp

## What is looked at twice a second.
func look() -> void:
	usual()
	greet()

## A villager who has told their name greets the player who passes, once a
## game day, while nobody else is speaking.
func greet() -> void:
	if camp.hud.speaking() or camp.talk.telling_now() != null:
		return
	var today := camp.current_day()
	for actor in camp.population.actors:
		if actor.outing != null or not actor.present() or not camp.population.people.knows(actor.person_id):
			continue
		var bond := camp.population.people.bond(actor.person_id)
		if not bond.introduced or camp.player.global_position.distance_to(actor.global_position) > GREET_REACH \
				or not camp.company.sees(actor, EYES):
			continue
		var words := camp.talk.line_of(actor, "greet")
		if words.is_empty() or not bond.once("greet", today):
			continue
		camp.say(actor, words)
		camp.mark_changed()
		return

## The innkeeper at work pours unasked for one he is close with, when they
## look at him with a mug that is not full: once each time they come up.
func usual() -> void:
	var keeper := camp.population.bartender
	if keeper == null:
		return
	if camp.player.global_position.distance_to(keeper.global_position) > USUAL_REARM:
		usual_due = true
		return
	if not usual_due or not camp.interactions.selected is VillageNPC or camp.interactions.selected != keeper:
		return
	var bar := keeper.duty as NpcBarJob
	if not keeper.present() or not keeper.at_work() or bar == null or not bar.takes_orders() \
			or camp.talk.circle_of(keeper) < NEAR_CIRCLE or camp.player.viewmodel.fill() >= BeerViewmodel.FILL_LEVEL - 0.01:
		return
	usual_due = false
	keeper.interact(camp.player)
	camp.say(keeper, camp.talk.line_of(keeper, "usual"))

## A companion who is near enough brings a potato to the fire they sit down
## at and puts it in the coals, once a game day, when the coals are free and
## the player's hands are empty. Returns whether they did.
func treat(outing: NpcOuting) -> bool:
	var bond := camp.population.people.bond(outing.actor.person_id)
	if bond == null or bond.circle < NEAR_CIRCLE or not is_instance_valid(outing.fire) or camp.food.holding():
		return false
	var meal := outing.fire.meal
	if meal.cooking or meal.portions > 0 or not bond.once("treat", camp.current_day()):
		return false
	camp.mark_changed()
	return meal.put_in_coals()

## A villager who is close and walks their road within JOIN_REACH of the burning `fire`
## the player is at joins them unasked, once a game day. Returns whether one
## did.
func join_fire(fire: Campfire) -> bool:
	var company := camp.company
	if company.companions.size() >= CampCompany.COMPANIONS:
		return false
	var today := camp.current_day()
	for actor in camp.population.actors:
		if not actor.present() or not actor.on_road():
			continue
		var bond := camp.population.people.bond(actor.person_id)
		if bond == null or bond.circle < CLOSE_CIRCLE \
				or actor.global_position.distance_to(fire.global_position) > JOIN_REACH or not company.sees(actor, EYES) \
				or not bond.once("join_fire", today):
			continue
		company.take_along(actor)
		actor.outing.unasked = true
		camp.say(actor, camp.talk.line_of(actor, "join_fire"))
		camp.mark_changed()
		return true
	return false
